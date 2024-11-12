-module(setup).

%% --------------------------------------------------------------------
%% Module: setup
%% Description:
%% This module handles the initial setup phase for nodes in a distributed system.
%% Specifically, it manages the propagation of setup messages between nodes, 
%% establishing the environment and clustering structures. The module allows nodes 
%% to identify their neighbors, assign a leader ID, and propagate setup requests to 
%% form clusters based on specific color and leader attributes.
%%
%% Key Features:
%% - Initiates setup by designating leaders and propagating the leader ID to connected nodes.
%% - Collects information from adjacent nodes to form clusters.
%% - Handles message propagation, ensuring nodes only respond if not already visited.
%% - In Phase 2, finalizes cluster boundaries by identifying adjacent clusters for each leader.
%%
%% Functions:
%% - `setup_loop/3`: Main loop to manage setup messages and node states.
%% - `setup_loop_propagate/7`: Propagates setup messages to neighboring nodes to form clusters.
%% - `wait_for_ack_from_neighbors/7`: Collects acknowledgments from neighbors to confirm 
%%   successful message propagation.
%% - `gather_adjacent_clusters/5`: Collects and filters unique leader IDs from neighboring clusters.
%% - `gather_adjacent_nodes/3`: Retrieves adjacent nodes for a given cluster.
%%
%% Preconditions:
%% - Each node must have an initial leader record and color assigned.
%% - Neighboring relationships should be pre-defined for accurate propagation.
%% - Nodes must have a unique PID to avoid conflicts during propagation.
%%
%% Postconditions:
%% - Successfully organizes nodes into clusters with designated leaders.
%% - Identifies and sets up adjacency information for each cluster.
%% - Finalizes and logs the setup configuration for all nodes.
%%
%% Usage:
%% This module is primarily used during the initial setup phase in a distributed system 
%% where nodes need to organize into clusters, establish leaders, and identify neighboring clusters.
%% --------------------------------------------------------------------


-export([setup_loop/3]).
-include("includes/node.hrl").

%% Primary loop for setting up the environment and node structures.
%% @spec setup_loop(#leader{}, pid(), boolean()) -> no_return()
%% @param Leader The leader record for the node undergoing setup.
%% @param StartSystemPid PID of the system startup process.
%% @param Visited Boolean flag indicating whether this node has already been visited.
%%
%% Preconditions:
%% - `Leader` must be a valid leader record.
%% - `StartSystemPid` is the PID of the initiating process.
%% - `Visited` is false initially for unvisited nodes.
%%
%% Postconditions:
%% - Continues the setup process by handling various setup-related messages.
setup_loop(Leader, StartSystemPid, Visited) ->
    Pid = self(),
    utils:save_data(Leader),
    receive
        {neighbors, Neighbors} ->
            %% Node receives neighbors, updates state, and acknowledges the system.
            UpdatedNode = Leader#leader.node#node{neighbors = Neighbors, leaderID = Pid, pid = Pid},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            StartSystemPid ! {ack_neighbors, self()},
            setup_loop(UpdatedLeader, StartSystemPid, Visited);

        {setup_server_request, FromPid} ->
            if
                Visited =:= true ->
                    %% Node has already been visited; notify the sender.
                    FromPid ! {self(), node_already_visited},
                    setup_loop(Leader, StartSystemPid, Visited);
                true ->
                    %% Node starts propagation as the initiating node.
                    setup_loop_propagate(
                        Leader#leader{serverID = FromPid},
                        Leader#leader.color,
                        self(),
                        true,  % Mark node as visited
                        Leader#leader.node#node.neighbors,
                        initiator,
                        StartSystemPid
                    )
            end;

        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            %% Node handles propagation requests based on visit status and color matching.
            if
                Visited =:= false andalso Leader#leader.color =:= SenderColor ->
                    %% Propagation continues with the same color.
                    UpdatedNode = Leader#leader.node#node{parent = FromPid, leaderID = PropagatedLeaderID},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    setup_loop_propagate(
                        UpdatedLeader,
                        Leader#leader.color,
                        FromPid,
                        true,  % Mark node as visited
                        Leader#leader.node#node.neighbors,
                        non_initiator,
                        StartSystemPid
                    );
                Visited =:= true ->
                    %% Node has already been visited; notify the sender.
                    FromPid ! {self(), node_already_visited},
                    setup_loop(Leader, StartSystemPid, Visited);
                true ->
                    %% Node with a different color acknowledges only.
                    FromPid ! {self(), ack_propagation_different_color},
                    setup_loop(Leader, StartSystemPid, Visited)
            end;

        {get_list_neighbors, FromPid} ->
            %% Provides the list of neighbors to the requesting node.
            FromPid ! {response_get_list_neighbors, Leader#leader.node#node.neighbors},
            node:leader_loop(Leader);

        {get_leader_info, FromPid} ->
            %% Sends the leader info to the requesting neighbor.
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
            setup_loop(Leader, StartSystemPid, Visited);

        {add_child, ChildPid} ->
            %% Adds a child to the node's list of children.
            UpdatedChildren = [ChildPid | Leader#leader.node#node.children],
            UpdatedNode = Leader#leader.node#node{children = UpdatedChildren},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            setup_loop(UpdatedLeader, StartSystemPid, Visited);

        {start_phase2, NodePIDs} ->
            %% Initiates Phase 2 setup for cluster connectivity.
            ServerPid = Leader#leader.serverID,
            NodePIDsWithoutSelf = lists:delete(self(), NodePIDs),
            AdjNodesToCluster = gather_adjacent_nodes(NodePIDsWithoutSelf, Leader#leader.node#node.leaderID, Leader#leader.node#node.neighbors),
            AdjNodesToCluster_no_duplicates = utils:remove_duplicates(AdjNodesToCluster),
            AllAdjacentClusters = gather_adjacent_clusters(
                lists:delete(self(), AdjNodesToCluster_no_duplicates), 
                Leader#leader.node#node.leaderID, [], [], Leader
            ),
            ServerPid ! {self(), phase2_complete, Leader#leader.node#node.leaderID, AllAdjacentClusters},
            FilteredNodes = lists:filter(
                fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                Leader#leader.nodes_in_cluster
            ),
            lists:foreach(fun(NodePid) -> NodePid ! {save_to_db_node} end, FilteredNodes),
            UpdatedLeader = Leader#leader{nodes_in_cluster = NodePIDs, adjClusters = AllAdjacentClusters},
            node:leader_loop(UpdatedLeader)
    end.

%% Propagates the setup message and handles recursive cascading.
%% @spec setup_loop_propagate(#leader{}, atom(), pid(), boolean(), list(), atom(), pid()) -> no_return()
%% @param Leader The leader record for the node.
%% @param Color Color of the node undergoing propagation.
%% @param FromPid The PID of the node initiating the propagation.
%% @param Visited Boolean flag indicating whether this node has already been visited.
%% @param Neighbors List of neighboring node PIDs.
%% @param InitiatorFlag Flag indicating whether this node is the initiator.
%% @param StartSystemPid The PID of the system start process.
%%
%% Preconditions:
%% - Leader must contain a valid node record.
%% - Color, FromPid, Visited, Neighbors, and InitiatorFlag must be valid inputs.
%%
%% Postconditions:
%% - Continues propagation to neighboring nodes and collects acknowledgement PIDs.
setup_loop_propagate(Leader, Color, FromPid, Visited, Neighbors, InitiatorFlag, StartSystemPid) ->
    Node = Leader#leader.node,
    NeighborsToSend = [N || N <- Neighbors, N =/= Node#node.parent],
    lists:foreach(fun(NeighborPid) -> NeighborPid ! {setup_node_request, Color, Node#node.leaderID, self()} end, NeighborsToSend),
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(NeighborsToSend, [], Leader, Color, FromPid, Visited, Neighbors),
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),
    case InitiatorFlag of
        initiator ->
            Leader#leader.serverID ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            FromPid ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,
    UpdatedLeader = Leader#leader{node = Node},
    setup_loop(UpdatedLeader, StartSystemPid, Visited).

%% Waits for acknowledgments from neighbors and collects their PIDs.
%% @spec wait_for_ack_from_neighbors(list(), list(), #leader{}, atom(), pid(), boolean(), list()) -> {ok, list()}
%% @param NeighborsToWaitFor List of neighboring PIDs from whom ACKs are expected.
%% @param AccumulatedPIDs List of PIDs accumulated from acknowledgments.
%% @param Node The leader node undergoing setup.
%% @param Color Color of the node.
%% @param StartSystemPid PID of the system start process.
%% @param Visited Boolean flag indicating visit status.
%% @param Neighbors List of node neighbors.
%% @return A tuple `{ok, AccumulatedPIDs}` containing the collected PIDs.
%%
%% Preconditions:
%% - `NeighborsToWaitFor` is a list of valid node PIDs.
%%
%% Postconditions:
%% - Returns a list of PIDs from neighbors that confirm the propagation.
wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors) ->
    if
        NeighborsToWaitFor =:= [] ->
            {ok, AccumulatedPIDs};
        true ->
            receive
                {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),
                    wait_for_ack_from_neighbors(RemainingNeighbors, NewAccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors);

                {FromNeighbor, ack_propagation_different_color} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(RemainingNeighbors, AccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors);

                {FromNeighbor, node_already_visited} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(RemainingNeighbors, AccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors);

                {setup_node_request, _SenderColor, _PropagatedLeaderID, FromPid} ->
                    FromPid ! {self(), node_already_visited},
                    wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors);

                _Other ->
                    {ok, AccumulatedPIDs}
            end
    end.

%% Collects unique leader IDs from adjacent clusters.
%% @spec gather_adjacent_clusters(list(), pid(), list(), list(), #leader{}) -> list()
%% @param PidList List of PIDs representing neighboring or cluster nodes.
%% @param LeaderID Leader ID of the current node.
%% @param AccumulatedClusters List of accumulated leader IDs.
%% @param NeighborsList List of neighboring nodes to exclude duplicates.
%% @param Leader The current node leader.
%% @return Returns a unique list of leader IDs for adjacent clusters.
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters, _NeighborsList, _Leader) ->
    AccumulatedClusters;
gather_adjacent_clusters([Pid | Rest], LeaderID, AccumulatedClusters, NeighborsList, Leader) ->
    Pid ! {get_leader_info, self()},
    receive
        {leader_info, NeighborLeaderID, NeighborColor} ->
            UpdatedClusters = case NeighborLeaderID =/= LeaderID of
                true -> [{Pid, NeighborColor, NeighborLeaderID} | AccumulatedClusters];
                false -> AccumulatedClusters
            end,
            UpdatedNeighborsList = [{Pid, NeighborColor, NeighborLeaderID} | NeighborsList],
            gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters, UpdatedNeighborsList, Leader);
        {get_leader_info, FromPid} ->
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color}
    after 5000 ->
        gather_adjacent_clusters(Rest, LeaderID, AccumulatedClusters, NeighborsList, Leader)
    end.


gather_adjacent_nodes([], _LeaderID, AccumulatedAdjNodes) ->
    % Se NodePIDsWithoutSelf è vuoto, restituisci AccumulatedAdjNodes senza fare nulla
    AccumulatedAdjNodes;
gather_adjacent_nodes([Pid | Rest], LeaderID, AccumulatedAdjNodes) ->
    % io:format("Recupero nodi adiacenti di ~p~n", [Pid]),
    Pid ! {get_list_neighbors, self()},
    receive
        {response_get_list_neighbors, Neighbors} ->
            % io:format("~p mi ha inviato ~p~n", [Pid, Neighbors]),
            UpdatedAccumulatedNodes = AccumulatedAdjNodes ++ Neighbors,
            gather_adjacent_nodes(Rest, LeaderID, UpdatedAccumulatedNodes)
    after 5000 ->
        gather_adjacent_nodes(Rest, LeaderID, AccumulatedAdjNodes)
    end.
-module(setup).

%% --------------------------------------------------------------------
%% Module: setup
%% Description:
%% This module implements the setup phase for a distributed system of 
%% nodes. Each node participates in a configuration process to establish 
%% connectivity with its neighbors, propagate leader and color information, 
%% and identify adjacent clusters within the network.
%%
%% Key Functions:
%% - setup_loop/3:
%%   The main loop that manages incoming setup requests, neighbor updates, 
%%   and connectivity acknowledgments. This loop enables each node to 
%%   communicate its leader and connectivity status to other nodes.
%%
%% - setup_loop_propagate/7:
%%   Manages the propagation phase, where a node sends setup requests to 
%%   neighbors, gathers acknowledgments, and informs the system of 
%%   successful setup completion.
%%
%% - wait_for_ack_from_neighbors/7:
%%   Recursively waits for acknowledgments from neighboring nodes, updating 
%%   the state based on the received messages and ensuring all expected 
%%   neighbors respond before proceeding.
%%
%% - gather_adjacent_clusters/5:
%%   Identifies clusters adjacent to the current node's cluster by requesting 
%%   leader information from neighboring nodes. Only nodes with different 
%%   leader IDs are considered part of adjacent clusters.
%%
%% - gather_adjacent_nodes/3:
%%   Collects neighboring nodes directly connected to the current node, 
%%   building a list of adjacent nodes within the cluster.
%%
%% Usage:
%% - This module is intended to be used in a distributed environment where 
%%   each node operates independently but needs to collaborate with others 
%%   to form clusters, assign leaders, and propagate connectivity data.
%% - Each function includes timeout handling for cases where a neighboring 
%%   node does not respond within the specified interval.
%%
%% Notes:
%% - This module assumes all nodes are correctly initialized and can 
%%   communicate with their neighbors.
%% - It also relies on utility functions (e.g., `utils:save_data/1` 
%%   and `utils:remove_duplicates/1`) to handle common tasks.
%%
%% --------------------------------------------------------------------


-export([setup_loop/3]).
-include("includes/node.hrl").

%% --------------------------------------------------------------------
%% Function: setup_loop/3
%% Description:
%% Main loop for the setup phase of a distributed node in the system.
%% This function handles the initial setup requests, propagates
%% information, manages neighboring nodes, and updates the system
%% about each node's connectivity and leader information.
%%
%% Input:
%% - Leader: Record holding information about the node’s leader, color, and children.
%% - StartSystemPid: Process ID for communicating the setup acknowledgments and data.
%% - Visited: Boolean indicating whether the node has been visited or processed.
%%
%% Preconditions:
%% - The setup phase has been initiated.
%% - Leader record and StartSystemPid must be valid.
%%
%% Output:
%% - No return value. The function operates in a loop to handle incoming
%%   messages for setting up the node’s initial configuration.
%% --------------------------------------------------------------------
setup_loop(Leader, StartSystemPid, Visited) ->
    %% Retrieve the current process ID for the node.
    Pid = self(),
    %% Save the Leader data for future reference.
    utils:save_data(Leader),
    receive
        {neighbors, Neighbors} ->
            %% Node receives neighbors list, updates state with neighbors,
            %% assigns itself as the leader, and sends acknowledgment.
            UpdatedNode = Leader#leader.node#node{neighbors = Neighbors, leaderID = Pid, pid = Pid},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            StartSystemPid ! {ack_neighbors, self()},
            setup_loop(UpdatedLeader, StartSystemPid, Visited);
        {setup_server_request, FromPid} ->
            %% Handles setup requests. Checks if the node is already visited.
            if
                Visited =:= true ->
                    %% Node has already been visited; sends notification back.
                    FromPid ! {self(), node_already_visited},
                    setup_loop(Leader, StartSystemPid, Visited);
                true ->
                    %% Node has not been visited; begins propagation setup as initiator.
                    setup_loop_propagate(
                        Leader#leader{serverID = FromPid},
                        Leader#leader.color,
                        self(),
                        % Marks node as visited.
                        true,
                        Leader#leader.node#node.neighbors,
                        initiator,
                        StartSystemPid
                    )
            end;
        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            %% Processes setup requests and propagates if conditions match.
            if
                Visited =:= false andalso Leader#leader.color =:= SenderColor ->
                    %% Propagation can continue; update leader with new parent and leader ID.
                    UpdatedNode = Leader#leader.node#node{
                        parent = FromPid, leaderID = PropagatedLeaderID
                    },
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    setup_loop_propagate(
                        UpdatedLeader,
                        Leader#leader.color,
                        FromPid,
                        % Marks node as visited.
                        true,
                        Leader#leader.node#node.neighbors,
                        non_initiator,
                        StartSystemPid
                    );
                Visited =:= true ->
                    %% Node has already been visited; notifies sender.
                    FromPid ! {self(), node_already_visited},
                    setup_loop(Leader, StartSystemPid, Visited);
                true ->
                    %% Node does not match the color; only acknowledges request.
                    FromPid ! {self(), ack_propagation_different_color},
                    setup_loop(Leader, StartSystemPid, Visited)
            end;
        {get_list_neighbors, FromPid} ->
            %% Returns the list of neighbors to the requesting node.
            FromPid ! {response_get_list_neighbors, Leader#leader.node#node.neighbors},
            node:leader_loop(Leader);
        {get_leader_info, FromPid} ->
            %% Sends leader information (leader ID and color) to the requester.
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
            setup_loop(Leader, StartSystemPid, Visited);
        {add_child, ChildPid} ->
            %% Adds a child PID to the node's list of children.
            UpdatedChildren = [ChildPid | Leader#leader.node#node.children],
            UpdatedNode = Leader#leader.node#node{children = UpdatedChildren},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            setup_loop(UpdatedLeader, StartSystemPid, Visited);
        {start_phase2, NodePIDs} ->
            %% Initiates Phase 2, configuring adjacent nodes and clusters.
            ServerPid = Leader#leader.serverID,
            NodePIDsWithoutSelf = lists:delete(self(), NodePIDs),
            %% Gathers adjacent nodes for cluster connection.
            AdjNodesToCluster = gather_adjacent_nodes(
                NodePIDsWithoutSelf,
                Leader#leader.node#node.leaderID,
                Leader#leader.node#node.neighbors
            ),
            AdjNodesToCluster_no_duplicates = utils:remove_duplicates(AdjNodesToCluster),
            %% Gathers information on adjacent clusters.
            AllAdjacentClusters = gather_adjacent_clusters(
                lists:delete(self(), AdjNodesToCluster_no_duplicates),
                Leader#leader.node#node.leaderID,
                [],
                [],
                Leader
            ),
            %% Notifies the server of Phase 2 completion and adjacent clusters.
            ServerPid !
                {self(), phase2_complete, Leader#leader.node#node.leaderID, AllAdjacentClusters},
            %% Filters nodes, excluding the current node, and stores data in the database.
            FilteredNodes = lists:filter(
                fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                Leader#leader.nodes_in_cluster
            ),
            %% Saves each node's state in the database.
            lists:foreach(fun(NodePid) -> NodePid ! {save_to_db_node} end, FilteredNodes),
            %% Updates leader with nodes in the cluster and adjacent clusters.
            UpdatedLeader = Leader#leader{
                nodes_in_cluster = NodePIDs, adjClusters = AllAdjacentClusters
            },
            node:leader_loop(UpdatedLeader)
    end.

%% --------------------------------------------------------------------
%% Function: setup_loop_propagate/7
%% Description:
%% This function manages the propagation phase of the setup loop, where
%% a node communicates with its neighbors to establish connectivity and
%% leader information. Each neighboring node that isn't the parent is
%% sent a setup request.
%%
%% Input:
%% - Leader: Current leader record of the node initiating propagation.
%% - Color: Color associated with the leader or node.
%% - FromPid: PID of the sender process initiating this setup.
%% - Visited: Boolean indicating whether the node has been visited.
%% - Neighbors: List of neighboring PIDs to communicate with.
%% - InitiatorFlag: Specifies if the node is the initiator of this setup phase.
%% - StartSystemPid: PID of the process managing the system start phase.
%%
%% Preconditions:
%% - Leader, Neighbors, and other parameters must be valid and initialized.
%% - The initiating node is prepared to propagate setup information.
%%
%% Output:
%% - No return value. This function propagates setup information and then
%%   calls the main `setup_loop` with the updated state.
%% --------------------------------------------------------------------
setup_loop_propagate(Leader, Color, FromPid, Visited, Neighbors, InitiatorFlag, StartSystemPid) ->
    %% Retrieve the node information from the Leader record.
    Node = Leader#leader.node,

    %% Filter out the parent node from neighbors, to avoid sending requests back.
    NeighborsToSend = [N || N <- Neighbors, N =/= Node#node.parent],

    %% Send the setup request to each valid neighboring node.
    lists:foreach(
        fun(NeighborPid) ->
            NeighborPid ! {setup_node_request, Color, Node#node.leaderID, self()}
        end,
        NeighborsToSend
    ),

    %% Wait for acknowledgments from the neighbors to proceed with setup.
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(
        NeighborsToSend, [], Leader, Color, FromPid, Visited, Neighbors
    ),

    %% Combine accumulated PIDs with the current node’s PID.
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),

    %% Handle the response based on whether the node is the initiator or not.
    case InitiatorFlag of
        initiator ->
            %% If initiator, notify the server of setup completion.
            Leader#leader.serverID ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            %% If non-initiator, send an acknowledgment with combined PIDs to the sender.
            FromPid ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,

    %% Update the leader record with the node information (preserving state).
    UpdatedLeader = Leader#leader{node = Node},

    %% Continue the setup loop with the updated leader and visited status.
    setup_loop(UpdatedLeader, StartSystemPid, Visited).

%% --------------------------------------------------------------------
%% Function: wait_for_ack_from_neighbors/7
%% Description:
%% Recursively waits for acknowledgment messages from neighboring nodes
%% during the setup phase. Based on the message type received, the
%% function updates the list of remaining neighbors and accumulated PIDs.
%%
%% Input:
%% - NeighborsToWaitFor: List of neighboring PIDs to wait for acknowledgments.
%% - AccumulatedPIDs: List of accumulated PIDs from neighbors with matching color.
%% - Node: The current node record.
%% - Color: Color associated with the current node.
%% - StartSystemPid: PID of the process managing the system start phase.
%% - Visited: Boolean indicating if the node has been visited.
%% - Neighbors: List of all neighboring nodes of the current node.
%%
%% Preconditions:
%% - NeighborsToWaitFor is a valid list of PIDs.
%% - AccumulatedPIDs is initialized, even if empty.
%%
%% Output:
%% - Returns `{ok, AccumulatedPIDs}` once all acknowledgments are received
%%   or there are no neighbors to wait for.
%% --------------------------------------------------------------------
wait_for_ack_from_neighbors(
    NeighborsToWaitFor, AccumulatedPIDs, Node, Color, StartSystemPid, Visited, Neighbors
) ->
    if
        %% If there are no more neighbors to wait for, return accumulated PIDs.
        NeighborsToWaitFor =:= [] ->
            {ok, AccumulatedPIDs};
        true ->
            receive
                {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                    %% Received acknowledgment with same color from neighbor.
                    %% Update the list of remaining neighbors and add NeighborPIDs.
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        NewAccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                {FromNeighbor, ack_propagation_different_color} ->
                    %% Received acknowledgment with different color; remove from wait list.
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                {FromNeighbor, node_already_visited} ->
                    %% Neighbor node is already visited; remove from wait list.
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                {setup_node_request, _SenderColor, _PropagatedLeaderID, FromPid} ->
                    %% Received a setup request; reply with already visited status.
                    FromPid ! {self(), node_already_visited},
                    wait_for_ack_from_neighbors(
                        NeighborsToWaitFor,
                        AccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                _Other ->
                    %% Unexpected message received; terminate with current AccumulatedPIDs.
                    {ok, AccumulatedPIDs}
            end
    end.

%% --------------------------------------------------------------------
%% Function: gather_adjacent_clusters/5
%% Description:
%% This function gathers information about clusters adjacent to the node's
%% cluster. It requests leader information from each neighboring node and
%% accumulates those with different leader IDs to build a list of
%% adjacent clusters.
%%
%% Input:
%% - Rest: List of remaining PIDs of nodes to query for adjacency.
%% - LeaderID: Leader ID of the current node's cluster.
%% - AccumulatedClusters: List of clusters already identified as adjacent.
%% - NeighborsList: List of neighboring nodes (used for internal updates).
%% - Leader: Current node's leader record for information reference.
%%
%% Preconditions:
%% - Each PID in Rest should be a valid neighbor PID.
%% - The leader information should be accessible by each node queried.
%%
%% Output:
%% - Returns a list of adjacent clusters in the format `{PID, Color, LeaderID}`.
%% --------------------------------------------------------------------
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters, _NeighborsList, _Leader) ->
    %% Base case: No more PIDs to process, return accumulated clusters.
    AccumulatedClusters;
gather_adjacent_clusters([Pid | Rest], LeaderID, AccumulatedClusters, NeighborsList, Leader) ->
    %% Send request for leader information to the neighboring PID.
    Pid ! {get_leader_info, self()},
    receive
        {leader_info, NeighborLeaderID, NeighborColor} ->
            %% If received leader info, check if the leader ID differs.
            UpdatedClusters =
                case NeighborLeaderID =/= LeaderID of
                    true -> [{Pid, NeighborColor, NeighborLeaderID} | AccumulatedClusters];
                    false -> AccumulatedClusters
                end,
            %% Update neighbors list with the current neighbor’s info.
            UpdatedNeighborsList = [{Pid, NeighborColor, NeighborLeaderID} | NeighborsList],
            %% Recursively gather adjacent clusters for the remaining PIDs.
            gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters, UpdatedNeighborsList, Leader);
        {get_leader_info, FromPid} ->
            %% Handle a request for leader info; respond with own leader details.
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color}
    after 5000 ->
        %% Timeout case: Proceed without response from this PID.
        gather_adjacent_clusters(Rest, LeaderID, AccumulatedClusters, NeighborsList, Leader)
    end.

%% --------------------------------------------------------------------
%% Function: gather_adjacent_nodes/3
%% Description:
%% This function gathers neighboring nodes by querying each PID for its
%% list of adjacent nodes, effectively building a complete set of all
%% directly connected nodes within the cluster.
%%
%% Input:
%% - Rest: List of PIDs of nodes to query for adjacency.
%% - LeaderID: Leader ID of the current node's cluster.
%% - AccumulatedAdjNodes: List of adjacent nodes accumulated so far.
%%
%% Preconditions:
%% - Each PID in Rest should be a valid neighbor PID.
%%
%% Output:
%% - Returns an updated list of adjacent nodes.
%% --------------------------------------------------------------------
gather_adjacent_nodes([], _LeaderID, AccumulatedAdjNodes) ->
    %% Base case: No more PIDs to process, return accumulated adjacent nodes.
    AccumulatedAdjNodes;
gather_adjacent_nodes([Pid | Rest], LeaderID, AccumulatedAdjNodes) ->
    %% Request the list of neighbors from the current PID.
    Pid ! {get_list_neighbors, self()},
    receive
        {response_get_list_neighbors, Neighbors} ->
            %% Append received neighbors to the accumulated nodes list.
            UpdatedAccumulatedNodes = AccumulatedAdjNodes ++ Neighbors,
            %% Recursively gather adjacent nodes for the remaining PIDs.
            gather_adjacent_nodes(Rest, LeaderID, UpdatedAccumulatedNodes)
    after 5000 ->
        %% Timeout case: Proceed without response from this PID.
        gather_adjacent_nodes(Rest, LeaderID, AccumulatedAdjNodes)
    end.

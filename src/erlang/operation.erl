-module(operation).

%% Module Description:
%% The `operation` module provides functions for managing cluster operations 
%% within a distributed system. It handles cluster color changes, merging adjacent 
%% clusters with similar attributes, and promotes nodes to leaders when necessary.
%%
%% This module includes three primary groups of operations:
%%
%% 1. **Color Change**: Functions related to changing the color of a cluster.
%%    - The `change_color/2` function initiates a color change for a cluster, 
%%      updates the leader’s state, and coordinates with adjacent clusters that 
%%      have the same color. 
%%
%% 2. **Merge Utilities**: Functions that handle merging adjacent clusters.
%%    - The module includes utilities for merging clusters, updating color and 
%%      leader information within clusters, and managing the adjacency lists.
%%    - `merge_adjacent_clusters/4` initiates a merge with each adjacent cluster 
%%      that shares the same color, creating a unified structure within the distributed 
%%      system.
%%
%% 3. **Recovery Utilities**: Functions that promote a regular node to a leader 
%%    when needed for cluster recovery or restructuring.
%%    - `promote_to_leader/5` transforms a node into a leader, updating it with 
%%      essential cluster and adjacency information, ensuring the continuity of 
%%      cluster management.
%%
%% The `operation` module works in conjunction with adjacent modules, including
%% `utils` for helper functions and `event` for event tracking, to facilitate smooth 
%% communication and robust management of clusters in the system.

% color change
-export([change_color/2]).

% merge utilities
-export([
    merge_adjacent_clusters/4,
    update_adj_cluster_color/4,
    update_existing_node/4,
    remove_cluster_from_adjacent/2,
    update_adjacent_cluster_info/3
]).
% recovery utilities
-export([promote_to_leader/5]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% ------------------
%%    COLOR CHANGE
%% ------------------

%% The leader performs a color change
%% @doc Changes the color of a leader’s cluster and initiates a merge process if adjacent clusters have the same color.
%% @spec change_color(#leader{}, #event{}) -> #leader{}
%% @param Leader The leader record representing the cluster leader.
%% @param Event The event containing the new color information.
%% @return Returns an updated leader record after color change and any necessary merges.
%%
%% Preconditions:
%% - Leader is a valid leader record with initialized state.
%% - Event contains a color that can be assigned to the cluster.
%%
%% Postconditions:
%% - Updates the leader's color and initiates merges with adjacent clusters of the same color.
change_color(Leader, Event) ->
    Color = Event#event.color,
    ColorAtom = utils:normalize_color(Color),

    %% Update the color and last event of the leader
    UpdatedLeader1 = Leader#leader{color = ColorAtom, last_event = Event},

    CurrentLeaderID = Leader#leader.node#node.leaderID,

    % Gather adjacent clusters with the same color but a different leader ID
    SameColorAdjClusters = utils:unique_leader_clusters(
        [{NeighborPid, NeighborColor, LeaderID}
         || {NeighborPid, NeighborColor, LeaderID} <- Leader#leader.adjClusters,
            NeighborColor == ColorAtom,
            LeaderID =/= CurrentLeaderID]
    ),

    % Extract LeaderIDs from clusters with the same color
    LeaderIDs = [LeaderID || {_, _, LeaderID} <- SameColorAdjClusters],

    UpdatedLeader2 =
        case SameColorAdjClusters of
            [] ->
                UpdatedLeader1#leader{merge_in_progress = false};  % No merge to perform
            _ ->
                % Set merge_in_progress to true before starting merges
                UpdatedLeaderWithFlag = UpdatedLeader1#leader{merge_in_progress = true},
                merge_adjacent_clusters(SameColorAdjClusters, UpdatedLeaderWithFlag, LeaderIDs, Event)
        end,

    % Send updated color information to adjacent clusters
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            io:format("Sending color update to ~p from ~p: color=~p, nodes_in_cluster=~p~n",
                [OtherLeaderID, self(), UpdatedLeader2#leader.color, UpdatedLeader2#leader.nodes_in_cluster]),
            OtherLeaderID ! {color_adj_update, self(), UpdatedLeader2#leader.color,
                UpdatedLeader2#leader.nodes_in_cluster}
        end,
        UpdatedLeader2#leader.adjClusters
    ),

    % Notify the server about the color change completion
    UpdatedLeader2#leader.serverID ! {change_color_complete, self(), UpdatedLeader2},
    UpdatedLeader2.


%% ------------------
%%   MERGE UTILITIES
%% ------------------

%% Sequentially merges adjacent clusters with the same color
%% @doc Merges each adjacent cluster with the same color into the current leader’s cluster.
%% @spec merge_adjacent_clusters(list(), #leader{}, list(), #event{}) -> #leader{}
%% @param SameColorAdjClusters A list of adjacent clusters with the same color.
%% @param Leader The leader record of the current cluster.
%% @param LeaderIDs A list of leader IDs for adjacent clusters with the same color.
%% @param Event The event initiating the merge.
%% @return Returns an updated leader record after merging.
%%
%% Preconditions:
%% - Leader and Event are valid records.
%% - SameColorAdjClusters is a list of clusters adjacent to the leader.
%%
%% Postconditions:
%% - Adjacent clusters with the same color are merged into the leader's cluster.
merge_adjacent_clusters([], Leader, _LeaderIDs, _Event) ->
    % Merge completed or no clusters to merge; reset merge_in_progress
    Leader#leader{merge_in_progress = false};

merge_adjacent_clusters([{_NeighborPid, _NeighborColor, AdjLeaderID} | Rest], Leader, LeaderIDs, Event) ->
    % Set merge_in_progress to true before initiating merge
    UpdatedLeader = Leader#leader{merge_in_progress = true},
    AdjLeaderID ! {merge_request, self(), Event},
    NewLeader = wait_for_merge_response(AdjLeaderID, UpdatedLeader, LeaderIDs, Event),
    merge_adjacent_clusters(Rest, NewLeader, LeaderIDs, Event).

wait_for_merge_response(AdjLeaderID, Leader, LeaderIDs, Event) ->
    receive
        {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore, FromPid} when FromPid == AdjLeaderID ->
            % Proceed with merging clusters
            UpdatedAdjClusters = utils:join_adj_clusters(Leader#leader.adjClusters, AdjListIDMaggiore),
            FilteredAdjClusters = lists:filter(
                fun({_, _, LeaderID}) ->
                    not lists:member(LeaderID, LeaderIDs) andalso
                    LeaderID =/= Leader#leader.node#node.leaderID andalso
                    LeaderID =/= AdjLeaderID
                end,
                UpdatedAdjClusters
            ),
            UpdatedNodeList = utils:join_nodes_list(Leader#leader.nodes_in_cluster, Nodes_in_Cluster),
            UpdatedLeader = Leader#leader{
                adjClusters = FilteredAdjClusters,
                nodes_in_cluster = UpdatedNodeList
            },
            FromPid ! {became_node, self()},
            wait_for_turn_to_node(AdjLeaderID, UpdatedLeader, LeaderIDs, Event);

        {merge_rejected, FromPid} when FromPid == AdjLeaderID ->
            % Merge was rejected; reset merge_in_progress
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            UpdatedLeader;

        {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
            UpdatedLeader = handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster),
            wait_for_merge_response(AdjLeaderID, UpdatedLeader, LeaderIDs, Event)

    after 5000 ->
        % Timeout occurred; reset merge_in_progress
        UpdatedLeader = Leader#leader{merge_in_progress = false},
        UpdatedLeader
    end.


wait_for_turn_to_node(AdjLeaderID, Leader, LeaderIDs, Event) ->
    receive
        {turned_to_node, FromPid} when FromPid == AdjLeaderID ->
            % Merge completed successfully; no action needed
            Leader;

        {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
            UpdatedLeader = handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster),
            wait_for_turn_to_node(AdjLeaderID, UpdatedLeader, LeaderIDs, Event)

    after 4000 ->
        % Timeout occurred; reset merge_in_progress
        UpdatedLeader = Leader#leader{merge_in_progress = false},
        UpdatedLeader
    end.

handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster) ->
    % Print initial state before updating adjClusters
    io:format("Before update: Leader PID=~p, From PID=~p, Color=~p, Nodes_in_Cluster=~p, adjClusters=~p~n", 
              [self(), FromPid, Color, Nodes_in_Cluster, Leader#leader.adjClusters]),
    
    % Update the color of a specific cluster in the adjacency list
    UpdatedAdjClusters = operation:update_adj_cluster_color(
        Leader#leader.adjClusters, Nodes_in_Cluster, Color, FromPid
    ),
    
    % Log the state after updating adjClusters
    io:format("After update: Leader PID=~p, Updated Color=~p, Updated adjClusters=~p~n",
              [self(), Color, UpdatedAdjClusters]),
    
    % Create a new event
    Event1 = event:new(change_color, Color, FromPid),
    
    % Update the Leader record with new adjClusters and last_event
    UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters, last_event = Event1},
    
    % Send the updated adjacency clusters to the server
    io:format("Sending updated_AdjClusters to server: Server PID=~p, From PID=~p, UpdatedLeader=~p~n",
              [UpdatedLeader#leader.serverID, self(), UpdatedLeader]),
    
    UpdatedLeader#leader.serverID ! {updated_AdjClusters, self(), UpdatedLeader},
    
    % Return the updated leader
    UpdatedLeader.



%% Updates the color and leader ID of nodes in the adjacency list
%% @spec update_adj_cluster_color(list(), list(), atom(), pid()) -> list()
%% @param AdjClusters The list of adjacent clusters.
%% @param NodesInCluster The list of nodes in the leader’s cluster.
%% @param NewColor The new color to assign.
%% @param NewLeaderID The new leader ID.
%% @return Returns the updated adjacency list.
update_adj_cluster_color(AdjClusters, NodesInCluster, NewColor, NewLeaderID) ->
    lists:foldl(
        fun(NodeID, UpdatedAdjClusters) ->
            update_existing_node(UpdatedAdjClusters, NodeID, NewColor, NewLeaderID)
        end,
        AdjClusters,
        NodesInCluster
    ).

%% Updates a specific node in the adjacency list with new color and leader ID
%% @spec update_existing_node(list(), pid(), atom(), pid()) -> list()
%% @param AdjClusters The adjacency list of clusters.
%% @param NodeID The ID of the node to update.
%% @param NewColor The new color to assign.
%% @param NewLeaderID The new leader ID.
%% @return Returns an updated adjacency list.
update_existing_node([], _NodeID, _NewColor, _NewLeaderID) ->
    []; % If adjacency list is empty, return an empty list
update_existing_node([{NodeID, _OldColor, _OldLeaderID} | Rest], NodeID, NewColor, NewLeaderID) ->
    [{NodeID, NewColor, NewLeaderID} | Rest];
update_existing_node([Other | Rest], NodeID, NewColor, NewLeaderID) ->
    [Other | update_existing_node(Rest, NodeID, NewColor, NewLeaderID)].

%% Removes a cluster from the adjacency list
%% @spec remove_cluster_from_adjacent(pid(), list()) -> list()
%% @param DeadLeaderPid The PID of the dead leader to remove.
%% @param AdjacentClusters The adjacency list of clusters.
%% @return Returns the updated adjacency list without the removed cluster.
remove_cluster_from_adjacent(DeadLeaderPid, AdjacentClusters) ->
    lists:filter(
        fun({Pid, _Color, _LeaderID}) ->
            Pid =/= DeadLeaderPid
        end,
        AdjacentClusters
    ).

%% Updates the adjacency list with new leader information
%% @spec update_adjacent_cluster_info(pid(), map(), list()) -> list()
%% @param NewLeaderPid The PID of the new leader.
%% @param UpdatedClusterInfo A map with updated cluster information.
%% @param AdjacentClusters The current adjacency list.
%% @return Returns the updated adjacency list.
update_adjacent_cluster_info(NewLeaderPid, UpdatedClusterInfo, AdjacentClusters) ->
    AdjClustersWithoutOld = remove_cluster_from_adjacent(NewLeaderPid, AdjacentClusters),
    NewColor = utils:normalize_color(maps:get(color, UpdatedClusterInfo)),
    NewLeaderID = maps:get(leader_id, UpdatedClusterInfo, NewLeaderPid),
    NewEntry = {NewLeaderPid, NewColor, NewLeaderID},
    [NewEntry | AdjClustersWithoutOld].

%% ------------------
%%   RECOVERY UTILITIES
%% ------------------

%% Promotes a node to a leader using specified information.
%% @doc Promotes a node to leader and populates the leader’s record with cluster and adjacency information.
%% @spec promote_to_leader(#node{}, atom(), pid(), list(), list()) -> #leader{}
%% @param Node The node record to promote to leader.
%% @param Color The color to assign to the new leader.
%% @param ServerPid The PID of the server.
%% @param NodesInCluster The list of nodes in the new leader’s cluster.
%% @param AdjacentClusters The list of adjacent clusters.
%% @return Returns a leader record populated with specified parameters.
%%
%% Preconditions:
%% - Node is a valid node record.
%% - Color is a valid atom representing the color.
%% - ServerPid, NodesInCluster, and AdjacentClusters are correctly initialized.
%%
%% Postconditions:
%% - Returns a new leader record with updated adjacency and node information.
promote_to_leader(Node, Color, ServerPid, NodesInCluster, AdjacentClusters) ->
    Leader = #leader{
        node = Node#node{leaderID = Node#node.pid},
        color = Color,
        serverID = ServerPid,
        last_event = event:new(),
        adjClusters = AdjacentClusters,
        nodes_in_cluster = NodesInCluster
    },
    Leader.

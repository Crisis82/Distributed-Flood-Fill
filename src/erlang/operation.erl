-module(operation).

%% --------------------------------------------------------------------
%% Module: operation
%% Description:
%% The `operation` module provides a collection of functions for managing
%% color changes, merges, and recovery operations in a distributed cluster
%% system. Key responsibilities include updating and broadcasting color
%% changes, managing adjacent cluster relationships, and promoting nodes to
%% leaders as needed for recovery.

%% Key Functional Areas:
%% - **Color Change Management**:
%%   Functions such as `change_color/2` and `do_change_color/2` enable leaders
%%   to update their color and propagate these updates to adjacent clusters.
%%   These functions help to maintain color consistency and avoid conflicts
%%   across the network.

%% - **Merge Utilities**:
%%   Functions like `merge_adjacent_clusters/4` and `wait_for_merge_response/4`
%%   handle the merging of clusters when adjacent clusters share the same color.
%%   These utilities coordinate merging operations, ensuring that nodes and
%%   adjacency lists are correctly updated as clusters merge or reorganize.

%% - **Recovery Utilities**:
%%   Functions such as `promote_to_leader/5` allow the system to recover
%%   from leader failures by promoting eligible nodes to new leaders.
%%   This ensures that each cluster has an active leader to manage it and
%%   continue communication with other clusters.

%% Exported Functions:
%% - **change_color/2**: Initiates a color change for a leader and propagates
%%   the update to adjacent clusters and the server.
%% - **merge_adjacent_clusters/4**: Initiates the merging process between a
%%   leader and adjacent clusters with the same color.
%% - **remove_cluster_from_adjacent/2**: Removes a specified cluster from the
%%   adjacency list of clusters, typically due to a leader’s failure.
%% - **promote_to_leader/5**: Promotes a node to a leader, initializing its
%%   record with specific cluster and adjacency information.

%% Usage:
%% - The module is utilized by leaders to perform regular maintenance on
%%   clusters, ensuring color consistency and proper adjacency management.
%% - It plays a crucial role in handling cluster recovery, enabling seamless
%%   transitions when leaders fail or new leaders are elected.
%% --------------------------------------------------------------------


% color change
-export([change_color/2,
        send_periodic_updates/1,
        broadcast_leader_update/1]).

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

%% --------------------------------------------------------------------
%% Function: change_color/2
%% Description:
%% Updates the color of a leader and propagates this change to all
%% adjacent clusters. This function modifies the leader’s color based on
%% the specified event and notifies both adjacent clusters and the server
%% to ensure consistent color information across the network.
%%
%% Input:
%% - Leader: The current leader record (#leader{}) whose color is being updated.
%% - Event: An #event{} record that includes the new color and metadata for the color change.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with an initialized `adjClusters` field.
%% - Event must be a valid #event{} record with a color specified for the update.
%%
%% Output:
%% - Returns the updated leader record (#leader{}) with the new color applied.
%%
%% Usage:
%% - This function is typically called when a color conflict is detected between
%%   adjacent clusters. After updating the color, the function ensures that adjacent
%%   clusters are notified and the server is aware of the completed update.
%%
%% Side Effects:
%% - Sends `{color_adj_update, Self, NewColor, NodesInCluster}` messages to each
%%   adjacent leader, informing them of the new color and nodes in the cluster.
%% - Sends `{change_color_complete, Self, UpdatedLeader}` to the server upon
%%   completion of the color update.
%% --------------------------------------------------------------------
change_color(Leader, Event) ->
    %% Apply the color change to the leader using do_change_color/2.
    UpdatedLeader = do_change_color(Leader, Event),

    %% Send the updated color information to all adjacent clusters.
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            % io:format("Sending color update to ~p from ~p: color=~p, nodes_in_cluster=~p~n",
            %    [OtherLeaderID, self(), UpdatedLeader#leader.color, UpdatedLeader#leader.nodes_in_cluster]),
            OtherLeaderID ! {color_adj_update, self(), UpdatedLeader#leader.color,
                UpdatedLeader#leader.nodes_in_cluster}
        end,
        UpdatedLeader#leader.adjClusters
    ),

    %% Notify the server that the color change is complete.
    UpdatedLeader#leader.serverID ! {change_color_complete, self(), UpdatedLeader},

    %% Return the updated leader record.
    UpdatedLeader.




%% --------------------------------------------------------------------
%% Function: do_change_color/2
%% Description:
%% Applies a color change to a leader, updating adjacent clusters with the
%% same color and handling merge operations when necessary. The function
%% updates the leader's color based on the specified event, sets a merge
%% flag if there are clusters to merge, and recursively checks for further
%% color conflicts among adjacent clusters after each merge.
%%
%% Input:
%% - Leader: The #leader{} record to be updated, containing the current color,
%%   adjacency data, and other cluster metadata.
%% - Event: The #event{} record specifying the new color and other event metadata.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with initialized fields, including
%%   `adjClusters` and `node`.
%% - Event must be a valid #event{} record with a color to apply to the leader.
%%
%% Output:
%% - Returns the fully updated #leader{} record with the new color applied and
%%   any necessary merges completed.
%%
%% Side Effects:
%% - Calls `merge_adjacent_clusters/4` to handle merge operations between clusters
%%   when adjacent clusters with the same color but different leader IDs are found.
%% - Recursively calls itself if further adjacent clusters with the same color are
%%   found after an initial merge.
%%
%% Usage:
%% - This function is typically used during a color change event to ensure that
%%   all clusters adjacent to the leader are properly merged or updated. It is
%%   designed to handle cases where multiple adjacent clusters have the same color,
%%   requiring iterative merges.
%%
%% Notes:
%% - The function uses `utils:unique_leader_clusters/1` to filter out duplicate
%%   clusters by leader ID, ensuring that merges are performed only with unique
%%   clusters.
%% - The `merge_in_progress` flag is set to true during the merge process to prevent
%%   other operations from interfering with the current merge.
%% --------------------------------------------------------------------
do_change_color(Leader, Event) ->
    %% Retrieve and normalize the new color from the event.
    Color = Event#event.color,
    ColorAtom = utils:normalize_color(Color),
    
    %% Update the leader's color and record the last event.
    UpdatedLeader1 = Leader#leader{color = ColorAtom, last_event = Event},
    
    %% Retrieve the current leader ID.
    CurrentLeaderID = Leader#leader.node#node.leaderID,
    
    %% Gather adjacent clusters that have the same color but a different leader ID.
    SameColorAdjClusters = utils:unique_leader_clusters(
        [{NeighborPid, NeighborColor, LeaderID}
         || {NeighborPid, NeighborColor, LeaderID} <- UpdatedLeader1#leader.adjClusters,
            NeighborColor == ColorAtom,
            LeaderID =/= CurrentLeaderID]
    ),
    
    %% Extract LeaderIDs from clusters with the same color.
    LeaderIDs = [LeaderID || {_, _, LeaderID} <- SameColorAdjClusters],
    
    %% Determine if a merge is required based on adjacent clusters with the same color.
    UpdatedLeader2 =
        case SameColorAdjClusters of
            [] ->
                %% No clusters to merge, set merge_in_progress to false.
                UpdatedLeader1#leader{merge_in_progress = false};
            _ ->
                %% Set merge_in_progress to true and initiate the merge process.
                UpdatedLeaderWithFlag = UpdatedLeader1#leader{merge_in_progress = true},
                merge_adjacent_clusters(SameColorAdjClusters, UpdatedLeaderWithFlag, LeaderIDs, Event)
        end,
    
    %% Recheck for any adjacent clusters with the same color after the initial merge.
    MoreSameColorAdjClusters = utils:unique_leader_clusters(
        [{NeighborPid, NeighborColor, LeaderID}
         || {NeighborPid, NeighborColor, LeaderID} <- UpdatedLeader2#leader.adjClusters,
            NeighborColor == UpdatedLeader2#leader.color,
            LeaderID =/= UpdatedLeader2#leader.node#node.leaderID]
    ),
    
    %% Handle additional merges if necessary, or return the updated leader.
    case MoreSameColorAdjClusters of
        [] ->
            %% No additional clusters to merge, return the updated leader.
            UpdatedLeader2;
        _ ->
            %% Recursively call do_change_color to handle further merges.
            do_change_color(UpdatedLeader2, Event)
    end.


%% ------------------
%%   MERGE UTILITIES
%% ------------------

%% --------------------------------------------------------------------
%% Function: merge_adjacent_clusters/4
%% Description:
%% Initiates the merging process between a leader and its adjacent clusters
%% with the same color. This function iteratively sends merge requests to each
%% adjacent cluster and waits for their response. If a merge is successful, it
%% combines the adjacent cluster nodes and adjacency lists into the leader’s
%% data. If no clusters are available for merging, or the merge is rejected,
%% `merge_in_progress` is reset.
%%
%% Input:
%% - Leader: The #leader{} record of the current leader initiating merges.
%% - AdjacentClusters: List of adjacent clusters identified for potential merging,
%%   each item in the format `{NeighborPid, NeighborColor, LeaderID}`.
%% - LeaderIDs: List of LeaderIDs representing unique leaders of adjacent clusters.
%% - Event: The #event{} record that triggered the merge request.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with initialized adjacency data.
%% - AdjacentClusters must contain tuples with PIDs, colors, and leader IDs of adjacent clusters.
%% - LeaderIDs must be a list of unique leader IDs for identifying clusters.
%% - Event must be a valid #event{} record representing the merge initiation event.
%%
%% Output:
%% - Returns the updated #leader{} record with merged nodes and adjacency lists,
%%   or with `merge_in_progress` reset if no merges were performed.
%%
%% Side Effects:
%% - Sends `{merge_request, self(), Event}` messages to adjacent clusters.
%% - Calls `wait_for_merge_response/4` to handle each merge response.
%%
%% Usage:
%% - This function is invoked when a color change event identifies adjacent clusters
%%   with the same color, and a merge needs to be attempted.
%% --------------------------------------------------------------------
merge_adjacent_clusters([], Leader, _LeaderIDs, _Event) ->
    %% Merge completed or no clusters to merge; reset merge_in_progress.
    Leader#leader{merge_in_progress = false};

merge_adjacent_clusters([{_NeighborPid, _NeighborColor, AdjLeaderID} | Rest], Leader, LeaderIDs, Event) ->
    %% Set merge_in_progress to true before initiating merge.
    UpdatedLeader = Leader#leader{merge_in_progress = true},

    %% Send a merge request to the adjacent leader.
    AdjLeaderID ! {merge_request, self(), Event},

    %% Wait for the response from the adjacent leader.
    NewLeader = wait_for_merge_response(AdjLeaderID, UpdatedLeader, LeaderIDs, Event),

    %% Recursively process the next adjacent cluster for merging.
    merge_adjacent_clusters(Rest, NewLeader, LeaderIDs, Event).

%% --------------------------------------------------------------------
%% Function: wait_for_merge_response/4
%% Description:
%% Awaits and processes the response from an adjacent leader to a merge request.
%% If the merge is accepted, it updates the leader’s node list and adjacency list
%% with the merged data. If the merge is rejected or times out, it resets
%% `merge_in_progress`. This function also handles adjacency updates when notified
%% of color changes.
%%
%% Input:
%% - AdjLeaderID: The PID of the adjacent leader to wait for a response from.
%% - Leader: The #leader{} record of the current leader awaiting the merge response.
%% - LeaderIDs: List of unique leader IDs for filtering adjacency lists.
%% - Event: The #event{} record that triggered the merge request.
%%
%% Preconditions:
%% - AdjLeaderID must be a PID representing an adjacent cluster leader.
%% - Leader must be a valid #leader{} record with initialized adjacency and node lists.
%% - LeaderIDs must be a list of unique leader IDs for adjacency filtering.
%% - Event must be a valid #event{} record representing the merge initiation event.
%%
%% Output:
%% - Returns the updated #leader{} record reflecting the result of the merge attempt.
%%
%% Side Effects:
%% - Modifies `adjClusters` and `nodes_in_cluster` of the leader if the merge succeeds.
%% - Calls `wait_for_turn_to_node/4` if a merge requires further processing.
%%
%% Usage:
%% - This function is called by `merge_adjacent_clusters/4` after a merge request
%%   to process the adjacent leader's response.
%% --------------------------------------------------------------------

wait_for_merge_response(AdjLeaderID, Leader, LeaderIDs, Event) ->
    receive
        %% Successful merge response, proceed with merging clusters.
        {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore, FromPid} when FromPid == AdjLeaderID ->
            %% Update the adjacency list with merged data, excluding current leader and adjacent leader IDs.
            UpdatedAdjClusters = utils:join_adj_clusters(Leader#leader.adjClusters, AdjListIDMaggiore),
            FilteredAdjClusters = lists:filter(
                fun({_, _, LeaderID}) ->
                    not lists:member(LeaderID, LeaderIDs) andalso
                    LeaderID =/= Leader#leader.node#node.leaderID andalso
                    LeaderID =/= AdjLeaderID
                end,
                UpdatedAdjClusters
            ),

            %% Merge node lists of the leader and adjacent cluster.
            UpdatedNodeList = utils:join_nodes_list(Leader#leader.nodes_in_cluster, Nodes_in_Cluster),
            UpdatedLeader = Leader#leader{
                adjClusters = FilteredAdjClusters,
                nodes_in_cluster = UpdatedNodeList
            },

            %% Notify the adjacent leader that it has become a node.
            FromPid ! {became_node, self()},

            %% Proceed to turn the adjacent leader into a node.
            wait_for_turn_to_node(AdjLeaderID, UpdatedLeader, LeaderIDs, Event);

        %% Merge was rejected; reset merge_in_progress.
        {merge_rejected, FromPid} when FromPid == AdjLeaderID ->
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            UpdatedLeader;

        %% Handle color adjacency update from a different leader.
        {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
            UpdatedLeader = handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster),
            wait_for_merge_response(AdjLeaderID, UpdatedLeader, LeaderIDs, Event)

    after 5000 ->
        %% Timeout occurred; reset merge_in_progress.
        UpdatedLeader = Leader#leader{merge_in_progress = false},
        UpdatedLeader
    end.

%% --------------------------------------------------------------------
%% Function: wait_for_turn_to_node/4
%% Description:
%% Waits for an adjacent leader to confirm its role change to a node. This
%% function is part of the merging process, where an adjacent leader has
%% agreed to merge with the current leader and is now expected to become a
%% node within the leader’s cluster.
%%
%% Input:
%% - AdjLeaderID: The PID of the adjacent leader that will become a node.
%% - Leader: The #leader{} record of the current leader managing the merge.
%% - LeaderIDs: List of unique leader IDs for managing adjacency filtering.
%% - Event: The #event{} record that initiated the merge.
%%
%% Preconditions:
%% - AdjLeaderID must be a PID of a leader that has agreed to merge.
%% - Leader must be a valid #leader{} record with merge_in_progress set to true.
%% - Event must be a valid #event{} record representing the merge initiation.
%%
%% Output:
%% - Returns the updated #leader{} record if the adjacent leader confirms
%%   its role change or if a timeout occurs.
%%
%% Side Effects:
%% - Sends an update message to `handle_color_adj_update/4` if a color
%%   adjacency update is received.
%%
%% Usage:
%% - This function is called by `merge_adjacent_clusters/4` as part of the
%%   process of incorporating an adjacent cluster into the leader’s cluster.
%% --------------------------------------------------------------------
wait_for_turn_to_node(AdjLeaderID, Leader, LeaderIDs, Event) ->
    receive
        %% Successful merge and role change confirmation
        {turned_to_node, FromPid} when FromPid == AdjLeaderID ->
            %% Merge completed successfully; return the leader without further updates.
            Leader;

        %% Handle color adjacency update for adjacent clusters
        {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
            UpdatedLeader = handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster),
            wait_for_turn_to_node(AdjLeaderID, UpdatedLeader, LeaderIDs, Event)

    after 4000 ->
        %% Timeout occurred; reset merge_in_progress and return the updated leader.
        UpdatedLeader = Leader#leader{merge_in_progress = false},
        UpdatedLeader
    end.

%% --------------------------------------------------------------------
%% Function: handle_color_adj_update/4
%% Description:
%% Processes a color adjacency update from an adjacent leader, updating the
%% local adjacency list to reflect the new color of the specified cluster.
%% This function also creates a new event and notifies the server of the
%% update.
%%
%% Input:
%% - Leader: The #leader{} record of the current leader receiving the update.
%% - FromPid: The PID of the adjacent leader sending the color update.
%% - Color: The new color assigned to the adjacent cluster.
%% - Nodes_in_Cluster: List of node PIDs in the adjacent cluster.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with an adjacency list.
%% - FromPid must be a PID of an adjacent cluster leader.
%% - Color must be a valid atom representing the updated color.
%% - Nodes_in_Cluster must be a list of node PIDs.
%%
%% Output:
%% - Returns the updated #leader{} record with updated adjacency data.
%%
%% Side Effects:
%% - Updates `adjClusters` to reflect the new color of the adjacent cluster.
%% - Sends `{updated_AdjClusters, self(), UpdatedLeader}` to the server.
%%
%% Usage:
%% - Called when a color adjacency update is received during merging
%%   or periodic updates from adjacent clusters.
%% --------------------------------------------------------------------
handle_color_adj_update(Leader, FromPid, Color, Nodes_in_Cluster) ->
    %% Log the state before updating adjClusters.
    % io:format("Before update: Leader PID=~p, From PID=~p, Color=~p, Nodes_in_Cluster=~p, adjClusters=~p~n", 
    %          [self(), FromPid, Color, Nodes_in_Cluster, Leader#leader.adjClusters]),
    
    %% Update the color of the specified cluster in the adjacency list.
    UpdatedAdjClusters = operation:update_adj_cluster_color(
        Leader#leader.adjClusters, Nodes_in_Cluster, Color, FromPid
    ),
    
    %% Log the state after updating adjClusters.
    % io:format("After update: Leader PID=~p, Updated Color=~p, Updated adjClusters=~p~n",
    %          [self(), Color, UpdatedAdjClusters]),
    
    %% Create a new event to capture the color change.
    Event1 = event:new(change_color, Color, FromPid),
    
    %% Update the Leader record with new adjClusters and last_event.
    UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters, last_event = Event1},
    
    %% Notify the server about the updated adjacency clusters.
    % io:format("Sending updated_AdjClusters to server: Server PID=~p, From PID=~p, UpdatedLeader=~p~n",
    %          [UpdatedLeader#leader.serverID, self(), UpdatedLeader]),
    
    UpdatedLeader#leader.serverID ! {updated_AdjClusters, self(), UpdatedLeader},
    
    %% Return the updated leader record.
    UpdatedLeader.

%% --------------------------------------------------------------------
%% Function: send_periodic_updates/1
%% Description:
%% Periodically sends updated color information to each adjacent cluster.
%% This function is used to ensure consistency in color data among clusters
%% and to notify adjacent clusters of any changes in node membership.
%%
%% Input:
%% - Leader: The #leader{} record containing the leader’s current color
%%   and list of nodes in the cluster.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with initialized color, node,
%%   and adjacency information.
%%
%% Output:
%% - No return value. Sends `{color_adj_update, self(), Color, Nodes_in_cluster}`
%%   messages to each adjacent cluster.
%%
%% Side Effects:
%% - Logs each color update sent to adjacent clusters.
%%
%% Usage:
%% - This function is periodically called by the leader to keep adjacent
%%   clusters updated on color and membership information.
%% --------------------------------------------------------------------
send_periodic_updates(Leader) ->
    AdjClusters = Leader#leader.adjClusters,
    NodesInCluster = Leader#leader.nodes_in_cluster,
    Color = Leader#leader.color,

    %% Send updated color information to each adjacent cluster.
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            % io:format("Sending color update to ~p from ~p: color=~p, nodes_in_cluster=~p~n",
            %     [OtherLeaderID, self(), Color, NodesInCluster]),
            
            OtherLeaderID ! {color_adj_update, self(), Color, NodesInCluster}
        end,
        AdjClusters
    ).

%% --------------------------------------------------------------------
%% Function: broadcast_leader_update/1
%% Description:
%% Sends a periodic leader update message to all nodes in the cluster,
%% informing them of the current leader's ID. This function filters out
%% the leader's own PID from the update list to avoid redundant messages.
%%
%% Input:
%% - Leader: The #leader{} record containing the leader’s node information
%%   and the list of nodes in its cluster.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with a list of nodes in the
%%   cluster and a defined leader ID.
%%
%% Output:
%% - Returns `ok` after broadcasting the update to all nodes in the cluster.
%%
%% Side Effects:
%% - Sends `{leader_update_periodic, LeaderID}` messages to each node in
%%   the cluster except the leader itself.
%%
%% Usage:
%% - This function is called periodically by the leader to maintain
%%   synchronization of leader information among cluster nodes.
%% --------------------------------------------------------------------
broadcast_leader_update(Leader) ->
    LeaderID = Leader#leader.node#node.leaderID,
    NodesInCluster = Leader#leader.nodes_in_cluster,

    %% Exclude the leader's own PID from the list if necessary.
    NodesToUpdate = lists:filter(fun(NodePid) -> NodePid =/= LeaderID end, NodesInCluster),

    %% Send the leader update message to each node in the cluster.
    lists:foreach(
        fun(NodePid) ->
            NodePid ! {leader_update_periodic, LeaderID}
        end,
        NodesToUpdate
    ),
    ok.

%% --------------------------------------------------------------------
%% Function: update_adj_cluster_color/4
%% Description:
%% Updates the color and leader ID for nodes in the adjacency list of a
%% cluster. This function iterates through the specified nodes in the
%% leader's cluster and updates their color and leader ID in the adjacency
%% list.
%%
%% Input:
%% - AdjClusters: The list of tuples representing adjacent clusters in the
%%   format `{NodeID, Color, LeaderID}`.
%% - NodesInCluster: The list of node PIDs that belong to the leader's cluster.
%% - NewColor: The atom representing the new color to assign to the nodes.
%% - NewLeaderID: The PID of the leader that will now manage the nodes.
%%
%% Preconditions:
%% - AdjClusters must be a list of tuples with each element containing a
%%   node PID, color, and leader ID.
%% - NodesInCluster must be a list of valid node PIDs to update.
%% - NewColor must be an atom representing the updated color.
%% - NewLeaderID must be a valid PID of the new leader.
%%
%% Output:
%% - Returns an updated adjacency list with modified colors and leader IDs
%%   for the specified nodes.
%%
%% Usage:
%% - Called by `handle_color_adj_update/4` when there is a color change,
%%   to update the adjacency list with the new color and leader information.
%% --------------------------------------------------------------------
update_adj_cluster_color(AdjClusters, NodesInCluster, NewColor, NewLeaderID) ->
    lists:foldl(
        fun(NodeID, UpdatedAdjClusters) ->
            update_existing_node(UpdatedAdjClusters, NodeID, NewColor, NewLeaderID)
        end,
        AdjClusters,
        NodesInCluster
    ).

%% --------------------------------------------------------------------
%% Function: update_existing_node/4
%% Description:
%% Updates the color and leader ID of a specific node within the adjacency
%% list. If the node exists in the list, it replaces the old color and
%% leader ID with the new values; otherwise, it leaves the list unchanged.
%%
%% Input:
%% - AdjClusters: The adjacency list in the format `{NodeID, Color, LeaderID}`.
%% - NodeID: The PID of the node to update within the adjacency list.
%% - NewColor: The atom representing the new color to assign to the node.
%% - NewLeaderID: The PID of the new leader to assign to the node.
%%
%% Preconditions:
%% - AdjClusters must be a list of tuples where each entry has a node PID,
%%   color, and leader ID.
%% - NodeID must be a valid PID of a node in the adjacency list.
%% - NewColor must be a valid atom representing the new color.
%% - NewLeaderID must be a valid PID of the new leader.
%%
%% Output:
%% - Returns an updated adjacency list with the specified node’s color
%%   and leader ID modified. If the node is not found, the list remains unchanged.
%%
%% Usage:
%% - Used by `update_adj_cluster_color/4` to update individual nodes within
%%   the adjacency list.
%% --------------------------------------------------------------------
update_existing_node([], _NodeID, _NewColor, _NewLeaderID) ->
    []; % If adjacency list is empty, return an empty list
update_existing_node([{NodeID, _OldColor, _OldLeaderID} | Rest], NodeID, NewColor, NewLeaderID) ->
    [{NodeID, NewColor, NewLeaderID} | Rest];
update_existing_node([Other | Rest], NodeID, NewColor, NewLeaderID) ->
    [Other | update_existing_node(Rest, NodeID, NewColor, NewLeaderID)].


%% --------------------------------------------------------------------
%% Function: remove_cluster_from_adjacent/2
%% Description:
%% Removes a specified cluster, identified by its leader PID, from the
%% adjacency list of clusters. This function is typically used to
%% update the adjacency list when a cluster leader has been removed.
%%
%% Input:
%% - DeadLeaderPid: The PID of the dead leader to be removed from the
%%   adjacency list.
%% - AdjacentClusters: A list of tuples `{Pid, Color, LeaderID}`, where
%%   each tuple represents an adjacent cluster with its process ID, color,
%%   and leader ID.
%%
%% Preconditions:
%% - DeadLeaderPid must be a valid PID representing a leader to be removed.
%% - AdjacentClusters must be a list of tuples where each entry contains
%%   a PID, color, and leader ID.
%%
%% Output:
%% - Returns an updated adjacency list with the specified dead leader
%%   cluster removed.
%%
%% Usage:
%% - Called when a cluster leader fails, to update adjacent clusters by
%%   removing the dead leader’s reference from their adjacency lists.
%% --------------------------------------------------------------------
remove_cluster_from_adjacent(DeadLeaderPid, AdjacentClusters) ->
    lists:filter(
        fun({Pid, _Color, _LeaderID}) ->
            Pid =/= DeadLeaderPid
        end,
        AdjacentClusters
    ).

%% --------------------------------------------------------------------
%% Function: update_adjacent_cluster_info/3
%% Description:
%% Updates the adjacency list by inserting a new or updated cluster entry
%% based on the provided leader PID and cluster information. This function
%% removes any existing entry for the specified leader and then adds a new
%% entry with updated color and leader ID.
%%
%% Input:
%% - NewLeaderPid: The PID of the new leader to be added or updated in
%%   the adjacency list.
%% - UpdatedClusterInfo: A map containing the new cluster information,
%%   including the color and leader ID.
%% - AdjacentClusters: The current adjacency list of clusters, represented
%%   as a list of tuples `{Pid, Color, LeaderID}`.
%%
%% Preconditions:
%% - NewLeaderPid must be a valid PID of a leader.
%% - UpdatedClusterInfo must be a map containing at least the color and
%%   leader ID for the cluster.
%% - AdjacentClusters must be a list of tuples representing current
%%   adjacent clusters.
%%
%% Output:
%% - Returns an updated adjacency list with the specified leader entry
%%   modified or added.
%%
%% Usage:
%% - Used when adjacent clusters need to update their records with new
%%   leader information, such as after a leader change or color update.
%% --------------------------------------------------------------------
update_adjacent_cluster_info(NewLeaderPid, UpdatedClusterInfo, AdjacentClusters) ->
    %% Remove the old entry for this leader in the adjacency list.
    AdjClustersWithoutOld = remove_cluster_from_adjacent(NewLeaderPid, AdjacentClusters),
    
    %% Extract the new color and leader ID for the cluster.
    NewColor = utils:normalize_color(maps:get(color, UpdatedClusterInfo)),
    NewLeaderID = maps:get(leader_id, UpdatedClusterInfo, NewLeaderPid),
    
    %% Create a new entry with the updated information.
    NewEntry = {NewLeaderPid, NewColor, NewLeaderID},
    
    %% Insert the updated entry into the adjacency list.
    [NewEntry | AdjClustersWithoutOld].


%% ------------------
%%   RECOVERY UTILITIES
%% ------------------

%% --------------------------------------------------------------------
%% Function: promote_to_leader/5
%% Description:
%% Promotes a node to a leader, initializing the leader’s record with
%% specific cluster and adjacency information. This function sets the
%% leader’s color, assigns the server PID, and populates lists of
%% cluster nodes and adjacent clusters.
%%
%% Input:
%% - Node: The node record to be promoted to leader status.
%% - Color: The color to assign to the new leader, represented as an atom.
%% - ServerPid: The PID of the server managing the system.
%% - NodesInCluster: A list of nodes included in the new leader’s cluster.
%% - AdjacentClusters: A list of clusters adjacent to the new leader.
%%
%% Preconditions:
%% - Node must be a valid `#node{}` record.
%% - Color must be an atom representing the cluster’s color.
%% - ServerPid must be a valid process ID for server communication.
%% - NodesInCluster must be a list of valid node PIDs in the cluster.
%% - AdjacentClusters must be a list of adjacent clusters in tuple format.
%%
%% Output:
%% - Returns a `#leader{}` record populated with the specified color,
%%   server PID, cluster nodes, and adjacency list.
%%
%% Usage:
%% - This function is called when a node is designated as a new leader,
%%   allowing it to inherit responsibility for managing its cluster.
%% - The returned leader record includes the server PID, adjacency data,
%%   and a unique color, ready for integration into the system.
%%
%% Example:
%% - promote_to_leader(Node, green, ServerPid, NodesInCluster, AdjacentClusters).
%% --------------------------------------------------------------------
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


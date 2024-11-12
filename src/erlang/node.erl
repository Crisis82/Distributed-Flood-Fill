-module(node).

%% Module Description:
%% This module defines functions for creating and managing nodes and leaders
%% in a distributed network. Nodes have attributes such as position, PID, 
%% leader ID, neighbors, and connections to parent or child nodes.
%% Leaders are responsible for managing clusters and coordinating nodes,
%% and they have additional metadata, including color and adjacent clusters.

-export([
    new_node/8,
    new_leader/5,
    create_node/2,
    leader_loop/1,
    node_loop/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% Creates a basic node with the given parameters, including its PID and neighbors.
%% @doc Initializes a standard node with position, hierarchy, time, PID, and neighbors.
%% @spec new_node(integer(), integer(), pid(), list(), term(), pid(), pid(), list()) -> #node{}
%% @param X The X coordinate of the node.
%% @param Y The Y coordinate of the node.
%% @param Parent The PID of the parent node.
%% @param Children A list of child nodes' PIDs.
%% @param Time The initial timestamp or time reference for the node.
%% @param LeaderID The PID of the leader node.
%% @param Pid The process ID of this node.
%% @param Neighbors A list of neighboring nodes' PIDs.
%% @return Returns an #node{} record with populated fields.
%%
%% Preconditions:
%% - X and Y are integers representing valid coordinates.
%% - Parent, LeaderID, and Pid must be valid PIDs.
%% - Children and Neighbors are lists of PIDs.
%%
%% Postconditions:
%% - Returns a new node record with the specified parameters.
new_node(X, Y, Parent, Children, Time, LeaderID, Pid, Neighbors) ->
    #node{
        x = X,
        y = Y,
        parent = Parent,
        children = Children,
        time = Time,
        leaderID = LeaderID,
        pid = Pid,
        neighbors = Neighbors
    }.

%% Creates a leader node, assigns its own PID as the leaderID, and initializes neighbors.
%% @doc Initializes a new leader node with its PID as its own leaderID.
%% @spec new_leader(integer(), integer(), atom(), pid(), pid()) -> #leader{}
%% @param X The X coordinate of the leader node.
%% @param Y The Y coordinate of the leader node.
%% @param Color The color assigned to the leader node.
%% @param ServerPid The PID of the central server process.
%% @param StartSystemPid The PID of the system startup process.
%% @return Returns an initialized leader record.
%%
%% Preconditions:
%% - X and Y are integers representing the leader’s coordinates.
%% - Color is an atom representing the leader's color.
%% - ServerPid and StartSystemPid are valid PIDs.
%%
%% Postconditions:
%% - Returns a leader record with an initialized node and leader ID set to the leader's PID.
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    % Step 1: Create a base node with a given PID and empty neighbors
    Node = new_node(X, Y, ServerPid, [], undefined, undefined, undefined, []),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{
        node = Node,
        color = Color,
        serverID = ServerPid,
        last_event = event:new(undefined, undefined, undefined),
        adjClusters = [],
        nodes_in_cluster = [],
        merge_in_progress = false
    },

    % Step 3: Start the node process and update leaderID and pid fields
    UpdatedLeader = create_node(Leader, StartSystemPid),
    UpdatedLeader.

%% Spawns a process for a node, initializing it with its own leaderID and empty neighbors.
%% @doc Spawns a process for the node loop and registers its PID with a unique identifier.
%% @spec create_node(#leader{}, pid()) -> #leader{}
%% @param Leader The leader record with an embedded node record.
%% @param StartSystemPid The PID responsible for starting the system.
%% @return Returns the leader record with updated PID and leaderID fields.
%%
%% Preconditions:
%% - Leader must be a valid leader record containing an initialized node.
%% - StartSystemPid must be a valid PID.
%%
%% Postconditions:
%% - A process for the node is spawned, and its PID is assigned as the node's PID and leaderID.
create_node(Leader, StartSystemPid) ->
    % Spawn the process for the node loop
    Pid = spawn(fun() ->
        setup:setup_loop(Leader, StartSystemPid, false)
    end),

    %% Register the pid with the alias node_X_Y
    register(
        list_to_atom(
            lists:flatten(
                io_lib:format("node~p_~p", [Leader#leader.node#node.x, Leader#leader.node#node.y])
            )
        ),
        Pid
    ),

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},
    UpdatedLeader.


%% Leader loop to receive messages and update state.
%% @doc Main loop for a leader to handle incoming messages and update its state.
%% @spec leader_loop(#leader{}) -> any()
%% @param Leader The leader record containing state and message-handling functions.
%%
%% Preconditions:
%% - Leader must be a valid leader record with initialized state.
%%
%% Postconditions:
%% - Continuously processes messages and updates the leader's state as needed.
leader_loop(Leader) ->
    handle_messages_leader(Leader).

%% Recursive function to handle all messages in the leader's queue.
%% @doc Processes incoming messages for the leader, updating its state based on message content.
%% @spec handle_messages_leader(#leader{}) -> any()
%% @param Leader The leader record with embedded node state.
%%
%% Preconditions:
%% - Leader is a valid leader record with the necessary fields populated.
%%
%% Postconditions:
%% - Continuously updates the leader's state based on received messages.
handle_messages_leader(Leader) ->

    % Save the leader's data to persistent storage
    utils:save_data(Leader),

    % Get the length of the message queue
    QueueLength = erlang:process_info(self(), message_queue_len),

    % If the message queue is empty, continue looping
    case QueueLength of
        {message_queue_len, 0} ->
            handle_messages_leader(Leader); % Re-enters the main leader loop

        _ ->
            % Otherwise, receive and process the next message, then recursively call handle_messages_leader
            receive
                {get_leader_info, FromPid} ->
                    FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
                    handle_messages_leader(Leader);

                {new_leader_elected, NewLeaderPid} ->
                    % Update the leader's node with the new leader PID
                    UpdatedNode = Leader#leader.node#node{leaderID = NewLeaderPid},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);

                {remove_adjacent_cluster, DeadLeaderPid} ->
                    % Remove a dead cluster from the adjacency list
                    NewAdjClusters = operation:remove_cluster_from_adjacent(
                        DeadLeaderPid, Leader#leader.adjClusters
                    ),
                    UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);

                {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo} ->
                    % Update adjacency list with the new leader info
                    NewAdjClusters = operation:update_adjacent_cluster_info(
                        NewLeaderPid, UpdatedClusterInfo, Leader#leader.adjClusters
                    ),
                    UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);

                {aggiorna_leader, NewLeader} ->
                    handle_messages_leader(NewLeader);

                {save_to_db, _ServerPid} ->
                    % Save leader information to local DB
                    utils:save_data(Leader),
                    
                    % Create a list of nodes in the cluster excluding the leader’s PID
                    FilteredNodes = lists:filter(
                        fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                        Leader#leader.nodes_in_cluster
                    ),
                    
                    % Transform all nodes in the cluster (except leader) into normal nodes
                    lists:foreach(
                        fun(NodePid) ->
                            NodePid ! {transform_to_normal_node}
                        end,
                        FilteredNodes
                    ),
                    
                    handle_messages_leader(Leader);

                {transform_to_normal_node} ->
                    % Save only the node data to a local JSON file
                    Node = Leader#leader.node,
                    utils:save_data(Node),
                    node_loop(Node);

                {leader_update, NewLeader} ->
                    % Update leader ID for this node and propagate it to child nodes
                    Node = Leader#leader.node,
                    lists:foreach(
                        fun(child) ->
                            child ! {leader_update, NewLeader}
                        end,
                        Node#node.children
                    ),
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);

                {change_color_request, Event} ->
                    % Handle color change request with consistency checks
                    TimeDifference = 
                        convert_time_to_ms(Event#event.timestamp) -
                        convert_time_to_ms(Leader#leader.last_event#event.timestamp),

                    io:format(
                        "~n~n~p : Handling 'change_color_request'.~n" ++
                        "Last event: ~p~n" ++
                        "New event: ~p~n" ++
                        "Time difference: ~p ms~n",
                        [self(), 
                        Leader#leader.last_event#event.timestamp, 
                        Event#event.timestamp,
                        TimeDifference]
                    ),

                    IsColorShared = utils:check_same_color(Event#event.color, Leader#leader.adjClusters),
                    
                    io:format("New event: ~p, ~p, ~p~n", [Event#event.type, Event#event.color, Event#event.from]),

                    if
                        TimeDifference >= 0 ->
                            % Newer event case
                            io:format("This is a new event, proceeding normally.~n"),
                            Leader#leader.serverID ! {operation_request, Event, self()},
                            receive 
                                {server_ok, Event} ->
                                    UpdatedLeader = operation:change_color(Leader, Event),
                                    handle_messages_leader(UpdatedLeader)                            
                            end;

                        IsColorShared andalso TimeDifference >= -3000 ->
                            % Consistency case 1: recovery for color merge within 3 seconds
                            io:format("Old event requiring merge: RECOVER~n"),
                            OldColor = Leader#leader.color,
                            io:format("Change color to ~p ~n", [Event#event.color]),
                            Leader#leader.serverID ! {operation_request, Event, self()},
                            receive 
                                {server_ok, Event} ->
                                    UpdatedLeader = operation:change_color(Leader, Event)                              
                            end,
                            io:format("Re-apply: ~p ~n", [OldColor]),
                            NewEvent = Event#event{color = OldColor},
                            UpdatedLeader#leader.serverID ! {operation_request, NewEvent, self()},
                            receive 
                                {server_ok, NewEvent} ->
                                    UpdatedLeader1 = operation:change_color(UpdatedLeader, NewEvent)                              
                            end,
                            handle_messages_leader(UpdatedLeader1);

                        not IsColorShared andalso TimeDifference >= -3000 ->
                            % Consistency case 2: drop if merge is not required within 3 seconds
                            io:format("Old event not requiring merge: DROP~n");

                        true ->
                            io:format("Too old event: ~p~n", [Event])
                    end,
                    handle_messages_leader(Leader);

                {server_ok, Event} ->
                    % The server confirms to proceed with the operation
                    case Event#event.type of
                        color -> UpdatedLeader = operation:change_color(Leader, Event);
                        merge -> UpdatedLeader = operation:merge(Leader, Event)
                    end,
                    handle_messages_leader(UpdatedLeader);

                {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
                    % Print initial state of adjClusters before update
                    io:format("Before update: Leader PID=~p, Color=~p, Nodes_in_Cluster=~p, adjClusters=~p~n", 
                            [self(), Color, Nodes_in_Cluster, Leader#leader.adjClusters]),
                    
                    % Update color of a specific cluster in the adjacency list
                    UpdatedAdjClusters = operation:update_adj_cluster_color(
                        Leader#leader.adjClusters, Nodes_in_Cluster, Color, FromPid
                    ),
                    
                    % Log after update
                    io:format("After update: Leader PID=~p, Updated Color=~p, Updated adjClusters=~p~n",
                            [self(), Color, UpdatedAdjClusters]),
                    
                    % Create a new event
                    Event1 = event:new(change_color, Color, FromPid),
                    
                    % Update leader record with new adjacency list and last event
                    UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters, last_event = Event1},
                    
                    % Send the updated adjacency clusters to the server
                    io:format("Sending updated_AdjClusters to server: Server PID=~p, From PID=~p, UpdatedLeader=~p~n",
                            [UpdatedLeader#leader.serverID, self(), UpdatedLeader]),
                    
                    UpdatedLeader#leader.serverID ! {updated_AdjClusters, self(), UpdatedLeader},
                    
                    % Continue handling messages
                    handle_messages_leader(UpdatedLeader);

                {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore, FromPid} ->
                    % Handle response to a merge request
                    io:format("-------------------------------------------------- ~p : Received response_to_merge from ~p~n", [self(), FromPid]),
                    UpdatedAdjClusters = utils:join_adj_clusters(Leader#leader.adjClusters, AdjListIDMaggiore),
                    FilteredAdjClusters = lists:filter(
                        fun({_, _, LeaderID}) ->
                            LeaderID =/= Leader#leader.node#node.leaderID andalso
                            LeaderID =/= FromPid
                        end,
                        UpdatedAdjClusters
                    ),
                    UpdatedNodeList = utils:join_nodes_list(Leader#leader.nodes_in_cluster, Nodes_in_Cluster),
                    UpdatedLeader = Leader#leader{
                        adjClusters = FilteredAdjClusters,
                        nodes_in_cluster = UpdatedNodeList
                    },
                    FromPid ! {became_node, self()},
                    receive
                        {turned_to_node, FromPid} ->
                            handle_messages_leader(UpdatedLeader)
                    after 4000 ->
                        io:format("~p : Timeout waiting for turned_to_node from ~p, proceeding.~n", [self(), FromPid]),
                        handle_messages_leader(Leader)
                    end,
                    io:format("-------------------------------------------------- ~p : Handled response_to_merge of ~p~n", [self(), FromPid]),
                    handle_messages_leader(UpdatedLeader);

                {merge_request, LeaderID, Event} ->
                    if
                        LeaderID == self() ->
                            io:format("~p -> Received merge_request from self. Rejecting merge.~n", [self()]),
                            LeaderID ! {merge_rejected, self()},
                            handle_messages_leader(Leader);

                        Leader#leader.merge_in_progress ->
                            io:format("~p -> Merge in progress. Rejecting merge_request from ~p.~n", [self(), LeaderID]),
                            LeaderID ! {merge_rejected, self()},
                            handle_messages_leader(Leader);

                        true ->
                            % Accept the merge request; set merge_in_progress to true
                            UpdatedLeader = Leader#leader{merge_in_progress = true},
                            % Proceed with merge logic
                            handle_merge_request(UpdatedLeader, LeaderID, Event)
                    end;






            {update_nodes_in_cluster, NodesInCluster, NewLeaderID, NewColor} ->
                Node = Leader#leader.node,
                Neighbors = Node#node.neighbors,

                UpdatedNeighbors = lists:map(
                    fun({NeighborPid, _NeighborColor, _NeighborLeaderID} = Neighbor) ->
                        case lists:member(NeighborPid, NodesInCluster) of
                            true ->
                                % io:format("Updating neighbor ~p with new leader ~p and color ~p.~n", [
                                %     NeighborPid, NewLeaderID, NewColor
                                % ]),
                                {NeighborPid, NewColor, NewLeaderID};
                            false ->
                                Neighbor
                        end
                    end,
                    Neighbors
                ),

                UpdatedNode = Node#node{neighbors = UpdatedNeighbors},
                UpdatedLeader = Leader#leader{node = UpdatedNode},

                handle_messages_leader(UpdatedLeader);

                _Other ->
                    % Unhandled messages
                    handle_messages_leader(Leader)
            end
    end.



%% Main function for the node loop
%% @doc Main loop for nodes to receive and process messages continuously.
%% @spec node_loop(#node{}) -> any()
%% @param Node The node record containing state and message-handling functions.
%%
%% Preconditions:
%% - Node must be a valid node record with the necessary fields populated.
%%
%% Postconditions:
%% - Continuously processes messages and updates the node's state as needed.
node_loop(Node) ->
    handle_node_messages(Node).

%% Recursive function to handle all messages in the node's queue.
%% @doc Processes incoming messages for the node, updating its state based on message content.
%% @spec handle_node_messages(#node{}) -> any()
%% @param Node The node record.
%%
%% Preconditions:
%% - Node is a valid node record with necessary attributes.
%%
%% Postconditions:
%% - Continuously updates the node's state based on received messages.
handle_node_messages(Node) ->
    % Save the node's data to persistent storage
    utils:save_data(Node),

    % Get the length of the message queue
    QueueLength = erlang:process_info(self(), message_queue_len),

    % If the message queue is empty, continue looping
    case QueueLength of
        {message_queue_len, 0} ->
            node_loop(Node); % Re-enters the main node loop

        _ ->
            % Otherwise, receive and process the next message, then recursively call handle_node_messages
            receive
                {change_color_request, Event} ->
                    Node#node.leaderID ! {change_color_request, Event},
                    handle_node_messages(Node);

                {leader_update, NewLeader} ->
                    % Propagate the leader update to child nodes
                    lists:foreach(
                        fun(child) ->
                            child ! {leader_update, NewLeader}
                        end,
                        Node#node.children
                    ),
                    % Update the node's leader ID
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    handle_node_messages(UpdatedNode);

                {get_leader_info, FromPid} ->
                    Node#node.leaderID ! {get_leader_info, FromPid},
                    handle_node_messages(Node);

                % {merge_request, FromPid, Event} ->
                %    Node#node.leaderID ! {merge_request, FromPid, Event};

                {new_leader_elected, ServerID, Color, NodesInCluster, AdjacentClusters} ->
                    % Promote the current node to leader
                    UpdatedLeader = operation:promote_to_leader(
                        Node,
                        Color,
                        ServerID,
                        NodesInCluster,
                        AdjacentClusters
                    ),
                    leader_loop(UpdatedLeader); % Switches to the leader loop
                
                {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
                    Node#node.leaderID ! {color_adj_update, FromPid, Color, Nodes_in_Cluster};

                _Other ->
                    Node#node.leaderID ! _Other,
                    handle_node_messages(Node)
            end
    end.

%% Collects change color requests within a specific time window.
%% @doc Collects all `change_color_request` messages received within the specified end time.
%% @spec collect_change_color_requests(integer(), list()) -> {ok, list()}
%% @param EndTime The time limit to collect requests, in milliseconds.
%% @param Messages The list to store collected messages.
%% @return Returns a tuple `{ok, Messages}` containing all collected messages.
%%
%% Preconditions:
%% - EndTime must be a valid integer timestamp in milliseconds.
%% - Messages is a list to store incoming messages.
%%
%% Postconditions:
%% - Returns a list of messages collected within the time limit.
collect_change_color_requests(EndTime, Messages) ->
    Now = erlang:monotonic_time(millisecond),
    RemainingTime = EndTime - Now,
    if RemainingTime =< 0 ->
        {ok, Messages};
    true ->
        receive
            {change_color_request, NewEvent} ->
                collect_change_color_requests(EndTime, [NewEvent | Messages]);
            _Other ->
                collect_change_color_requests(EndTime, Messages)
        after RemainingTime ->
            {ok, Messages}
        end
    end.

%% Converts a time tuple to milliseconds.
%% @doc Converts a time represented as {Hour, Minute, Second} to milliseconds.
%% @spec convert_time_to_ms({integer(), integer(), integer()}) -> integer()
%% @param TimeTuple A tuple {Hour, Minute, Second}.
%% @return Returns the time in milliseconds.
%%
%% Preconditions:
%% - TimeTuple must be a valid tuple in the form {Hour, Minute, Second}.
%%
%% Postconditions:
%% - Returns the equivalent time in milliseconds.
convert_time_to_ms({Hour, Minute, Second}) ->
    (Hour * 3600 + Minute * 60 + Second) * 1000.

handle_merge_request(Leader, LeaderID, Event) ->
    EventTimestampMs = convert_time_to_ms(Event#event.timestamp),
    LastEventTimestampMs = convert_time_to_ms(Leader#leader.last_event#event.timestamp),
    if
        EventTimestampMs < LastEventTimestampMs andalso Event#event.color =/= Leader#leader.color ->
            io:format("~p -> Merge request rejected due to outdated timestamp. Rejecting merge.~n", [self()]),
            LeaderID ! {merge_rejected, self()},
            % Reset merge_in_progress since merge is rejected
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            handle_messages_leader(UpdatedLeader);

        Event#event.color =/= Leader#leader.color ->
            io:format("~p -> Merge request received from ID ~p.~n", [self(), LeaderID]),
            io:format("Event color does not match current leader color. Color change detected.~n"),
            LeaderID ! {merge_rejected, self()},
            % Reset merge_in_progress since merge is rejected
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            handle_messages_leader(UpdatedLeader);

        true ->
            io:format("~p -> Merge request accepted from ID ~p.~n", [self(), LeaderID]),
            % Proceed with merge
            collect_and_handle_events(Leader, LeaderID, Event)
    end.

collect_and_handle_events(Leader, LeaderID, Event) ->
    EndTime = erlang:monotonic_time(millisecond) + 2000,
    {ok, CollectedMessages} = collect_change_color_requests(EndTime, []),

    EventTimestampMs = convert_time_to_ms(Event#event.timestamp),

    OldEvents = [NewEvent || NewEvent <- CollectedMessages,
                    convert_time_to_ms(NewEvent#event.timestamp) < EventTimestampMs,
                    convert_time_to_ms(NewEvent#event.timestamp) >= EventTimestampMs - 2000],
    NewEvents = [NewEvent || NewEvent <- CollectedMessages,
                    convert_time_to_ms(NewEvent#event.timestamp) > EventTimestampMs],

    case OldEvents of
        [] ->
            io:format("No color change events to handle. Proceeding with merge.~n"),
            LeaderID ! {response_to_merge, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters, self()},
            % Wait for the leader to become a node
            wait_for_leader_to_become_node(Leader, LeaderID, NewEvents);
        _ ->
            io:format("Received color change events with older timestamp. Cancelling merge.~n"),
            LeaderID ! {merge_rejected, self()},
            % Reset merge_in_progress since merge is rejected
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            % Re-inject the old events into the message loop
            lists:foreach(fun(Event_change_color) -> self() ! {change_color_request, Event_change_color} end, OldEvents),
            handle_messages_leader(UpdatedLeader)
    end.

wait_for_leader_to_become_node(Leader, LeaderID, NewEvents) ->
    receive
        {became_node, LeaderID} ->
            lists:foreach(
                fun(NodePid) ->
                    io:format("~p : Sending leader_update to ~p with new leader ~p.~n", [self(), NodePid, LeaderID]),
                    NodePid ! {leader_update, LeaderID}
                end,
                Leader#leader.nodes_in_cluster
            ),
            Node = Leader#leader.node,
            UpdatedNode = Node#node{leaderID = LeaderID},
            % Notify server to remove self from leaders
            Leader#leader.serverID ! {remove_myself_from_leaders, self()},
            LeaderID ! {turned_to_node, self()},
            io:format("~p : Sent turned_to_node to ~p~n", [self(), LeaderID]),
            % Re-inject any new events into the node's message loop
            lists:foreach(fun(NewEvent) -> self() ! {change_color_request, NewEvent} end, NewEvents),
            % Node loop with updated node
            node_loop(UpdatedNode)
    after 4000 ->
        io:format("~p : Timeout waiting for {became_node, LeaderID}. Continuing as leader.~n", [self()]),
        % Reset merge_in_progress since merge didn't complete
        UpdatedLeader = Leader#leader{merge_in_progress = false},
        handle_messages_leader(UpdatedLeader)
    end.

-module(node).

%% --------------------------------------------------------------------
%% Module: node
%%
%% Module Description:
%% This module defines functions for creating and managing nodes and leaders
%% in a distributed network. Nodes have attributes such as position, PID,
%% leader ID, neighbors, and connections to parent or child nodes.
%% Leaders are responsible for managing clusters and coordinating nodes,
%% and they have additional metadata, including color and adjacent clusters.
%%
%% Functions provided by the module:
%% - new_node/8: Initializes a basic node with specified attributes.
%% - new_leader/5: Creates a leader node and initializes its attributes.
%% - create_node/2: Starts a node process and updates the node with its PID and leader ID.
%% - leader_loop/1: Main loop for handling messages in the leader's process.
%% - node_loop/1: Main loop for handling messages in the node's process.
%%
%% The module enables the dynamic management of nodes and leaders in the network,
%% including handling color changes, cluster management, leader election, and
%% merging of clusters based on timestamped events.
%%
%% The following functions are used to process and handle incoming messages:
%% - Messages related to leader updates, color changes, cluster updates, and merges.
%% - Persistent storage of node and leader data.
%% - Handling of merge requests and consistency checks for event timestamps.
%% --------------------------------------------------------------------

-export([
    new_node/8,
    new_leader/5,
    create_node/2,
    leader_loop/1,
    node_loop/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% --------------------------------------------------------------------
%% Function: new_node/8
%% Description:
%% Creates and initializes a standard node with specific coordinates, hierarchy,
%% time reference, process identifiers (PIDs), and neighboring nodes.
%%
%% Input:
%% - X: Integer representing the X coordinate of the node.
%% - Y: Integer representing the Y coordinate of the node.
%% - Parent: The PID of the parent node in the node hierarchy.
%% - Children: List of child node PIDs under this node in the hierarchy.
%% - Time: Initial timestamp or time reference for this node.
%% - LeaderID: PID of the leader node this node is associated with.
%% - Pid: The process ID of the node itself.
%% - Neighbors: List of PIDs of neighboring nodes.
%%
%% Preconditions:
%% - X and Y must be integers that specify valid coordinates.
%% - Parent, LeaderID, and Pid must be valid PIDs.
%% - Children and Neighbors must be lists of PIDs.
%%
%% Output:
%% - Returns a `#node{}` record with populated fields based on the input parameters.
%%
%% Usage:
%% - Use `new_node/8` to initialize a basic node in the network, specifying its
%%   position, relationships, and neighbors, allowing for further configuration
%%   as a standard node or potential leader.
%% --------------------------------------------------------------------
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

%% --------------------------------------------------------------------
%% Function: new_leader/5
%% Description:
%% Creates and initializes a leader node with specific coordinates, a unique color,
%% server and startup PIDs. This function uses `new_node/8` to first create a base node
%% and then promotes it to a leader, setting its own PID as the leader ID and initializing
%% adjacency clusters.
%%
%% Input:
%% - X: Integer representing the X coordinate of the leader node.
%% - Y: Integer representing the Y coordinate of the leader node.
%% - Color: Atom representing the color assigned to the leader node.
%% - ServerPid: PID of the central server process managing the leader.
%% - StartSystemPid: PID of the system startup process.
%%
%% Preconditions:
%% - X and Y must be integers specifying the leader's coordinates.
%% - Color must be an atom that represents the leader's unique color.
%% - ServerPid and StartSystemPid must be valid PIDs.
%%
%% Output:
%% - Returns a `#leader{}` record initialized with specified parameters, including:
%%   * The node's position and hierarchy as a base node.
%%   * Leader-specific attributes like `color`, `serverID`, and adjacency clusters.
%%
%% Usage:
%% - Use `new_leader/5` when initializing a node that will serve as a leader, to ensure
%%   it has the appropriate structure and connections to act as a leader within the network.
%% --------------------------------------------------------------------
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    %% Step 1: Create a base node with default and undefined values
    Node = new_node(X, Y, ServerPid, [], undefined, undefined, undefined, []),

    %% Step 2: Initialize leader structure with node details and leader-specific fields
    Leader = #leader{
        node = Node,
        color = Color,
        serverID = ServerPid,
        last_event = event:new(undefined, undefined, undefined),
        adjClusters = [],
        nodes_in_cluster = [],
        merge_in_progress = false
    },

    %% Step 3: Start the node process and update `leaderID` and `pid` fields in the leader record
    UpdatedLeader = create_node(Leader, StartSystemPid),
    UpdatedLeader.

%% --------------------------------------------------------------------
%% Function: create_node/2
%% Description:
%% Starts the process for the node and updates the node with its PID and leader ID,
%% marking it as a new, active entity within the network.
%%
%% Input:
%% - Leader: The `#leader{}` record to initialize.
%% - StartSystemPid: The PID of the system startup process.
%%
%% Output:
%% - Returns the updated `#leader{}` record with PID and leader ID fields populated.
%%
%% Usage:
%% - This function is invoked during the initialization of a new leader node.
%%   It enables the leader to operate as a process and communicate within the network.
%% --------------------------------------------------------------------
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

%% --------------------------------------------------------------------
%% Function: leader_loop/1
%% Description:
%% The main loop for a leader node that continuously receives and processes
%% messages. Each message is handled in the `handle_messages_leader/1` function,
%% where the leader’s state may be updated or adjacent clusters may be notified.
%%
%% Input:
%% - Leader: The leader record containing the current state and message-handling functions.
%%
%% Preconditions:
%% - Leader must be a valid leader record with an initialized state.
%%
%% Output:
%% - This function does not return. It continuously processes messages in a loop.
%%
%% Usage:
%% - Use this function to start a leader node's main message-handling loop.
%% --------------------------------------------------------------------
leader_loop(Leader) ->
    handle_messages_leader(Leader).

%% --------------------------------------------------------------------
%% Function: handle_messages_leader/1
%% Description:
%% A recursive function to handle messages sent to a leader node, updating the
%% leader's state as needed based on the content of each message.
%%
%% Input:
%% - Leader: The leader record containing the current node state.
%%
%% Preconditions:
%% - Leader must be a valid leader record with initialized fields for state and configuration.
%%
%% Output:
%% - This function does not return. It continuously updates the leader's state
%%   and manages the node’s responsibilities in the network.
%%
%% Usage:
%% - This function is automatically called within `leader_loop/1` and manages
%%   message-driven state changes for the leader node.
%% --------------------------------------------------------------------
handle_messages_leader(Leader) ->
    % Save the leader's data to persistent storage
    utils:save_data(Leader),

    % Get the length of the message queue
    QueueLength = erlang:process_info(self(), message_queue_len),

    % If the message queue is empty, continue looping
    case QueueLength of
        {message_queue_len, 0} ->
            % Re-enters the main leader loop
            handle_messages_leader(Leader);
        _ ->
            % Otherwise, receive and process the next message, then recursively call handle_messages_leader
            receive
                {get_leader_info, FromPid} ->
                    % Respond with the current leader's ID and color
                    FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
                    handle_messages_leader(Leader);
                {new_leader_elected, NewLeaderPid} ->
                    % Update the leader's node record to reflect the new leader ID
                    UpdatedNode = Leader#leader.node#node{leaderID = NewLeaderPid},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);
                {remove_adjacent_cluster, DeadLeaderPid} ->
                    % Remove a specified dead cluster from the leader's adjacency list
                    NewAdjClusters = operation:remove_cluster_from_adjacent(
                        DeadLeaderPid, Leader#leader.adjClusters
                    ),
                    UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);
                {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo} ->
                    % Update the adjacency list with information from the new leader
                    NewAdjClusters = operation:update_adjacent_cluster_info(
                        NewLeaderPid, UpdatedClusterInfo, Leader#leader.adjClusters
                    ),
                    UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);
                {aggiorna_leader, NewLeader} ->
                    % Continue message handling with the updated leader state
                    handle_messages_leader(NewLeader);
                {save_to_db, _ServerPid} ->
                    % Save the leader's current state to the local database
                    utils:save_data(Leader),

                    % Filter out the leader's own PID to get only the non-leader nodes in the cluster
                    FilteredNodes = lists:filter(
                        fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                        Leader#leader.nodes_in_cluster
                    ),

                    % Convert all nodes in the cluster (except the leader) into regular nodes
                    lists:foreach(
                        fun(NodePid) ->
                            NodePid ! {transform_to_normal_node}
                        end,
                        FilteredNodes
                    ),

                    % Continue processing messages with the updated leader state
                    handle_messages_leader(Leader);
                {transform_to_normal_node} ->
                    % Save only the node data to a JSON file for this non-leader node
                    Node = Leader#leader.node,
                    utils:save_data(Node),
                    % Transition to the node loop for regular node behavior
                    node_loop(Node);
                {leader_update, NewLeader} ->
                    % Update the leader ID in this node and notify its child nodes of the new leader
                    Node = Leader#leader.node,
                    lists:foreach(
                        fun(child) ->
                            child ! {leader_update, NewLeader}
                        end,
                        Node#node.children
                    ),
                    % Update the node's internal state with the new leader information
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);
                {change_color_request, Event} ->
                    % Handle a color change request while maintaining consistency across clusters.
                    % Calculate the time difference between the current event and the last event recorded.
                    TimeDifference =
                        convert_time_to_ms(Event#event.timestamp) -
                            convert_time_to_ms(Leader#leader.last_event#event.timestamp),

                    io:format(
                        "~n~n~p : Handling 'change_color_request'.~n" ++
                            "Last event: ~p~n" ++
                            "New event: ~p~n" ++
                            "Time difference: ~p ms~n",
                        [
                            self(),
                            Leader#leader.last_event#event.timestamp,
                            Event#event.timestamp,
                            TimeDifference
                        ]
                    ),

                    % Check if the color specified in the event is shared with adjacent clusters.
                    IsColorShared = utils:check_same_color(
                        Event#event.color, Leader#leader.adjClusters
                    ),

                    io:format("New event: ~p, ~p, ~p~n", [
                        Event#event.type, Event#event.color, Event#event.from
                    ]),

                    if
                        TimeDifference >= 0 ->
                            % Case 1: Newer event received
                            % Process the event normally, as it has a more recent timestamp.
                            io:format("This is a new event, proceeding normally.~n"),
                            Leader#leader.serverID ! {operation_request, Event, self()},
                            receive
                                {server_ok, Event} ->
                                    % Update the leader's color after confirmation from the server.
                                    UpdatedLeader = operation:change_color(Leader, Event),
                                    handle_messages_leader(UpdatedLeader)
                            end;
                        IsColorShared andalso TimeDifference >= -3000 ->
                            % Consistency Case 1: Older event that requires color merge (within 3 seconds)
                            % Temporarily change color to handle the merge, then revert to the original color.
                            io:format("Old event requiring merge: RECOVER~n"),
                            OldColor = Leader#leader.color,
                            io:format("Change color to ~p ~n", [Event#event.color]),
                            Leader#leader.serverID ! {operation_request, Event, self()},
                            receive
                                {server_ok, Event} ->
                                    UpdatedLeader = operation:change_color(Leader, Event)
                            end,
                            io:format("Re-apply: ~p ~n", [OldColor]),
                            % Revert the color back to the original after merging.
                            NewEvent = Event#event{color = OldColor},
                            UpdatedLeader#leader.serverID ! {operation_request, NewEvent, self()},
                            receive
                                {server_ok, NewEvent} ->
                                    UpdatedLeader1 = operation:change_color(UpdatedLeader, NewEvent)
                            end,
                            handle_messages_leader(UpdatedLeader1);
                        not IsColorShared andalso TimeDifference >= -3000 ->
                            % Consistency Case 2: Older event without merge requirement (within 3 seconds)
                            % Simply drop this event as no color consistency adjustment is needed.
                            io:format("Old event not requiring merge: DROP~n");
                        true ->
                            % Too old event: Discard events that are beyond the acceptable time difference.
                            io:format("Too old event: ~p~n", [Event])
                    end,
                    % Continue processing further messages for the leader.
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
                    % io:format(
                    %     "Before update: Leader PID=~p, Color=~p, Nodes_in_Cluster=~p, adjClusters=~p~n",
                    %     [self(), Color, Nodes_in_Cluster, Leader#leader.adjClusters]
                    % ),

                    % Update color of a specific cluster in the adjacency list
                    UpdatedAdjClusters = operation:update_adj_cluster_color(
                        Leader#leader.adjClusters, Nodes_in_Cluster, Color, FromPid
                    ),

                    % Log after update
                    % io:format(
                    %     "After update: Leader PID=~p, Updated Color=~p, Updated adjClusters=~p~n",
                    %     [self(), Color, UpdatedAdjClusters]
                    % ),

                    % Create a new event
                    Event1 = event:new(change_color, Color, FromPid),

                    % Update leader record with new adjacency list and last event
                    UpdatedLeader = Leader#leader{
                        adjClusters = UpdatedAdjClusters, last_event = Event1
                    },

                    % Send the updated adjacency clusters to the server
                    % io:format(
                    %     "Sending updated_AdjClusters to server: Server PID=~p, From PID=~p, UpdatedLeader=~p~n",
                    %     [UpdatedLeader#leader.serverID, self(), UpdatedLeader]
                    % ),

                    UpdatedLeader#leader.serverID ! {updated_AdjClusters, self(), UpdatedLeader},

                    % Continue handling messages
                    handle_messages_leader(UpdatedLeader);
                {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore, FromPid} ->
                    % Handle response to a merge request
                    % io:format(
                    %     "-------------------------------------------------- ~p : Received response_to_merge from ~p~n",
                    %     [self(), FromPid]
                    % ),
                    UpdatedAdjClusters = utils:join_adj_clusters(
                        Leader#leader.adjClusters, AdjListIDMaggiore
                    ),
                    FilteredAdjClusters = lists:filter(
                        fun({_, _, LeaderID}) ->
                            LeaderID =/= Leader#leader.node#node.leaderID andalso
                                LeaderID =/= FromPid
                        end,
                        UpdatedAdjClusters
                    ),
                    UpdatedNodeList = utils:join_nodes_list(
                        Leader#leader.nodes_in_cluster, Nodes_in_Cluster
                    ),
                    UpdatedLeader = Leader#leader{
                        adjClusters = FilteredAdjClusters,
                        nodes_in_cluster = UpdatedNodeList
                    },
                    FromPid ! {became_node, self()},
                    receive
                        {turned_to_node, FromPid} ->
                            handle_messages_leader(UpdatedLeader)
                    after 4000 ->
                        io:format(
                            "~p : Timeout waiting for turned_to_node from ~p, proceeding.~n", [
                                self(), FromPid
                            ]
                        ),
                        handle_messages_leader(Leader)
                    end,
                    % io:format(
                    %     "-------------------------------------------------- ~p : Handled response_to_merge of ~p~n",
                    %     [self(), FromPid]
                    % ),
                    handle_messages_leader(UpdatedLeader);
                {merge_request, LeaderID, Event} ->
                    if
                        LeaderID == self() ->
                            io:format(
                                "~p -> Received merge_request from self. Rejecting merge.~n", [
                                    self()
                                ]
                            ),
                            LeaderID ! {merge_rejected, self()},
                            handle_messages_leader(Leader);
                        Leader#leader.merge_in_progress ->
                            io:format(
                                "~p -> Merge in progress. Rejecting merge_request from ~p.~n", [
                                    self(), LeaderID
                                ]
                            ),
                            LeaderID ! {merge_rejected, self()},
                            handle_messages_leader(Leader);
                        true ->
                            % Accept the merge request; set merge_in_progress to true
                            UpdatedLeader = Leader#leader{merge_in_progress = true},
                            % Proceed with merge logic
                            handle_merge_request(UpdatedLeader, LeaderID, Event)
                    end;
                {still_leader, FromPid} ->
                    %% Il leader risponde indicando che è ancora un leader
                    FromPid ! {still_leader_response, self(), true},
                    handle_messages_leader(Leader);
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
                {leader_update_periodic, NewLeader} -> 
                    %% Compare the NewLeader with the current leader (self)
                    if 
                        NewLeader =/= self() -> 
                            %% If the NewLeader is different from the current leader (self), transform to a node
                            io:format("~p : New leader is different from current leader. Transforming to node.~n", [self()]),
                            %% Send the message to the current leader to transform into a regular node
                            Leader#leader.node#node.pid ! {transform_to_normal_node};
                        true -> 
                            %% If they are the same, just update the leader and continue
                            UpdatedLeader = Leader#leader{node = Leader#leader.node#node{leaderID = NewLeader}},
                            handle_messages_leader(UpdatedLeader)
                    end;
                _Other ->
                    % Unhandled messages
                    handle_messages_leader(Leader)
            after 1000 ->
                %% Nessun messaggio ricevuto entro 1000 ms, invio aggiornamenti periodici
                io:format(
                    "~p : Aggiorno i miei adjCLuster sui miei nodi (operazione periodica)~n", [
                        self()
                    ]
                ),
                operation:send_periodic_updates(Leader),
                operation:broadcast_leader_update(Leader),
                %% Continua il loop
                handle_messages_leader(Leader)
            end
    end.

%% --------------------------------------------------------------------
%% Function: node_loop/1
%% Description:
%% Main loop for the node, continuously receiving and processing messages.
%% This function serves as the entry point for message handling, routing
%% each message to the appropriate handler based on its content.
%%
%% Input:
%% - Node: A `#node{}` record containing the node's state and metadata.
%%
%% Preconditions:
%% - Node must be a valid `#node{}` record with required fields populated.
%%
%% Output:
%% - Continuously calls `handle_node_messages/1` to process messages until
%%   the node is terminated or becomes a leader.
%%
%% Usage:
%% - This function is called once at the start and re-entered each time
%%   there are messages to process, ensuring the node is always responsive.
%% --------------------------------------------------------------------
node_loop(Node) ->
    handle_node_messages(Node).

%% --------------------------------------------------------------------
%% Function: handle_node_messages/1
%% Description:
%% Processes messages in the node's queue, updating the node's state as
%% necessary based on the content of each message. This function performs
%% actions like handling color change requests, updating leader info, and
%% promoting the node to a leader if required.
%%
%% Input:
%% - Node: A `#node{}` record representing the current state and attributes
%%   of the node.
%%
%% Preconditions:
%% - Node must be a valid `#node{}` record with necessary fields.
%%
%% Output:
%% - Continuously processes each incoming message and updates the node's
%%   state, calling itself recursively to handle messages as they arrive.
%%
%% Side Effects:
%% - Saves node data persistently via `utils:save_data/1`.
%% - Sends messages to other nodes and updates internal state based on message types.
%% --------------------------------------------------------------------
handle_node_messages(Node) ->
    %% Persist the node's data
    utils:save_data(Node),

    %% Check the length of the message queue
    QueueLength = erlang:process_info(self(), message_queue_len),

    %% If there are no messages, re-enter the main loop
    case QueueLength of
        {message_queue_len, 0} ->
            %% Re-enters the main loop
            node_loop(Node);
        _ ->
            %% Receive and process the next message in the queue
            receive
                %% Handle change color requests
                {change_color_request, Event} ->
                    Node#node.leaderID ! {change_color_request, Event},
                    handle_node_messages(Node);
                %% Update leader information and propagate to child nodes
                {leader_update, NewLeader} ->
                    lists:foreach(
                        fun(Child) ->
                            Child ! {leader_update, NewLeader}
                        end,
                        Node#node.children
                    ),
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    handle_node_messages(UpdatedNode);
                %% Periodic leader update
                {leader_update_periodic, NewLeader} ->
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    handle_node_messages(UpdatedNode);
                %% Forward leader info requests
                {get_leader_info, FromPid} ->
                    Node#node.leaderID ! {get_leader_info, FromPid},
                    handle_node_messages(Node);
                %% Promote node to leader and switch to leader loop
                {new_leader_elected, ServerID, Color, NodesInCluster, AdjacentClusters} ->
                    UpdatedLeader = operation:promote_to_leader(
                        Node,
                        Color,
                        ServerID,
                        NodesInCluster,
                        AdjacentClusters
                    ),
                    leader_loop(UpdatedLeader);
                %% Forward color adjacency updates
                {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
                    Node#node.leaderID ! {color_adj_update, FromPid, Color, Nodes_in_Cluster},
                    handle_node_messages(Node);
                %% Respond that the node is not a leader
                {still_leader, FromPid} ->
                    FromPid ! {still_leader_response, self(), false},
                    handle_node_messages(Node);
                %% Forward any unrecognized message to the leader
                _Other ->
                    Node#node.leaderID ! _Other,
                    handle_node_messages(Node)
            end
    end.

%% --------------------------------------------------------------------
%% Function: collect_change_color_requests/2
%% Description:
%% Collects incoming `change_color_request` events until a specified timeout.
%% This function accumulates color change events in a list and returns it
%% once the timeout expires or if no further events are received within
%% the remaining time.
%%
%% Input:
%% - EndTime: The end time in milliseconds, calculated as the current time plus the desired timeout.
%% - Messages: The list of collected messages, initially an empty list.
%%
%% Preconditions:
%% - EndTime must be a valid integer representing the future time when collection should stop.
%% - Messages must be a list, typically empty when the function is first called.
%%
%% Output:
%% - Returns `{ok, Messages}` where `Messages` is a list of collected `change_color_request` events.
%%
%% Usage:
%% - This function is used during event handling to capture and queue
%%   incoming `change_color_request` events for later processing.
%%
%% Side Effects:
%% - Waits for incoming messages within the remaining time and accumulates any
%%   `change_color_request` events. Ignores unrelated messages.
%% --------------------------------------------------------------------
collect_change_color_requests(EndTime, Messages) ->
    %% Get the current time and calculate the remaining time for collection
    Now = erlang:monotonic_time(millisecond),
    RemainingTime = EndTime - Now,

    %% Check if the remaining time is up
    if
        RemainingTime =< 0 ->
            %% Timeout reached, return collected messages
            {ok, Messages};
        true ->
            receive
                %% Case: Collects a `change_color_request` event
                {change_color_request, NewEvent} ->
                    %% Recurse, adding the new event to the message list
                    collect_change_color_requests(EndTime, [NewEvent | Messages]);
                %% Case: Ignores any other messages and continues collecting
                _Other ->
                    collect_change_color_requests(EndTime, Messages)
            after RemainingTime ->
                %% Timeout reached without receiving a `change_color_request`, return messages
                {ok, Messages}
            end
    end.

%% --------------------------------------------------------------------
%% Function: convert_time_to_ms/1
%% Description:
%% Converts a time tuple `{Hour, Minute, Second}` to milliseconds for easy
%% comparison. This function is useful for timestamp comparisons during merge
%% requests and event handling.
%%
%% Input:
%% - `{Hour, Minute, Second}`: A tuple representing time in hours, minutes, and seconds.
%%
%% Preconditions:
%% - The input tuple should contain valid integers for hours, minutes, and seconds.
%%
%% Output:
%% - Returns the time converted to milliseconds as an integer.
%%
%% Usage:
%% - This function is used in conjunction with timestamp handling, allowing
%%   timestamps to be compared in a consistent format.
%% --------------------------------------------------------------------
convert_time_to_ms({Hour, Minute, Second}) ->
    (Hour * 3600 + Minute * 60 + Second) * 1000.

%% --------------------------------------------------------------------
%% Function: handle_merge_request/3
%% Description:
%% Handles an incoming merge request by comparing the event timestamp and
%% color. If the event is outdated or the color does not match the leader’s
%% current color, the merge is rejected, and the leader continues as normal.
%% If the merge request is valid, the function proceeds to handle further
%% events to complete the merge.
%%
%% Input:
%% - Leader: The #leader{} record representing the current state of the leader.
%% - LeaderID: The PID of the leader requesting the merge.
%% - Event: The #event{} record containing details about the color change and timestamp.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with an initialized last_event field.
%% - LeaderID must be a valid PID requesting the merge.
%% - Event must be a valid #event{} record containing a timestamp and color.
%%
%% Output:
%% - If the merge is accepted, `collect_and_handle_events/3` is called to manage the merge process.
%% - If the merge is rejected due to an outdated event or color mismatch, the leader state is reset,
%%   and the leader message handling resumes.
%%
%% Usage:
%% - This function is invoked when a merge request is received, ensuring that only up-to-date,
%%   color-consistent merge requests proceed.
%%
%% Side Effects:
%% - Sends `{merge_rejected, self()}` to the LeaderID if the merge is rejected.
%% - Calls `handle_messages_leader/1` if the merge is rejected, resetting the leader's state.
%% --------------------------------------------------------------------
handle_merge_request(Leader, LeaderID, Event) ->
    %% Convert event and last event timestamps to milliseconds for comparison
    EventTimestampMs = convert_time_to_ms(Event#event.timestamp),
    LastEventTimestampMs = convert_time_to_ms(Leader#leader.last_event#event.timestamp),

    %% Check if the merge request is outdated or if there's a color mismatch
    if
        %% Case: Outdated event or color mismatch
        EventTimestampMs < LastEventTimestampMs andalso Event#event.color =/= Leader#leader.color ->
            io:format(
                "~p -> Merge request rejected due to outdated timestamp. Rejecting merge.~n", [
                    self()
                ]
            ),
            LeaderID ! {merge_rejected, self()},
            %% Reset merge_in_progress as the merge is rejected
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            handle_messages_leader(UpdatedLeader);
        %% Case: Color mismatch, no outdated timestamp
        Event#event.color =/= Leader#leader.color ->
            io:format("~p -> Merge request received from ID ~p.~n", [self(), LeaderID]),
            io:format("Event color does not match current leader color. Color change detected.~n"),
            LeaderID ! {merge_rejected, self()},
            %% Reset merge_in_progress as the merge is rejected
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            handle_messages_leader(UpdatedLeader);
        %% Case: Valid merge request, proceed with merge
        true ->
            io:format("~p -> Merge request accepted from ID ~p.~n", [self(), LeaderID]),
            %% Proceed with handling events to complete the merge
            collect_and_handle_events(Leader, LeaderID, Event)
    end.

%% --------------------------------------------------------------------
%% Function: collect_and_handle_events/3
%% Description:
%% Collects and processes color change events related to a cluster’s leader
%% status before proceeding with a merge. This function gathers recent color
%% change requests within a specified time window and categorizes them as
%% either old or new events relative to the provided event timestamp. If
%% old events are detected, the merge is canceled, and these events are
%% re-injected into the message queue for further handling. If no old
%% events are detected, the merge proceeds.
%%
%% Input:
%% - Leader: The #leader{} record initiating the merge or color change.
%% - LeaderID: The PID of the leader initiating or awaiting the merge.
%% - Event: The #event{} record containing the event triggering this process.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with initialized fields.
%% - LeaderID must be a valid PID.
%% - Event must be a valid #event{} record containing a timestamp.
%%
%% Output:
%% - No direct return value. Depending on event timing, either initiates a
%%   merge with the specified leader or cancels the merge and reprocesses
%%   older events.
%%
%% Side Effects:
%% - Sends `{response_to_merge, NodesInCluster, AdjClusters, Self}` to proceed
%%   with merge, or `{merge_rejected, Self}` if the merge is canceled.
%% - Re-injects any older events into the message queue if merge is canceled.
%%
%% Usage:
%% - Called when a leader change or merge is requested to determine if other
%%   events with earlier timestamps should take priority. Ensures that merges
%%   only occur if no conflicting color change events are pending.
%% --------------------------------------------------------------------

collect_and_handle_events(Leader, LeaderID, Event) ->
    %% Set the end time for collecting change color requests (2 seconds from now)
    EndTime = erlang:monotonic_time(millisecond) + 2000,
    {ok, CollectedMessages} = collect_change_color_requests(EndTime, []),

    %% Convert event timestamp to milliseconds for easier comparison
    EventTimestampMs = convert_time_to_ms(Event#event.timestamp),

    %% Separate old and new events based on the specified 2-second window
    OldEvents = [
        NewEvent
     || NewEvent <- CollectedMessages,
        convert_time_to_ms(NewEvent#event.timestamp) < EventTimestampMs,
        convert_time_to_ms(NewEvent#event.timestamp) >= EventTimestampMs - 2000
    ],
    NewEvents = [
        NewEvent
     || NewEvent <- CollectedMessages,
        convert_time_to_ms(NewEvent#event.timestamp) > EventTimestampMs
    ],

    %% Determine whether to proceed with or cancel the merge based on collected events
    case OldEvents of
        [] ->
            %% No conflicting events; proceed with the merge
            io:format("No color change events to handle. Proceeding with merge.~n"),
            LeaderID !
                {response_to_merge, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters,
                    self()},
            %% Wait for the leader to confirm node transition
            wait_for_leader_to_become_node(Leader, LeaderID, NewEvents);
        _ ->
            %% Conflicting events detected; cancel the merge
            io:format("Received color change events with older timestamp. Cancelling merge.~n"),
            LeaderID ! {merge_rejected, self()},
            %% Reset merge_in_progress due to merge rejection
            UpdatedLeader = Leader#leader{merge_in_progress = false},
            %% Re-inject old events into the message queue for handling
            lists:foreach(
                fun(Event_change_color) -> self() ! {change_color_request, Event_change_color} end,
                OldEvents
            ),
            %% Resume leader message handling with updated leader
            handle_messages_leader(UpdatedLeader)
    end.

%% --------------------------------------------------------------------
%% Function: wait_for_leader_to_become_node/3
%% Description:
%% Waits for a confirmation that a leader has transitioned to a node role
%% following a successful merge. Upon receiving confirmation, it updates
%% the leader's cluster nodes with the new leader's PID and notifies the
%% server to remove the current process from the leaders list. If no
%% confirmation is received within the timeout, it resets `merge_in_progress`
%% and continues operating as the leader.
%%
%% Input:
%% - Leader: The #leader{} record awaiting confirmation of the merge.
%% - LeaderID: The PID of the leader transitioning to a node.
%% - NewEvents: A list of new color change events to be reprocessed if
%%   the merge completes.
%%
%% Preconditions:
%% - Leader must be a valid #leader{} record with `nodes_in_cluster`.
%% - LeaderID must be a valid PID representing the new leader.
%%
%% Output:
%% - No direct return value. If confirmation is received, it re-injects
%%   new events into the node's message loop. If timeout occurs, resets
%%   `merge_in_progress`.
%%
%% Side Effects:
%% - Sends `{leader_update_periodic, LeaderID}` messages to each node in
%%   the cluster upon receiving `{became_node, LeaderID}` confirmation.
%% - Notifies the server to remove the current leader with `{remove_myself_from_leaders, Self}`.
%%
%% Usage:
%% - Called after a merge request to confirm the role change of a leader.
%% - Ensures the leader either transitions to a node or continues as leader if
%%   no confirmation is received.
%% --------------------------------------------------------------------

wait_for_leader_to_become_node(Leader, LeaderID, NewEvents) ->
    receive
        {became_node, LeaderID} ->
            % Notify each node in the cluster about the new leader
            lists:foreach(
                fun(NodePid) ->
                    io:format("~p : Sending leader_update to ~p with new leader ~p.~n", [
                        self(), NodePid, LeaderID
                    ]),
                    NodePid ! {leader_update_periodic, LeaderID}
                end,
                Leader#leader.nodes_in_cluster
            ),

            % Update the node's leader ID to reflect the new leader
            Node = Leader#leader.node,
            UpdatedNode = Node#node{leaderID = LeaderID},

            % Notify the server to remove this process from the list of leaders
            Leader#leader.serverID ! {remove_myself_from_leaders, self()},

            % Inform the new leader that this process has turned into a node
            LeaderID ! {turned_to_node, self()},
            io:format("~p : Sent turned_to_node to ~p~n", [self(), LeaderID]),

            % Re-inject any new events back into the message queue for processing as a node
            lists:foreach(
                fun(NewEvent) -> self() ! {change_color_request, NewEvent} end, NewEvents
            ),

            % Start the node loop with the updated node configuration
            node_loop(UpdatedNode)
    after 4000 ->
        % Timeout occurred, continue as leader and reset merge_in_progress
        io:format("~p : Timeout waiting for {became_node, LeaderID}. Continuing as leader.~n", [
            self()
        ]),

        % Reset the merge_in_progress flag since the merge didn't complete
        UpdatedLeader = Leader#leader{merge_in_progress = false},

        % Return to handling messages as a leader
        handle_messages_leader(UpdatedLeader)
    end.

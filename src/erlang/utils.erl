-module(utils).

%% ------------------------------------------------------------------
%% @module utils
%% @description
%% This module provides a set of utility functions for managing and processing data 
%% related to clusters, nodes, and events in a distributed system. It includes:
%% - List operations: Functions to remove duplicates, merge lists, and filter elements 
%%   based on specific criteria, such as color or unique identifiers.
%% - Formatting utilities: Functions for converting data, such as timestamps and colors, 
%%   into specific formats or representations.
%% - JSON handling: Functions for converting internal data structures into JSON format, 
%%   and saving them to files for persistent storage and easy readability.
%% - Logging: Utilities for recording system operations with timestamps, enhancing 
%%   traceability and debugging.
%% - Data backup: Functions to store data from nodes and leaders in a file-based format, 
%%   supporting data persistence for recovery or auditing.
%%
%% Each function is designed with input validation, ensuring that data consistency and 
%% integrity are maintained throughout distributed operations. These utilities enhance 
%% modularity and maintainability by isolating common tasks into this shared module.
%% ------------------------------------------------------------------


% Exported functions for list operations
-export([
    remove_duplicates/1,
    check_same_color/2,
    get_same_color/2,
    join_adj_clusters/2,
    join_nodes_list/2,
    is_pid_list/1,
    unique_leader_clusters/1
]).

% Exported functions for formatting utilities
-export([
    format_time/1,
    format_timestamp/1,
    normalize_color/1,
    pid_to_string/1,
    atom_to_string/1
]).

% Exported functions for JSON operations
-export([
    save_leader_data_to_file/1,
    convert_adj_clusters/1,
    convert_node_list/1
]).

% Exported functions for logging
-export([
    log_operation/1
]).

% Exported functions for data backup
-export([
    save_data/1,
    save_node_data_to_file/1
]).

% Include necessary record definitions
-include("includes/node.hrl").
-include("includes/event.hrl").

%% ------------------
%%    LISTS OPERATIONS
%% ------------------

%% Removes duplicate elements from a list.
%% @param List A list of elements.
%% @return A list with duplicates removed.
remove_duplicates(List) ->
    lists:usort(List).

%% Retrieves unique clusters by LeaderID.
%% Preconditions: Clusters is a list of tuples {Pid, Color, LeaderID}.
%% @param Clusters List of cluster data.
%% @return A list of unique clusters by LeaderID.
unique_leader_clusters(Clusters) ->
    ClusterMap = maps:from_list(
        lists:map(fun({Pid, Color, LeaderID}) -> {LeaderID, {Pid, Color, LeaderID}} end, Clusters)
    ),
    maps:values(ClusterMap).

%% Checks if any adjacent cluster has the same color.
%% Preconditions: AdjClusters is a list of tuples {Pid, Color, LeaderID}.
%% @param ColorToMatch The color to match.
%% @param AdjClusters List of adjacent clusters.
%% @return true if an adjacent cluster has the same color, false otherwise.
check_same_color(ColorToMatch, AdjClusters) ->
    lists:member(ColorToMatch, [Color || {_, Color, _} <- AdjClusters, ColorToMatch =:= Color]).

%% Gets a list of adjacent clusters with the same color.
%% Preconditions: AdjClusters is a list of tuples {Pid, Color, LeaderID}.
%% @param ColorToMatch The color to match.
%% @param AdjClusters List of adjacent clusters.
%% @return A list of clusters with the matching color.
get_same_color(ColorToMatch, AdjClusters) ->
    [Match || {_, Color, _} = Match <- AdjClusters, ColorToMatch =:= Color].

%% Joins two lists of adjacent clusters, removing duplicates.
%% @param AdjClusters1 First list of adjacent clusters.
%% @param AdjClusters2 Second list of adjacent clusters.
%% @return A merged list of unique adjacent clusters.
join_adj_clusters(AdjClusters1, AdjClusters2) ->
    lists:usort(AdjClusters1 ++ AdjClusters2).

%% Joins two lists of PIDs, ensuring no duplicates.
%% Preconditions: Both lists should contain only PIDs.
%% @param List1 First list of PIDs.
%% @param List2 Second list of PIDs.
%% @return A merged list of unique PIDs.
join_nodes_list(List1, List2) ->
    % Verifica che entrambi gli input siano liste di PID
    SafeList1 =
        case is_pid_list(List1) of
            true -> List1;
            false -> []
        end,
    SafeList2 =
        case is_pid_list(List2) of
            true -> List2;
            false -> []
        end,
    % Rimuove i duplicati usando usort per ottenere una lista unica
    lists:usort(SafeList1 ++ SafeList2).

%% Checks if a list contains only PIDs.
%% @param List The list to check.
%% @return true if all elements are PIDs, false otherwise.
is_pid_list(List) ->
    lists:all(fun erlang:is_pid/1, List).

%% ------------------
%%    FORMATTING
%% ------------------

%% Formats a time tuple as "HH:MM:SS".
%% Preconditions: Input should be a valid time tuple or 'undefined'.
%% @param TimeTuple A tuple {Hour, Minute, Second} or undefined.
%% @return Formatted time string or "undefined".
format_time({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_time(undefined) -> "undefined".

%% Formats a timestamp tuple as "HH:MM:SS".
%% Preconditions: Input should be a valid timestamp tuple or 'undefined'.
%% @param TimestampTuple A tuple {Hour, Minute, Second} or undefined.
%% @return Formatted timestamp string or "undefined".
format_timestamp({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_timestamp(undefined) -> "undefined".

%% Ensures color is an atom, converting if necessary.
%% @param Color The color to normalize.
%% @return An atom representing the color.
normalize_color(Color) when is_atom(Color) ->
    Color;
normalize_color(Color) when is_list(Color) ->
    list_to_atom(Color).

%% Converts a PID to a string.
%% Preconditions: Input should be a valid PID or 'undefined'.
%% @param Pid The PID to convert.
%% @return String representation of the PID or "undefined".
pid_to_string(Pid) when is_pid(Pid) ->
    erlang:pid_to_list(Pid);
pid_to_string(undefined) ->
    "undefined".

%% Converts an atom to a JSON-friendly string.
%% Preconditions: Input should be an atom.
%% @param Atom The atom to convert.
%% @return String representation of the atom.
atom_to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
atom_to_string(Other) -> Other.

%% ------------------
%%    JSON
%% ------------------

%% Saves leader data as JSON in a file.
%% Preconditions: Leader must be a valid leader record with node, color, and serverID fields.
%% @param Leader The leader data to save.
%% @return none. The leader data is saved in the specified file path.
save_leader_data_to_file(Leader) ->
    Node = Leader#leader.node,
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("../DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),
    filelib:ensure_dir(Filename),
    TimeFormatted = format_time(Node#node.time),
    JsonData = io_lib:format(
        "{\n\"leader_id\": \"~s\", \"color\": \"~s\", \"server_id\": \"~s\", \"adj_clusters\": ~s, \"nodes_in_cluster\": ~s,\n" ++
            "\"node\": {\n\"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": ~p, \"leader_id\": \"~s\", \"pid\": \"~s\", \"neighbors\": ~s\n}}",
        [
            pid_to_string(Node#node.pid),
            atom_to_string(Leader#leader.color),
            pid_to_string(Leader#leader.serverID),
            convert_adj_clusters(Leader#leader.adjClusters),
            convert_node_list(Leader#leader.nodes_in_cluster),
            X, Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            TimeFormatted,
            pid_to_string(Node#node.leaderID),
            pid_to_string(Node#node.pid),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),
    file:write_file(Filename, lists:flatten(JsonData)).

%% Converts a list of adjacent clusters to JSON format.
%% Preconditions: AdjClusters should be a list of tuples {Pid, Color, LeaderID}.
%% @param AdjClusters List of adjacent clusters.
%% @return JSON string representation of the adjacent clusters.
convert_adj_clusters(AdjClusters) ->
    JsonClusters = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [pid_to_string(Pid), atom_to_string(Color), pid_to_string(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- AdjClusters
    ],
    "[" ++ string:join(JsonClusters, ",") ++ "]".

%% Converts a list of nodes to JSON format.
%% Preconditions: Nodes should be a list of PIDs.
%% @param Nodes List of node PIDs.
%% @return JSON string representation of the node list.
convert_node_list(Nodes) ->
    JsonNodes = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    "[" ++ string:join(JsonNodes, ",") ++ "]".

%% ------------------
%%    LOGGING
%% ------------------

%% Logs an operation with a timestamp.
%% Preconditions: Event should be a record with a timestamp, type, color, and from fields.
%% @param Event The event to log.
%% @return none. The event is logged to the specified file path.
log_operation(Event) ->
    TimestampStr = format_timestamp(Event#event.timestamp),
    Reference = get_reference(Event#event.from),
    LogFile = lists:flatten(io_lib:format("../DB/logs/~p.log", [Reference])),
    filelib:ensure_dir(LogFile),
    LogEntry = io_lib:format("~s: {~p, ~p, ~p}~n", [
        TimestampStr, Event#event.type, Event#event.color, Reference
    ]),
    file:write_file(LogFile, lists:flatten(LogEntry), [append]).

%% Retrieves a reference for a process.
%% Preconditions: Pid must be a valid process ID.
%% @param Pid The process ID to get the reference for.
%% @return The registered name or reference of the process.
get_reference(Pid) ->
    {_, Reference} = process_info(Pid, registered_name),
    Reference.

%% ------------------
%%    DATA BACKUP
%% ------------------

%% Saves either node or leader data to a file.
%% Preconditions: NodeOrLeader must be either a node or leader record.
%% @param NodeOrLeader The data to save.
%% @return none. The data is saved in the specified file path.
save_data(NodeOrLeader) ->
    case NodeOrLeader of
        #node{} = Node -> save_node_data_to_file(Node);
        _ -> save_leader_data_to_file(NodeOrLeader)
    end.

%% Saves node data as JSON in a file.
%% Preconditions: Node should be a record with x, y, parent, children, time, leaderID, and neighbors fields.
%% @param Node The node data to save.
%% @return none. The node data is saved in the specified file path.
save_node_data_to_file(Node) ->
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("../DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),
    filelib:ensure_dir(Filename),
    JsonData = io_lib:format(
        "{\n\"pid\": \"~s\", \"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": \"~s\", \"leader_id\": \"~s\", \"neighbors\": ~s\n}",
        [
            pid_to_string(Node#node.pid),
            X, Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            format_time(Node#node.time),
            pid_to_string(Node#node.leaderID),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),
    file:write_file(Filename, lists:flatten(JsonData)).

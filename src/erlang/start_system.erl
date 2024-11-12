-module(start_system).

%% --------------------------------------------------------------------
%% Module: start_system
%% Description:
%% The `start_system` module initiates and configures a distributed node system in a grid layout.
%% It creates a server, generates nodes with color attributes, assigns neighbors, and synchronizes the 
%% initial setup by ensuring nodes receive and acknowledge their configuration. The module supports 
%% loading node colors from a configuration file or using a preset color palette.
%%
%% Key Features:
%% - Initializes the server and grid of nodes in an NxM matrix.
%% - Assigns a unique color to each node, either from a file or a default color palette.
%% - Configures neighbor relationships based on node positions in the grid.
%% - Waits for acknowledgment from all nodes before initiating server setup.
%% - Saves the final node data configuration in JSON format.
%%
%% Preconditions:
%% - The grid dimensions (N, M) should be specified.
%% - An optional file with colors may be provided if FromFile is set to true.
%% - Nodes should be implemented with compatible properties for neighbors and color attributes.
%%
%% Postconditions:
%% - A server process is created and all nodes are initialized with their colors and neighbors.
%% - All nodes are configured and acknowledge their setup to the server.
%% - Final node configuration is saved to a JSON file for further use.
%%
%% Usage:
%% The module is used as the entry point for setting up the system, including server, nodes, 
%% and neighbor configuration, and should be called with desired grid dimensions.
%% --------------------------------------------------------------------

-export([start/3]).
-include("includes/node.hrl").

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white]).

%% --------------------------------------------------------------------
%% Function: load_colors_from_file/1
%% Description:
%% Loads colors from a specified file. Each line in the file represents one color, 
%% which is converted to an atom for easy processing.
%%
%% Input:
%% - Filename: The name of the file containing color data.
%%
%% Preconditions:
%% - The file should exist at the specified path and contain valid color names.
%%
%% Output:
%% - A list of colors in atom form, one for each line in the file.
%% - If the file cannot be read, an empty list is returned.
%% --------------------------------------------------------------------
load_colors_from_file(Filename) ->
    case file:read_file(Filename) of
        {ok, BinaryData} ->
            Lines = binary:split(BinaryData, <<"\n">>, [global]),
            [binary_to_atom(Line, utf8) || Line <- Lines, Line =/= <<>>];
        {error, _Reason} ->
            []
    end.

%% --------------------------------------------------------------------
%% Function: start/3
%% Description:
%% Initializes the server and generates an NxM grid of nodes with colors, either 
%% from a file or a preset palette. Each node is assigned neighbors, and the setup 
%% is synchronized by awaiting acknowledgments from each node.
%%
%% Input:
%% - N: Number of rows in the node grid.
%% - M: Number of columns in the node grid.
%% - FromFile: Boolean indicating whether to load colors from a file.
%%
%% Preconditions:
%% - N and M must be greater than zero.
%% - If FromFile is true, a valid color file should be present at "../config/colors.txt".
%%
%% Output:
%% - No direct output; initializes the system and synchronizes the setup.
%% --------------------------------------------------------------------
start(N, M, FromFile) ->
    ServerPid = server:start_server(self()),

    %% Node creation and color assignment
    Nodes = case FromFile of
        true ->
            Colors = load_colors_from_file("../config/colors.txt"),
            if
                Colors =:= [] -> exit(file_error);
                length(Colors) < N * M -> exit(insufficient_colors);
                true -> [
                    node:new_leader(X, Y, lists:nth((Y - 1) * M + X, Colors), ServerPid, self())
                    || X <- lists:seq(1, N), Y <- lists:seq(1, M)
                ]
            end;
        false ->
            L = length(?palette),
            [node:new_leader(X, Y, lists:nth(rand:uniform(L), ?palette), ServerPid, self())
                || X <- lists:seq(1, N), Y <- lists:seq(1, M)]
    end,

    %% Neighbor assignment
    UpdatedNodes = lists:map(
        fun(#leader{node = Node} = Leader) ->
            X = Node#node.x,
            Y = Node#node.y,
            Pid = Node#node.pid,
            Neighbors = find_neighbors(X, Y, Nodes, N, M),
            UpdatedNode = Node#node{neighbors = Neighbors},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            Pid ! {neighbors, Neighbors},
            UpdatedLeader
        end,
        Nodes
    ),

    ack_loop(UpdatedNodes, length(UpdatedNodes)),
    save_nodes_data(UpdatedNodes),
    ServerPid ! {start_setup, UpdatedNodes, self()},

    receive
        {finih_setup, _LeaderIDs} -> tcp_server:start()
    end.

%% --------------------------------------------------------------------
%% Function: save_nodes_data/1
%% Description:
%% Converts each node's data into JSON format and writes it to a file. 
%% Each node includes details like coordinates, neighbors, and color.
%%
%% Input:
%% - Nodes: List of leader records with complete node details.
%%
%% Preconditions:
%% - Nodes list should be non-empty and contain valid node structures.
%%
%% Output:
%% - No direct output; saves node data to "../data/nodes_data.json".
%% --------------------------------------------------------------------
save_nodes_data(Nodes) ->
    JsonNodes = lists:map(
        fun(#leader{node = Node, color = Color, serverID = ServerID, adjClusters = AdjClusters}) ->
            node_to_json(Node#node.x, Node#node.y, Node#node.parent, Node#node.children, 
                         Node#node.time, Node#node.leaderID, Node#node.pid, Node#node.neighbors, 
                         Color, ServerID, AdjClusters)
        end,
        Nodes
    ),
    JsonString = "[" ++ string:join(JsonNodes, ",") ++ "]",
    file:write_file("../data/nodes_data.json", JsonString).

%% --------------------------------------------------------------------
%% Function: node_to_json/11
%% Description:
%% Converts node data fields to a JSON-formatted string.
%%
%% Input:
%% - X, Y: Coordinates of the node.
%% - Parent, Children: Relationships to other nodes.
%% - Time, LeaderID, Pid: Unique identifiers and timestamps.
%% - Neighbors: List of PIDs for neighboring nodes.
%% - Color: Color assigned to the node.
%% - ServerID: PID of the server managing this node.
%% - AdjClusters: List of adjacent clusters.
%%
%% Preconditions:
%% - All input fields should be initialized and valid for a node.
%%
%% Output:
%% - A JSON string representing the node's data.
%% --------------------------------------------------------------------
node_to_json(X, Y, Parent, Children, Time, LeaderID, Pid, Neighbors, Color, ServerID, AdjClusters) ->
    XStr = integer_to_list(X),
    YStr = integer_to_list(Y),
    ParentStr = pid_to_string(Parent),
    ChildrenStr = lists:map(fun pid_to_string/1, Children),
    TimeStr = io_lib:format("~p", [Time]),
    LeaderIDStr = pid_to_string(LeaderID),
    PidStr = pid_to_string(Pid),
    NeighborsStr = lists:map(fun pid_to_string/1, Neighbors),
    ColorStr = atom_to_list(Color),
    ServerIDStr = pid_to_string(ServerID),
    AdjClustersStr = lists:map(fun pid_to_string/1, AdjClusters),

    io_lib:format(
        "{\"x\": ~s, \"y\": ~s, \"parent\": \"~s\", \"children\": ~s, \"time\": \"~s\", \"leaderID\": \"~s\", \"pid\": \"~s\", \"neighbors\": ~s, \"color\": \"~s\", \"serverID\": \"~s\", \"adjClusters\": ~s}",
        [XStr, YStr, ParentStr, io_lib:format("~p", [ChildrenStr]), TimeStr, LeaderIDStr, 
         PidStr, io_lib:format("~p", [NeighborsStr]), ColorStr, ServerIDStr, 
         io_lib:format("~p", [AdjClustersStr])]
    ).

%% --------------------------------------------------------------------
%% Function: pid_to_string/1
%% Description:
%% Converts an Erlang PID to a string for JSON compatibility.
%%
%% Input:
%% - Pid: The process ID of a node.
%%
%% Preconditions:
%% - Pid must be a valid Erlang PID.
%%
%% Output:
%% - String representation of the PID.
%% --------------------------------------------------------------------
pid_to_string(Pid) ->
    lists:flatten(io_lib:format("~p", [Pid])).

%% --------------------------------------------------------------------
%% Function: ack_loop/2
%% Description:
%% Waits for acknowledgment messages from all nodes to confirm setup completion.
%%
%% Input:
%% - Nodes: List of initialized nodes.
%% - RemainingACKs: Number of acknowledgments expected.
%%
%% Preconditions:
%% - RemainingACKs should equal the number of nodes in the grid.
%%
%% Output:
%% - No direct output; completes when all nodes have acknowledged.
%% --------------------------------------------------------------------
ack_loop(_, 0) ->
    io:format("All acknowledgments received.~n~n~n");
ack_loop(Nodes, RemainingACKs) ->
    receive
        {ack_neighbors, _Pid} ->
            ack_loop(Nodes, RemainingACKs - 1)
    end.

%% --------------------------------------------------------------------
%% Function: find_neighbors/4
%% Description:
%% Identifies neighboring nodes for a specific node in the NxM grid based on coordinates.
%%
%% Input:
%% - X, Y: Coordinates of the current node.
%% - Nodes: List of all nodes in the grid.
%% - N, M: Dimensions of the grid.
%%
%% Preconditions:
%% - X and Y must be valid coordinates within the grid.
%% - Nodes list must include all nodes for accurate neighbor assignment.
%%
%% Output:
%% - A list of PIDs for the neighboring nodes.
%% --------------------------------------------------------------------
find_neighbors(X, Y, Nodes, N, M) ->
    NeighborCoords = [
        {X + DX, Y + DY}
     || DX <- [-1, 0, 1],
        DY <- [-1, 0, 1],
        not (DX =:= 0 andalso DY =:= 0),
        X + DX >= 1,
        X + DX =< N,
        Y + DY >= 1,
        Y + DY =< M
    ],
    [
        NeighborNode#node.pid
     || #leader{node = NeighborNode} <- Nodes,
        lists:member({NeighborNode#node.x, NeighborNode#node.y}, NeighborCoords)
    ].

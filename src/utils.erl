-module(utils).

% lists operations
-export([
    remove_duplicates/1,
    check_same_color/2,
    get_same_color/2,
    join_adj_clusters/2,
    join_nodes_list/2,
    is_pid_list/1
]).
% formatting
-export([
    format_time/1,
    format_timestamp/1,
    normalize_color/1,
    pid_to_string/1,
    atom_to_string/1
]).
% JSON
-export([
    save_leader_data_to_file/1,
    convert_adj_clusters/1,
    convert_node_list/1
]).
% logging
-export([
    log_operation/1
]).
% data backup
-export([
    save_data/1,
    save_node_data_to_file/1
]).

-include("node.hrl").
-include("event.hrl").

%% ------------------
%%
%%  LISTS OPERATIONS
%%
%% ------------------

remove_duplicates(List) ->
    lists:usort(List).

%% Funzione per rimuovere duplicati in base al LeaderID
% unique_leader_clusters(Clusters) ->
%     % Usa una mappa per tenere solo un cluster per LeaderID
%     ClusterMap = maps:from_list(
%         lists:map(fun({Pid, Color, LeaderID}) -> {LeaderID, {Pid, Color, LeaderID}} end, Clusters)
%     ),
%     maps:values(ClusterMap).

%% Checks if there is an adjacent cluster with the same color
check_same_color(ColorToMatch, AdjClusters) ->
    lists:member(ColorToMatch, [Color || {_, Color, _} <- AdjClusters, ColorToMatch =:= Color]).

%% Returns the list of adjacents cluster with the same color
get_same_color(ColorToMatch, AdjClusters) ->
    [Match || {_, Color, _} = Match <- AdjClusters, ColorToMatch =:= Color].

%% Funzione di supporto per unire due liste di cluster adiacenti, evitando duplicati
join_adj_clusters(AdjClusters1, AdjClusters2) ->
    lists:usort(AdjClusters1 ++ AdjClusters2).

%% Funzione di supporto per unire due liste di PID, evitando duplicati
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

%% Funzione di supporto per verificare se una lista contiene solo PID
is_pid_list(List) ->
    lists:all(fun erlang:is_pid/1, List).

%% ------------------
%%
%%    FORMATTING
%%
%% ------------------

%% Funzione di supporto per formattare il tempo in una stringa "HH:MM:SS"
format_time({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_time(undefined) ->
    "undefined".

%% Funzione di supporto per formattare il timestamp in "HH:MM:SS"
format_timestamp({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_timestamp(undefined) ->
    "undefined".

%% Ensures the color is an atom. Converts to atom if it's a string.
normalize_color(Color) when is_atom(Color) ->
    Color;
normalize_color(Color) when is_list(Color) ->
    list_to_atom(Color).

%% Funzione per convertire un PID in stringa
pid_to_string(Pid) when is_pid(Pid) ->
    erlang:pid_to_list(Pid);
pid_to_string(undefined) ->
    "undefined".

%% Funzione per convertire un atomo in una stringa JSON-friendly
atom_to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
atom_to_string(Other) -> Other.

%% ------------------
%%
%%      JSON
%%
%% ------------------
%%
%% Funzione per salvare i dati di Leader in un file JSON locale
save_leader_data_to_file(Leader) ->
    Node = Leader#leader.node,

    % Ottieni le coordinate X e Y per costruire il nome del file
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),

    % Crea la cartella DB/X_Y/ se non esiste
    filelib:ensure_dir(Filename),

    % Ottieni il tempo come stringa formattata "HH:MM:SS"
    TimeFormatted = format_time(Node#node.time),

    % Costruisci i dati JSON del leader e del nodo associato in formato stringa
    JsonData = io_lib:format(
        "{\n\"leader_id\": \"~s\", \"color\": \"~s\", \"server_id\": \"~s\", \"adj_clusters\": ~s, \"nodes_in_cluster\": ~s,\n" ++
            "\"node\": {\n\"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": ~p, \"leader_id\": \"~s\", \"pid\": \"~s\", \"neighbors\": ~s\n}}",
        [
            pid_to_string(Node#node.pid),
            atom_to_string(Leader#leader.color),
            pid_to_string(Leader#leader.serverID),
            convert_adj_clusters(Leader#leader.adjClusters),
            convert_node_list(Leader#leader.nodes_in_cluster),
            X,
            Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            TimeFormatted,
            pid_to_string(Node#node.leaderID),
            pid_to_string(Node#node.pid),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Salva i dati JSON in DB/X_Y/data.json
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Dati di Leader (~p,~p) con PID ~p salvati in: ~s~n", [X, Y, self(), Filename]).

%% Funzione helper per convertire la lista di cluster adiacenti in formato JSON-friendly
convert_adj_clusters(AdjClusters) ->
    JsonClusters = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [pid_to_string(Pid), atom_to_string(Color), pid_to_string(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- AdjClusters
    ],
    "[" ++ string:join(JsonClusters, ",") ++ "]".

%% Funzione helper per convertire la lista di nodi in formato JSON-friendly
convert_node_list(Nodes) ->
    JsonNodes = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    "[" ++ string:join(JsonNodes, ",") ++ "]".

%% ------------------
%%
%%      LOGGING
%%
%% ------------------

%% Funzione per salvare l'operazione nel log con il timestamp passato come parametro
log_operation(Event) ->
    % Formatta il timestamp come stringa
    TimestampStr = format_timestamp(Event#event.timestamp),

    % Crea il percorso per il file di log DB/logs/nodeX_Y.log
    Reference = get_reference(Event#event.from),
    LogFile = lists:flatten(io_lib:format("DB/logs/~p.log", [Reference])),

    % Assicurati che la directory esista
    filelib:ensure_dir(LogFile),

    % Scrivi l'operazione nel file di log
    LogEntry = io_lib:format("~s: {~p, ~p, ~p}~n", [
        TimestampStr, Event#event.type, Event#event.color, Reference
    ]),
    file:write_file(LogFile, lists:flatten(LogEntry), [append]),

    io:format("Operazione loggata: '~s: {~p, ~p, ~p}'~n", [
        TimestampStr, Event#event.type, Event#event.color, Reference
    ]).

get_reference(Pid) ->
    {_, Reference} = process_info(Pid, registered_name),
    Reference.

%% ------------------
%%
%%    DATA BACKUP
%%
%% ------------------

save_data(NodeOrLeader) ->
    % Extract Node and Leader data accordingly
    io:format("SALVO I DATI~n"),
    case NodeOrLeader of
        #node{} = Node ->
            % Handle node data saving
            save_node_data_to_file(Node);
        _ ->
            % Handle leader data saving
            save_leader_data_to_file(NodeOrLeader)
    end.

save_node_data_to_file(Node) ->
    % Get coordinates X and Y
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),

    % Ensure the directory exists
    filelib:ensure_dir(Filename),

    % Costruisci i dati JSON del nodo in formato stringa
    JsonData = io_lib:format(
        "{\n\"pid\": \"~s\", \"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": \"~s\", \"leader_id\": \"~s\", \"neighbors\": ~s\n}",
        [
            pid_to_string(Node#node.pid),
            X,
            Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            format_time(Node#node.time),
            pid_to_string(Node#node.leaderID),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Save the JSON data to the file
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Node data saved in: ~s~n", [Filename]).

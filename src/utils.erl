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
    log_operation/1,
    reference/2
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
    RefNode = get_reference(Node#node.pid),
    RefLeader = get_reference(Node#node.leaderID),

    % Costruisce il nome del file con la reference del Pid
    Filename = io_lib:format("DB/json/~p.json", [RefNode]),

    % Crea la cartella se non esiste
    filelib:ensure_dir(Filename),

    % Costruisci i dati JSON del leader e del nodo associato in formato stringa
    JsonData = io_lib:format(
        "{\n\"leader_id\": \"~s\", \"color\": \"~s\", \"server_id\": \"~s\", \"adj_clusters\": ~s, \"cluster_nodes\": ~s,\n" ++
            "\"node\": {\n\"pid\": \"~s\", \"x\": ~p, \"y\": ~p, \"leader_id\": \"~s\", \"neighbors\": ~s\n}}",
        [
            RefLeader,
            atom_to_string(Leader#leader.color),
            server,
            convert_adj_clusters(Leader#leader.adj_clusters),
            convert_node_list(Leader#leader.cluster_nodes),
            RefNode,
            Node#node.x,
            Node#node.y,
            RefLeader,
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Salva i dati JSON in Filename
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Dati del Leader ~p salvati in: ~s~n", [RefLeader, Filename]).

%% Funzione helper per convertire la lista di cluster adiacenti in formato JSON-friendly
convert_adj_clusters(AdjClusters) ->
    JsonClusters = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [get_reference(Pid), atom_to_string(Color), get_reference(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- AdjClusters
    ],
    "[" ++ string:join(JsonClusters, ",") ++ "]".

%% Funzione helper per convertire la lista di nodi in formato JSON-friendly
convert_node_list(Nodes) ->
    JsonNodes = [io_lib:format("\"~s\"", [get_reference(NodePid)]) || NodePid <- Nodes],
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

reference(Pid, Node) ->
    register(
        list_to_atom(
            lists:flatten(
                io_lib:format("node~p_~p", [Node#node.x, Node#node.y])
            )
        ),
        Pid
    ).

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
    % Get references
    RefNode = get_reference(Node#node.pid),
    RefLeader = get_reference(Node#node.leaderID),

    % Costruisce il nome del file con la reference del Pid
    Filename = io_lib:format("DB/json/~p.json", [RefNode]),

    % Ensure the directory exists
    filelib:ensure_dir(Filename),

    % Costruisci i dati JSON del nodo in formato stringa
    JsonData = io_lib:format(
        "{\n\"pid\": \"~s\", \"x\": ~p, \"y\": ~p, \"leader_id\": \"~s\", \"neighbors\": ~s\n}",
        [
            RefNode,
            Node#node.x,
            Node#node.y,
            RefLeader,
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Save the JSON data to Filename
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Node data saved in: ~s~n", [Filename]).

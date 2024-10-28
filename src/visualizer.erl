-module(visualizer).
-export([start_visualizer/1, check_for_updates/1, read_leader_configuration_csv/1]).

%% Avvio del visualizzatore
start_visualizer(NODES) ->
    io:format("Visualizer inizia a monitorare il file CSV per eventuali cambiamenti...~n"),
    check_for_updates(NODES).

%% Loop per controllare i cambiamenti nel file CSV ogni 2 secondi
check_for_updates(NODES) ->
    %% Legge e visualizza il contenuto di leader_configuration.csv
    case read_leader_configuration_csv("leader_configuration.csv") of
        ok ->
            io:format("File leader_configuration.csv letto con successo.~n");
        {error, nofile} ->
            io:format("File leader_configuration.csv non trovato. Riprovo tra 2 secondi...~n");
        {error, Reason} ->
            io:format("Errore nella lettura del file leader_configuration.csv: ~p~n", [Reason])
    end,
    %% Continua il loop ogni 2 secondi
    timer:sleep(2000),
    check_for_updates(NODES).

%% Funzione per leggere e visualizzare la configurazione CSV dei leader
read_leader_configuration_csv(FilePath) ->
    case file:read_file(FilePath) of
        {ok, Content} ->
            %% Converte il contenuto del file CSV in liste di righe e campi
            Lines = string:split(binary_to_list(Content), "\n", all),
            DataRows = lists:map(fun parse_csv_row/1, tl(Lines)), %% Ignora l'intestazione
            %% Costruisce una mappa della griglia con NODES
            GridMap = build_grid_map(NODES, DataRows),
            %% Stampa la griglia su un file
            print_grid_to_file(GridMap),
            ok;
        {error, enoent} ->
            {error, nofile};
        {error, Reason} ->
            {error, Reason}
    end.

%% Funzione per analizzare una riga CSV
parse_csv_row(Line) ->
    %% Divide la riga CSV in campi e li converte in termini appropriati
    [LeaderPidStr, ColorStr, NodesStr, AdjacentClustersStr] = string:split(Line, ",", all),
    Color = list_to_atom(ColorStr),
    Nodes = string:split(NodesStr, "|", all),
    AdjacentClusters = lists:map(fun parse_cluster/1, string:split(AdjacentClustersStr, "|", all)),
    #{leader_pid => LeaderPidStr, color => Color, nodes => Nodes, adjacent_clusters => AdjacentClusters}.

%% Funzione per analizzare ciascun cluster adiacente
parse_cluster(ClusterStr) ->
    [PidStr, ColorStr] = string:split(ClusterStr, ":", all),
    {PidStr, list_to_atom(ColorStr)}.

%% Funzione per costruire una mappa della griglia dai dati di configurazione
build_grid_map(NODES, Config) ->
    lists:foldl(fun({X, Y, Pid}, Acc) ->
        Color = get_color(Pid, Config),
        Leader = is_leader(Pid, Config),
        MapEntry = {X, Y, Color, Leader},
        [MapEntry | Acc]
    end, [], NODES).

%% Funzione per ottenere il colore di un PID dal CSV
get_color(Pid, Config) ->
    case lists:keyfind(Pid, leader_pid, Config) of
        {_, #{color := Color}} -> Color;
        _ -> undefined
    end.

%% Funzione per verificare se un nodo è un leader
is_leader(Pid, Config) ->
    case lists:keyfind(Pid, leader_pid, Config) of
        false -> false;
        _ -> true
    end.

%% Mappa dei colori con lettere
color_to_letter(red) -> "R";
color_to_letter(green) -> "G";
color_to_letter(blue) -> "B";
color_to_letter(yellow) -> "Y";
color_to_letter(orange) -> "O";
color_to_letter(purple) -> "P";
color_to_letter(pink) -> "K";
color_to_letter(brown) -> "N";
color_to_letter(black) -> "L";
color_to_letter(white) -> "W";
color_to_letter(undefined) -> " ".

%% Funzione per stampare la griglia su un file txt
print_grid_to_file(GridMap) ->
    {ok, File} = file:open("grid_output.txt", [write]),
    lists:foreach(fun(Row) ->
        %% Formatta ogni riga come stringa
        FormattedRow = lists:map(fun({_, _, Color, Leader}) ->
            Letter = color_to_letter(Color),
            if Leader -> Letter ++ "*"; true -> Letter end
        end, Row),
        %% Unisce i nodi in una riga con spazi
        Line = string:join(FormattedRow, " ") ++ "\n",
        io:format(File, "~s", [Line])
    end, group_rows(GridMap)),
    file:close(File),
    io:format("Griglia dei nodi salvata su grid_output.txt~n").

%% Funzione per raggruppare i nodi per riga
group_rows(GridMap) ->
    lists:foldl(fun({X, Y, Color, Leader}, Acc) ->
        case lists:keyfind(X, 1, Acc) of
            false -> [{X, [{X, Y, Color, Leader}]} | Acc];
            {X, List} -> lists:keyreplace(X, 1, Acc, {X, [{X, Y, Color, Leader} | List]})
        end
    end, [], GridMap).

%% Funzione di utilità per convertire un PID in stringa
pid_to_string(Pid) ->
    lists:flatten(io_lib:format("~p", [Pid])).

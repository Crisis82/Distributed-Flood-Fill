%% start_system.erl
-module(start_system).
-export([start/2]).

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white]).

%% Funzione principale che avvia il sistema, il server e i nodi, imposta la sincronizzazione e salva i dati dei nodi.
%% Input:
%% - N: numero di righe della matrice dei nodi
%% - M: numero di colonne della matrice dei nodi
%% Output:
%% - Avvia il server e configura i nodi; salva i dati dei nodi in un file JSON
start(N, M) ->
    %% Avvio del server
    io:format("Sono start_system e avvio server.~n"),
    ServerPid = server:start_server(),
    io:format("Sono start_system e ho concluso l'avvio del server.~n"),

    %% Creazione dei nodi nella griglia NxM
    io:format("Sono start_system e inizio a creare nodi.~n"),
    L = length(?palette),
    % Crea ogni nodo con coordinate (X, Y) e un colore casuale
    Nodes = [
        {X, Y,
            node:create_node(node:new_leader({X, Y}, lists:nth(rand:uniform(L), ?palette)), self())}
     || X <- lists:seq(1, N), Y <- lists:seq(1, M)
    ],
    io:format("Sono start_system e ho finito di creare nodi.~n"),

    %% Sincronizzazione dei nodi con il time_server
    io:format("Sono start_system ed avvio il sync fra time-server e nodi.~n"),
    % Avvia il server del tempo e sincronizza i nodi
    time_server:start(Nodes),

    %% Assegnazione dei vicini per ciascun nodo
    io:format("Sono start_system e assegno i vicini ai nodi.~n"),
    % Crea una mappa delle coordinate dei nodi per accesso rapido
    NodeMap = maps:from_list([{{X, Y}, Pid} || {X, Y, Pid} <- Nodes]),
    lists:foreach(
        fun({X, Y, Pid}) ->
            % Trova i vicini del nodo e li invia al processo del nodo
            Neighbors = find_neighbors(X, Y, N, M, NodeMap),
            PIDs = [element(3, Neighbor) || Neighbor <- Neighbors],
            % Invia i PID dei vicini al nodo
            element(3, Pid) ! {neighbors, PIDs}
        end,
        Nodes
    ),
    io:format("Sono start_system e ho assegnato i vicini ai nodi.~n"),

    %% Attendi gli ACK da tutti i nodi per confermare la configurazione
    ack_loop(Nodes, length(Nodes)),

    %% Dopo aver ricevuto tutti gli ACK, invia il setup al server
    io:format("Tutti gli ACK ricevuti, avvio il setup dei nodi con il server.~n"),

    % Appiattisce la lista dei nodi per salvarli come JSON
    NODES = flatten_nodes(Nodes),
    % Salva i dati dei nodi
    save_nodes_data(NODES),

    % Invia i nodi al server per completare il setup
    io:format("Invio messaggio {start_setup, ~p} a ~p.~n", [NODES, ServerPid]),
    ServerPid ! {start_setup, NODES},

    % Avvia il server TCP per la visualizzazione
    io:format("Avvio il tcp_server per visualizzare i nodi.~n"),
    tcp_server:start().

%% Funzione che salva i dati dei nodi in un file JSON
%% Input:
%% - Nodes: lista di tuple {X, Y, Pid} per ciascun nodo
%% Output:
%% - Nessun output diretto, ma salva un file "nodes_data.json" contenente i dati dei nodi
save_nodes_data(Nodes) ->
    % Converte ciascun nodo in stringa JSON
    JsonNodes = lists:map(
        fun({X, Y, Pid}) ->
            node_to_json(X, Y, Pid)
        end,
        Nodes
    ),
    % Combina le stringhe dei nodi in un array JSON
    JsonString = "[" ++ string:join(JsonNodes, ",") ++ "]",
    % Scrive l'array JSON su file
    file:write_file("nodes_data.json", JsonString).

%% Funzione di utilità per convertire un singolo nodo in formato JSON
%% Input:
%% - X, Y: coordinate del nodo
%% - Pid: processo ID del nodo
%% Output:
%% - Restituisce una stringa JSON che rappresenta il nodo
node_to_json(X, Y, Pid) ->
    XStr = integer_to_list(X),
    YStr = integer_to_list(Y),
    PidStr = pid_to_string(Pid),
    io_lib:format("{\"x\": ~s, \"y\": ~s, \"pid\": \"~s\"}", [XStr, YStr, PidStr]).

%% Funzione per convertire un PID in una stringa
%% Input:
%% - Pid: processo ID Erlang
%% Output:
%% - Una stringa che rappresenta il PID
pid_to_string(Pid) ->
    erlang:pid_to_list(Pid).

%% Loop che attende tutti gli ACK dai nodi per completare la configurazione
%% Input:
%% - Nodes: lista dei nodi configurati
%% - RemainingACKs: numero di ACK ancora attesi
%% Output:
%% - Si conclude una volta che tutti gli ACK sono stati ricevuti
ack_loop(_, 0) ->
    io:format("Tutti gli ACK sono stati ricevuti.~n");
ack_loop(Nodes, RemainingACKs) ->
    receive
        {ack_neighbors, Pid} ->
            % Log dell'ACK ricevuto dal nodo specificato
            io:format("Ricevuto ACK dal nodo con PID: ~p~n", [Pid]),
            % Continua ad attendere finché non riceve tutti gli ACK richiesti
            ack_loop(Nodes, RemainingACKs - 1)
    end.

%% Funzione per trovare i vicini di un nodo nella griglia
%% Input:
%% - X, Y: coordinate del nodo corrente
%% - N, M: dimensioni massime della griglia (NxM)
%% - NodeMap: mappa che associa le coordinate al PID del nodo
%% Output:
%% - Restituisce una lista di PIDs dei vicini del nodo corrente
find_neighbors(X, Y, N, M, NodeMap) ->
    % Calcola le coordinate dei potenziali vicini (esclude il nodo stesso)
    NeighborCoords = [
        {X + DX, Y + DY}
     || DX <- [-1, 0, 1],
        DY <- [-1, 0, 1],
        not (DX == 0 andalso DY == 0),
        X + DX >= 1,
        X + DX =< N,
        Y + DY >= 1,
        Y + DY =< M
    ],
    % Ottiene il PID dei vicini dalle coordinate trovate
    [
        Pid
     || {NX, NY} <- NeighborCoords,
        Pid <- [maps:get({NX, NY}, NodeMap)]
    ].

%% Funzione di utilità per appiattire la lista dei nodi se necessario
%% Input:
%% - Nodes: lista di nodi, dove ciascun nodo può essere {X, Y, Pid} o {X, Y, {_, _, Pid}}
%% Output:
%% - Restituisce una lista di nodi {X, Y, Pid} senza annidamenti
flatten_nodes(Nodes) ->
    % Verifica se la struttura è già appiattita (il terzo elemento è direttamente un PID)
    case
        lists:any(
            fun
                ({_, _, Pid}) -> is_pid(Pid);
                (_) -> false
            end,
            Nodes
        )
    of
        % Se già appiattito, restituisce Nodes così com'è
        true -> Nodes;
        % Altrimenti, appiattisce il terzo elemento in ciascun nodo
        false -> [{X, Y, Pid} || {X, Y, {_, _, Pid}} <- Nodes]
    end.

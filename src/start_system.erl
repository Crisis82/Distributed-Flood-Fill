%% start_system.erl
-module(start_system).
-export([start/2]).
-include("node.hrl").

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white]).

%% Funzione principale che avvia il sistema, il server e i nodi, imposta la sincronizzazione e salva i dati dei nodi.
%% Input:
%% - N: numero di righe della matrice dei nodi
%% - M: numero di colonne della matrice dei nodi
start(N, M) ->
    %% Avvio del server
    io:format("Sono start_system e avvio server.~n"),
    ServerPid = server:start_server(self()),
    io:format("Sono start_system e ho concluso l'avvio del server.~n"),

    %% Creazione dei nodi nella griglia NxM
    io:format("Sono start_system e inizio a creare nodi.~n"),
    L = length(?palette),
    % Crea ogni nodo con coordinate (X, Y) e un colore casuale
    Nodes = [
        node:new_leader(X, Y, lists:nth(rand:uniform(L), ?palette), ServerPid, self())
     || X <- lists:seq(1, N), Y <- lists:seq(1, M)
    ],

    %% Stampa delle informazioni dei nodi creati
    io:format("I seguenti nodi sono stati creati:.~n"),
    lists:foreach(
        fun(#leader{node = Node, color = Color, serverID = ServerID, adjClusters = AdjClusters}) ->
            io:format("Node Information:~n"),
            io:format("  Coordinates: (~p, ~p)~n", [Node#node.x, Node#node.y]),
            io:format("  Parent: ~p~n", [Node#node.parent]),
            io:format("  Children: ~p~n", [Node#node.children]),
            io:format("  Time: ~p~n", [Node#node.time]),
            io:format("  Leader ID: ~p~n", [Node#node.leaderID]),
            io:format("  PID: ~p~n", [Node#node.pid]),
            io:format("  Color: ~p~n", [Color]),
            io:format("  Server ID: ~p~n", [ServerID]),
            io:format("  Adjacent Clusters: ~p~n~n", [AdjClusters])
        end,
        Nodes
    ),

    io:format("Sono start_system e ho finito di creare nodi.~n"),

    %% Itera attraverso ciascun nodo nella lista `Nodes`, assegna i vicini e aggiorna il campo neighbors
    UpdatedNodes = lists:map(
        fun(#leader{node = Node} = Leader) ->
            X = Node#node.x,
            Y = Node#node.y,
            Pid = Node#node.pid,

            %% Trova i vicini basandosi direttamente sulla lista `Nodes`
            Neighbors = find_neighbors(X, Y, Nodes, N, M),

            %% Stampa i PID dei vicini
            io:format("Node (~p, ~p) PID: ~p has neighbors: ~p~n", [X, Y, Pid, Neighbors]),

            %% Crea una nuova versione di Leader con il campo neighbors aggiornato
            UpdatedNode = Node#node{neighbors = Neighbors},
            UpdatedLeader = Leader#leader{node = UpdatedNode},

            %% Invia i vicini al processo nodo
            io:format(
                "Sono il start_system ~p e invio a PID: ~p il messaggio: {neighbors, ~p}~n", [
                    self(), Pid, Neighbors
                ]
            ),
            Pid ! {neighbors, Neighbors},

            %% Restituisce il Leader aggiornato
            UpdatedLeader
        end,
        Nodes
    ),

    io:format("Sono start_system e ho assegnato i vicini ai nodi.~n"),

    %% Attendi gli ACK da tutti i nodi per confermare la configurazione
    ack_loop(UpdatedNodes, length(UpdatedNodes)),

    %% Sincronizzazione dei nodi con il time_server
    io:format("Sono start_system ed avvio il sync fra time-server e nodi.~n"),
    time_server:start(UpdatedNodes),

    %% Dopo aver ricevuto tutti gli ACK, invia il setup al server
    io:format("Tutti gli ACK ricevuti, avvio il setup dei nodi con il server.~n"),

    % Appiattisce la lista dei nodi per salvarli come JSON
    % Salva i dati dei nodi
    io:format("Nodes = ~p~n", [UpdatedNodes]),
    save_nodes_data(UpdatedNodes),

    %% Stampa delle informazioni dei nodi creati
    io:format("I seguenti nodi sono stati creati:.~n"),
    lists:foreach(
        fun(#leader{node = Node, color = Color, serverID = ServerID, adjClusters = AdjClusters}) ->
            io:format("Node Information:~n"),
            io:format("  Coordinates: (~p, ~p)~n", [Node#node.x, Node#node.y]),
            io:format("  Parent: ~p~n", [Node#node.parent]),
            io:format("  Children: ~p~n", [Node#node.children]),
            io:format("  Time: ~p~n", [Node#node.time]),
            io:format("  Leader ID: ~p~n", [Node#node.leaderID]),
            io:format("  PID: ~p~n", [Node#node.pid]),
            io:format("  Color: ~p~n", [Color]),
            io:format("  Server ID: ~p~n", [ServerID]),
            io:format("  Adjacent Clusters: ~p~n~n", [AdjClusters])
        end,
        UpdatedNodes
    ),

    % Invia i nodi al server per completare il setup
    io:format("Invio messaggio {start_setup, ~p, ~p} a ~p.~n", [UpdatedNodes, self(), ServerPid]),
    ServerPid ! {start_setup, UpdatedNodes, self()},

    % Avvia il server TCP per la visualizzazione
    receive
        {finih_setup, _LeaderIDs} ->
            io:format("Avvio il tcp_server per visualizzare i nodi.~n"),
            tcp_server:start()
        % io:format("FINITO, ora inizio a fare cose belle.~n"),
        % simulation:start(LeaderIDs, "failure")
    end.

%% Funzione che salva i dati dei nodi in un file JSON con tutti i campi
%% Input:
%% - Nodes: lista di record `leader`, ciascuno contenente un nodo `node` con tutti i campi
%% Output:
%% - Nessun output diretto, ma salva un file "nodes_data.json" contenente i dati dei nodi completi
save_nodes_data(Nodes) ->
    % Converte ciascun nodo in stringa JSON con tutti i campi
    JsonNodes = lists:map(
        fun(#leader{node = Node, color = Color, serverID = ServerID, adjClusters = AdjClusters}) ->
            node_to_json(
                Node#node.x,
                Node#node.y,
                Node#node.parent,
                Node#node.children,
                Node#node.time,
                Node#node.leaderID,
                Node#node.pid,
                Node#node.neighbors,
                Color,
                ServerID,
                AdjClusters
            )
        end,
        Nodes
    ),
    % Combina le stringhe dei nodi in un array JSON
    JsonString = "[" ++ string:join(JsonNodes, ",") ++ "]",
    % Scrive l'array JSON su file
    file:write_file("nodes_data.json", JsonString).

%% Funzione di utilità per convertire un singolo nodo in formato JSON con tutti i campi
%% Input:
%% - Parametri dei campi del nodo
%% Output:
%% - Restituisce una stringa JSON che rappresenta il nodo completo
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
        [
            XStr,
            YStr,
            ParentStr,
            io_lib:format("~p", [ChildrenStr]),
            TimeStr,
            LeaderIDStr,
            PidStr,
            io_lib:format("~p", [NeighborsStr]),
            ColorStr,
            ServerIDStr,
            io_lib:format("~p", [AdjClustersStr])
        ]
    ).

%% Funzione di utilità per convertire un PID in una stringa per il JSON
pid_to_string(Pid) ->
    lists:flatten(io_lib:format("~p", [Pid])).

%% Loop che attende tutti gli ACK dai nodi per completare la configurazione
%% Input:
%% - Nodes: lista dei nodi configurati
%% - RemainingACKs: numero di ACK ancora attesi
%% Output:
%% - Si conclude una volta che tutti gli ACK sono stati ricevuti
ack_loop(_, 0) ->
    io:format("Tutti gli ACK sono stati ricevuti.~n~n~n");
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
%% - Nodes: lista dei nodi esistenti
%% - N, M: dimensioni della griglia
%% Output:
%% - Restituisce una lista di PID dei vicini del nodo corrente
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

    %% Trova i PID dei nodi vicini in base alle coordinate
    [
        NeighborNode#node.pid
     || #leader{node = NeighborNode} <- Nodes,
        lists:member({NeighborNode#node.x, NeighborNode#node.y}, NeighborCoords)
    ].

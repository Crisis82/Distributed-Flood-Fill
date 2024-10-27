%% start_system.erl
-module(start_system).
-export([start/0]).

start() ->
    %% Avvio del server
    io:format("Sono start_system e avvio server.~n"),
    ServerPid = server:start_server(),
    io:format("Sono start_system e ho concluso l'avvio del server.~n"),

    %% Lettura delle dimensioni dalla matrice NxM
    io:format("Sono start_system e leggo dimensioni.~n"),
    {ok, DimBinary} = file:read_file("dimensions.txt"),
    DimStrings = binary:split(DimBinary, [<<"\n">>], [global, trim]),
    [N, M] = [list_to_integer(binary_to_list(X)) || X <- DimStrings],

    %% Lettura dei colori
    io:format("Sono start_system e leggo colori.~n"),
    {ok, ColorsBinary} = file:read_file("colors.txt"),
    Colors = lists:map(
        fun binary_to_list/1, binary:split(ColorsBinary, [<<"\n">>], [global, trim])
    ),

    %% Creazione dei nodi
    io:format("Sono start_system e inizio a creare nodi.~n"),
    Nodes = [
        {X, Y, node:create_node({X, Y}, lists:nth(Y, lists:nth(X, Colors)), self())}
     || X <- lists:seq(1, N), Y <- lists:seq(1, M)
    ],
    io:format("Sono start_system e ho finito di creare nodi.~n"),

    %% Sync fra time_server e nodi
    io:format("Sono start_system ed avvio il sync fra time-server e nodi.~n"),
    time_server:start(Nodes),

    %% Assegnazione dei vicini
    io:format("Sono start_system e assegno i vicini ai nodi.~n"),
    %% Costruisci una mappa per accesso rapido ai nodi
    NodeMap = maps:from_list([{{X, Y}, Pid} || {X, Y, Pid} <- Nodes]),
    lists:foreach(
        fun({X, Y, Pid}) ->
            Neighbors = find_neighbors(X, Y, N, M, NodeMap),
            PIDs = [element(3, Neighbor) || Neighbor <- Neighbors],
            %% Invia i vicini e attendi ACK
            element(3, Pid) ! {neighbors, PIDs}
        end,
        Nodes
    ),
    io:format("Sono start_system e ho assegnato i vicini ai nodi.~n"),

    %% Attendi conferma dai nodi (ACK)
    ack_loop(Nodes, length(Nodes)),

    %% Dopo aver ricevuto tutti gli ACK, avvia il setup del server
    io:format("Tutti gli ACK ricevuti, avvio il setup dei nodi con il server.~n"),

    NODES = flatten_nodes(Nodes),

    %% io:format("Nodes = ~p.~n", [NODES]),

    io:format("Invio messaggio {start_setup, ~p} a ~p.~n", [NODES, ServerPid]),
    ServerPid ! {start_setup, NODES}.

%% Loop che attende tutti gli ACK
ack_loop(_, 0) ->
    io:format("Tutti gli ACK sono stati ricevuti.~n");
ack_loop(Nodes, RemainingACKs) ->
    receive
        {ack_neighbors, Pid} ->
            io:format("Ricevuto ACK dal nodo con PID: ~p~n", [Pid]),
            ack_loop(Nodes, RemainingACKs - 1)
    end.

%% Trova i vicini di un nodo
find_neighbors(X, Y, N, M, NodeMap) ->
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
    [
        Pid
     || {NX, NY} <- NeighborCoords,
        Pid <- [maps:get({NX, NY}, NodeMap)]
    ].

%% Funzione per rimuovere l'annidamento delle tuple, se esiste
flatten_nodes(Nodes) ->
    % io:format("Nodes = ~p~n",[Nodes]),

    %% Verifica se il terzo elemento è già un PID (quindi non c'è annidamento)
    case
        lists:any(
            fun
                ({_, _, Pid}) -> is_pid(Pid);
                (_) -> false
            end,
            Nodes
        )
    of
        %% Se è già appiattito, restituisci Nodes così com'è
        true -> Nodes;
        %% Esegui il flattening se necessario
        false -> [{X, Y, Pid} || {X, Y, {_, _, Pid}} <- Nodes]
    end.

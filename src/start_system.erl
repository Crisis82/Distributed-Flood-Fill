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

    %% Creazione dei nodi
    io:format("Sono start_system e inizio a creare nodi.~n"),
    Palette = [red, green, blue, yellow, orange, purple, pink, brown, black, white],
    L = length(Palette),
    Nodes = [
        {X, Y, node:create_node({X, Y}, lists:nth(rand:uniform(L), Palette), self())}
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
    % Salva NODES come stringa
    save_nodes_data(NODES),

    io:format("Invio messaggio {start_setup, ~p} a ~p.~n", [NODES, ServerPid]),
    ServerPid ! {start_setup, NODES},

    %% Alla fine di start_system:start/0
    io:format("Avvio il visualizer per monitorare i cambiamenti.~n"),
    visualizzatore:start().


% Funzione principale per convertire e salvare i nodi in formato JSON
save_nodes_data(Nodes) ->
    % Converte la lista di nodi in una lista di stringhe JSON-compatibili
    JsonNodes = lists:map(fun({X, Y, Pid}) ->
                              node_to_json(X, Y, Pid)
                          end, Nodes),
                          
    % Combina le stringhe dei nodi in un array JSON
    JsonString = "[" ++ string:join(JsonNodes, ",") ++ "]",
    
    % Scrive il JSON su file
    file:write_file("nodes_data.json", JsonString).

% Funzione di utilità per convertire un singolo nodo in formato JSON
node_to_json(X, Y, Pid) ->
    XStr = integer_to_list(X),
    YStr = integer_to_list(Y),
    PidStr = pid_to_string(Pid),
    io_lib:format("{\"x\": ~s, \"y\": ~s, \"pid\": \"~s\"}", [XStr, YStr, PidStr]).

% Funzione di utilità per convertire un PID in stringa
pid_to_string(Pid) ->
    erlang:pid_to_list(Pid).

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
%% node.erl
-module(node).
-export([create_node/3, node_loop/9, node_loop/10, node_loop_propagate/12]).


%% Funzione per la creazione di un nodo
%% La funzione crea un processo nodo, inizializzandolo con posizione (X, Y), colore, e PID del sistema di avvio
create_node({X, Y}, Color, StartSystemPid) ->
    Pid = spawn(fun() -> node_loop(X,                 % Posizione X
                                   Y,                 % Posizione Y
                                   Color,             % Colore del nodo
                                   StartSystemPid,    % PID del sistema di avvio
                                   false,             % Stato di visita (Visited)
                                   self(),            % ID del Leader (inizialmente sé stesso)
                                   0,                 % Tempo (sincronizzato dal server)
                                   undefined,         % Nodo padre (Parent)
                                   [])                % Lista di figli (Children)
                end),
    io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [X, Y, Color, Pid]),
    {X, Y, Pid}.

%% Loop principale del nodo
%% Questa funzione gestisce il ciclo di ricezione dei messaggi e lo stato del nodo
node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children) ->
    receive
        %% Gestione dei vicini
        %% Riceve la lista dei nodi vicini e la memorizza, notificando il sistema di avvio
        {neighbors, Neighbors} ->
            io:format("Node (~p, ~p) received neighbors: ~p~n", [X, Y, Neighbors]),
            StartSystemPid ! {ack_neighbors, self()},
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

        %% Gestione di altri messaggi non definiti per debugging
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [X, Y]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children)
    end.

%% Variante del loop principale che include i vicini nel parametro
node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors) ->
    receive
        %% Richiesta di setup dal server
        %% Avvia la propagazione dei messaggi di setup se il nodo non è stato ancora visitato
        {setup_server_request, FromPid} ->
            if
                %% Nodo già visitato, risponde al server con 'node_already_visited'
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, already visited, responding to server.~n",
                        [X, Y]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

                %% Nodo non visitato, avvia la propagazione del messaggio di setup
                true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, not visited, starting propagation of my leaderID: ~p.~n",
                        [X, Y, LeaderID]
                    ),
                    UpdatedVisited = true,
                    %% Inizia la propagazione come nodo iniziatore (initiator)
                    node_loop_propagate(
                        X,
                        Y,
                        Color,
                        StartSystemPid,
                        UpdatedVisited,
                        Time,
                        Neighbors,
                        LeaderID,
                        FromPid,       % Imposta il server come destinatario finale
                        initiator,     % Flag per indicare il nodo iniziatore
                        Parent,
                        Children
                    )
            end;

        %% Richiesta di setup da un altro nodo (propagazione)
        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            if
                %% Se il nodo non è visitato e ha lo stesso colore, continua la propagazione
                Visited == false andalso Color == SenderColor ->
                    io:format("Node (~p, ~p) has the same color as the requesting node.~n", [X, Y]),
                    UpdatedVisited = true,
                    UpdatedParent = FromPid,      % Imposta il nodo padre
                    UpdatedLeaderID = PropagatedLeaderID, % Propaga l'ID del leader
                    node_loop_propagate(
                        X,
                        Y,
                        Color,
                        StartSystemPid,
                        UpdatedVisited,
                        Time,
                        Neighbors,
                        UpdatedLeaderID,
                        FromPid,
                        non_initiator, % Flag per i nodi non iniziatori
                        UpdatedParent,
                        Children
                    );

                %% Nodo già visitato, risponde con 'node_already_visited'
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) has already been visited, responding accordingly.~n", [X, Y]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

                %% Nodo di colore diverso, risponde solo con conferma di ricezione
                true ->
                    io:format("Node (~p, ~p) has a different color, sends only received.~n", [X, Y]),
                    FromPid ! {self(), ack_propagation_different_color},
                    node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors)
            end;

        %% Fase 2 di avvio dal leader
        {start_phase2, NodePIDs, ServerPid} ->
            io:format("Leader Node (~p, ~p) starting Phase 2.~n", [X, Y]),
            %% Richiede l'ID del leader dai nodi vicini per determinare cluster adiacenti
            lists:foreach(
                fun(NeighborPid) ->
                    NeighborPid ! {get_leaderID, self()}
                end,
                Neighbors
            ),
            %% Colleziona i cluster adiacenti del nodo corrente
            AdjacentClustersSelf = collect_adjacent_clusters(Neighbors, [], LeaderID, Color, X, Y),
            %% Invia messaggio di inizio fase 2 a tutti i nodi del cluster
            NodePIDsFiltered = lists:filter(fun(NodePID) -> NodePID =/= self() end, NodePIDs),
            lists:foreach(
                fun(NodePID) ->
                    io:format("Leader Node (~p, ~p) - ~p sends message to ~p.~n", [
                        X, Y, self(), NodePID
                    ]),
                    NodePID ! {start_phase2_node, self()}
                end,
                NodePIDsFiltered
            ),
            %% Raccoglie i cluster adiacenti da altri nodi
            AdjacentClustersOthers = collect_adjacent_clusters_from_nodes(NodePIDsFiltered, []),
            %% Unisce tutti i cluster adiacenti e li invia al server
            AllAdjacentClusters = lists:usort(
                lists:append(AdjacentClustersSelf, AdjacentClustersOthers)
            ),
            io:format("Leader Node (~p, ~p) sending adjacent clusters ~p to server.~n", [
                X, Y, AllAdjacentClusters
            ]),
            ServerPid ! {self(), phase2_complete, LeaderID, AllAdjacentClusters},
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

        %% Gestione di start_phase2_node per nodi nel cluster
        {start_phase2_node, LeaderPid} ->
            io:format("Node (~p, ~p) in cluster starting Phase 2 neighbor check.~n", [X, Y]),
            lists:foreach(
                fun(NeighborPid) ->
                    NeighborPid ! {get_leaderID, self()}
                end,
                Neighbors
            ),
            %% Colleziona cluster adiacenti dai vicini
            AdjacentClusters = collect_adjacent_clusters(Neighbors, [], LeaderID, Color, X, Y),
            UniqueAdjacentClusters = lists:usort(AdjacentClusters),
            io:format("Node (~p, ~p) sending adjacent clusters ~p to Leader.~n", [
                X, Y, UniqueAdjacentClusters
            ]),
            LeaderPid ! {adjacent_clusters_info, self(), UniqueAdjacentClusters},
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

        %% Gestione della richiesta dell'ID del leader dai vicini
        {get_leaderID, FromPid} ->
            FromPid ! {leaderID_info, self(), LeaderID, Color},
            io:format("Node (~p, ~p) responding with leaderID ~p and color ~p to ~p~n", [
                X, Y, LeaderID, Color, FromPid
            ]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors);

        %% Aggiunta di un figlio alla lista
        {add_child, ChildPid} ->
            UpdatedChildren = [ChildPid | Children],
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, UpdatedChildren, Neighbors);

        %% Sincronizzazione del tempo dal server
        {time, ServerTime} ->
            io:format("Node (~p, ~p) updated its time to ~p~n", [X, Y, ServerTime]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, ServerTime, Parent, Children, Neighbors);

        %% Messaggi non gestiti
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [X, Y]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Parent, Children, Neighbors)
    end.

%% Funzione per propagare il messaggio di setup e gestire la cascata
%% La funzione propaga il leader ID e colore ai vicini, escludendo il nodo che ha inviato la richiesta
node_loop_propagate(
    X,
    Y,
    Color,
    StartSystemPid,
    Visited,
    Time,
    Neighbors,
    PropagatedLeaderID,
    FromPid,
    InitiatorFlag,
    Parent,
    Children
) ->
    io:format("Node (~p, ~p) is propagating as leader with ID: ~p and color: ~p.~n", [
        X, Y, PropagatedLeaderID, Color
    ]),
    NeighborsToSend = [N || N <- Neighbors, N =/= FromPid], % Esclude il nodo mittente dalla lista dei vicini
    io:format("Node (~p, ~p) will send messages to neighbors: ~p~n", [X, Y, NeighborsToSend]),
    %% Propaga a ciascun vicino
    lists:foreach(
        fun(NeighborPid) ->
            io:format(
                "Node (~p, ~p) is propagating leaderID: ~p and color: ~p, towards ~p.~n",
                [X, Y, PropagatedLeaderID, Color, NeighborPid]
            ),
            NeighborPid ! {setup_node_request, Color, PropagatedLeaderID, self()}
        end,
        NeighborsToSend
    ),
    io:format("Waiting for ACKs for Node (~p, ~p).~n", [X, Y]),
    %% Attende gli ACK dai vicini e raccoglie i loro PID
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(
        NeighborsToSend,
        [],
        X,
        Y,
        Color,
        StartSystemPid,
        Visited,
        PropagatedLeaderID,
        Time,
        Neighbors,
        Parent,
        Children
    ),
    io:format("Finished receiving ACKs for Node (~p, ~p).~n", [X, Y]),
    %% Se il nodo è iniziatore, invia i PID combinati al server
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),
    case InitiatorFlag of
        initiator ->
            io:format("Node (~p, ~p) is the initiator and sends combined PIDs to the server.~n", [X, Y]),
            FromPid ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            FromPid ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,
    %% Continua il ciclo principale del nodo
    node_loop(X, Y, Color, StartSystemPid, Visited, PropagatedLeaderID, Time, Parent, Children, Neighbors).

%% Funzione helper per attendere gli ACK dai vicini e raccogliere i loro PID
wait_for_ack_from_neighbors(
    NeighborsToWaitFor,
    AccumulatedPIDs,
    X,
    Y,
    Color,
    StartSystemPid,
    Visited,
    LeaderID,
    Time,
    Neighbors,
    Parent,
    Children
) ->
    if
        NeighborsToWaitFor == [] ->
            {ok, AccumulatedPIDs};
        true ->
            receive
                %% Gestione ACK dallo stesso colore, aggiunge i PID dei vicini
                {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        NewAccumulatedPIDs,
                        X,
                        Y,
                        Color,
                        StartSystemPid,
                        Visited,
                        LeaderID,
                        Time,
                        Neighbors,
                        Parent,
                        Children
                    );

                %% Gestione ACK di colore diverso
                {FromNeighbor, ack_propagation_different_color} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        X,
                        Y,
                        Color,
                        StartSystemPid,
                        Visited,
                        LeaderID,
                        Time,
                        Neighbors,
                        Parent,
                        Children
                    );

                %% Gestione nodo già visitato
                {FromNeighbor, node_already_visited} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        X,
                        Y,
                        Color,
                        StartSystemPid,
                        Visited,
                        LeaderID,
                        Time,
                        Neighbors,
                        Parent,
                        Children
                    );

                %% Timeout in caso di mancata risposta dai vicini
                _Other ->
                    io:format("Timeout while waiting for ACKs from neighbors: ~p~n", [NeighborsToWaitFor]),
                    {ok, AccumulatedPIDs}
            end
    end.


%% Funzione per collezionare cluster adiacenti da una lista di vicini
%% Utilizzata nella fase 2 per determinare cluster vicini che hanno leader ID diverso
collect_adjacent_clusters([], AdjacentClusters, _OwnLeaderID, _Color, _X, _Y) ->
    AdjacentClusters;
collect_adjacent_clusters([Neighbor | RestNeighbors], AdjacentClusters, OwnLeaderID, Color, X, Y) ->
    receive
        {leaderID_info, FromPid, NeighborLeaderID, NeighborColor} ->
            %% Verifica se il leader ID del vicino è diverso
            NewAdjacentClusters =
                if
                    NeighborLeaderID =/= OwnLeaderID ->
                        [{NeighborLeaderID, NeighborColor} | AdjacentClusters];
                    true ->
                        AdjacentClusters
                end,
            collect_adjacent_clusters(RestNeighbors, NewAdjacentClusters, OwnLeaderID, Color, X, Y);
        %% Richiede l'ID del leader al vicino
        {get_leaderID, FromPid} ->
            FromPid ! {leaderID_info, self(), OwnLeaderID, Color},
            collect_adjacent_clusters(RestNeighbors, AdjacentClusters, OwnLeaderID, Color, X, Y)
    after 5000 ->
        AdjacentClusters
    end.

%% Funzione per raccogliere cluster adiacenti dai nodi
%% Utilizzata dal leader per raccogliere le informazioni di cluster dai nodi nel cluster
collect_adjacent_clusters_from_nodes([], AccumulatedAdjacentClusters) ->
    lists:usort(AccumulatedAdjacentClusters);
collect_adjacent_clusters_from_nodes([NodePID | RestNodePIDs], AccumulatedAdjacentClusters) ->
    receive
        {adjacent_clusters_info, NodePID, NodeAdjacentClusters} ->
            %% Aggiunge i cluster adiacenti ricevuti alla lista accumulata
            NewAccumulatedAdjacentClusters = lists:append(AccumulatedAdjacentClusters, NodeAdjacentClusters),
            collect_adjacent_clusters_from_nodes(RestNodePIDs, NewAccumulatedAdjacentClusters)
    after 5000 ->
        %% Timeout per la raccolta dei cluster adiacenti
        AccumulatedAdjacentClusters
    end.
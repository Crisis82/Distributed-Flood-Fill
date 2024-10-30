%% node.erl
-module(node).
-export([create_node/2, node_loop/3, node_loop/4, node_loop_propagate/6]).

%% Definition of the node record
-record(node, {x, y, parent, children = [], time, leaderID}).
-record(leader, {node, color, serverID, adjClusters = []}).

%% Creation of a new node
new_node(X, Y) ->
    #node{
        x = X,
        y = Y
    }.

%% Creation of a new leader
new_leader(X, Y, Color) ->
    Node = new_node(X, Y),
    #leader{node = Node, color = Color}.

%% Funzione per l'inizializzazione di un nodo
%% Input:
%% - Leader: un record 'leader' contenente i propri parametri
%% - StartSystemPid: PID del sistema di avvio
%% Output:
%% - Restituisce una tupla {X, Y, Pid}, dove 'X' e 'Y' sono le coordinate del nodo e 'Pid' è il PID del nodo creato
create_node(Leader, StartSystemPid) ->
    % Spawna un processo nodo e avvia il ciclo node_loop
    Pid = spawn(fun() ->
        node_loop(
            % Nodo
            Leader,
            % PID del sistema di avvio
            StartSystemPid,
            % Stato di visita
            false
        )
    end),
    io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
        Leader#leader.node#node.x, Leader#leader.node#node.y, Leader#leader.color, Pid
    ]),
    % previosly returned {X, Y, Pid}.
    % TODO: fix in start_system.erl
    {Leader#leader.node#node{leaderID = Pid}}.

%% Loop principale del nodo che gestisce la ricezione dei messaggi e aggiorna lo stato
%% Input:
%% - Leader: un record 'leader' contenente i propri parametri
%% - StartSystemPid: PID del sistema di avvio
%% - Visited: flag booleano per indicare se il nodo è stato visitato
node_loop(Leader, StartSystemPid, Visited) ->
    receive
        %% Gestione dei vicini
        %% Riceve la lista dei nodi vicini e la memorizza, notificando il sistema di avvio
        {neighbors, Neighbors} ->
            io:format("Node (~p, ~p) received neighbors: ~p~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, Neighbors
            ]),
            StartSystemPid ! {ack_neighbors, self()},
            % Ritorna a node_loop con i vicini aggiunti
            node_loop(
                Leader, StartSystemPid, Visited, Neighbors
            );
        %% Gestione di altri messaggi non definiti per debugging
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y
            ]),
            node_loop(Leader, StartSystemPid, Visited)
    end.

%% Variante del loop principale che include i vicini nel parametro
%% Input:
%% - Leader: un record 'leader' contenente i propri parametri
%% - StartSystemPid: PID del sistema di avvio
%% - Visited: flag booleano per indicare se il nodo è stato visitato
%% - Neighbors: lista dei PID dei vicini
%% Output:
%% - Nessun output diretto; mantiene il nodo in ascolto per nuovi messaggi
node_loop(Node, StartSystemPid, Visited, Neighbors) ->
    receive
        %% Richiesta di setup dal server
        %% Avvia la propagazione dei messaggi di setup se il nodo non è stato ancora visitato
        {setup_server_request, FromPid} ->
            if
                %% Nodo già visitato, risponde al server con 'node_already_visited'
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, already visited, responding to server.~n",
                        [Node#leader.node#node.x, Node#leader.node#node.y]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(
                        Node,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                %% Nodo non visitato, avvia la propagazione del messaggio di setup
                true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, not visited, starting propagation of my leaderID: ~p.~n",
                        [
                            Node#leader.node#node.x,
                            Node#leader.node#node.y,
                            Node#leader.node#node.leaderID
                        ]
                    ),
                    %% Inizia la propagazione come nodo iniziatore
                    node_loop_propagate(
                        Node#leader{serverID = FromPid},
                        Node#leader.color,
                        StartSystemPid,
                        %% Aggiorna lo stato di visitato a True
                        true,
                        Neighbors,
                        %% Flag per indicare il nodo iniziatore
                        initiator
                    )
            end;
        %% Richiesta di setup da un altro nodo (propagazione)
        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            if
                %% Se il nodo non è visitato e ha lo stesso colore, continua la propagazione
                Visited == false andalso Node#leader.color == SenderColor ->
                    io:format("Node (~p, ~p) has the same color as the requesting node.~n", [
                        Node#leader.node#node.x, Node#leader.node#node.y
                    ]),
                    node_loop_propagate(
                        % Imposta il nodo padre ed aggiorna il proprion leaderID con quello propagato
                        Node#leader.node#node{parent = FromPid, leaderID = PropagatedLeaderID},
                        Node#leader.color,
                        StartSystemPid,
                        %% Aggiorna lo stato di visitato a True
                        true,
                        Neighbors,
                        % Flag per i nodi non iniziatori
                        non_initiator
                    );
                %% Nodo già visitato, risponde con 'node_already_visited'
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) has already been visited, responding accordingly.~n", [
                            Node#leader.node#node.x, Node#leader.node#node.y
                        ]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(
                        Node,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                %% Nodo di colore diverso, risponde solo con conferma di ricezione
                true ->
                    io:format("Node (~p, ~p) has a different color, sends only received.~n", [
                        Node#leader.node#node.x, Node#leader.node#node.y
                    ]),
                    FromPid ! {self(), ack_propagation_different_color},
                    node_loop(
                        Node,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    )
            end;
        %% Fase 2 di avvio dal leader
        {start_phase2, NodePIDs} ->
            io:format("Leader Node (~p, ~p) starting Phase 2.~n", [
                Node#leader.node#node.x, Node#leader.node#node.y
            ]),
            % Richiede l'ID del leader dai vicini per determinare cluster adiacenti
            lists:foreach(
                fun(NeighborPid) ->
                    NeighborPid ! {get_leader_info, self()}
                end,
                Neighbors
            ),
            % Colleziona i cluster adiacenti del nodo corrente
            AdjacentClustersSelf = collect_adjacent_clusters(Node, Neighbors),
            % Filtra il PID del leader stesso e notifica tutti i nodi del cluster
            NodePIDsFiltered = lists:filter(fun(NodePID) -> NodePID =/= self() end, NodePIDs),
            lists:foreach(
                fun(NodePID) ->
                    io:format("Leader Node (~p, ~p) - ~p sends message to ~p.~n", [
                        Node#leader.node#node.x, Node#leader.node#node.y, self(), NodePID
                    ])
                end,
                NodePIDsFiltered
            ),
            % Colleziona i cluster adiacenti dagli altri nodi
            AdjacentClustersOthers = collect_adjacent_clusters_from_nodes(NodePIDsFiltered, []),
            % Unisce tutti i cluster adiacenti e li invia al server
            AllAdjacentClusters = lists:usort(
                lists:append(AdjacentClustersSelf, AdjacentClustersOthers)
            ),
            io:format("Leader Node (~p, ~p) sending adjacent clusters ~p to server.~n", [
                Node#leader.node#node.x, Node#leader.node#node.y, AllAdjacentClusters
            ]),
            Node#leader.serverID !
                {self(), phase2_complete, Node#leader{adjClusters = AllAdjacentClusters}},
            node_loop(
                Node, StartSystemPid, Visited, Neighbors
            );
        %% Gestione di start_phase2_node per i nodi nel cluster
        {start_phase2_node} ->
            io:format("Node (~p, ~p) in cluster starting Phase 2 neighbor check.~n", [
                Node#node.x, Node#node.y
            ]),
            lists:foreach(
                fun(NeighborPid) ->
                    NeighborPid ! {get_leader_info, self()}
                end,
                Neighbors
            ),
            % Colleziona cluster adiacenti dai vicini
            AdjacentClusters = collect_adjacent_clusters(Node#node.leaderID, Neighbors),
            UniqueAdjacentClusters = lists:usort(AdjacentClusters),
            io:format("Node (~p, ~p) sending adjacent clusters ~p to Leader.~n", [
                Node#node.x, Node#node.y, UniqueAdjacentClusters
            ]),
            Node#node.leaderID ! {adjacent_clusters_info, self(), UniqueAdjacentClusters},
            node_loop(
                Node, StartSystemPid, Visited, Neighbors
            );
        %% Gestione della richiesta dell'ID del leader dai vicini
        {get_leader_info, FromPid} ->
            %% TODO: check this beacause not all are nodes in this case
            Node#node.leaderID ! {send_leader_info, self(), FromPid},
            node_loop(
                Node, StartSystemPid, Visited, Neighbors
            );
        %% Implementare get_color e receive_color
        {send_leader_info, ToPid} ->
            ToPid ! {leader_info, Node},
            io:format("Node (~p, ~p) responding with leaderID ~p and color ~p to ~p~n", [
                Node#leader.node#node.x,
                Node#leader.node#node.y,
                Node#leader.node#node.leaderID,
                Node#leader.color,
                ToPid
            ]),
            node_loop(
                Node, StartSystemPid, Visited, Neighbors
            );
        %% Aggiunta di un figlio alla lista
        {add_child, ChildPid} ->
            UpdatedChildren = [ChildPid | Node#node.children],
            node_loop(
                Node#node{children = UpdatedChildren},
                StartSystemPid,
                Visited,
                Neighbors
            );
        %% Sincronizzazione del tempo dal server
        {time, ServerTime} ->
            io:format("Node (~p, ~p) updated its time to ~p~n", [
                Node#node.x, Node#node.y, ServerTime
            ]),
            node_loop(
                Node#node{time = ServerTime},
                StartSystemPid,
                Visited,
                Neighbors
            );
        %% Messaggi non gestiti
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [Node#node.x, Node#node.y]),
            node_loop(
                Node, StartSystemPid, Visited, Neighbors
            )
    end.

%% node.erl

%% Funzione per propagare il messaggio di setup e gestire la cascata
%% Input:
%% - Node: un record 'nodo' contenente i propri parametri
%% - StartSystemPid: PID del sistema di avvio
%% - Visited: flag booleano per il controllo di visita
%% - Neighbors: lista dei PID dei nodi vicini
%% - PropagatedLeaderID: ID del leader propagato
%% - FromPid: PID del nodo mittente della richiesta di setup
%% - InitiatorFlag: flag per indicare se il nodo è l’iniziatore della propagazione
%% Output:
%% - Nessun output diretto; mantiene il nodo in ascolto per nuovi messaggi
node_loop_propagate(
    Node,
    Color,
    StartSystemPid,
    Visited,
    Neighbors,
    %% FromPid, %%probably removable
    InitiatorFlag
) ->
    io:format("Node (~p, ~p) is propagating as leader with ID: ~p and color: ~p.~n", [
        Node#node.x, Node#node.y, Node#node.leaderID, Color
    ]),
    % Esclude il nodo mittente dalla lista dei vicini per evitare loop
    NeighborsToSend = [N || N <- Neighbors, N =/= Node#node.parent],
    io:format("Node (~p, ~p) will send messages to neighbors: ~p~n", [
        Node#node.x, Node#node.y, NeighborsToSend
    ]),

    % Invia il messaggio di setup a ciascun vicino
    lists:foreach(
        fun(NeighborPid) ->
            io:format(
                "Node (~p, ~p) is propagating leaderID: ~p and color: ~p, towards ~p.~n",
                [Node#node.x, Node#node.y, Node#node.leaderID, Color, NeighborPid]
            ),
            NeighborPid ! {setup_node_request, Color, Node#node.leaderID, self()}
        end,
        NeighborsToSend
    ),

    % Attende gli ACK dai vicini e raccoglie i loro PID
    io:format("Waiting for ACKs for Node (~p, ~p).~n", [Node#node.x, Node#node.y]),
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(
        NeighborsToSend,
        % Inizializza lista dei PID accumulati
        [],
        Node,
        Color,
        StartSystemPid,
        Visited,
        Neighbors
    ),

    % Se il nodo è l’iniziatore, invia i PID combinati al server
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),
    case InitiatorFlag of
        initiator ->
            io:format("Node (~p, ~p) is the initiator and sends combined PIDs to the server.~n", [
                Node#node.x, Node#node.y
            ]),
            Node#leader.serverID ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            Node#leader.serverID ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,

    % Continua il ciclo principale del nodo con lo stato aggiornato
    node_loop(
        Node, StartSystemPid, Visited, Neighbors
    ).

%% Funzione helper per attendere gli ACK dai vicini e raccogliere i loro PID
%% Input:
%% - NeighborsToWaitFor: lista dei PID dei vicini da cui si attendono ACK
%% - AccumulatedPIDs: lista accumulata dei PID dei vicini che hanno risposto
%% - Parametri di stato del nodo: X, Y, Color, StartSystemPid, Visited, LeaderID, Time, Neighbors, Parent, Children
%% Output:
%% - {ok, AccumulatedPIDs}: lista di PID che confermano la propagazione
wait_for_ack_from_neighbors(
    NeighborsToWaitFor,
    AccumulatedPIDs,
    Node,
    Color,
    StartSystemPid,
    Visited,
    Neighbors
) ->
    if
        % Se non ci sono vicini da attendere, restituisce la lista dei PID accumulati
        NeighborsToWaitFor == [] ->
            {ok, AccumulatedPIDs};
        true ->
            receive
                %% Gestione ACK dallo stesso colore, aggiunge i PID dei vicini
                {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                    % Rimuove il vicino che ha risposto dalla lista e aggiunge i suoi PID
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),
                    % Richiama la funzione ricorsivamente con lista aggiornata
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        NewAccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                %% Gestione ACK di colore diverso
                {FromNeighbor, ack_propagation_different_color} ->
                    % Rimuove il vicino dalla lista e prosegue senza aggiungere PID
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                %% Gestione nodo già visitato
                {FromNeighbor, node_already_visited} ->
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    wait_for_ack_from_neighbors(
                        RemainingNeighbors,
                        AccumulatedPIDs,
                        Node,
                        Color,
                        StartSystemPid,
                        Visited,
                        Neighbors
                    );
                %% Timeout in caso di mancata risposta dai vicini
                _Other ->
                    io:format("Timeout while waiting for ACKs from neighbors: ~p~n", [
                        NeighborsToWaitFor
                    ]),
                    {ok, AccumulatedPIDs}
            end
    end.

%% Funzione per collezionare cluster adiacenti da una lista di vicini
%% Utilizzata nella fase 2 per determinare cluster vicini che hanno un leader ID diverso
%% Input:
%% - Lista di vicini, lista dei cluster adiacenti inizialmente vuota, ID del leader e colore del nodo corrente, coordinate (X, Y)
%% Output:
%% - Restituisce una lista dei cluster adiacenti univoci
collect_adjacent_clusters(Node, []) ->
    Node#leader.adjClusters;
collect_adjacent_clusters(Node, [_Neighbor | RestNeighbors]) ->
    receive
        {leader_info, NeighborLeader} ->
            % Verifica se il leader ID del vicino è diverso
            NewAdjacentClusters =
                if
                    NeighborLeader#leader.node#node.leaderID =/= Leader#leader.leader#node.leaderID ->
                        [
                            {NeighborLeader#node.leaderID, NeighborLeader#leader.color}
                            | Leader#leader.adjClusters
                        ];
                    true ->
                        Leader#leader.adjClusters
                end,
            % Richiama la funzione ricorsivamente per continuare con i vicini rimanenti
            collect_adjacent_clusters(
                Leader#leader{adjClusters = NewAdjacentClusters}, RestNeighbors
            );
        % Richiede l'ID del leader al vicino
        {send_neighbour_info, ToPid} ->
            ToPid ! {get_leader_info, self()};
        {get_leader_info, FromPid} ->
            Node#leader.node#node.leaderID ! {send_leader_info, FromPid};
        {send_leader_info, ToPid} ->
            ToPid ! {send_leader_info, Node},
            collect_adjacent_clusters(Node, RestNeighbors)
    after 5000 ->
        % Timeout per la risposta del vicino, ritorna la lista di cluster adiacenti raccolti
        Node#leader.adjClusters
    end.

%% Funzione per raccogliere cluster adiacenti dai nodi
%% Utilizzata dal leader per raccogliere le informazioni di cluster dai nodi nel cluster
%% Input:
%% - Lista di PID dei nodi, lista dei cluster adiacenti accumulata
%% Output:
%% - Restituisce una lista univoca dei cluster adiacenti a tutti i nodi del cluster
collect_adjacent_clusters_from_nodes([], AccumulatedAdjacentClusters) ->
    lists:usort(AccumulatedAdjacentClusters);
collect_adjacent_clusters_from_nodes([NodePID | RestNodePIDs], AccumulatedAdjacentClusters) ->
    receive
        {adjacent_clusters_info, NodePID, NodeAdjacentClusters} ->
            % Aggiunge i cluster adiacenti ricevuti dal nodo alla lista accumulata
            NewAccumulatedAdjacentClusters = lists:append(
                AccumulatedAdjacentClusters, NodeAdjacentClusters
            ),
            collect_adjacent_clusters_from_nodes(RestNodePIDs, NewAccumulatedAdjacentClusters)
    after 5000 ->
        % Timeout per la raccolta delle informazioni dal nodo
        AccumulatedAdjacentClusters
    end.

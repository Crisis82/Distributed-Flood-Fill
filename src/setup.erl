-module(setup).
-export([setup_loop/3]).
-include("node.hrl").

%% Loop to setup the enviroment and the structures
setup_loop(Leader, StartSystemPid, Visited) ->
    io:format("Sono il nodo (~p, ~p) con PID ~p e sono pronto per ricevere nuovi messaggi!!~n", [
        Leader#leader.node#node.x, Leader#leader.node#node.y, self()
    ]),

    Pid = self(),

    utils:save_data(Leader),
    receive
        {neighbors, Neighbors} ->
            io:format("Node (~p, ~p) received neighbors: ~p~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, Neighbors
            ]),
            % Update node state with neighbors and notify system
            UpdatedNode = Leader#leader.node#node{neighbors = Neighbors, leaderID = Pid, pid = Pid},
            UpdatedLeader = Leader#leader{node = UpdatedNode},

            io:format(
                "SETUP ~p : Sono il nodo (~p, ~p) con PID ~p e invio a il messaggio {ack_neighbors, ~p} a ~p~n",
                [
                    self(),
                    Leader#leader.node#node.x,
                    Leader#leader.node#node.y,
                    Pid,
                    Pid,
                    StartSystemPid
                ]
            ),

            StartSystemPid ! {ack_neighbors, self()},

            setup_loop(
                UpdatedLeader, StartSystemPid, Visited
            );
        %% Server setup request
        %% Starts setup message propagation if the node hasn't been visited
        {setup_server_request, FromPid} ->
            if
                %% Node already visited, responds with 'node_already_visited'
                Visited =:= true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, already visited, responding to server.~n",
                        [Leader#leader.node#node.x, Leader#leader.node#node.y]
                    ),
                    FromPid ! {self(), node_already_visited},
                    setup_loop(
                        Leader,
                        StartSystemPid,
                        Visited
                    );
                %% Unvisited node, starts message propagation
                true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, not visited, starting propagation of my leaderID: ~p.~n",
                        [
                            Leader#leader.node#node.x,
                            Leader#leader.node#node.y,
                            Leader#leader.node#node.leaderID
                        ]
                    ),
                    %% Start propagation as the initiating node
                    setup_loop_propagate(
                        Leader#leader{serverID = FromPid},
                        Leader#leader.color,
                        self(),
                        %% Set visited status to true
                        true,
                        Leader#leader.node#node.neighbors,
                        %% Flag indicating initiating node
                        initiator,
                        StartSystemPid
                    )
            end;
        %% Node setup request from another node (propagation)
        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            if
                %% Unvisited node with the same color, continue propagation
                Visited =:= false andalso Leader#leader.color =:= SenderColor ->
                    io:format("Node (~p, ~p) has the same color as the requesting node (~p).~n", [
                        Leader#leader.node#node.x, Leader#leader.node#node.y, FromPid
                    ]),

                    % Update leaderID and pid in the node
                    UpdatedNode = Leader#leader.node#node{
                        parent = FromPid, leaderID = PropagatedLeaderID
                    },
                    UpdatedLeader = Leader#leader{node = UpdatedNode},

                    setup_loop_propagate(
                        %% Becames a simple node
                        UpdatedLeader,
                        Leader#leader.color,
                        FromPid,
                        %% Set visited status to true
                        true,
                        Leader#leader.node#node.neighbors,
                        %% Flag for non-initiating nodes
                        non_initiator,
                        StartSystemPid
                    );
                %% Node already visited, responds with 'node_already_visited'
                Visited =:= true ->
                    io:format(
                        "Node (~p, ~p) has already been visited, responding accordingly to ~p.~n", [
                            Leader#leader.node#node.x, Leader#leader.node#node.y, FromPid
                        ]
                    ),
                    FromPid ! {self(), node_already_visited},
                    setup_loop(
                        %% Already visited, so it doesn't change the type
                        Leader,
                        StartSystemPid,
                        Visited
                    );
                %% Node with different color, only acknowledges receipt
                true ->
                    io:format("Node (~p, ~p) has a different color (~p), sends only received to ~p.~n", [
                        Leader#leader.node#node.x, Leader#leader.node#node.y, Leader#leader.color, FromPid
                    ]),
                    FromPid ! {self(), ack_propagation_different_color},
                    setup_loop(
                        %% Different color, thus the node can be a leader of another cluster
                        Leader,
                        StartSystemPid,
                        Visited
                    )
            end;
        {get_list_neighbors, FromPid} ->
            io:format("~p: Invio a ~p la lista dei miei vicini: ~n~p~n", [
                self(), FromPid, Leader#leader.node#node.neighbors
            ]),
            FromPid ! {response_get_list_neighbors, Leader#leader.node#node.neighbors},
            node:leader_loop(Leader);
        %% Leader ID request from neighbors
        {get_leader_info, FromPid} ->
            io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
                self(), FromPid
            ]),
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
            setup_loop(Leader, StartSystemPid, Visited);
        % TODO: not used, can be removed
        %% Adding a child to the list
        {add_child, ChildPid} ->
            UpdatedChildren = [ChildPid | Leader#leader.node#node.children],
            UpdatedNode = Leader#leader.node#node{children = UpdatedChildren},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            setup_loop(UpdatedLeader, StartSystemPid, Visited);
        %% Fase 2 di avvio dal leader
        {start_phase2, NodePIDs} ->
            ServerPid = Leader#leader.serverID,
            X = Leader#leader.node#node.x,
            Y = Leader#leader.node#node.y,
            InitialNeighbors = Leader#leader.node#node.neighbors,
            LeaderID = Leader#leader.node#node.leaderID,

            io:format("Leader Node (~p, ~p) starting Phase 2.~n", [X, Y]),

            NodePIDsWithoutSelf = lists:delete(self(), NodePIDs),

            io:format("InitialNeighbors: ~p~nNodePIDsWithoutSelf: ~p~n", [
                InitialNeighbors, NodePIDsWithoutSelf
            ]),

            AdjNodesToCluster = gather_adjacent_nodes(
                NodePIDsWithoutSelf, LeaderID, InitialNeighbors
            ),
            AdjNodesToCluster_no_duplicates = utils:remove_duplicates(AdjNodesToCluster),

            io:format("AdjNodesToCluster: ~p,~nAdjNodesToCluster_no_duplicates: ~p~n", [
                AdjNodesToCluster, lists:delete(self(), AdjNodesToCluster_no_duplicates)
            ]),

            %% Usa `gather_adjacent_clusters` per raccogliere informazioni sui Neighbors del
            AllAdjacentClusters = gather_adjacent_clusters(
                lists:delete(self(), AdjNodesToCluster_no_duplicates), LeaderID, [], [], Leader
            ),

            io:format("AllAdjacentClusters: ~p~n", [
                AllAdjacentClusters
            ]),

            %% Invia il messaggio ai nodi del cluster con le informazioni finali
            ServerPid ! {self(), phase2_complete, LeaderID, AllAdjacentClusters},

            % Crea una lista dei nodi nel cluster escludendo il PID del leader
            FilteredNodes = lists:filter(
                fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                Leader#leader.nodes_in_cluster
            ),

            % Invia richiesta di salvataggio a tutti i nodi in FilteredNodes
            lists:foreach(
                fun(NodePid) ->
                    NodePid ! {save_to_db_node}
                end,
                FilteredNodes
            ),

            UpdatedLeader = Leader#leader{
                nodes_in_cluster = NodePIDs, adjClusters = AllAdjacentClusters
            },

            node:leader_loop(UpdatedLeader)
    end.

%% Funzione per propagare il messaggio di setup e gestire la cascata
%% Input:
%% - Node: un record 'leader' contenente i parametri del nodo corrente
%% - Color: colore del nodo che si sta propagando
%% - StartSystemPid: PID del sistema di avvio
%% - Visited: flag booleano per il controllo di visita
%% - Neighbors: lista dei PID dei nodi vicini
%% - InitiatorFlag: flag per indicare se il nodo è l’iniziatore della propagazione
%% Output:
%% - Nessun output diretto; mantiene il nodo in ascolto per nuovi messaggi
setup_loop_propagate(
    Leader,
    Color,
    FromPid,
    Visited,
    Neighbors,
    InitiatorFlag,
    StartSystemPid
) ->
    Node = Leader#leader.node,

    io:format("Node (~p, ~p) is propagating as leader with ID: ~p and color: ~p.~n", [
        Node#node.x, Node#node.y, Node#node.leaderID, Color
    ]),

    %% Esclude il nodo parent dalla lista dei vicini per evitare loop
    NeighborsToSend = [N || N <- Neighbors, N =/= Node#node.parent],
    io:format("Node (~p, ~p) will send messages to neighbors: ~p~n", [
        Node#node.x, Node#node.y, NeighborsToSend
    ]),

    %% Invia il messaggio di setup a ciascun vicino
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

    %% Attende gli ACK dai vicini e raccoglie i loro PID
    io:format("Waiting for ACKs for Node (~p, ~p).~n", [Node#node.x, Node#node.y]),
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(
        NeighborsToSend,
        [],
        Leader,
        Color,
        FromPid,
        Visited,
        Neighbors
    ),

    %% Se il nodo è l’iniziatore, invia i PID combinati al server
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),
    case InitiatorFlag of
        initiator ->
            io:format("Node (~p, ~p) is the initiator and sends combined PIDs to the server.~n", [
                Node#node.x, Node#node.y
            ]),
            io:format("INVIO : ~p~n", [CombinedPIDs]),
            Leader#leader.serverID ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            io:format(
                "Node (~p, ~p) is NOT the initiator and sends combined PIDs ~p to the other node : ~p~n",
                [Node#node.x, Node#node.y, CombinedPIDs, FromPid]
            ),
            FromPid ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,
    %% Continua il ciclo principale del nodo con lo stato aggiornato
    UpdatedLeader = Leader#leader{node = Node},

    setup_loop(
        UpdatedLeader, StartSystemPid, Visited
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
        NeighborsToWaitFor =:= [] ->
            {ok, AccumulatedPIDs};
        true ->
            receive
                %% Gestione ACK dallo stesso colore, aggiunge i PID dei vicini
                {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                    % Rimuove il vicino che ha risposto dalla lista e aggiunge i suoi PID
                    RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                    NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),

                    io:format(
                        "~p -> Ho ricevuto da ~p ack_propagation_same_color; mancano ~p.~n", [
                            self(), FromNeighbor, RemainingNeighbors
                        ]
                    ),

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
                    io:format(
                        "~p -> Ho ricevuto da ~p ack_propagation_different_color; mancano ~p.~n", [
                            self(), FromNeighbor, RemainingNeighbors
                        ]
                    ),
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
                    io:format("~p -> Ho ricevuto da ~p node_already_visited; mancano ~p.~n", [
                        self(), FromNeighbor, RemainingNeighbors
                    ]),

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
                    io:format("Timeout while waiting for ACKs from neighbors: ~p, ~p~n", [
                        NeighborsToWaitFor, _Other
                    ]),
                    {ok, AccumulatedPIDs}
            end
    end.

% Funzione per inviare il messaggio e raccogliere i leader ID distinti dai vicini
%% Input:
%% - PidList: lista dei PID dei vicini o nodi nel cluster
%% - LeaderID: leader ID del nodo corrente
%% - AccumulatedClusters: lista dei leader ID già accumulati
%% Output:
%% - Lista aggiornata dei leader ID distinti per i cluster adiacenti
%% Funzione per inviare il messaggio e raccogliere i leader ID distinti dai vicini
%% evitando messaggi inutili se i dati sono già presenti in `neighbors`.
%% Funzione aggiornata per raccogliere le informazioni sui neighbors
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters, _NeighborsList, _Leader) ->
    % Restituisce la lista finale dei neighbors e clusters senza duplicati
    AccumulatedClusters;
gather_adjacent_clusters([Pid | Rest], LeaderID, AccumulatedClusters, NeighborsList, Leader) ->
    io:format("Al momento so: ~p~n", [NeighborsList]),
    io:format("Ora invio a: ~p , mancano~p~n", [Pid, Rest]),

    %% Se il vicino non è già nel formato {Pid, Color, LeaderID}, invia richiesta per ottenere le informazioni
    Pid ! {get_leader_info, self()},
    receive
        {leader_info, NeighborLeaderID, NeighborColor} ->
            io:format("~p -> Ho ricevuto la risposta da ~p con LeaderID: ~p e Color: ~p.~n", [
                self(), Pid, NeighborLeaderID, NeighborColor
            ]),
            % Aggiungi come neighbor solo se ha un LeaderID diverso
            UpdatedClusters =
                case NeighborLeaderID =/= LeaderID of
                    true -> [{Pid, NeighborColor, NeighborLeaderID} | AccumulatedClusters];
                    false -> AccumulatedClusters
                end,
            UpdatedNeighborsList = [{Pid, NeighborColor, NeighborLeaderID} | NeighborsList],
            gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters, UpdatedNeighborsList, Leader);
        %% Leader ID request from neighbors
        {get_leader_info, FromPid} ->
            io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
                self(), FromPid
            ]),
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color}
    after 5000 ->
        io:format("TIMEOUT per: ~p~n", [Pid]),
        gather_adjacent_clusters(Rest, LeaderID, AccumulatedClusters, NeighborsList, Leader)
    end.

gather_adjacent_nodes([], _LeaderID, AccumulatedAdjNodes) ->
    % Se NodePIDsWithoutSelf è vuoto, restituisci AccumulatedAdjNodes senza fare nulla
    AccumulatedAdjNodes;
gather_adjacent_nodes([Pid | Rest], LeaderID, AccumulatedAdjNodes) ->
    io:format("Recupero nodi adiacenti di ~p~n", [Pid]),
    Pid ! {get_list_neighbors, self()},
    receive
        {response_get_list_neighbors, Neighbors} ->
            io:format("~p mi ha inviato ~p~n", [Pid, Neighbors]),
            UpdatedAccumulatedNodes = AccumulatedAdjNodes ++ Neighbors,
            gather_adjacent_nodes(Rest, LeaderID, UpdatedAccumulatedNodes)
    after 5000 ->
        gather_adjacent_nodes(Rest, LeaderID, AccumulatedAdjNodes)
    end.

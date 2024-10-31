-module(node).
-export([
    create_node/2,
    node_loop/3,
    node_loop_propagate/7,
    new_node/3,
    new_leader/5
]).
-include("node.hrl").

%% new_node/3
%% Creates a basic node with the given parameters, including its PID and neighbors.
new_node(X, Y, Parent) ->
    #node{
        x = X,
        y = Y,
        parent = Parent
    }.

%% new_leader/5
%% Creates a leader node, assigns its own PID as the leaderID, and initializes neighbors.
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    % Step 1: Create a base node with an initial PID and empty neighbors
    Node = new_node(X, Y, ServerPid),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{node = Node, color = Color, serverID = ServerPid},

    % Step 3: Start the node process and update leaderID and pid fields
    UpdatedLeader = create_node(Leader, StartSystemPid),
    UpdatedLeader.

%% create_node/2
%% Spawns a process for a node, initializing it with its own leaderID and empty neighbors.
create_node(Leader, StartSystemPid) ->
    % Spawn the process for the node loop
    Pid = spawn(fun() ->
        node_loop(Leader, StartSystemPid, false)
    end),

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},

    io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
        UpdatedNode#node.x, UpdatedNode#node.y, Leader#leader.color, Pid
    ]),
    Pid ! {aggiorna_leader, UpdatedLeader},
    UpdatedLeader.

%% node_loop/3
%% Main node loop to receive messages and update state.
node_loop(Leader, StartSystemPid, Visited) ->
    io:format("Sono il nodo (~p, ~p) con PID ~p e sono pronto per ricevere nuovi messaggi!!~n", [
        Leader#leader.node#node.x, Leader#leader.node#node.y, self()
    ]),

    receive
        {aggiorna_leader, NewLeader} ->
            node_loop(NewLeader, StartSystemPid, Visited);
        {neighbors, Neighbors} ->
            io:format("Node (~p, ~p) received neighbors: ~p~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, Neighbors
            ]),
            % Update node state with neighbors and notify system
            UpdatedNode = Leader#leader.node#node{neighbors = Neighbors},
            UpdatedLeader = Leader#leader{node = UpdatedNode},

            io:format(
                "Sono il nodo (~p, ~p) con PID ~p e invio a il messaggio {ack_neighbors, ~p} a ~p~n",
                [
                    Leader#leader.node#node.x,
                    Leader#leader.node#node.y,
                    self(),
                    self(),
                    StartSystemPid
                ]
            ),

            StartSystemPid ! {ack_neighbors, self()},

            node_loop(
                UpdatedLeader, StartSystemPid, Visited
            );
        %% Sincronizzazione del tempo dal server
        {time, ServerTime} ->
            UpdatedNode = Leader#leader.node#node{time = ServerTime},
            UpdatedLeader = Leader#leader{node = UpdatedNode},

            io:format(
                "Node (~p, ~p) ha ricevuto il serverTime ~p e quindi updated its time to ~p~n", [
                    Leader#leader.node#node.x,
                    Leader#leader.node#node.y,
                    ServerTime,
                    Leader#leader.node#node.time
                ]
            ),

            node_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
        %% Server setup request
        %% Starts setup message propagation if the node hasn't been visited
        {setup_server_request, FromPid} ->
            if
                %% Node already visited, responds with 'node_already_visited'
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) receives setup_server_request, already visited, responding to server.~n",
                        [Leader#leader.node#node.x, Leader#leader.node#node.y]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(
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
                    node_loop_propagate(
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
                Visited == false andalso Leader#leader.color == SenderColor ->
                    io:format("Node (~p, ~p) has the same color as the requesting node.~n", [
                        Leader#leader.node#node.x, Leader#leader.node#node.y
                    ]),

                    % Update leaderID and pid in the node
                    UpdatedNode = Leader#leader.node#node{
                        parent = FromPid, leaderID = PropagatedLeaderID
                    },

                    node_loop_propagate(
                        %% Becames a simple node
                        UpdatedNode,
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
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) has already been visited, responding accordingly.~n", [
                            Leader#leader.node#node.x, Leader#leader.node#node.y
                        ]
                    ),
                    FromPid ! {self(), node_already_visited},
                    node_loop(
                        %% Already visited, so it doesn't change the type
                        Leader,
                        StartSystemPid,
                        Visited
                    );
                %% Node with different color, only acknowledges receipt
                true ->
                    io:format("Node (~p, ~p) has a different color (~p), sends only received.~n", [
                        Leader#leader.node#node.x, Leader#leader.node#node.y, Leader#leader.color
                    ]),
                    FromPid ! {self(), ack_propagation_different_color},
                    node_loop(
                        %% Different color, thus the node can be a leader of another cluster
                        Leader,
                        StartSystemPid,
                        Visited
                    )
            end;
        %% Fase 2 di avvio dal leader
        {start_phase2, NodePIDs} ->
            ServerPid = Leader#leader.serverID,
            X = Leader#leader.node#node.x,
            Y = Leader#leader.node#node.y,
            Neighbors = Leader#leader.node#node.neighbors,
            LeaderID = Leader#leader.node#node.leaderID,
            io:format("Leader Node (~p, ~p) starting Phase 2.~n", [X, Y]),

            %% Invia messaggio {get_leader_info, self()} a ciascun vicino e raccoglie le risposte
            AllAdjacentClusters = gather_adjacent_clusters(Neighbors, LeaderID, []),

            io:format("AllAdjacentClusters : ~p ~n", [AllAdjacentClusters]),

            io:format("Nodi cluster: ~p ~n", [NodePIDs]),

            %% Invia messaggio a ciascun nodo nel cluster `NodePIDs` per verificare cluster adiacenti
            FinalAdjacentClusters = gather_adjacent_clusters(
                NodePIDs, LeaderID, AllAdjacentClusters
            ),

            io:format("FinalAdjacentClusters : ~p ~n", [FinalAdjacentClusters]),

            %% Invia i cluster adiacenti finali al server
            ServerPid ! {self(), phase2_complete, LeaderID, FinalAdjacentClusters},

            UpdatedLeader = Leader#leader{
                nodes_in_cluster = NodePIDs, adjClusters = FinalAdjacentClusters
            },

            node_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
        %% Leader ID request from neighbors
        {get_leader_info, FromPid} ->
            io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
                self(), FromPid
            ]),
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
            node_loop(
                Leader,
                StartSystemPid,
                Visited
            );
        %% Adding a child to the list
        {add_child, ChildPid} ->
            UpdatedChildren = [ChildPid | Leader#leader.node#node.children],
            UpdatedNode = Leader#leader.node#node{children = UpdatedChildren},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            node_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
        %% Updates the leaderID
        {leader_update, NewLeader} ->
            UpdatedNode = Leader#node{leaderID = NewLeader},
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                Leader#node.children
            ),
            node_loop(
                UpdatedNode,
                StartSystemPid,
                Visited
            );
        %% Request to change the color of the cluster
        {color_change_request, NewColor} ->
            io:format("Node (~p, ~p) received a color change request to ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, NewColor
            ]),
            %% Invia il messaggio di cambio colore al leader
            Leader#node.leaderID ! {color_change, NewColor},
            node_loop(
                Leader, StartSystemPid, Visited
            );
        %% Change the color of the cluster
        {color_change, NewColor} ->
            io:format("Node (~p, ~p) changed color to ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, NewColor
            ]),
            % Updates the color of the cluster
            UpdatedLeader = Leader#leader{color = NewColor},
            % Notifies the server of the color change
            Leader#leader.serverID ! {color_change_complete, self(), NewColor},
            % Checks if the color is equal to one of the adjacent clusters.
            % If it's the case, sends a merge request to the ones that shares the same NewColor.
            lists:foreach(
                fun({SameColorNeighborPid, _SameColorNeighborColor}) ->
                    io:format("Node (~p, ~p) sends merge request to ~p.~n", [
                        Leader#leader.node#node.x, Leader#leader.node#node.y, SameColorNeighborPid
                    ]),
                    SameColorNeighborPid ! {merge_request, self()}
                end,
                lists:filter(
                    fun({_AdjLeaderID, AdjClusterColor}) ->
                        if
                            AdjClusterColor == NewColor ->
                                true;
                            true ->
                                false
                        end
                    end,
                    Leader#leader.adjClusters
                )
            ),
            node_loop(
                UpdatedLeader, StartSystemPid, Visited
            );
        %% Merge request from another cluster
        {merge_request, FromPid} ->
            io:format("Node (~p, ~p) received a merge request from ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, FromPid
            ]),
            % Updates the parent and leaderID on the loop
            UpdatedNode = Leader#leader.node#node{parent = FromPid, leaderID = FromPid},
            %% Propagates the leaderID update
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, FromPid}
                end,
                Leader#leader.node#node.children
            ),
            %% Sends its own adjacency clusters' list to the requesting node
            %% NOTE: this also work as an ACK for the merge request
            FromPid ! {adj_cluster_merge, self(), Leader#leader.adjClusters},
            node_loop(
                %% The node is no more a leader
                UpdatedNode,
                StartSystemPid,
                Visited
            );
        %% Receives the adjacency clusters list after a merge request as an ACK
        {adj_cluster_merge, NeighborPid, NeighborAjdCluster} ->
            io:format("Node (~p, ~p) received adjacency clusters from ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, NeighborPid
            ]),
            %% Updates the adjacency clusters with the received ones
            UpdatedAdjClusters = custom_merge(Leader#leader.adjClusters, NeighborAjdCluster),
            UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters},
            node_loop(
                UpdatedLeader, StartSystemPid, Visited
            );
        %% Unhandled messages
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y
            ]),
            node_loop(
                Leader, StartSystemPid, Visited
            )
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
node_loop_propagate(
    Leader,
    Color,
    FromPid,
    Visited,
    Neighbors,
    InitiatorFlag,
    StartSystemPid
) ->
    %% Checks if the node is a leader
    if
        is_record(Leader, leader) ->
            Node = Leader#leader.node;
        true ->
            Node = Leader
    end,

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

    %% Se il nodo era leader, aggiorna il nodo interno
    if
        is_record(Leader, leader) ->
            UpdatedLeader = Leader#leader{node = Node};
        true ->
            UpdatedLeader = Node
    end,

    %% Continua il ciclo principale del nodo con lo stato aggiornato
    node_loop(
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
        NeighborsToWaitFor == [] ->
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
                    io:format("Timeout while waiting for ACKs from neighbors: ~p~n", [
                        NeighborsToWaitFor
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
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters) ->
    % Restituisce la lista finale senza duplicati
    AccumulatedClusters;
gather_adjacent_clusters([Pid | Rest], LeaderID, AccumulatedClusters) ->
    Pid ! {get_leader_info, self()},
    receive
        {leader_info, NeighborLeaderID, NeighborColor} ->
            io:format("~p -> Ho ricevuto la risposta da ~p e mi ha mandato: {~p,~p}.~n", [
                self(), Pid, NeighborLeaderID, NeighborColor
            ]),
            %% Se il leaderID è diverso, aggiungilo alla lista
            UpdatedClusters =
                case NeighborLeaderID =/= LeaderID of
                    true -> [{NeighborLeaderID, NeighborColor} | AccumulatedClusters];
                    false -> AccumulatedClusters
                end,
            io:format("Per ora ho ~p e mi rimangono : ~p ~n", [UpdatedClusters, Rest]),
            gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters)
        % Timeout opzionale
    after 5000 ->
        gather_adjacent_clusters(Rest, LeaderID, AccumulatedClusters)
    end.

%% Custom merge because Erlang lists:merge doesn't suit our needs
custom_merge(AdjClusters, []) ->
    AdjClusters;
custom_merge(AdjClusters, [NeighborAdjCluster | RestNeighborAdjClusters]) ->
    %% TODO: check for duplicates, otherwise append
    UpdatedAdjClusters =
        case lists:member(NeighborAdjCluster, AdjClusters) of
            true ->
                AdjClusters;
            false ->
                lists:append(AdjClusters, [NeighborAdjCluster])
        end,
    custom_merge(UpdatedAdjClusters, RestNeighborAdjClusters).

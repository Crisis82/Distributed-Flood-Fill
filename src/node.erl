-module(node).
-export([
    create_node/2,
    leader_loop/3,
    node_loop_propagate/7,
    new_node/8,
    new_leader/5
]).
-include("node.hrl").
-include("event.hrl").

%% new_node/8
%% Creates a basic node with the given parameters, including its PID and neighbors.
new_node(X, Y, Parent, Children, Time, LeaderID, Pid, Neighbors) ->
    #node{
        x = X,
        y = Y,
        parent = Parent,
        children = Children,
        time = Time,
        leaderID = LeaderID,
        pid = Pid,
        neighbors = Neighbors
    }.

%% new_leader/5
%% Creates a leader node, assigns its own PID as the leaderID, and initializes neighbors.
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    % Step 1: Create a base node with an initial PID and empty neighbors
    Node = new_node(X, Y, ServerPid, [], undefined, undefined, undefined, []),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{
        node = Node, color = Color, serverID = ServerPid, adjClusters = [], nodes_in_cluster = []
    },

    % Step 3: Start the node process and update leaderID and pid fields
    UpdatedLeader = create_node(Leader, StartSystemPid),
    UpdatedLeader.

%% create_node/2
%% Spawns a process for a node, initializing it with its own leaderID and empty neighbors.
create_node(Leader, StartSystemPid) ->
    % Spawn the process for the node loop
    Pid = spawn(fun() ->
        leader_loop(Leader, StartSystemPid, false)
    end),
    %% Register the pid to the alias node_X_Y
    %% register(list_to_atom(lists:flatten(io_lib:format("node_~p_~p",[Leader#leader.node#node.x, Leader#leader.node#node.y]))), Pid).

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},

    io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
        UpdatedNode#node.x, UpdatedNode#node.y, Leader#leader.color, Pid
    ]),
    Pid ! {aggiorna_leader, UpdatedLeader},
    UpdatedLeader.

%% leader_loop/3
%% Main node loop to receive messages and update state.
leader_loop(Leader, StartSystemPid, Visited) ->
    io:format("Sono il nodo (~p, ~p) con PID ~p e sono pronto per ricevere nuovi messaggi!!~n", [
        Leader#leader.node#node.x, Leader#leader.node#node.y, self()
    ]),

    save_data(Leader),

    receive
        {aggiorna_leader, NewLeader} ->
            leader_loop(NewLeader, StartSystemPid, Visited);
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

            leader_loop(
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

            leader_loop(
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
                    leader_loop(
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
                    UpdatedLeader = Leader#leader{node = UpdatedNode},

                    node_loop_propagate(
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
                Visited == true ->
                    io:format(
                        "Node (~p, ~p) has already been visited, responding accordingly.~n", [
                            Leader#leader.node#node.x, Leader#leader.node#node.y
                        ]
                    ),
                    FromPid ! {self(), node_already_visited},
                    leader_loop(
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
                    leader_loop(
                        %% Different color, thus the node can be a leader of another cluster
                        Leader,
                        StartSystemPid,
                        Visited
                    )
            end;
        {get_list_neighbors, FromPid} ->
            io:format("~p: Invio a ~p la lista dei miei vicini", [self(), FromPid]),
            FromPid ! {response_get_list_neighbors, Leader#leader.node#node.neighbors};
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
            AdjNodesToCluster_no_duplicates = remove_duplicates(AdjNodesToCluster),

            io:format("AdjNodesToCluster: ~p,~nAdjNodesToCluster_no_duplicates: ~p~n", [
                AdjNodesToCluster, AdjNodesToCluster_no_duplicates
            ]),

            %% Usa `gather_adjacent_clusters` per raccogliere informazioni sui Neighbors del
            AllAdjacentClusters = gather_adjacent_clusters(
                AdjNodesToCluster_no_duplicates, LeaderID, [], []
            ),

            io:format("AllAdjacentClusters: ~p~n", [
                AllAdjacentClusters
            ]),

            %% Invia il messaggio ai nodi del cluster con le informazioni finali
            ServerPid ! {self(), phase2_complete, LeaderID, AllAdjacentClusters},

            UpdatedLeader = Leader#leader{
                nodes_in_cluster = NodePIDs, adjClusters = AllAdjacentClusters
            },

            leader_loop(
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
            leader_loop(
                Leader,
                StartSystemPid,
                Visited
            );
        %% Adding a child to the list
        {add_child, ChildPid} ->
            UpdatedChildren = [ChildPid | Leader#leader.node#node.children],
            UpdatedNode = Leader#leader.node#node{children = UpdatedChildren},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            leader_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
        {save_to_db, ServerPid} ->
            % Procedura per salvare le informazioni su DB locale
            save_data(Leader),
            ServerPid ! {ack_save_to_db, self()},

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

            % Continua il loop
            leader_loop(
                Leader,
                StartSystemPid,
                Visited
            );
        {save_to_db_node} ->
            % Salva solo i dati del nodo in un file JSON locale
            Node = Leader#leader.node,
            save_data(Node),
            node_loop(Node, StartSystemPid, Visited);
        %% Updates the leaderID
        {leader_update, NewLeader} ->
            UpdatedLeader = Leader#node{leaderID = NewLeader},
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                Leader#node.children
            ),
            leader_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
        {change_color, Color} ->
            self() ! {change_color, self(), Color, event:new()},
            leader_loop(
                Leader,
                StartSystemPid,
                Visited
            );
        {change_color, PID, Color, _Time} ->
            io:format(
                "Node (~p, ~p) ha ricevuto una richiesta di cambio colore da ~p e cambia il colore a ~p.~n",
                [
                    Leader#leader.node#node.x, Leader#leader.node#node.y, PID, Color
                ]
            ),

            %% Aggiorna il colore del leader o del nodo
            UpdatedLeader = Leader#leader{color = Color},

            %% Notifica ai vicini il cambio di colore
            notify_neighbors_of_color_change(UpdatedLeader, Color, StartSystemPid, Visited);
        {color_adj_update, FromPid, Color} ->
            io:format("Nodo (~p, ~p) ha ricevuto color_adj_update da ~p con nuovo colore ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, FromPid, Color
            ]),

            %% Aggiorna il colore nella lista dei cluster adiacenti
            UpdatedAdjClusters = update_adj_cluster_color(
                Leader#leader.adjClusters, FromPid, Color
            ),
            UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters},
            %% Continua il ciclo con lo stato aggiornato
            leader_loop(UpdatedLeader, StartSystemPid, Visited);
        {cluster_data, _FromLeaderPid, FromLeaderData} ->
            % Merge clusters
            UpdatedLeader = merge_clusters(Leader, FromLeaderData),
            % Continue as leader
            leader_loop(UpdatedLeader, StartSystemPid, Visited);
        %% Gestisco richiesta di merge da un altro leader
        {merge_request, LeaderID} ->
            io:format(
                "~p -> Richiesta di merge ricevuta da ID ~p.~n", [
                    self(), LeaderID
                ]
            ),

            % Inform cluster about the leader update
            lists:foreach(
                fun(NodePid) ->
                    io:format("Sending leader_update to ~p con nuovo leader ~p.~n", [
                        NodePid, LeaderID
                    ]),
                    NodePid ! {leader_update, LeaderID}
                end,
                Leader#leader.nodes_in_cluster
            ),

            % Send current nodes_in_cluster and adjClusters to the new leader
            LeaderID !
                {response_to_merge, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters},

            io:format("Sending response_to_merge to ~p con ~p e ~p.~n", [
                LeaderID, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters
            ]),

            % Update the leaderID of the current node
            Node = Leader#leader.node,
            UpdatedNode = Node#node{leaderID = LeaderID},

            Leader#leader.serverID ! {remove_myself_from_leaders, self()},

            % lists:foreach(
            %    fun({pid, _NeighborColor, _NeighborLeaderID}) ->
            %        io:format("Sending remove_myself_from_leaders to ~p.~n", [
            %            pid
            %        ]),
            %        pid ! {remove_myself_from_leaders, LeaderIDMinore}
            %    end,
            %    Leader#leader.adjClusters
            % ),

            % Transform into a regular node and start the node loop
            node_loop(UpdatedNode, StartSystemPid, Visited);
        {leader_update, new_leader} ->
            Node = Leader#leader.node,
            UpdatedNode = Node#node{leaderID = new_leader},

            UpdatedLeader = Leader#leader{node = UpdatedNode},

            leader_loop(UpdatedLeader, StartSystemPid, Visited);
        {update_nodes_in_cluster, NodesInCluster, NewLeaderID, NewColor} ->
            Node = Leader#leader.node,
            Neighbors = Node#node.neighbors,

            UpdatedNeighbors = lists:map(
                fun({NeighborPid, _NeighborColor, _NeighborLeaderID} = Neighbor) ->
                    case lists:member(NeighborPid, NodesInCluster) of
                        true ->
                            io:format("Updating neighbor ~p with new leader ~p and color ~p.~n", [
                                NeighborPid, NewLeaderID, NewColor
                            ]),
                            {NeighborPid, NewColor, NewLeaderID};
                        false ->
                            Neighbor
                    end
                end,
                Neighbors
            ),

            UpdatedNode = Node#node{neighbors = UpdatedNeighbors},
            UpdatedLeader = Leader#leader{node = UpdatedNode},

            leader_loop(UpdatedLeader, StartSystemPid, Visited);
        %% Unhandled messages
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y
            ]),
            leader_loop(
                Leader, StartSystemPid, Visited
            )
    end.

merge_clusters(Leader1, Leader2) ->
    % Merge nodes_in_cluster, removing duplicates
    NodesInCluster = lists:usort(
        Leader1#leader.nodes_in_cluster ++ Leader2#leader.nodes_in_cluster
    ),
    % Merge adjClusters, ensuring no duplicates
    AdjClusters = lists:usort(Leader1#leader.adjClusters ++ Leader2#leader.adjClusters),
    % Remove self references from adjClusters
    AdjClustersFiltered = [
        {Pid, Color, LeaderID}
     || {Pid, Color, LeaderID} <- AdjClusters,
        Pid =/= Leader1#leader.node#node.pid,
        Pid =/= Leader2#leader.node#node.pid
    ],
    % Update the leader's state
    UpdatedLeader = Leader1#leader{
        nodes_in_cluster = NodesInCluster,
        adjClusters = AdjClustersFiltered
    },
    UpdatedLeader.

notify_neighbors_of_color_change(Leader, Color, StartSystemPid, Visited) ->
    ColorAtom =
        if
            is_atom(Color) -> Color;
            true -> list_to_atom(Color)
        end,
    SameColorAdjClusters = [
        {NeighborPid, NeighborColor, LeaderID}
     || {NeighborPid, NeighborColor, LeaderID} <- Leader#leader.adjClusters,
        NeighborColor == ColorAtom
    ],

    io:format("Gli adjacents clusters sono ~p, quelli con il colore ~p sono: ~p.~n", [
        Leader#leader.adjClusters, ColorAtom, SameColorAdjClusters
    ]),

    UpdatedLeader =
        case SameColorAdjClusters of
            [] ->
                io:format(
                    "Nessun vicino con lo stesso colore. Invio color_adj_update a tutti i vicini.~n"
                ),
                Leader;
            _ ->
                io:format(
                    "Vicini con lo stesso colore trovati. Avvio processo di merge sequenziale.~n"
                ),
                % Avvia il merge sequenziale per ogni cluster con lo stesso colore

                merge_adjacent_clusters(SameColorAdjClusters, Leader, StartSystemPid, Visited)
        end,

    % Invia color_adj_update a ciascun cluster adiacente aggiornato
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            io:format("Inviando color_adj_update a ~p.~n", [OtherLeaderID]),
            OtherLeaderID ! {color_adj_update, self(), UpdatedLeader#leader.color}
        end,
        UpdatedLeader#leader.adjClusters
    ),

    % Comunica al server la nuova configurazione del leader
    UpdatedLeader#leader.serverID ! {change_color_complete, self(), UpdatedLeader},

    X = Leader#leader.node#node.x,
    Y = Leader#leader.node#node.y,
    Event = event:new(),

    % scrivi log
    log_operation(X, Y, Event, io_lib:format("Cambio colore a ~p", [Color])),

    % Continua il ciclo principale del leader
    leader_loop(UpdatedLeader, StartSystemPid, Visited).

merge_adjacent_clusters([], Leader, _StartSystemPid, _Visited) ->
    % Nessun altro cluster da gestire, restituisce il leader aggiornato
    Leader;
merge_adjacent_clusters(
    [{_NeighborPid, _NeighborColor, AdjLeaderID} | Rest], Leader, StartSystemPid, Visited
) ->
    io:format("Inviando merge_request al leader adiacente con PID ~p.~n", [AdjLeaderID]),
    % scrivi log
    X = Leader#leader.node#node.x,
    Y = Leader#leader.node#node.y,
    Event = event:new(),

    log_operation(
        X,
        Y,
        Event,
        io_lib:format("Inviando merge_request al leader adiacente con PID ~p", [AdjLeaderID])
    ),
    AdjLeaderID ! {merge_request, self()},
    receive
        {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore} ->
            % Unisce i cluster adiacenti e rimuove eventuali duplicati
            UpdatedAdjClusters = join_adj_clusters(Leader#leader.adjClusters, AdjListIDMaggiore),

            % Rimuove se stesso e l'altro leader dalla lista dei cluster adiacenti
            FilteredAdjClusters = lists:filter(
                fun({_, _, LeaderID}) ->
                    LeaderID =/= Leader#leader.node#node.leaderID andalso
                        LeaderID =/= AdjLeaderID
                end,
                UpdatedAdjClusters
            ),

            % Unisce le liste dei nodi nel cluster
            UpdatedNodeList = join_nodes_list(Leader#leader.nodes_in_cluster, Nodes_in_Cluster),

            % Crea il nuovo leader aggiornato
            UpdatedLeader = Leader#leader{
                adjClusters = FilteredAdjClusters,
                nodes_in_cluster = UpdatedNodeList
            },

            io:format("Aggiornamento del leader con il merge completato: ~p~n", [UpdatedLeader]),

            % Continua il merge per i prossimi vicini
            merge_adjacent_clusters(Rest, UpdatedLeader, StartSystemPid, Visited)
        % Timeout di esempio per evitare blocchi
    after 5000 ->
        io:format("Timeout nel ricevere la risposta dal leader adiacente con PID ~p.~n", [
            AdjLeaderID
        ]),
        % Ritorna l'ultimo leader conosciuto
        Leader
    end.

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

update_adj_cluster_color([], _FromPid, _Color) ->
    % Caso base: lista vuota
    [];
update_adj_cluster_color([{FromPid, _OldColor, LeaderID} | Rest], FromPid, NewColor) ->
    % Aggiorna il colore
    [{FromPid, NewColor, LeaderID} | Rest];
update_adj_cluster_color([Other | Rest], FromPid, NewColor) ->
    % Ricorsivamente per gli altri elementi
    [Other | update_adj_cluster_color(Rest, FromPid, NewColor)].

node_loop(Node, _StartSystemPid, _Visited) ->
    io:format("~p -> Sono il nodo (~p, ~p) con PID ~p e sono associato al Leader ~p~n", [
        self(),
        Node#node.x,
        Node#node.y,
        Node#node.pid,
        Node#node.leaderID
    ]),
    save_data(Node),
    receive
        {change_color, Color} ->
            Node#node.leaderID ! {change_color, Node#node.pid, Color, event:new()},
            node_loop(Node, _StartSystemPid, _Visited);
        {leader_update, NewLeaderPid} ->
            % Update the node's leader ID
            UpdatedNode = Node#node{leaderID = NewLeaderPid},
            % Continue the node loop
            node_loop(UpdatedNode, _StartSystemPid, _Visited);
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [
                Node#node.x, Node#node.y
            ]),
            node_loop(Node, _StartSystemPid, _Visited)
    end.

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
    % Get coordinates X and Y
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),

    % Ensure the directory exists
    filelib:ensure_dir(Filename),

    % Costruisci i dati JSON del nodo in formato stringa
    JsonData = io_lib:format(
        "{\n\"pid\": \"~s\", \"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": \"~s\", \"leader_id\": \"~s\", \"neighbors\": ~s\n}",
        [
            pid_to_string(Node#node.pid),
            X,
            Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            format_time(Node#node.time),
            pid_to_string(Node#node.leaderID),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Save the JSON data to the file
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Node data saved in: ~s~n", [Filename]).

%% Funzione per salvare i dati di Leader in un file JSON locale
save_leader_data_to_file(Leader) ->
    Node = Leader#leader.node,

    % Ottieni le coordinate X e Y per costruire il nome del file
    X = Node#node.x,
    Y = Node#node.y,
    Dir = io_lib:format("DB/~p_~p/", [X, Y]),
    Filename = lists:concat([Dir, "data.json"]),

    % Crea la cartella DB/X_Y/ se non esiste
    filelib:ensure_dir(Filename),

    % Ottieni il tempo come stringa formattata "HH:MM:SS"
    TimeFormatted = format_time(Node#node.time),

    % Costruisci i dati JSON del leader e del nodo associato in formato stringa
    JsonData = io_lib:format(
        "{\n\"leader_id\": \"~s\", \"color\": \"~s\", \"server_id\": \"~s\", \"adj_clusters\": ~s, \"nodes_in_cluster\": ~s,\n" ++
            "\"node\": {\n\"x\": ~p, \"y\": ~p, \"parent\": \"~s\", \"children\": ~s, \"time\": ~p, \"leader_id\": \"~s\", \"pid\": \"~s\", \"neighbors\": ~s\n}}",
        [
            pid_to_string(Node#node.pid),
            atom_to_string(Leader#leader.color),
            pid_to_string(Leader#leader.serverID),
            convert_adj_clusters(Leader#leader.adjClusters),
            convert_node_list(Leader#leader.nodes_in_cluster),
            X,
            Y,
            pid_to_string(Node#node.parent),
            convert_node_list(Node#node.children),
            TimeFormatted,
            pid_to_string(Node#node.leaderID),
            pid_to_string(Node#node.pid),
            convert_adj_clusters(Node#node.neighbors)
        ]
    ),

    % Salva i dati JSON in DB/X_Y/data.json
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Dati di Leader (~p,~p) con PID ~p salvati in: ~s~n", [X, Y, self(), Filename]).

%% Funzione di supporto per formattare il tempo in una stringa "HH:MM:SS"
format_time({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_time(undefined) ->
    "undefined".

%% Funzione helper per convertire la lista di cluster adiacenti in formato JSON-friendly
convert_adj_clusters(AdjClusters) ->
    JsonClusters = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [pid_to_string(Pid), atom_to_string(Color), pid_to_string(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- AdjClusters
    ],
    "[" ++ string:join(JsonClusters, ",") ++ "]".

%% Funzione helper per convertire la lista di nodi in formato JSON-friendly
convert_node_list(Nodes) ->
    JsonNodes = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    "[" ++ string:join(JsonNodes, ",") ++ "]".

%% Funzione per convertire un PID in stringa
pid_to_string(Pid) when is_pid(Pid) ->
    erlang:pid_to_list(Pid);
pid_to_string(undefined) ->
    "undefined".

%% Funzione per convertire un atomo in una stringa JSON-friendly
atom_to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
atom_to_string(Other) -> Other.

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

    leader_loop(
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
%% Funzione per inviare il messaggio e raccogliere i leader ID distinti dai vicini
%% evitando messaggi inutili se i dati sono già presenti in `neighbors`.
%% Funzione aggiornata per raccogliere le informazioni sui neighbors
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters, _NeighborsList) ->
    % Restituisce la lista finale dei neighbors e clusters senza duplicati
    AccumulatedClusters;
gather_adjacent_clusters([Pid | Rest], LeaderID, AccumulatedClusters, NeighborsList) ->
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
            gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters, UpdatedNeighborsList)
    after 5000 ->
        gather_adjacent_clusters(Rest, LeaderID, AccumulatedClusters, NeighborsList)
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

remove_duplicates(List) ->
    lists:usort(List).

%% Funzione per salvare l'operazione nel log con il timestamp passato come parametro
log_operation(X, Y, Event, Operation) ->
    % Formatta il timestamp come stringa
    TimestampStr = format_timestamp(Event#event.timestamp),

    % Crea il percorso per il file di log DB/X_Y/log
    Dir = io_lib:format("DB/~p_~p/", [X, Y]),
    LogFile = lists:concat([Dir, "log"]),

    % Assicurati che la directory esista
    filelib:ensure_dir(LogFile),

    % Scrivi l'operazione nel file di log
    LogEntry = io_lib:format("~s - ~s~n", [TimestampStr, Operation]),
    file:write_file(LogFile, lists:flatten(LogEntry), [append]),

    io:format("Operazione loggata: ~s - ~s~n", [TimestampStr, Operation]).

%% Funzione di supporto per formattare il timestamp in "HH:MM:SS"
format_timestamp({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_timestamp(undefined) ->
    "undefined".

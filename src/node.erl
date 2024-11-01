-module(node).
-export([
    create_node/2,
    leader_loop/3,
    node_loop_propagate/7,
    new_node/8,
    new_leader/5
]).
-include("node.hrl").

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
        %% Fase 2 di avvio dal leader
        {start_phase2, NodePIDs} ->
            ServerPid = Leader#leader.serverID,
            X = Leader#leader.node#node.x,
            Y = Leader#leader.node#node.y,
            InitialNeighbors = Leader#leader.node#node.neighbors,
            LeaderID = Leader#leader.node#node.leaderID,

            io:format("Leader Node (~p, ~p) starting Phase 2.~n", [X, Y]),

            %% Usa `gather_adjacent_clusters` per raccogliere informazioni evitando messaggi inutili
            {AllAdjacentClusters, NeighborsList} = gather_adjacent_clusters(
                InitialNeighbors, LeaderID, [], []
            ),

            io:format("AllAdjacentClusters: ~p~nNeighborsList: ~p~n", [
                AllAdjacentClusters, NeighborsList
            ]),

            %% Invia il messaggio ai nodi del cluster con le informazioni finali
            ServerPid ! {self(), phase2_complete, LeaderID, AllAdjacentClusters},

            %% Aggiorna il leader con le informazioni raccolte e i nuovi neighbors
            UpdatedNode = Leader#leader.node#node{neighbors = NeighborsList},
            UpdatedLeader = Leader#leader{
                node = UpdatedNode, nodes_in_cluster = NodePIDs, adjClusters = AllAdjacentClusters
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
            save_to_local_db(Leader),
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
            save_to_local_db_node(Node),
            node_loop(Node, StartSystemPid, Visited);
        %% Updates the leaderID
        {leader_update, NewLeader} ->
            UpdatedNode = Leader#node{leaderID = NewLeader},
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                Leader#node.children
            ),
            leader_loop(
                UpdatedNode,
                StartSystemPid,
                Visited
            );
        {change_color, Color} ->
            self() ! {change_color, self(), Color, Leader#leader.node#node.time},
            leader_loop(
                Leader,
                StartSystemPid,
                Visited
            );
        {change_color, PID, Color, Time} ->
            io:format(
                "Node (~p, ~p) ha ricevuto una richiesta di cambio colore da ~p e cambia il colore a ~p.~n",
                [
                    Leader#leader.node#node.x, Leader#leader.node#node.y, PID, Color
                ]
            ),

            %% Aggiorna il colore del leader o del nodo
            UpdatedLeader = Leader#leader{color = Color},

            %% Notifica ai vicini il cambio di colore
            notify_neighbors_of_color_change(Leader#leader.node#node.neighbors, Color),

            %% Segnala al server il cambio di colore
            io:format("Il nodo ~p invia change_color_complete a server.~n", [
                self()
            ]),

            Leader#leader.serverID ! {change_color_complete, self(), Color, Time},

            %% Continua il ciclo con il colore aggiornato
            leader_loop(
                UpdatedLeader,
                StartSystemPid,
                Visited
            );
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
        {merge_request_from_small_ID, FromLeaderPid} ->
            io:format(
                "Received merge_request_from_small_ID from ~p. Relinquishing leadership to ~p.~n", [
                    FromLeaderPid
                ]
            ),
            % Send cluster data to the sender
            FromLeaderPid ! {cluster_data, self(), Leader},
            % Update nodes to have new leader ID
            update_nodes_leader_id(Leader#leader.nodes_in_cluster, FromLeaderPid),
            % Become a regular node
            node_loop(
                update_to_regular_node(Leader#leader.node, FromLeaderPid), StartSystemPid, Visited
            );
        {cluster_data, FromLeaderPid, FromLeaderData} ->
            % Merge clusters
            UpdatedLeader = merge_clusters(Leader, FromLeaderData),
            % Continue as leader
            leader_loop(UpdatedLeader, StartSystemPid, Visited);
        {merge_request_from_greater_ID, FromLeaderPid} ->
            io:format(
                "Received merge_request_from_greater_ID from ~p. Accepting merge and keeping leadership.~n",
                [FromLeaderPid]
            ),
            % Request cluster data from sender
            FromLeaderPid ! {cluster_data_request, self()},
            receive
                {cluster_data, FromLeaderPid, FromLeaderData} ->
                    % Merge clusters
                    UpdatedLeader = merge_clusters(Leader, FromLeaderData),
                    % Update nodes in merged cluster
                    update_nodes_leader_id(FromLeaderData#leader.nodes_in_cluster, self()),
                    % Notify sender it is now a regular node
                    FromLeaderPid ! {merge_ack, self(), leader},
                    % Inform neighbors
                    notify_neighbors_of_color_change(
                        UpdatedLeader#leader.node#node.neighbors, UpdatedLeader#leader.color
                    ),
                    % Notify server
                    UpdatedLeader#leader.serverID ! {cluster_merge_complete, self(), UpdatedLeader},
                    % Continue as leader
                    leader_loop(UpdatedLeader, StartSystemPid, Visited)
            after 5000 ->
                io:format("Timeout waiting for cluster data from ~p~n", [FromLeaderPid]),
                leader_loop(Leader, StartSystemPid, Visited)
            end;
        {cluster_data_request, ToLeaderPid} ->
            % Send cluster data
            ToLeaderPid ! {cluster_data, self(), Leader},
            % Update nodes to have new leader ID
            update_nodes_leader_id(Leader#leader.nodes_in_cluster, ToLeaderPid),
            % Become a regular node
            node_loop(
                update_to_regular_node(Leader#leader.node, ToLeaderPid), StartSystemPid, Visited
            );
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

update_nodes_leader_id(NodePIDs, NewLeaderPid) ->
    lists:foreach(
        fun(NodePid) ->
            NodePid ! {leader_update, NewLeaderPid}
        end,
        NodePIDs
    ).
update_to_regular_node(Node, NewLeaderPid) ->
    Node#node{leaderID = NewLeaderPid}.

notify_neighbors_of_color_change(Neighbors, Color) ->
    Self = self(),
    % Identify neighbors with the same color
    SameColorNeighbors = [
        {NeighborPid, NeighborColor, LeaderID}
     || {NeighborPid, NeighborColor, LeaderID} <- Neighbors,
        NeighborColor == Color
    ],
    case SameColorNeighbors of
        [] ->
            % No neighbors with the same color, send color_adj_update to all
            io:format(
                "No neighbors with the same color. Sending color_adj_update to all neighbors.~n"
            ),
            lists:foreach(
                fun({NeighborPid, _NeighborColor, _LeaderID}) ->
                    io:format("Sending color_adj_update to ~p.~n", [NeighborPid]),
                    NeighborPid ! {color_adj_update, Self, Color}
                end,
                Neighbors
            );
        _ ->
            % Neighbors with the same color exist
            io:format("Neighbors with the same color found. Checking for merge possibilities.~n"),
            lists:foreach(
                fun({_NeighborPid, _NeighborColor, LeaderID}) ->
                    % Compare Leader PIDs
                    case erlang:compare(LeaderID, Self) of
                        gt ->
                            % Neighbor's LeaderID is greater, send merge_request_from_small_ID
                            io:format("Sending merge_request_from_small_ID to Leader PID ~p.~n", [
                                LeaderID
                            ]),
                            LeaderID ! {merge_request_from_small_ID, Self};
                        lt ->
                            % Self has greater ID, send merge_request_from_greater_ID
                            io:format(
                                "Sending merge_request_from_greater_ID to Leader PID ~p.~n", [
                                    LeaderID
                                ]
                            ),
                            LeaderID ! {merge_request_from_greater_ID, Self};
                        eq ->
                            % If PIDs are equal, do nothing
                            io:format("Same PID as Leader PID ~p; no merge required.~n", [LeaderID])
                    end
                end,
                SameColorNeighbors
            )
    end.

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
    receive
        {change_color, Color} ->
            Node#node.leaderID ! {change_color, Node#node.pid, Color, Node#node.time},
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

%% Funzione per salvare i dati di un nodo in un file JSON locale
save_to_local_db_node(Node) ->
    % Ottieni le coordinate X e Y per costruire il nome del file
    X = Node#node.x,
    Y = Node#node.y,
    Filename = io_lib:format("DB/~p_~p_node.json", [X, Y]),

    % Crea la cartella DB se non esiste
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

    % Salva i dati JSON in un file locale
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Dati del nodo salvati in: ~s~n", [Filename]).

%% Funzione di supporto per formattare il tempo in una stringa "HH:MM:SS"
format_time({Hour, Minute, Second}) ->
    io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second]);
format_time(undefined) ->
    "undefined".

%% Funzione per salvare i dati di Leader in un file JSON locale
save_to_local_db(Leader) ->
    Node = Leader#leader.node,

    % Ottieni le coordinate X e Y per costruire il nome del file
    X = Node#node.x,
    Y = Node#node.y,
    Filename = io_lib:format("DB/~p_~p.json", [X, Y]),

    % Crea la cartella DB se non esiste
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

    % Salva i dati JSON in un file locale
    file:write_file(Filename, lists:flatten(JsonData)),
    io:format("Dati di Leader (~p,~p) con PID ~p salvati in: ~s~n", [X, Y, self(), Filename]).

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
pid_to_string(Pid) -> erlang:pid_to_list(Pid).

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
gather_adjacent_clusters([], _LeaderID, AccumulatedClusters, NeighborsList) ->
    % Restituisce la lista finale dei neighbors e clusters senza duplicati
    {AccumulatedClusters, NeighborsList};
gather_adjacent_clusters(
    [{Pid, NeighborColor, NeighborLeaderID} | Rest], LeaderID, AccumulatedClusters, NeighborsList
) ->
    % Controlla se il vicino ha un LeaderID diverso e aggiungilo a clusters e neighbors
    UpdatedClusters =
        case NeighborLeaderID =/= LeaderID of
            true -> [{Pid, NeighborColor, NeighborLeaderID} | AccumulatedClusters];
            false -> AccumulatedClusters
        end,
    UpdatedNeighborsList = [{Pid, NeighborColor, NeighborLeaderID} | NeighborsList],
    gather_adjacent_clusters(Rest, LeaderID, UpdatedClusters, UpdatedNeighborsList);
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

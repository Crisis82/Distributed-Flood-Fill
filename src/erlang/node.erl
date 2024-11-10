-module(node).

-export([
    new_leader/3,
    create_node/1,
    leader_loop/1,
    node_loop/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% Creates a basic node with the given parameters, including its PID and neighbors.
new_node(Pid, X, Y, LeaderID, Neighbors) ->
    #node{
        pid = Pid,
        x = X,
        y = Y,
        leaderID = LeaderID,
        neighbors = Neighbors
    }.

%% Creates a leader node, assigns its own PID as the leaderID, and initializes neighbors.
new_leader(X, Y, Color) ->
    % Step 1: Create a base node with an initial PID and empty neighbors
    Node = new_node(undefined, X, Y, undefined, []),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{
        node = Node,
        color = Color,
        last_event = event:new(undefined, undefined, undefined),
        adj_clusters = [],
        cluster_nodes = []
    },

    % Step 3: Start the node process and update leaderID and pid fields
    UpdatedLeader = create_node(Leader),
    UpdatedLeader.

%% Spawns a process for a node, initializing it with its own leaderID and empty neighbors.
create_node(Leader) ->
    % Spawn the process for the node loop
    Pid = spawn(fun() ->
        setup:setup_loop(Leader, false)
    end),

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},

    % io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
    %     UpdatedNode#node.x, UpdatedNode#node.y, Leader#leader.color, Pid
    % ]),
    UpdatedLeader.

%% Leader loop to receive messages and update state.
% Funzione principale del leader
leader_loop(Leader) ->
    % Inizializza il ciclo di elaborazione dei messaggi
    handle_messages_leader(Leader).

% Funzione ricorsiva per gestire tutti i messaggi in coda
handle_messages_leader(Leader) ->
    % Salva i dati del leader
    utils:save_data(Leader),

    % Ottiene la lunghezza della coda dei messaggi
    QueueLength = erlang:process_info(self(), message_queue_len),

    % Stampa la lunghezza della coda solo se ci sono messaggi
    %case QueueLength of
    %    {message_queue_len, Len} when Len > 0 ->
    %        % io:format("~p: Lunghezza coda messaggi: ~p~n", [self(),Len]);
    %    _ ->
    %        ok
    %end,

    % Se la coda dei messaggi è vuota, termina la ricorsione
    case QueueLength of
        {message_queue_len, 0} ->
            %% io:format("Tutti i messaggi sono stati elaborati. Nessun messaggio rimanente in coda.~n"),

            % Riprende il ciclo leader principale
            handle_messages_leader(Leader);
        _ ->
            % Altrimenti, riceve e gestisce il messaggio successivo e poi richiama `handle_messages_leader` ricorsivamente

            receive
                {get_leader_info, FromPid} ->
                    % io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
                    %     self(), FromPid
                    % ]),
                    FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
                    handle_messages_leader(Leader);
                {new_leader_elected, NewLeaderPid} ->
                    % Update the leader's node to use the new leader PID
                    UpdatedNode = Leader#leader.node#node{leaderID = NewLeaderPid},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);
                {remove_adjacent_cluster, DeadLeaderPid} ->
                    % Remove the dead cluster from the adjacency list
                    NewAdjClusters = operation:remove_cluster_from_adjacent(
                        DeadLeaderPid, Leader#leader.adj_clusters
                    ),
                    UpdatedLeader = Leader#leader{adj_clusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);
                {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo} ->
                    % Update the adjacency list with the new leader info
                    NewAdjClusters = operation:update_adjacent_cluster_info(
                        NewLeaderPid, UpdatedClusterInfo, Leader#leader.adj_clusters
                    ),
                    UpdatedLeader = Leader#leader{adj_clusters = NewAdjClusters},
                    handle_messages_leader(UpdatedLeader);
                {aggiorna_leader, NewLeader} ->
                    handle_messages_leader(NewLeader);
                {save_to_db} ->
                    % Procedura per salvare le informazioni su DB locale
                    utils:save_data(Leader),
                    % server ! {ack_save_to_db, self()},

                    % Crea una lista dei nodi nel cluster escludendo il PID del leader
                    FilteredNodes = lists:filter(
                        fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                        Leader#leader.cluster_nodes
                    ),

                    % Trasforma tutti i nodi del cluster (tranne leader in nodi normali)
                    lists:foreach(
                        fun(NodePid) ->
                            NodePid ! {trasform_to_normal_node}
                        end,
                        FilteredNodes
                    ),

                    % Continua il loop
                    handle_messages_leader(Leader);
                {trasform_to_normal_node} ->
                    % Salva solo i dati del nodo in un file JSON locale
                    Node = Leader#leader.node,
                    utils:save_data(Node),
                    node_loop(Node);
                %% Updates the leaderID
                {leader_update, NewLeader} ->
                    % propagate update to other cluster nodes
                    OtherClusterNodes = lists:delete(self(), Leader#leader.cluster_nodes),
                    lists:foreach(
                        fun(child) ->
                            child ! {leader_update, NewLeader}
                        end,
                        OtherClusterNodes
                    ),
                    UpdatedNode = Leader#leader.node#node{leaderID = NewLeader},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},
                    handle_messages_leader(UpdatedLeader);
                %% Leader receives direcly a color change request
                {change_color_request, Event} ->
                    % GreaterEvent = event:greater(Event, Leader#leader.last_event),
                    TimeDifference =
                        convert_time_to_ms(Event#event.timestamp) -
                            convert_time_to_ms(Leader#leader.last_event#event.timestamp),

                    io:format(
                        "~n~n~p : Gestione della richiesta 'change_color_request'.~n" ++
                            "Ultimo evento: ~p~n" ++
                            "Nuovo evento: ~p~n" ++
                            "Differenza di tempo: ~p ms~n",
                        [
                            self(),
                            Leader#leader.last_event#event.timestamp,
                            Event#event.timestamp,
                            TimeDifference
                        ]
                    ),

                    IsColorShared = utils:check_same_color(
                        Event#event.color, Leader#leader.adj_clusters
                    ),

                    io:format("Nuovo evento: ~p, ~p, ~p, ~n", [
                        Event#event.type, Event#event.color, Event#event.from
                    ]),

                    if
                        % Default case (newer timestamp)
                        TimeDifference >= 0 ->
                            io:format("E' un nuovo evento: PROCEDO NORMALMENTE ~n"),
                            server ! {operation_request, Event, self()},
                            receive
                                {server_ok, Event2} ->
                                    UpdatedLeader = operation:change_color(Leader, Event2),
                                    handle_messages_leader(UpdatedLeader)
                            end;
                        % Consistency (case 1): recover, only if timestamp difference is within 3 seconds
                        IsColorShared andalso TimeDifference >= -3000 ->
                            io:format(
                                "E' un vecchio evento che richiedeva di eseguire un merge: RECOVER ~n"
                            ),
                            OldColor = Leader#leader.color,
                            % Recover recolor operation and then merge
                            io:format("Change color to ~p ~n", [Event#event.color]),
                            server ! {operation_request, Event, self()},
                            receive
                                {server_ok, Event2} ->
                                    UpdatedLeader = operation:change_color(Leader, Event2)
                            end,
                            % Re-apply the old color
                            io:format("Re-apply: ~p ~n", [OldColor]),
                            NewEvent = Event#event{color = OldColor},
                            server ! {operation_request, NewEvent, self()},
                            receive
                                {server_ok, NewEvent2} ->
                                    UpdatedLeader1 = operation:change_color(
                                        UpdatedLeader, NewEvent2
                                    )
                            end,
                            handle_messages_leader(UpdatedLeader1);
                        % Consistency (case 2): drop, only if timestamp difference is within 3 seconds
                        not IsColorShared andalso TimeDifference >= -3000 ->
                            io:format(
                                "E' un vecchio evento che NON richiedeva di eseguire un merge: DROP ~n"
                            );
                        % Other cases
                        true ->
                            io:format("Troppo vecchio ~p", [Event])
                    end,
                    handle_messages_leader(Leader);
                %% The leader receives the ok from the server to proceed with the operation
                {server_ok, Event} ->
                    case Event#event.type of
                        color -> UpdatedLeader = operation:change_color(Leader, Event);
                        merge -> UpdatedLeader = operation:merge(Leader, Event)
                    end,
                    handle_messages_leader(UpdatedLeader);
                %% Updates the color to Color of the triple with FromPid as NeighborID in adj_clusters
                %IMPORTANTE
                {color_adj_update, FromPid, Color, ClusterNodes} ->
                    UpdatedAdjClusters = operation:update_adj_cluster_color(
                        Leader#leader.adj_clusters, ClusterNodes, Color, FromPid
                    ),
                    Event1 = event:new(change_color, Color, FromPid),
                    UpdatedLeader = Leader#leader{
                        adj_clusters = UpdatedAdjClusters, last_event = Event1
                    },
                    server ! {updated_adj_clusters, self(), UpdatedLeader},
                    % Continua il ciclo con lo stato aggiornato
                    handle_messages_leader(UpdatedLeader);
                {response_to_merge, ClusterNodes, AdjListIDMaggiore, FromPid} ->
                    io:format(
                        "-------------------------------------------------- ~p : HO RICEVUTO response_to_merge da ~p~n",
                        [self(), FromPid]
                    ),
                    UpdatedAdjClusters = utils:join_adj_clusters(
                        Leader#leader.adj_clusters, AdjListIDMaggiore
                    ),
                    FilteredAdjClusters = lists:filter(
                        fun({_, _, LeaderID}) ->
                            LeaderID =/= Leader#leader.node#node.leaderID andalso
                                LeaderID =/= FromPid
                        end,
                        UpdatedAdjClusters
                    ),
                    UpdatedNodeList = utils:join_nodes_list(
                        Leader#leader.cluster_nodes, ClusterNodes
                    ),
                    UpdatedLeader = Leader#leader{
                        adj_clusters = FilteredAdjClusters,
                        cluster_nodes = UpdatedNodeList
                    },
                    FromPid ! {became_node, self()},
                    receive
                        {turned_to_node, _FromPid} ->
                            handle_messages_leader(UpdatedLeader)
                        % Timeout di 2 secondi per la risposta turned_to_node
                    after 4000 ->
                        io:format(
                            "~p : Timeout in attesa di turned_to_node da ~p, passo al successivo.~n",
                            [self(), FromPid]
                        ),
                        handle_messages_leader(Leader)
                    end,
                    io:format(
                        "-------------------------------------------------- ~p : HO GESTITO response_to_merge di ~p~n",
                        [self(), FromPid]
                    ),
                    handle_messages_leader(UpdatedLeader);
                {merge_request, LeaderID, Event} ->
                    if
                        LeaderID == self() ->
                            io:format(
                                "~p -> Richiesta di merge ricevuta da se stesso. Merge rifiutato.~n",
                                [self()]
                            ),
                            LeaderID ! {merge_rejected, self()},
                            handle_messages_leader(Leader);
                        true ->
                            EventTimestampMs = convert_time_to_ms(Event#event.timestamp),
                            LastEventTimestampMs = convert_time_to_ms(
                                Leader#leader.last_event#event.timestamp
                            ),
                            if
                                EventTimestampMs < LastEventTimestampMs andalso
                                    Event#event.color =/= Leader#leader.color ->
                                    io:format(
                                        "~p -> Richiesta di merge rifiutata per timestamp obsoleto. Merge rifiutato.~n",
                                        [self()]
                                    ),
                                    LeaderID ! {merge_rejected, self()},
                                    handle_messages_leader(Leader);
                                true ->
                                    if
                                        Event#event.color =/= Leader#leader.color ->
                                            io:format(
                                                "~p -> Richiesta di merge ricevuta da ID ~p.~n", [
                                                    self(), LeaderID
                                                ]
                                            ),
                                            io:format(
                                                "Il colore dell'evento non coincide con il colore attuale del leader. Cambio colore rilevato.~n"
                                            );
                                        true ->
                                            io:format(
                                                "~p -> Richiesta di merge ricevuta da ID ~p.~n", [
                                                    self(), LeaderID
                                                ]
                                            )
                                    end,

                                    EndTime = erlang:monotonic_time(millisecond) + 2000,
                                    {ok, CollectedMessages} = collect_change_color_requests(
                                        EndTime, []
                                    ),

                                    OldEvents = [
                                        NewEvent
                                     || NewEvent <- CollectedMessages,
                                        convert_time_to_ms(NewEvent#event.timestamp) <
                                            EventTimestampMs,
                                        convert_time_to_ms(NewEvent#event.timestamp) >=
                                            EventTimestampMs - 2000
                                    ],
                                    NewEvents = [
                                        NewEvent
                                     || NewEvent <- CollectedMessages,
                                        convert_time_to_ms(NewEvent#event.timestamp) >
                                            EventTimestampMs
                                    ],

                                    if
                                        OldEvents =/= [] ->
                                            io:format(
                                                "Ricevuti eventi di cambio colore con timestamp inferiore a quello del merge. Annullamento merge.~n"
                                            ),
                                            LeaderID ! {merge_rejected, self()},
                                            lists:foreach(
                                                fun(Event_change_color) ->
                                                    self() !
                                                        {change_color_request, Event_change_color}
                                                end,
                                                OldEvents
                                            ),
                                            handle_messages_leader(Leader);
                                        true ->
                                            io:format(
                                                "Nessun evento di cambio colore da gestire. Procedo con il merge.~n"
                                            )
                                    end,

                                    LeaderID !
                                        {response_to_merge, Leader#leader.cluster_nodes,
                                            Leader#leader.adj_clusters, self()},

                                    receive
                                        {became_node, LeaderID2} ->
                                            lists:foreach(
                                                fun(NodePid) ->
                                                    io:format(
                                                        "~p : Invio leader_update a ~p con nuovo leader ~p.~n",
                                                        [self(), NodePid, LeaderID2]
                                                    ),
                                                    NodePid ! {leader_update, LeaderID2}
                                                end,
                                                Leader#leader.cluster_nodes
                                            ),
                                            Node = Leader#leader.node,
                                            UpdatedNode = Node#node{leaderID = LeaderID},
                                            server !
                                                {remove_myself_from_leaders, self()},
                                            LeaderID ! {turned_to_node, self()},
                                            io:format("~p : Invio turned_to_node a ~p~n", [
                                                self(), LeaderID
                                            ]),

                                            if
                                                Event#event.color =/= Leader#leader.color ->
                                                    NewEvent = event:new(
                                                        change_color, Leader#leader.color, self()
                                                    ),
                                                    io:format(
                                                        "~p : Invio un change_color_request con il nuovo colore: ~p e timestamp: ~p.~n",
                                                        [
                                                            self(),
                                                            NewEvent#event.color,
                                                            NewEvent#event.timestamp
                                                        ]
                                                    ),
                                                    self() ! {change_color_request, NewEvent};
                                                true ->
                                                    ok
                                            end,

                                            lists:foreach(
                                                fun(NewEvent) ->
                                                    self() ! {change_color_request, NewEvent}
                                                end,
                                                NewEvents
                                            ),
                                            node_loop(UpdatedNode)
                                    after 4000 ->
                                        io:format(
                                            "~p : Timeout nell'attesa di {became_node, LeaderID}. Continua come leader.~n",
                                            [self()]
                                        ),
                                        handle_messages_leader(Leader)
                                    end
                            end
                    end;
                {update_cluster_nodes, ClusterNodes, NewLeaderID, NewColor} ->
                    Node = Leader#leader.node,
                    Neighbors = Node#node.neighbors,

                    UpdatedNeighbors = lists:map(
                        fun({NeighborPid, _NeighborColor, _NeighborLeaderID} = Neighbor) ->
                            case lists:member(NeighborPid, ClusterNodes) of
                                true ->
                                    % io:format("Updating neighbor ~p with new leader ~p and color ~p.~n", [
                                    %     NeighborPid, NewLeaderID, NewColor
                                    % ]),
                                    {NeighborPid, NewColor, NewLeaderID};
                                false ->
                                    Neighbor
                            end
                        end,
                        Neighbors
                    ),

                    UpdatedNode = Node#node{neighbors = UpdatedNeighbors},
                    UpdatedLeader = Leader#leader{node = UpdatedNode},

                    handle_messages_leader(UpdatedLeader);
                %% Unhandled messages
                _Other ->
                    % io:format(
                    %     "!!!!!!!!!!!! -> LEADER (~p, ~p) con PID ~p received an unhandled message: ~p.~n", [
                    %         Leader#leader.node#node.x, Leader#leader.node#node.y, self(), _Other
                    %     ]
                    % ),
                    handle_messages_leader(Leader)
            end
    end.

% Funzione principale del nodo
node_loop(Node) ->
    % Inizializza il ciclo di elaborazione dei messaggi
    handle_messages_node(Node).

% Funzione ricorsiva per gestire tutti i messaggi in coda
handle_messages_node(Node) ->
    % Salva i dati del nodo
    utils:save_data(Node),

    % Ottiene la lunghezza della coda dei messaggi
    QueueLength = erlang:process_info(self(), message_queue_len),

    % Stampa la lunghezza della coda solo se ci sono messaggi
    %case QueueLength of
    %    {message_queue_len, Len} when Len > 0 ->
    %        io:format("~p: Lunghezza coda messaggi: ~p~n", [self(),Len]);
    %    _ ->
    %        ok
    %end,

    % Se la coda dei messaggi è vuota, termina la ricorsione
    case QueueLength of
        {message_queue_len, 0} ->
            %% io:format("Tutti i messaggi sono stati elaborati. Nessun messaggio rimanente in coda.~n"),

            % Riprende il ciclo principale del nodo
            node_loop(Node);
        _ ->
            receive
                {change_color_request, Event} ->
                    Node#node.leaderID !
                        {change_color_request, Event},
                    handle_messages_node(Node);
                {leader_update, NewLeader} ->
                    UpdatedNode = Node#node{leaderID = NewLeader},
                    handle_messages_node(UpdatedNode);
                {get_leader_info, FromPid} ->
                    Node#node.leaderID ! {get_leader_info, FromPid},
                    handle_messages_node(Node);
                {merge_request, FromPid, Event} ->
                    Node#node.leaderID ! {merge_request, FromPid, Event};
                {new_leader_elected, Color, ClusterNodes, AdjacentClusters} ->
                    %% Promuove il nodo attuale a leader
                    UpdatedLeader = operation:promote_to_leader(
                        Node,
                        Color,
                        ClusterNodes,
                        AdjacentClusters
                    ),

                    % Passa il controllo al ciclo del leader
                    leader_loop(UpdatedLeader);
                _Other ->
                    Node#node.leaderID ! _Other,
                    handle_messages_node(Node)
            end
    end.

collect_change_color_requests(EndTime, Messages) ->
    Now = erlang:monotonic_time(millisecond),
    RemainingTime = EndTime - Now,
    if
        RemainingTime =< 0 ->
            {ok, Messages};
        true ->
            receive
                {change_color_request, NewEvent} ->
                    % io:format("Ho ricevuto un messaggio! ~n"),
                    collect_change_color_requests(EndTime, [NewEvent | Messages]);
                _Other ->
                    % io:format("Ho ricevuto un messaggio! ~n"),
                    collect_change_color_requests(EndTime, Messages)
            after RemainingTime ->
                {ok, Messages}
            end
    end.

convert_time_to_ms({Hour, Minute, Second}) ->
    (Hour * 3600 + Minute * 60 + Second) * 1000.

-module(node).

-export([
    new_node/8,
    new_leader/5,
    create_node/2,
    leader_loop/1,
    node_loop/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

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

%% Creates a leader node, assigns its own PID as the leaderID, and initializes neighbors.
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    % Step 1: Create a base node with an initial PID and empty neighbors
    Node = new_node(X, Y, ServerPid, [], undefined, undefined, undefined, []),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{
        node = Node,
        color = Color,
        serverID = ServerPid,
        last_event = event:new(undefined, undefined, undefined),
        adjClusters = [],
        nodes_in_cluster = []
    },

    % Step 3: Start the node process and update leaderID and pid fields
    UpdatedLeader = create_node(Leader, StartSystemPid),
    UpdatedLeader.

%% Spawns a process for a node, initializing it with its own leaderID and empty neighbors.
create_node(Leader, StartSystemPid) ->
    % Spawn the process for the node loop
    Pid = spawn(fun() ->
        setup:setup_loop(Leader, StartSystemPid, false)
    end),

    %% Register the pid to the alias node_X_Y
    register(
        list_to_atom(
            lists:flatten(
                io_lib:format("node~p_~p", [Leader#leader.node#node.x, Leader#leader.node#node.y])
            )
        ),
        Pid
    ),

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},

    % io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
    %     UpdatedNode#node.x, UpdatedNode#node.y, Leader#leader.color, Pid
    % ]),
    UpdatedLeader.

%% Leader loop to receive messages and update state.
leader_loop(Leader) ->
    % io:format("Sono il LEADER (~p, ~p) con PID ~p e sono pronto per ricevere nuovi messaggi!!~n", [
    %     Leader#leader.node#node.x, Leader#leader.node#node.y, self()
    % ]),

    utils:save_data(Leader),

    receive
        {get_leader_info, FromPid} ->
            % io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
            %     self(), FromPid
            % ]),
            FromPid ! {leader_info, Leader#leader.node#node.leaderID, Leader#leader.color},
            leader_loop(Leader);
        {new_leader_elected, NewLeaderPid} ->
            % Update the leader's node to use the new leader PID
            UpdatedNode = Leader#leader.node#node{leaderID = NewLeaderPid},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            leader_loop(UpdatedLeader);
        {remove_adjacent_cluster, DeadLeaderPid} ->
            % Remove the dead cluster from the adjacency list
            NewAdjClusters = operation:remove_cluster_from_adjacent(
                DeadLeaderPid, Leader#leader.adjClusters
            ),
            UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
            leader_loop(UpdatedLeader);
        {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo} ->
            % Update the adjacency list with the new leader info
            NewAdjClusters = operation:update_adjacent_cluster_info(
                NewLeaderPid, UpdatedClusterInfo, Leader#leader.adjClusters
            ),
            UpdatedLeader = Leader#leader{adjClusters = NewAdjClusters},
            leader_loop(UpdatedLeader);
        {aggiorna_leader, NewLeader} ->
            leader_loop(NewLeader);
        {save_to_db, _ServerPid} ->
            % Procedura per salvare le informazioni su DB locale
            utils:save_data(Leader),
            % ServerPid ! {ack_save_to_db, self()},

            % Crea una lista dei nodi nel cluster escludendo il PID del leader
            FilteredNodes = lists:filter(
                fun(NodePid) -> NodePid =/= Leader#leader.node#node.pid end,
                Leader#leader.nodes_in_cluster
            ),

            % Trasforma ttutti i nodi del cluster (tranne leader in nodi normali)
            lists:foreach(
                fun(NodePid) ->
                    NodePid ! {trasform_to_normal_node}
                end,
                FilteredNodes
            ),

            % Continua il loop
            leader_loop(Leader);
        {trasform_to_normal_node} ->
            % Salva solo i dati del nodo in un file JSON locale
            Node = Leader#leader.node,
            utils:save_data(Node),
            node_loop(Node);
        %% Updates the leaderID
        {leader_update, NewLeader} ->
            Node = Leader#leader.node,

            % propagate update to children
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                Node#node.children
            ),

            UpdatedNode = Node#node{leaderID = NewLeader},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            leader_loop(UpdatedLeader);
        %% Leader receives direcly a color change request
        {change_color_request , Event} ->

            GreaterEvent = event:greater(Leader#leader.last_event, Event),
            TimeDifference = abs(
                convert_time_to_ms(Leader#leader.last_event#event.timestamp) -
                convert_time_to_ms(Event#event.timestamp)
            ),


            io:format(
                "~n~n~p : Gestione della richiesta 'change_color_request'.~n" ++
                "Ultimo evento: ~p~n" ++
                "Nuovo evento: ~p~n" ++
                "Risultato confronto - LAST > NEW_EVENT: ~p, NEW_EVENT > LAST: ~p~n" ++
                "Differenza di tempo: ~p ms~n",
                [self(), Leader#leader.last_event, Event, GreaterEvent, not GreaterEvent, TimeDifference]
            ),

            IsColorShared = utils:check_same_color(Event#event.color, Leader#leader.adjClusters),
            
            if
                % Default case (newer timestamp)
                GreaterEvent ->
                    io:format("E' un nuovo evento: PROCEDO NORMALMENTE ~n"),
                    Leader#leader.serverID ! {operation_request, Event, self()},
                    receive 
                        {server_ok, Event} ->
                            UpdatedLeader = operation:change_color(Leader, Event),
                            leader_loop(UpdatedLeader)                            
                    end;
                % Consistency (case 1): recover, only if timestamp difference is within 2 seconds
                not GreaterEvent andalso IsColorShared andalso TimeDifference =< 1000 ->
                    io:format("E' un vecchio evento che richiedeva di eseguire un merge: RECOVER ~n"),
                    OldColor = Leader#leader.color,
                    % Recover recolor operation and then merge
                    io:format("Change color to ~p ~n", [Event#event.color]),
                    Leader#leader.serverID ! {operation_request, Event, self()},
                    receive 
                        {server_ok, Event} ->
                            UpdatedLeader = operation:change_color(Leader, Event)                              
                    end,
                    % Re-apply the old color
                    io:format("Re-apply: ~p ~n", [OldColor]),
                    NewEvent = Event#event{color = OldColor},
                    UpdatedLeader#leader.serverID ! {operation_request, NewEvent, self()},
                    receive 
                        {server_ok, NewEvent} ->
                            UpdatedLeader1 = operation:change_color(UpdatedLeader, NewEvent)                              
                    end,
                    leader_loop(UpdatedLeader1);
                % Consistency (case 2): drop, only if timestamp difference is within 2 seconds
                not GreaterEvent andalso not IsColorShared andalso TimeDifference =< 1000 ->
                    io:format("E' un vecchio evento che NON richiedeva di eseguire un merge: DROP ~n");
                % Other cases
                true ->
                    io:format("Troppo vecchio ~p", [Event])
            end,
            leader_loop(Leader);


        %% The leader receives the ok from the server to proceed with the operation
        {server_ok, Event} ->
            case Event#event.type of
                color -> UpdatedLeader = operation:change_color(Leader, Event);
                merge -> UpdatedLeader = operation:merge(Leader, Event)
            end,
            leader_loop(UpdatedLeader);
        %% Updates the color to Color of the triple with FromPid as NeighborID in adjClusters
        {color_adj_update, FromPid, Color, Nodes_in_Cluster} ->
            % Verifica se il colore ricevuto corrisponde al colore del leader
            if
                Color =:= Leader#leader.color andalso self() < FromPid ->
                    Event = event:new(change_color, Color, self()),
                    UpdatedLeader = operation:change_color(Leader, Event);
                true ->
                    % Altrimenti, aggiorna AdjClusters come in precedenza
                    UpdatedAdjClusters = operation:update_adj_cluster_color(
                        Leader#leader.adjClusters, Nodes_in_Cluster, Color, FromPid
                    ),
                    Event1 =  event:new(change_color, Color, FromPid),
                    UpdatedLeader = Leader#leader{adjClusters = UpdatedAdjClusters, last_event = Event1},
                    UpdatedLeader#leader.serverID ! {updated_AdjCLusters, self(), UpdatedLeader}
            end,

            % Continua il ciclo con lo stato aggiornato
            leader_loop(UpdatedLeader);


        
        {merge_request, LeaderID, Event} ->

            % Verifica se il colore dell'evento è diverso da quello del leader, indicando un change_color precedente
            if 
                Event#event.color =/= Leader#leader.color ->
                    io:format("~p -> Richiesta di merge ricevuta da ID ~p.~n", [self(), LeaderID]),
                    io:format("~p -> Richiesta di merge: ~p.~n",  [self(), Event]),
                    io:format("Il colore dell'evento non coincide con il colore attuale del leader. Cambio colore rilevato.~n");
                true ->
                    io:format("~p -> Richiesta di merge ricevuta da ID ~p.~n", [self(), LeaderID]),
                    io:format("~p -> Richiesta di merge: ~p.~n",  [self(), Event])
            end,

            % Attende 2 secondi per raccogliere eventuali messaggi di cambio colore
            EndTime = erlang:monotonic_time(millisecond) + 2000,
            {ok, CollectedMessages} = collect_change_color_requests(EndTime, []),

            io:format("Ricevuti eventi : ~p.~n", [CollectedMessages]),

            % Converti il timestamp dell'evento corrente in millisecondi
            EventTimestampMs = convert_time_to_ms(Event#event.timestamp),

            % Separare i messaggi raccolti in base al timestamp in millisecondi
            OldEvents = [NewEvent || NewEvent <- CollectedMessages,
                            convert_time_to_ms(NewEvent#event.timestamp) < EventTimestampMs,
                            convert_time_to_ms(NewEvent#event.timestamp) >= EventTimestampMs - 2000],
            NewEvents = [NewEvent || NewEvent <- CollectedMessages,
                            convert_time_to_ms(NewEvent#event.timestamp) > EventTimestampMs],

            io:format("Ricevuti eventi di cambio colore con timestamp inferiore a quello del merge: ~p.~n", [OldEvents]),
            io:format("Ricevuti eventi di cambio colore con timestamp superiore a quello del merge: ~p.~n", [NewEvents]),

            % Gestione degli eventi di cambio colore precedenti (OldEvents)
            if
                OldEvents =/= [] ->
                    io:format("Ricevuti eventi di cambio colore con timestamp inferiore a quello del merge. Annullamento merge.~n"),
                    LeaderID ! {merge_rejected, self()},

                    % Invia a se stesso il messaggio di change_color_request per ciascun evento in OldEvents
                    lists:foreach(fun(Event_change_color) ->
                        self() ! {change_color_request, Event_change_color}
                    end, OldEvents),

                    leader_loop(Leader);
                true ->
                    io:format("Nessun evento di cambio colore da gestire. Procedo con il merge.~n")
            end,

            % Procedi con il merge

            % Informa il cluster del cambio leader
            lists:foreach(
                fun(NodePid) ->
                    io:format("Invio leader_update a ~p con nuovo leader ~p.~n", [
                        NodePid, LeaderID
                    ]),
                    NodePid ! {leader_update, LeaderID}
                end,
                Leader#leader.nodes_in_cluster
            ),

            % Invia nodes_in_cluster e adjClusters al nuovo leader
            LeaderID !
                {response_to_merge, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters},

            io:format("~p : Invio response_to_merge a ~p con ~p e ~p.~n", [
                self() ,LeaderID, Leader#leader.nodes_in_cluster, Leader#leader.adjClusters
            ]),

            % Aggiorna leaderID del nodo corrente
            Node = Leader#leader.node,
            UpdatedNode = Node#node{leaderID = LeaderID},

            Leader#leader.serverID ! {remove_myself_from_leaders, self()},

            % Invia un change_color_request con il nuovo colore se c'è stato un cambio colore precedente
            if 
                Event#event.color =/= Leader#leader.color ->
                    % Crea un nuovo evento con il timestamp corrente e il colore aggiornato
                    NewEvent = Event#event{timestamp = erlang:time()},
                    
                    io:format("Invio un change_color_request con il nuovo colore: ~p e timestamp: ~p.~n", 
                            [NewEvent#event.color, NewEvent#event.timestamp]),

                    % Invia a se stesso il messaggio di change_color_request con il nuovo evento
                    self() ! {change_color_request, NewEvent};
                true -> ok
            end,


            % Inoltra gli eventi con timestamp superiore al leader
            lists:foreach(
                fun(NewEvent) ->
                    self() ! {change_color_request, NewEvent}
                end,
                NewEvents
            ),

            

            % Trasforma in nodo normale e avvia node_loop
            node_loop(UpdatedNode);

        {update_nodes_in_cluster, NodesInCluster, NewLeaderID, NewColor} ->
            Node = Leader#leader.node,
            Neighbors = Node#node.neighbors,

            UpdatedNeighbors = lists:map(
                fun({NeighborPid, _NeighborColor, _NeighborLeaderID} = Neighbor) ->
                    case lists:member(NeighborPid, NodesInCluster) of
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

            leader_loop(UpdatedLeader);
        %% Unhandled messages
        _Other ->
            % io:format(
            %     "!!!!!!!!!!!! -> LEADER (~p, ~p) con PID ~p received an unhandled message: ~p.~n", [
            %         Leader#leader.node#node.x, Leader#leader.node#node.y, self(), _Other
            %     ]
            % ),
            leader_loop(Leader)
    end.

node_loop(Node) ->
    % io:format("~p -> Sono il nodo (~p, ~p) con PID ~p e sono associato al Leader ~p~n", [
    %     self(),
    %     Node#node.x,
    %     Node#node.y,
    %     Node#node.pid,
    %     Node#node.leaderID
    % ]),
    utils:save_data(Node),
    receive
        {change_color_request , Event} ->
            Node#node.leaderID !
                {change_color_request , Event},
            node_loop(Node);
        {leader_update, NewLeader} ->
            % propagate update to children
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                Node#node.children
            ),
            % Update the node's leader ID
            UpdatedNode = Node#node{leaderID = NewLeader},
            node_loop(UpdatedNode);
        % TODO: useless. merge is done only if the leader finds a cluster
        % with the same color after color update
        % {merge_request, LeaderID} ->
        %     Node#node.leaderID !
        %         {event:new(color, utils:normalize_color(Color), Node#node.leaderID)},
        %     node_loop(Node);

        % TODO: i think is useless, because nodes becomes normal only after setup
        {get_leader_info, FromPid} ->
            % io:format(
            %     "~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader: \n"
            %     "\n"
            %     "                essendo un nodo normale e non sapendo il colore \n"
            %     "\n"
            %     "                inoltro la richiesta al mio leader.~n",
            %     [
            %         self(), FromPid
            %     ]
            % ),
            Node#node.leaderID ! {get_leader_info, FromPid},
            node_loop(Node);
        {new_leader_elected, ServerID, Color, NodesInCluster, AdjacentClusters} ->
            % io:format("Node ~p is now the new leader of the cluster with color ~p.~n", [
            %     self(), Color
            % ]),

            %% Utilizza la funzione promote_to_leader per creare un nuovo leader
            UpdatedLeader = operation:promote_to_leader(
                % Il nodo attuale da promuovere
                Node,
                Color,
                % Manteniamo lo stesso server ID
                ServerID,
                NodesInCluster,
                AdjacentClusters
            ),

            %% Continua come nuovo leader con lo stato aggiornato
            leader_loop(UpdatedLeader);
        _Other ->
            % io:format(
            %     "!!!!!!!!!!!! -> NODE (~p, ~p) con PID ~p received an unhandled message: ~p.~n", [
            %         Node#node.x, Node#node.y, self(), _Other
            %     ]
            % ),
            node_loop(Node)
    end.



collect_change_color_requests(EndTime, Messages) ->
    Now = erlang:monotonic_time(millisecond),
    RemainingTime = EndTime - Now,
    if RemainingTime =< 0 ->
        {ok, Messages};
    true ->
        receive
            {change_color_request, NewEvent} ->
                io:format("Ho ricevuto un messaggio! ~n"),
                collect_change_color_requests(EndTime, [NewEvent | Messages]);
            _Other ->
                io:format("Ho ricevuto un messaggio! ~n"),
                collect_change_color_requests(EndTime, Messages)
        after RemainingTime ->
            {ok, Messages}
        end
    end.


convert_time_to_ms({Hour, Minute, Second}) ->
    (Hour * 3600 + Minute * 60 + Second) * 1000.

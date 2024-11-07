-module(node).

-export([
    new_leader/5,
    leader_loop/1
]).

-include("node.hrl").
-include("event.hrl").

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
new_leader(X, Y, Color, ServerPid, StartSystemPid) ->
    % Step 1: Create a base node with an initial PID and empty neighbors
    Node = new_node(undefined, X, Y, ServerPid, []),

    % Step 2: Create the leader record with the initial node
    Leader = #leader{
        node = Node,
        color = Color,
        serverID = ServerPid,
        last_event = event:new(undefined, undefined, undefined),
        adj_clusters = [],
        cluster_nodes = []
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
    utils:reference(Pid, Leader#leader.node),

    % Update leaderID and pid in the node
    UpdatedNode = Leader#leader.node#node{leaderID = Pid, pid = Pid},
    UpdatedLeader = Leader#leader{node = UpdatedNode},

    io:format("Node (~p, ~p) created with color: ~p, PID: ~p~n", [
        UpdatedNode#node.x, UpdatedNode#node.y, Leader#leader.color, Pid
    ]),
    UpdatedLeader.

%% Leader loop to receive messages and update state.
leader_loop(Leader) ->
    io:format("Sono il LEADER (~p, ~p) con PID ~p e sono pronto per ricevere nuovi messaggi!!~n", [
        Leader#leader.node#node.x, Leader#leader.node#node.y, self()
    ]),

    utils:save_data(Leader),

    receive
        {get_leader_info, FromPid} ->
            io:format("~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader.~n", [
                self(), FromPid
            ]),
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
                DeadLeaderPid, Leader#leader.adj_clusters
            ),
            UpdatedLeader = Leader#leader{adj_clusters = NewAdjClusters},
            leader_loop(UpdatedLeader);
        {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo} ->
            % Update the adjacency list with the new leader info
            NewAdjClusters = operation:update_adjacent_cluster_info(
                NewLeaderPid, UpdatedClusterInfo, Leader#leader.adj_clusters
            ),
            UpdatedLeader = Leader#leader{adj_clusters = NewAdjClusters},
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
                Leader#leader.cluster_nodes
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
            % propagate update to other cluster nodes
            ClusterNodes = lists:delete(self(), Leader#leader.cluster_nodes),
            lists:foreach(
                fun(child) ->
                    child ! {leader_update, NewLeader}
                end,
                ClusterNodes
            ),
            UpdatedNode = Leader#leader.node#node{leaderID = NewLeader},
            UpdatedLeader = Leader#leader{node = UpdatedNode},
            leader_loop(UpdatedLeader);
        %% Leader receives direcly a color change request
        {change_color_request, Color} ->
            self() !
                {change_color_request, self(),
                    event:new(color, utils:normalize_color(Color), self())},
            leader_loop(Leader);
        %% Request to change color from a node or himself
        {change_color_request, _Pid, Event} ->
            GreaterEvent = event:greater(Event, Leader#leader.last_event),

            io:format(
                "~p : Gestione della richiesta 'change_color_request'.~n" ++
                    "Ultimo evento: ~p~n" ++
                    "Nuovo evento: ~p~n" ++
                    "Risultato confronto - NEW_EVENT > LAST: ~p, LAST > NEW_EVENT: ~p~n",
                [self(), Leader#leader.last_event, Event, GreaterEvent, not GreaterEvent]
            ),

            IsColorShared = utils:check_same_color(Event#event.color, Leader#leader.adj_clusters),

            if
                % Default case (newer timestamp)
                GreaterEvent ->
                    io:format("E' un nuovo evento: PROCEDO NORMALMENTE ~n"),
                    Leader#leader.serverID ! {operation_request, Event};
                % Consistency (case 1): recover
                not GreaterEvent andalso IsColorShared ->
                    io:format(
                        "E' un vecchio evento che richiedeva di eseguire un merge: RECOVER ~n"
                    ),
                    OldColor = Leader#leader.color,
                    % Recover recolor operation and then merge
                    Leader#leader.serverID ! {operation_request, Event},
                    % Re-apply the old color
                    Leader#leader.serverID ! {operation_request, Event#event{color = OldColor}};
                % Consistency (case 2): drop
                not GreaterEvent andalso not IsColorShared ->
                    io:format(
                        "E' un vecchio evento che NON richiedeva di eseguire un merge: DROP ~n"
                    ),
                    io:format("Richiesta di cambio colore rifiutata: timestamp troppo vecchio.~n");
                % Consistency (case 3): managed by central server

                % Other cases
                true ->
                    io:format("Situazione non prevista: evento ~p", [Event])
            end,
            leader_loop(Leader);
        %% The leader receives the ok from the server to proceed with the operation
        {server_ok, Event} ->
            case Event#event.type of
                color -> UpdatedLeader = operation:change_color(Leader, Event);
                merge -> UpdatedLeader = operation:merge(Leader, Event)
            end,
            leader_loop(UpdatedLeader);
        %% Updates the color to Color of the triple with FromPid as NeighborID in adj_clusters
        {color_adj_update, FromPid, Color, cluster_nodes} ->
            io:format("Nodo (~p, ~p) ha ricevuto color_adj_update da ~p con nuovo colore ~p.~n", [
                Leader#leader.node#node.x, Leader#leader.node#node.y, FromPid, Color
            ]),

            UpdatedAdjClusters = operation:update_adj_cluster_color(
                Leader#leader.adj_clusters, cluster_nodes, Color, FromPid
            ),

            UpdatedLeader = Leader#leader{adj_clusters = UpdatedAdjClusters},
            UpdatedLeader#leader.serverID ! {updated_AdjCLusters, self(), UpdatedLeader},
            %% Continua il ciclo con lo stato aggiornato
            leader_loop(UpdatedLeader);
        %% TODO: importare quello che manga nella funzione operation:merge, poi si puo rimuovere
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
                Leader#leader.cluster_nodes
            ),

            % Send current cluster_nodes and adj_clusters to the new leader
            LeaderID !
                {response_to_merge, Leader#leader.cluster_nodes, Leader#leader.adj_clusters},

            io:format("Sending response_to_merge to ~p con ~p e ~p.~n", [
                LeaderID, Leader#leader.cluster_nodes, Leader#leader.adj_clusters
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
            %    Leader#leader.adj_clusters
            % ),

            % Transform into a regular node and start the node loop
            node_loop(UpdatedNode);
        %% Unhandled messages
        _Other ->
            io:format(
                "!!!!!!!!!!!! -> LEADER (~p, ~p) con PID ~p received an unhandled message: ~p.~n", [
                    Leader#leader.node#node.x, Leader#leader.node#node.y, self(), _Other
                ]
            ),
            leader_loop(Leader)
    end.

node_loop(Node) ->
    io:format("~p -> Sono il nodo (~p, ~p) con PID ~p e sono associato al Leader ~p~n", [
        self(),
        Node#node.x,
        Node#node.y,
        Node#node.pid,
        Node#node.leaderID
    ]),
    utils:save_data(Node),
    receive
        {change_color_request, Color} ->
            Node#node.leaderID !
                {change_color_request, self(),
                    event:new(color, utils:normalize_color(Color), Node#node.leaderID)},
            node_loop(Node);
        % Update the node's leader ID
        {leader_update, NewLeader} ->
            UpdatedNode = Node#node{leaderID = NewLeader},
            node_loop(UpdatedNode);
        % TODO: i think is useless, because nodes becomes normal only after setup
        {get_leader_info, FromPid} ->
            io:format(
                "~p -> Ho ricevuto una richiesta da ~p di fornirgli il mio leader: \n"
                "\n"
                "                essendo un nodo normale e non sapendo il colore \n"
                "\n"
                "                inoltro la richiesta al mio leader.~n",
                [
                    self(), FromPid
                ]
            ),
            Node#node.leaderID ! {get_leader_info, FromPid},
            node_loop(Node);
        {new_leader_elected, ServerID, Color, ClusterNodes, AdjacentClusters} ->
            io:format("Node ~p is now the new leader of the cluster with color ~p.~n", [
                self(), Color
            ]),

            %% Utilizza la funzione promote_to_leader per creare un nuovo leader
            UpdatedLeader = operation:promote_to_leader(
                % Il nodo attuale da promuovere
                Node,
                Color,
                % Manteniamo lo stesso server ID
                ServerID,
                ClusterNodes,
                AdjacentClusters
            ),

            %% Continua come nuovo leader con lo stato aggiornato
            leader_loop(UpdatedLeader);
        _Other ->
            io:format(
                "!!!!!!!!!!!! -> NODE (~p, ~p) con PID ~p received an unhandled message: ~p.~n", [
                    Node#node.x, Node#node.y, self(), _Other
                ]
            ),
            node_loop(Node)
    end.

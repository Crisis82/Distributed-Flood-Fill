-module(operation).

% color change
-export([change_color/2]).
% merge
-export([merge/2]).
% merge utils
-export([
    merge_adjacent_clusters/2,
    update_adj_cluster_color/4,
    update_existing_node/4,
    remove_cluster_from_adjacent/2,
    update_adjacent_cluster_info/3
]).
% recovery utils
-export([promote_to_leader/5]).

-include("node.hrl").
-include("event.hrl").

%% ------------------
%%
%%    COLOR CHANGE
%%
%% ------------------

%% The leader performs a recolor
change_color(Leader, Event) ->
    io:format(
        "Node (~p, ~p) ha ricevuto una richiesta di cambio colore a ~p.~n",
        [
            Leader#leader.node#node.x, Leader#leader.node#node.y, Event#event.color
        ]
    ),

    %% Aggiorna il colore e l'ultima operazione sul cluster
    UpdatedLeader = Leader#leader{color = Event#event.color, last_event = Event},

    %% Invia color_adj_update a ciascun cluster adiacente
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            io:format("Inviando color_adj_update a ~p.~n", [OtherLeaderID]),
            OtherLeaderID !
                {color_adj_update, self(), UpdatedLeader#leader.color,
                    UpdatedLeader#leader.cluster_nodes}
        end,
        UpdatedLeader#leader.adj_clusters
    ),

    %% Controlla la presenza di cluster adiacenti con lo stesso colore
    IsColorShared = utils:check_same_color(Event#event.color, Leader#leader.adj_clusters),
    if
        IsColorShared ->
            io:format("Cluster adiacente con lo stesso colore trovato.~n"),
            %% Notifica il server della necessità di un merge
            Leader#leader.serverID ! {Event#event{type = merge}};
        true ->
            io:format("Nessun cluster adiacente che condivide lo stesso colore.~n")
    end,

    % Comunica al server la fine del color change
    UpdatedLeader#leader.serverID ! {change_color_complete, self(), UpdatedLeader},

    utils:log_operation(Event),
    UpdatedLeader.

%% ------------------
%%
%% COLOR CHANGE UTILS
%%
%% ------------------

%% ------------------
%%
%%      MERGE
%%
%% ------------------

%% The leader performs a merge
merge(Leader, Event) ->
    % Lists cannot be empty because is checked before invoking merge
    SameColorAdjClusters = utils:get_same_color(Event#event.color, Leader#leader.adj_clusters),

    io:format("Gli adjacents clusters sono ~p, quelli con il colore ~p sono: ~p.~n", [
        Leader#leader.adj_clusters, Event#event.color, SameColorAdjClusters
    ]),

    UpdatedLeader = merge_adjacent_clusters(SameColorAdjClusters, Leader),

    % TODO: color update already done in change_color, here we should remove
    % each SameColorAdjCluster from its own neighbor's adj_clusters, because
    % he will be no more a leader
    %% Invia color_adj_update a ciascun cluster adiacente aggiornato
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            io:format("Inviando color_adj_update a ~p.~n", [OtherLeaderID]),
            OtherLeaderID !
                {color_adj_update, self(), UpdatedLeader#leader.color,
                    UpdatedLeader#leader.cluster_nodes}
        end,
        UpdatedLeader#leader.adj_clusters
    ),

    % Comunica al server la fine del merge
    UpdatedLeader#leader.serverID ! {merge_complete, self(), UpdatedLeader},

    % scrivi log
    utils:log_operation(Event),
    UpdatedLeader.

%% ------------------
%%
%%    MERGE UTILS
%%
%% ------------------

merge_adjacent_clusters([], Leader) ->
    % Nessun altro cluster da gestire, restituisce il leader aggiornato
    Leader;
merge_adjacent_clusters(
    [{_NeighborPid, _NeighborColor, AdjLeaderID} | Rest], Leader
) ->
    io:format("Inviando merge_request al leader adiacente con PID ~p.~n", [AdjLeaderID]),
    % scrivi log
    Event = event:new(),
    utils:log_operation(Event),

    AdjLeaderID ! {merge_request, self()},
    receive
        {response_to_merge, cluster_nodes, AdjListIDMaggiore} ->
            % Unisce i cluster adiacenti e rimuove eventuali duplicati
            UpdatedAdjClusters = utils:join_adj_clusters(
                Leader#leader.adj_clusters, AdjListIDMaggiore
            ),

            % Rimuove se stesso e l'altro leader dalla lista dei cluster adiacenti
            FilteredAdjClusters = lists:filter(
                fun({_, _, LeaderID}) ->
                    LeaderID =/= Leader#leader.node#node.leaderID andalso
                        LeaderID =/= AdjLeaderID
                end,
                UpdatedAdjClusters
            ),

            % Unisce le liste dei nodi nel cluster
            UpdatedNodeList = utils:join_nodes_list(
                Leader#leader.cluster_nodes, cluster_nodes
            ),

            % Crea il nuovo leader aggiornato
            UpdatedLeader = Leader#leader{
                adj_clusters = FilteredAdjClusters,
                cluster_nodes = UpdatedNodeList
            },

            io:format("Aggiornamento del leader con il merge completato: ~p~n", [UpdatedLeader]),

            % Continua il merge per i prossimi vicini
            merge_adjacent_clusters(Rest, UpdatedLeader)
        % Timeout di esempio per evitare blocchi
    after 5000 ->
        io:format("Timeout nel ricevere la risposta dal leader adiacente con PID ~p.~n", [
            AdjLeaderID
        ]),
        % Ritorna l'ultimo leader conosciuto
        Leader
    end.

update_adj_cluster_color(AdjClusters, ClusterNodes, NewColor, NewLeaderID) ->
    lists:foldl(
        fun(NodeID, UpdatedAdjClusters) ->
            update_existing_node(UpdatedAdjClusters, NodeID, NewColor, NewLeaderID)
        end,
        AdjClusters,
        ClusterNodes
    ).

update_existing_node([], _NodeID, _NewColor, _NewLeaderID) ->
    % If the adjacency list is empty, return an empty list (no update needed)
    [];
update_existing_node([{NodeID, _OldColor, _OldLeaderID} | Rest], NodeID, NewColor, NewLeaderID) ->
    % Node found, update its color and leader ID
    io:format("Node found: ~p, updating to new color ~p and leader ID ~p~n", [
        NodeID, NewColor, NewLeaderID
    ]),
    [{NodeID, NewColor, NewLeaderID} | Rest];
update_existing_node([Other | Rest], NodeID, NewColor, NewLeaderID) ->
    % Keep the current element and continue searching
    [Other | update_existing_node(Rest, NodeID, NewColor, NewLeaderID)].

remove_cluster_from_adjacent(DeadLeaderPid, AdjacentClusters) ->
    lists:filter(
        fun({Pid, _Color, _LeaderID}) ->
            Pid =/= DeadLeaderPid
        end,
        AdjacentClusters
    ).

update_adjacent_cluster_info(NewLeaderPid, UpdatedClusterInfo, AdjacentClusters) ->
    % Remove old entry for the leader if it exists
    AdjClustersWithoutOld = remove_cluster_from_adjacent(NewLeaderPid, AdjacentClusters),
    % Add updated info for the new leader
    % Normalizza il colore e aggiungi la nuova informazione del leader
    NewColor = utils:normalize_color(maps:get(color, UpdatedClusterInfo)),
    NewLeaderID = maps:get(leader_id, UpdatedClusterInfo, NewLeaderPid),
    NewEntry = {NewLeaderPid, NewColor, NewLeaderID},
    [NewEntry | AdjClustersWithoutOld].

%% ------------------
%%
%%  RECOVERY UTILS
%%
%% ------------------

%% Funzione per promuovere un nodo a leader utilizzando le informazioni ricevute.
promote_to_leader(Node, Color, ServerPid, AdjacentClusters, ClusterNodes) ->
    %% Costruisci il record leader partendo dal nodo esistente e aggiungi le informazioni specifiche del leader.
    Leader = #leader{
        %% Imposta il PID del nodo come leaderID
        node = Node#node{leaderID = Node#node.pid},
        color = Color,
        serverID = ServerPid,
        %% Inizializza l'ultimo evento, se necessario
        last_event = event:new(undefined, undefined, undefined),
        adj_clusters = AdjacentClusters,
        cluster_nodes = ClusterNodes
    },

    %% Log di conferma della promozione del nodo a leader
    io:format(
        "Il nodo (~p, ~p) con PID ~p è stato promosso a leader con colore ~p~n",
        [Node#node.x, Node#node.y, Node#node.pid, Color]
    ),

    %% Restituisci il record leader aggiornato
    Leader.

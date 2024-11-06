-module(operation).

% color change
-export([change_color/2]).
% merge
% -export([merge/2]).
% merge utils
-export([
    merge_adjacent_clusters/3,
    update_adj_cluster_color/4,
    update_existing_node/4,
    remove_cluster_from_adjacent/2,
    update_adjacent_cluster_info/3
]).
% recovery utils
-export([promote_to_leader/5]).

-include("includes/node.hrl").
-include("includes/event.hrl").

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

    Color = Event#event.color,

    

    % Converte il colore in atomo se non lo è già
    ColorAtom = utils:normalize_color(Color),
    
    %% Aggiorna il colore e l'ultima operazione sul cluster
    UpdatedLeader1 = Leader#leader{color = ColorAtom, last_event = Event},

    SameColorAdjClusters = utils:unique_leader_clusters(
        [{NeighborPid, NeighborColor, LeaderID}
         || {NeighborPid, NeighborColor, LeaderID} <- Leader#leader.adjClusters,
            NeighborColor == ColorAtom]
    ),

    io:format("Gli adjacents clusters sono ~p, quelli con il colore ~p sono: ~p.~n", [
        Leader#leader.adjClusters, ColorAtom, SameColorAdjClusters
    ]),


    % Estrai i LeaderID dai cluster con lo stesso colore
    LeaderIDs = [LeaderID || {_, _, LeaderID} <- SameColorAdjClusters],


    UpdatedLeader =
        case SameColorAdjClusters of
            [] ->
                io:format(
                    "Nessun vicino con lo stesso colore. Invio color_adj_update a tutti i vicini.~n"
                ),
                UpdatedLeader1;
            _ ->
                io:format(
                    "Vicini con lo stesso colore trovati. Avvio processo di merge sequenziale.~n"
                ),
                % Avvia il merge sequenziale per ogni cluster con lo stesso colore

                UpdatedLeader2 = merge_adjacent_clusters(SameColorAdjClusters, UpdatedLeader1, LeaderIDs),
                io:format(
                    "Leader dopo tutti i merge: ~p.~n",  [UpdatedLeader2]
                ),
                UpdatedLeader2
        end,

    io:format("~p : Devo inviare la mia nuova configurazione (color_adj_update) a tutti i leader dei cluster vicini: ~p.~n", [
        self(), UpdatedLeader#leader.adjClusters
    ]),

    % Invia color_adj_update a ciascun cluster adiacente aggiornato
    lists:foreach(
        fun({_PID, _NeighborColor, OtherLeaderID}) ->
            io:format("Inviando {color_adj_update, ~p, ~p, ~p} a ~p.~n", [self(), UpdatedLeader#leader.color,
                    UpdatedLeader#leader.nodes_in_cluster, OtherLeaderID]),
            OtherLeaderID !
                {color_adj_update, self(), UpdatedLeader#leader.color,
                    UpdatedLeader#leader.nodes_in_cluster}
        end,
        UpdatedLeader#leader.adjClusters
    ),

    % Comunica al server la fine del color change
    UpdatedLeader#leader.serverID ! {change_color_complete, self(), UpdatedLeader},

    utils:log_operation(Event),

    io:format("FINAL CONFIGURATION for the NEW leader ~p : ~p~n", [self(),UpdatedLeader]),
    UpdatedLeader.

%% ------------------
%%
%% COLOR CHANGE UTILS
%%
%% ------------------



%% ------------------
%%
%%    MERGE UTILS
%%
%% ------------------

merge_adjacent_clusters([], Leader, _LeaderIDs) ->
    % Nessun altro cluster da gestire, restituisce il leader aggiornato
    io:format(
                    "Leader dopo tutti i merge: ~p.~n",  [Leader]
                ),
    Leader;
merge_adjacent_clusters(
    [{_NeighborPid, _NeighborColor, AdjLeaderID} | Rest], Leader, LeaderIDs
) ->
    io:format("Inviando merge_request al leader adiacente con PID ~p.~n", [AdjLeaderID]),
    % scrivi log
    % X = Leader#leader.node#node.x,
    % Y = Leader#leader.node#node.y,
    % Event = event:new(),

    % log_operation(
    %     X,
    %     Y,
    %     Event,
    %     io_lib:format("Inviando merge_request al leader adiacente con PID ~p", [AdjLeaderID])
    % ),
    AdjLeaderID ! {merge_request, self()},
    receive
        {response_to_merge, Nodes_in_Cluster, AdjListIDMaggiore} ->
            io:format("~p : Ho ricevuto response_to_merge da ~p e mi ha inviato i suoi nodi : ~p e il suo ADJ cluster: ~p~n", [
                Leader#leader.node#node.leaderID, AdjLeaderID,Nodes_in_Cluster, AdjListIDMaggiore
            ]),
            % Unisce i cluster adiacenti e rimuove eventuali duplicati
            UpdatedAdjClusters = utils:join_adj_clusters(Leader#leader.adjClusters, AdjListIDMaggiore),

            % Rimuove se stesso e l'altro leader dalla lista dei cluster adiacenti
            FilteredAdjClusters = lists:filter(
                fun({_, _, LeaderID}) ->
                    not lists:member(LeaderID, LeaderIDs) andalso
                    LeaderID =/= Leader#leader.node#node.leaderID andalso
                    LeaderID =/= AdjLeaderID
                end,
                UpdatedAdjClusters
            ),


            % Unisce le liste dei nodi nel cluster
            UpdatedNodeList = utils:join_nodes_list(Leader#leader.nodes_in_cluster, Nodes_in_Cluster),

            % Crea il nuovo leader aggiornato
            UpdatedLeader = Leader#leader{
                adjClusters = FilteredAdjClusters,
                nodes_in_cluster = UpdatedNodeList
            },

            io:format("Aggiornamento del leader con il merge completato: ~p~n", [UpdatedLeader]),

            % Continua il merge per i prossimi vicini
            merge_adjacent_clusters(Rest, UpdatedLeader, LeaderIDs)
        % Timeout di esempio per evitare blocchi
    after 5000 ->
        io:format("Timeout nel ricevere la risposta dal leader adiacente con PID ~p.~n", [
            AdjLeaderID
        ]),
        % Ritorna l'ultimo leader conosciuto
        Leader
    end.

update_adj_cluster_color(AdjClusters, NodesInCluster, NewColor, NewLeaderID) ->
    lists:foldl(
        fun(NodeID, UpdatedAdjClusters) ->
            update_existing_node(UpdatedAdjClusters, NodeID, NewColor, NewLeaderID)
        end,
        AdjClusters,
        NodesInCluster
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
promote_to_leader(Node, Color, ServerPid, NodesInCluster, AdjacentClusters) ->
    %% Costruisci il record leader partendo dal nodo esistente e aggiungi le informazioni specifiche del leader.
    Leader = #leader{
        %% Imposta il PID del nodo come leaderID
        node = Node#node{leaderID = Node#node.pid},
        color = Color,
        serverID = ServerPid,
        %% Inizializza l'ultimo evento, se necessario
        last_event = event:new(),
        adjClusters = AdjacentClusters,
        nodes_in_cluster = NodesInCluster
    },

    %% Log di conferma della promozione del nodo a leader
    io:format(
        "Il nodo (~p, ~p) con PID ~p è stato promosso a leader con colore ~p~n",
        [Node#node.x, Node#node.y, Node#node.pid, Color]
    ),

    %% Restituisci il record leader aggiornato
    Leader.

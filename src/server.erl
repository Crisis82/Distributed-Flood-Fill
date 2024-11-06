-module(server).
-export([
    start_server/1
]).
-include("node.hrl").
-include("event.hrl").

%% Avvia il processo del server e registra l'inizio nel log
%% Output:
%% - Restituisce il PID del server appena creato
start_server(StartSystemPid) ->
    log_operation("Server started."),
    %% Avvia il server e passa a server_loop con uno stato vuoto
    ServerPid = spawn(fun() -> server_loop([], [], #{}, StartSystemPid) end),
    register(server, ServerPid),
    io:format("Server started with PID: ~p~n", [ServerPid]),
    ServerPid.

%% Ciclo principale del server che gestisce i messaggi e mantiene lo stato
%% Input:
%% - Nodes: lista dei nodi da configurare
%% - ProcessedNodes: lista dei nodi già configurati
%% - LeadersData: mappa dei leader e relativi dati di configurazione
server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid) ->
    receive
        %% Gestione del messaggio {start_setup, NewNodes} per iniziare la configurazione dei nodi
        {start_setup, NewNodes, StartSystemPid} ->
            log_operation("Received request to start node setup."),
            case NewNodes of
                % Nessun nodo da processare
                [] ->
                    log_operation("No nodes to process"),
                    server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid);
                % Processa il primo nodo e passa al resto
                [#leader{node = Node} = Leader | Rest] ->
                    % Monitora il processo leader e aggiungi il monitor_ref a LeadersData
                    MonitorRef = erlang:monitor(process, Node#node.pid),
                    log_operation(
                        io_lib:format("Monitoring leader ~p with MonitorRef ~p", [
                            Node#node.pid, MonitorRef
                        ])
                    ),

                    % Aggiungi il leader e il suo monitor_ref a LeadersData
                    UpdatedLeadersData = maps:put(
                        Node#node.pid, #{leader => Leader, monitor_ref => MonitorRef}, LeadersData
                    ),

                    % Inizia la configurazione del leader
                    Node#node.pid ! {setup_server_request, self()},

                    % Continua il loop del server con il leader monitorato e il LeadersData aggiornato
                    server_loop(
                        Rest, ProcessedNodes ++ [Leader], UpdatedLeadersData, StartSystemPid
                    )
            end;
        %% Gestione del messaggio {FromNode, node_setup_complete, CombinedPIDs, Color}
        %% ricevuto dai nodi al completamento del setup
        {FromNode, node_setup_complete, CombinedPIDs, Color} ->
            log_operation(
                io_lib:format("Node ~p has completed setup with nodes: ~p", [FromNode, CombinedPIDs])
            ),
            % Aggiorna la mappa LeadersData con il nodo configurato
            LeadersData1 = maps:put(
                FromNode, #{color => Color, nodes => CombinedPIDs}, LeadersData
            ),
            case Nodes of
                % Tutti i nodi sono stati configurati
                [] ->
                    log_operation("Setup completed for all nodes."),
                    io:format("Setup Phase 1 completed.~n~n LeadersData: ~p~n", [LeadersData1]),
                    % Avvia la Fase 2 per tutti i leader
                    start_phase2_for_all_leaders(
                        Nodes, ProcessedNodes, LeadersData1, [], StartSystemPid
                    );
                % Passa al prossimo nodo da configurare
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData1, StartSystemPid)
            end;
        %% Gestione del messaggio {FromNode, node_already_visited}
        %% che indica che un nodo è già stato configurato
        {FromNode, node_already_visited} ->
            log_operation(
                io_lib:format("Node ~p has already completed setup previously.", [FromNode])
            ),
            case Nodes of
                % Se tutti i nodi sono stati configurati
                [] ->
                    log_operation("Setup completed for all nodes."),
                    io:format("Setup Phase 1 completed. LeadersData: ~p~n", [LeadersData]),
                    start_phase2_for_all_leaders(
                        Nodes, ProcessedNodes, LeadersData, [], StartSystemPid
                    );
                % Passa al prossimo nodo da configurare
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData, StartSystemPid)
            end;
        %% Gestione dei messaggi non previsti

        {change_color_complete, LeaderPid, Leader} ->
            io:format("SERVER: ho ricevuto la nuova configurazione di ~p: ~p~n~n", [
                Leader#leader.node#node.leaderID, Leader
            ]),

            Color = Leader#leader.color,
            AdjC = Leader#leader.adj_clusters,
            ClusterNodes = Leader#leader.cluster_nodes,

            ValidClusterNodes =
                case is_list(ClusterNodes) of
                    true -> ClusterNodes;
                    false -> []
                end,

            io:format(
                "Leader PID ~p ha come nuovo colore ~p, come nuovi AdjCluster ~p e come nodi nel cluster ~p~n",
                [
                    LeaderPid, Color, AdjC, ValidClusterNodes
                ]
            ),

            % Log dell'operazione di cambio colore completata
            io:format("Leader PID ~p ha completato il cambio colore in ~p~n", [LeaderPid, Color]),

            % Inizializza LeaderInfo come mappa con i campi di base, se non esiste già
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{
                color => undefined, adjacent_clusters => [], nodes => []
            }),

            % Aggiorna LeaderInfo con i nuovi dati
            LeaderInfo1 = maps:put(color, Color, LeaderInfo),
            LeaderInfo2 = maps:put(adjacent_clusters, AdjC, LeaderInfo1),
            UpdatedLeaderInfo = maps:put(nodes, ValidClusterNodes, LeaderInfo2),

            % Aggiorna LeadersData con la nuova configurazione del leader
            UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

            io:format("~n~nNuova configurazione ~p~n", [UpdatedLeadersData]),

            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("leaders_data.json", JsonData),

            % Continua il ciclo con i dati aggiornati
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);
        {remove_myself_from_leaders, LeaderPid} ->
            % Rimuove LeaderPid da LeadersData
            UpdatedLeadersData = maps:remove(LeaderPid, LeadersData),

            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("leaders_data.json", JsonData),

            io:format("SERVER: Rimosso Leader PID ~p da LeadersData. Nuova configurazione: ~p~n", [
                LeaderPid, UpdatedLeadersData
            ]),

            % Continua il ciclo del server con LeadersData aggiornato
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);
        {updated_AdjCLusters, LeaderPid, Leader} ->
            io:format("SERVER: ho ricevuto la nuova configurazione di ~p: ~p~n~n", [
                Leader#leader.node#node.leaderID, Leader
            ]),

            Color = Leader#leader.color,
            AdjC = Leader#leader.adj_clusters,
            ClusterNodes = Leader#leader.cluster_nodes,

            ValidClusterNodes =
                case is_list(ClusterNodes) of
                    true -> ClusterNodes;
                    false -> []
                end,

            % Inizializza LeaderInfo come mappa con i campi di base, se non esiste già
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{
                color => undefined, adjacent_clusters => [], nodes => []
            }),

            % Aggiorna LeaderInfo con i nuovi dati
            LeaderInfo1 = maps:put(color, Color, LeaderInfo),
            LeaderInfo2 = maps:put(adjacent_clusters, AdjC, LeaderInfo1),
            UpdatedLeaderInfo = maps:put(nodes, ValidClusterNodes, LeaderInfo2),

            % Aggiorna LeadersData con la nuova configurazione del leader
            UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("leaders_data.json", JsonData),

            % Continua il ciclo con i dati aggiornati
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);
        {operation_request, Event} ->
            % TODO: for now just responds ok. To implement a operation queue
            Event#event.from ! {server_ok, Event},
            server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid);
        _Other ->
            io:format("!!!!!!!!!!!! -> SERVER Received unhandled message ~p.", [_Other]),
            server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid)
        % In your server_loop after detecting dead leaders
        % 10000 milliseconds
    after 10000 ->
        % Get all monitored PIDs
        LeaderPids = maps:keys(LeadersData),
        io:format("SERVER: Verifico se i Leader sono ancora vivi: ~p~n", [LeaderPids]),

        % Check which ones are not alive
        DeadLeaders = [Pid || Pid <- LeaderPids, not erlang:is_process_alive(Pid)],
        % Handle dead leaders
        UpdatedLeadersData = lists:foldl(
            fun(DeadPid, AccLeadersData) ->
                log_operation(io_lib:format("Detected that leader ~p is not alive.", [DeadPid])),
                % Handle the dead leader according to cluster size
                ClusterInfo = maps:get(DeadPid, AccLeadersData),
                ClusterNodes = maps:get(nodes, ClusterInfo, []),
                Color = maps:get(color, ClusterInfo),
                AdjacentClusters = maps:get(adjacent_clusters, ClusterInfo, []),
                NodesWithoutDeadLeader = lists:delete(DeadPid, ClusterNodes),
                case NodesWithoutDeadLeader of
                    [] ->
                        % Case 1: Single-node cluster
                        % Log the information of the dead leader
                        io:format(
                            "Leader morto: ~p, Colore: ~p, Nodi: ~p, Clusters adiacenti: ~p~n", [
                                DeadPid, Color, ClusterNodes, AdjacentClusters
                            ]
                        ),

                        % Remove the dead leader from LeadersData
                        NewLeadersData = maps:remove(DeadPid, AccLeadersData),
                        % Notify adjacent clusters to remove this cluster
                        notify_adjacent_clusters_to_remove_cluster(AdjacentClusters, DeadPid),
                        NewLeadersData;
                    _ ->
                        % Case 2: Multi-node cluster
                        % Elect a new leader
                        NewLeaderPid = hd(NodesWithoutDeadLeader),

                        % Log the old and new leader information
                        io:format(
                            "Leader morto: ~p, Colore: ~p, Nodi: ~p, Clusters adiacenti: ~p~n", [
                                DeadPid, Color, ClusterNodes, AdjacentClusters
                            ]
                        ),
                        io:format(
                            "Nuovo leader eletto: ~p, Colore: ~p, Nodi: ~p, Clusters adiacenti: ~p~n",
                            [NewLeaderPid, Color, NodesWithoutDeadLeader, AdjacentClusters]
                        ),

                        io:format("SERVER: Invio a ~p {new_leader_elected, ~p, ~p, ~p, ~p}~n", [
                            NewLeaderPid, self(), Color, NodesWithoutDeadLeader, AdjacentClusters
                        ]),

                        % Notify the new leader of its role
                        NewLeaderPid !
                            {new_leader_elected, self(), Color, NodesWithoutDeadLeader,
                                AdjacentClusters},

                        % Update the cluster info with the new leader
                        UpdatedClusterInfo = ClusterInfo#{
                            leader_pid => NewLeaderPid,
                            nodes => NodesWithoutDeadLeader
                        },
                        % Update LeadersData
                        NewLeadersData1 = maps:remove(DeadPid, AccLeadersData),
                        NewLeadersData = maps:put(
                            NewLeaderPid, UpdatedClusterInfo, NewLeadersData1
                        ),

                        % Notify adjacent clusters about the new leader
                        notify_adjacent_clusters_about_new_leader(
                            AdjacentClusters, NewLeaderPid, UpdatedClusterInfo
                        ),
                        % Update nodes in the cluster about the new leader
                        update_cluster_nodes_about_new_leader(NodesWithoutDeadLeader, NewLeaderPid),

                        NewLeadersData
                end
            end,
            LeadersData,
            DeadLeaders
        ),
        % Salva la nuova configurazione in JSON dopo aver aggiornato la struttura dei leader
        JsonData = save_leader_configuration_json(UpdatedLeadersData),
        file:write_file("leaders_data.json", JsonData),
        io:format(
            "Configurazione aggiornata salvata in leaders_data.json dopo la rilevazione del leader morto~n"
        ),

        % Continue the server loop with updated LeadersData
        server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid)
    end.

notify_adjacent_clusters_to_remove_cluster(AdjacentClusters, DeadLeaderPid) ->
    % Estrae i LeaderID dai cluster adiacenti e rimuove i duplicati
    UniqueLeaderIDs = lists:usort([LeaderID || {_, _, LeaderID} <- AdjacentClusters]),

    % Invia il messaggio {remove_adjacent_cluster, DeadLeaderPid} a ciascun LeaderID unico
    lists:foreach(
        fun(LeaderID) ->
            LeaderID ! {remove_adjacent_cluster, DeadLeaderPid}
        end,
        UniqueLeaderIDs
    ).

notify_adjacent_clusters_about_new_leader(AdjacentClusters, NewLeaderPid, UpdatedClusterInfo) ->
    lists:foreach(
        fun({AdjPid, _Color, _LeaderID}) ->
            AdjPid ! {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo}
        end,
        AdjacentClusters
    ).

update_cluster_nodes_about_new_leader(Nodes, NewLeaderPid) ->
    NodesWithoutLeader = lists:delete(NewLeaderPid, Nodes),
    lists:foreach(
        fun(NodePid) ->
            NodePid ! {leader_update, NewLeaderPid}
        end,
        NodesWithoutLeader
    ).

finish_setup(Nodes, ProcessedNodes, LeadersData, StartSystemPid) ->
    io:format("SETUP COMPLETATO PER TUTTI I NODI~n"),
    io:format("Chiedo a tutti i nodi di salvare le loro informazioni su DB locali~n"),

    % Ottieni i PID di tutti i leader e invia loro il messaggio di salvataggio
    LeaderPids = maps:keys(LeadersData),

    io:format("Leader Pids : ~p", [LeaderPids]),

    lists:foreach(
        fun(LeaderPid) ->
            % Invia il messaggio di salvataggio includendo il PID del server per l'ACK
            io:format("Chiedo a ~p di salvare i dati. ~n", [LeaderPid]),
            LeaderPid ! {save_to_db, self()}
        end,
        LeaderPids
    ),
    io:format("LeadersData : ~p", [LeadersData]),

    StartSystemPid ! {finih_setup, LeaderPids},

    server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid).

%% Funzione che salva la configurazione dei leader in formato JSON
%% Input:
%% - LeadersData: mappa che contiene i dati di configurazione di ciascun leader
%% Output:
%% - Una stringa JSON che rappresenta la configurazione di tutti i leader
save_leader_configuration_json(LeadersData) ->
    % Ottiene i PID dei leader e li converte in una lista JSON
    LeaderPids = maps:keys(LeadersData),
    JsonString = lists:map(fun(Pid) -> leader_to_json(LeadersData, Pid) end, LeaderPids),
    % Combina le stringhe JSON dei leader in un array JSON-like
    JsonData = "[" ++ string:join(JsonString, ",") ++ "]",
    % Salva su file
    file:write_file("leaders_data.json", JsonData),
    JsonData.

%% Funzione per convertire i dati di un leader in una stringa JSON
%% Input:
%% - LeadersData: mappa dei dati di tutti i leader
%% - LeaderPid: PID del leader di cui si vuole ottenere la stringa JSON
%% Output:
%% - Una stringa JSON che rappresenta il leader specificato
leader_to_json(LeadersData, LeaderPid) ->
    Cluster = maps:get(LeaderPid, LeadersData),
    AdjacentClustersJson = adjacent_clusters_to_json(maps:get(adjacent_clusters, Cluster)),
    Color = atom_to_string(maps:get(color, Cluster)),
    NodesJson = nodes_to_json(maps:get(nodes, Cluster)),
    % Converte il PID del leader in stringa
    LeaderPidStr = pid_to_string(LeaderPid),

    % Costruisce e restituisce la stringa JSON del leader
    io_lib:format(
        "{\"leader_id\": \"~s\", \"adjacent_clusters\": ~s, \"color\": \"~s\", \"nodes\": ~s}",
        [LeaderPidStr, AdjacentClustersJson, Color, NodesJson]
    ).

%% Funzione per convertire i cluster adiacenti in una lista JSON
%% Input:
%% - AdjacentClusters: lista di PID dei cluster adiacenti
%% Output:
%% - Una stringa JSON che rappresenta i cluster adiacenti
adjacent_clusters_to_json(AdjacentClusters) ->
    % Rimuove duplicati e genera la lista di stringhe JSON per ciascun cluster adiacente
    UniqueClusters = lists:usort(AdjacentClusters),
    ClustersJson = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [pid_to_string(Pid), atom_to_string(Color), pid_to_string(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- UniqueClusters
    ],
    "[" ++ string:join(ClustersJson, ",") ++ "]".

%% Funzione per convertire una lista di nodi in una stringa JSON
%% Input:
%% - Nodes: lista di PIDs dei nodi
%% Output:
%% - Una stringa JSON array con i PIDs dei nodi
nodes_to_json(Nodes) ->
    NodesJson = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    "[" ++ string:join(NodesJson, ",") ++ "]".

%% Funzione per convertire un PID in una stringa
%% Input:
%% - Pid: processo ID Erlang
%% Output:
%% - Una stringa che rappresenta il PID
pid_to_string(Pid) ->
    erlang:pid_to_list(Pid).

%% Funzione per convertire un atomo in una stringa JSON-compatibile
%% Input:
%% - Atom: atomo che si vuole convertire in stringa
%% Output:
%% - La rappresentazione dell’atomo come stringa
atom_to_string(Atom) when is_atom(Atom) -> atom_to_list(Atom);
atom_to_string(Other) -> Other.

%% Funzione per registrare le operazioni del server
%% Input:
%% - Message: stringa con il messaggio da registrare nel log
%% Output:
%% - Nessun output diretto; scrive il messaggio su "server_log.txt" e lo stampa su console
log_operation(Message) ->
    % Apre il file di log "server_log.txt" in modalità append (aggiunta in fondo)
    {ok, File} = file:open("server_log.txt", [append]),
    % Scrive il messaggio di log nel file, seguito da una nuova linea
    io:format(File, "~s~n", [Message]),
    % Chiude il file di log
    file:close(File),
    % Stampa il messaggio di log sulla console per monitoraggio immediato
    io:format("LOG: ~s~n", [Message]).

%% Funzione per avviare la Fase 2 per tutti i leader
%% Input:
%% - LeadersData: mappa contenente i dati di ciascun leader, inclusi PID e nodi nel cluster
%% - ProcessedLeaders: lista dei leader già processati nella Fase 2
%% Output:
%% - Nessun output diretto; aggiorna `LeadersData` con i cluster adiacenti e salva i risultati in JSON
start_phase2_for_all_leaders(Nodes, ProcessedNodes, LeadersData, ProcessedLeaders, StartSystemPid) ->
    % Filtra i leader non ancora processati nella Fase 2
    RemainingLeaders = maps:filter(
        fun(Key, _) -> not lists:member(Key, ProcessedLeaders) end, LeadersData
    ),

    io:format("Leader rimanenti: ~p", [RemainingLeaders]),
    % Seleziona i PID dei leader non processati
    case maps:keys(RemainingLeaders) of
        % Se non ci sono leader rimanenti, Fase 2 completata
        [] ->
            io:format("~n~n ------------------------------------- ~n"),
            io:format("Phase 2 completed. All leaders have been processed.~n"),
            io:format("~n ------------------------------------- ~n~n"),
            io:format("Final Overlay Network Data~n~p~n", [LeadersData]),
            % Converte e salva i dati finali dei leader in formato JSON
            JsonData = save_leader_configuration_json(LeadersData),
            file:write_file("leaders_data.json", JsonData),
            io:format("Dati dei leader salvasti in leaders_data.json ~n"),
            finish_setup(Nodes, ProcessedNodes, LeadersData, StartSystemPid);
        % Se ci sono leader rimanenti, processa il primo PID rimanente
        [LeaderPid | _] ->
            % Ottiene le informazioni del leader corrente dal dizionario LeadersData
            LeaderInfo = maps:get(LeaderPid, LeadersData),
            ClusterNodes = maps:get(nodes, LeaderInfo),

            % Log di avvio della Fase 2 per il leader corrente
            io:format("~n ------------------------------------- ~n"),
            io:format("~n Server starting Phase 2 for Leader PID: ~p~n", [LeaderPid]),
            io:format("~n ------------------------------------- ~n"),
            io:format("Server sending start_phase2 to Leader PID: ~p with nodes: ~p~n", [
                LeaderPid, ClusterNodes
            ]),

            % Invia il messaggio di avvio della Fase 2 al leader corrente
            LeaderPid ! {start_phase2, ClusterNodes},

            % Attende la risposta dal leader
            receive
                % Gestisce la risposta di completamento della Fase 2 dal leader
                {LeaderPid, phase2_complete, _LeaderID, AdjacentClusters} ->
                    % Aggiorna `LeadersData` con le informazioni sui cluster adiacenti ricevute dal leader
                    UpdatedLeaderInfo = maps:put(adjacent_clusters, AdjacentClusters, LeaderInfo),
                    UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

                    % Log delle informazioni dei cluster adiacenti ricevute dal leader
                    io:format(
                        "Server received adjacent clusters info from Leader PID: ~p with clusters: ~p~n",
                        [LeaderPid, AdjacentClusters]
                    ),

                    io:format(
                        "Per il momento ho: ~p~n",
                        [UpdatedLeadersData]
                    ),

                    % Richiama `start_phase2_for_all_leaders` per continuare con il prossimo leader
                    start_phase2_for_all_leaders(
                        Nodes,
                        ProcessedNodes,
                        UpdatedLeadersData,
                        [
                            LeaderPid | ProcessedLeaders
                        ],
                        StartSystemPid
                    )
            end
    end.

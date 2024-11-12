-module(server).

%% Module Description:
%% The `server` module manages the setup, configuration, and maintenance of nodes and leaders 
%% within a distributed system. It handles various responsibilities, including:
%%
%% 1. **Initialization and Setup**:
%%    - The `start_server/1` function initializes the server process, starting the setup phase
%%      for nodes and leaders in the network.
%%    - The `server_loop/4` function continuously listens for messages from nodes, coordinating
%%      setup operations and updating leader configurations as nodes are processed.
%%
%% 2. **Node and Leader Management**:
%%    - During setup, the server configures each node and assigns leaders to clusters, monitoring
%%      leader nodes and handling completed setups, reconfigurations, and color changes.
%%    - Functions like `start_phase2_for_all_leaders/5` initiate a secondary phase to establish 
%%      the adjacency and connectivity of each leader within the distributed network.
%%
%% 3. **Failure Detection and Recovery**:
%%    - The server identifies and responds to leader failures by removing dead leaders and promoting
%%      remaining nodes within the cluster as new leaders, updating cluster configurations accordingly.
%%    - Utility functions such as `notify_adjacent_clusters_to_remove_cluster/2` handle
%%      communication with adjacent clusters to ensure consistency after a leader failure.
%%
%% 4. **Data Persistence**:
%%    - The module uses JSON serialization functions like `save_leader_configuration_json/1` 
%%      to periodically save the state and configuration of all leaders to disk, preserving
%%      the system’s state across sessions.
%%
%% This module interacts with other components, such as `node` and `event`, to create a
%% robust and fault-tolerant network where clusters can reconfigure dynamically and
%% adjacent clusters maintain synchronization.

-export([
    start_server/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% Starts the server process and logs its initiation.
%% @doc Initializes the server and starts the main server loop with an empty state.
%% @spec start_server(pid()) -> pid()
%% @param StartSystemPid The PID of the process that started the system, used for inter-process communication.
%% @return Returns the PID of the newly created server process.
%%
%% Preconditions:
%% - StartSystemPid must be a valid and active PID of the initiating system process.
%%
%% Postconditions:
%% - A server process is spawned and the server loop starts with an empty state.
start_server(StartSystemPid) ->
    ServerPid = spawn(fun() -> server_loop([], [], #{}, StartSystemPid) end),
    ServerPid.

%% Main server loop to handle messages and maintain state.
%% @doc Continuously receives and processes messages related to node setup, leader changes, and color adjustments.
%% @spec server_loop(list(), list(), map(), pid()) -> no_return()
%% @param Nodes List of nodes that need to be configured.
%% @param ProcessedNodes List of nodes that have been configured.
%% @param LeadersData A map containing leaders and their configuration data.
%% @param StartSystemPid The PID of the system process that started the server.
%%
%% Preconditions:
%% - Nodes is a list containing node structures to be configured.
%% - ProcessedNodes is a list of nodes already configured.
%% - LeadersData is a map of leader PIDs to their configuration data.
%%
%% Postconditions:
%% - Continuously listens for and processes messages related to cluster setup, leader status, 
%%   color changes, and updates cluster configurations.
server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid) ->
    receive

        %% Handles {start_setup, NewNodes} to initiate node setup
        %% @doc Initiates setup for nodes passed in NewNodes.
        %% @param NewNodes A list of leader nodes to be configured.
        %% - If NewNodes is empty, no nodes need setup, so the server loop continues.
        %% - If NewNodes contains nodes, processes the first node and recurses for the remaining.
        {start_setup, NewNodes, StartSystemPid} ->
            case NewNodes of
                [] -> % No nodes to process; continue loop
                    server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid);

                [#leader{node = Node} = Leader | Rest] ->
                    MonitorRef = erlang:monitor(process, Node#node.pid),
                    UpdatedLeadersData = maps:put(
                        Node#node.pid, #{leader => Leader, monitor_ref => MonitorRef}, LeadersData
                    ),
                    % Begin setup for the leader
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(
                        Rest, ProcessedNodes ++ [Leader], UpdatedLeadersData, StartSystemPid
                    )
            end;

        %% Handles {FromNode, node_setup_complete, CombinedPIDs, Color}
        %% @doc Updates server state when a node completes setup.
        %% @param FromNode The node that completed setup.
        %% @param CombinedPIDs List of PIDs within the completed cluster.
        %% @param Color The assigned color for the node's cluster.
        {FromNode, node_setup_complete, CombinedPIDs, Color} ->
            LeadersData1 = maps:put(
                FromNode, #{color => Color, nodes => CombinedPIDs}, LeadersData
            ),
            case Nodes of
                [] -> % All nodes configured; proceed to Phase 2
                    start_phase2_for_all_leaders(
                        Nodes, ProcessedNodes, LeadersData1, [], StartSystemPid
                    );
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData1, StartSystemPid)
            end;

        %% Handles {FromNode, node_already_visited}
        %% @doc Indicates that a node has already been configured.
        %% @param FromNode The node that has already been configured.
        {FromNode, node_already_visited} ->
            case Nodes of
                [] -> % All nodes configured; proceed to Phase 2
                    start_phase2_for_all_leaders(
                        Nodes, ProcessedNodes, LeadersData, [], StartSystemPid
                    );
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData, StartSystemPid)
            end;

        %% Handles {change_color_complete, LeaderPid, Leader}
        %% @doc Updates server state with new color and adjacency data for a leader.
        %% @param LeaderPid The PID of the leader whose color change is complete.
        %% @param Leader The updated leader structure after the color change.
        {change_color_complete, LeaderPid, Leader} ->
            Color = Leader#leader.color,
            AdjC = Leader#leader.adjClusters,
            NodesInCluster = Leader#leader.nodes_in_cluster,

            ValidNodesInCluster = case is_list(NodesInCluster) of true -> NodesInCluster; false -> [] end,
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{color => undefined, adjacent_clusters => [], nodes => []}),
            LeaderInfo1 = maps:put(color, Color, LeaderInfo),
            LeaderInfo2 = maps:put(adjacent_clusters, AdjC, LeaderInfo1),
            UpdatedLeaderInfo = maps:put(nodes, ValidNodesInCluster, LeaderInfo2),
            UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("../data/leaders_data.json", JsonData),
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);

        %% Handles {remove_myself_from_leaders, LeaderPid}
        %% @doc Removes a leader from LeadersData when it terminates.
        %% @param LeaderPid The PID of the leader being removed.
        {remove_myself_from_leaders, LeaderPid} ->
            UpdatedLeadersData = maps:remove(LeaderPid, LeadersData),

            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("../data/leaders_data.json", JsonData),
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);

        %% Handles {updated_AdjCLusters, LeaderPid, Leader}
        %% @doc Updates server state with new adjacency information for a leader.
        %% @param LeaderPid The PID of the leader whose adjacency has changed.
        %% @param Leader The updated leader structure.
        {updated_AdjClusters, LeaderPid, Leader} ->
            Color = Leader#leader.color,
            AdjC = Leader#leader.adjClusters,
            NodesInCluster = Leader#leader.nodes_in_cluster,

            ValidNodesInCluster = case is_list(NodesInCluster) of true -> NodesInCluster; false -> [] end,

            % Retrieve existing LeaderInfo
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{color => undefined, adjacent_clusters => [], nodes => []}),
            io:format("Before update: LeaderInfo for ~p: ~p~n", [LeaderPid, LeaderInfo]),

            % Update the color in LeaderInfo
            LeaderInfo1 = maps:put(color, Color, LeaderInfo),
            io:format("After color update: LeaderInfo1: ~p~n", [LeaderInfo1]),

            % Update the adjacent clusters in LeaderInfo
            LeaderInfo2 = maps:put(adjacent_clusters, AdjC, LeaderInfo1),
            io:format("After adjClusters update: LeaderInfo2: ~p~n", [LeaderInfo2]),

            % Update the nodes in LeaderInfo
            UpdatedLeaderInfo = maps:put(nodes, ValidNodesInCluster, LeaderInfo2),
            io:format("Final UpdatedLeaderInfo: ~p~n", [UpdatedLeaderInfo]),

            % Update LeadersData with the new LeaderInfo
            UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),
            io:format("UpdatedLeadersData: ~p~n", [UpdatedLeadersData]),

            % Save to JSON and write to file
            JsonData = save_leader_configuration_json(UpdatedLeadersData),
            file:write_file("../data/leaders_data.json", JsonData),
            server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid);

        %% Handles {operation_request, Event, FromPid}
        %% @doc Responds to an operation request by acknowledging.
        %% @param Event The event triggering the operation.
        %% @param FromPid The PID of the process requesting the operation.
        {operation_request, Event, FromPid} ->
            FromPid ! {server_ok, Event},
            server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid);

        _Other ->
            server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid)
    after 5000 ->

        %% Checks for dead leaders every 5 seconds
        %% @doc Identifies and removes dead leaders, promotes new leaders as needed.
        %% Preconditions:
        %% - LeadersData is a map containing active leaders.
        %% Postconditions:
        %% - Updates LeadersData by removing dead leaders and promoting new ones where needed.
        LeaderPids = maps:keys(LeadersData),
        DeadLeaders = [Pid || Pid <- LeaderPids, not erlang:is_process_alive(Pid)],

        UpdatedLeadersData = lists:foldl(
            fun(DeadPid, AccLeadersData) ->
                ClusterInfo = maps:get(DeadPid, AccLeadersData),
                NodesInCluster = maps:get(nodes, ClusterInfo, []),
                Color = maps:get(color, ClusterInfo),
                AdjacentClusters = maps:get(adjacent_clusters, ClusterInfo, []),
                NodesWithoutDeadLeader = lists:delete(DeadPid, NodesInCluster),
                case NodesWithoutDeadLeader of
                    [] -> % No nodes left in the cluster, remove from LeadersData
                        NewLeadersData = maps:remove(DeadPid, AccLeadersData),
                        notify_adjacent_clusters_to_remove_cluster(AdjacentClusters, DeadPid),
                        NewLeadersData;
                    _ -> % Promote a new leader
                        NewLeaderPid = hd(NodesWithoutDeadLeader),
                        NewLeaderPid ! {new_leader_elected, self(), Color, NodesWithoutDeadLeader, AdjacentClusters},
                        UpdatedClusterInfo = ClusterInfo#{
                            leader_pid => NewLeaderPid,
                            nodes => NodesWithoutDeadLeader
                        },
                        NewLeadersData1 = maps:remove(DeadPid, AccLeadersData),
                        NewLeadersData = maps:put(NewLeaderPid, UpdatedClusterInfo, NewLeadersData1),
                        notify_adjacent_clusters_about_new_leader(AdjacentClusters, NewLeaderPid, UpdatedClusterInfo),
                        update_cluster_nodes_about_new_leader(NodesWithoutDeadLeader, NewLeaderPid),
                        NewLeadersData
                end
            end,
            LeadersData,
            DeadLeaders
        ),

        io:format("~nVERIFICO SE CI SONO CLUSTER ADIACENTI CON STESSO COLORE!~n~n"),

        %%%%%

        % Seed the random number generator if not already seeded
        case get(rand_seeded) of
            true ->
                ok;
            undefined ->
                rand:seed(exsplus),
                put(rand_seeded, true)
        end,


        % io:format("Leaders DATA : ~p ~n~n",[LeadersData]),

        % Per ogni leader, controlla i cluster adiacenti con lo stesso colore
        LeaderPids = maps:keys(LeadersData),
        lists:foreach(
            fun(LeaderPid) ->
                LeaderInfo = maps:get(LeaderPid, LeadersData),
                Color = maps:get(color, LeaderInfo),
                AdjacentClusters = maps:get(adjacent_clusters, LeaderInfo, []),

                % Aggiungi log per diagnosticare il contenuto di AdjacentClusters
                % io:format("~nLeader ~p ha i seguenti cluster adiacenti: ~p~n", [LeaderPid, AdjacentClusters]),

                % Ora, per ciascun AdjacentCluster (come tupla) in AdjacentClusters, verifica se ha lo stesso colore
                AdjacentLeadersWithSameColor = lists:foldl(
                    fun({_, NeighborColor, AdjacentLeaderPid}, Acc) ->
                        case maps:is_key(AdjacentLeaderPid, LeadersData) of
                            true ->
                                if NeighborColor == Color ->
                                    [AdjacentLeaderPid | Acc];
                                true ->
                                    Acc
                                end;
                            false ->
                                %io:format("Leader adiacente ~p non trovato in LeadersData~n", [AdjacentLeaderPid]),
                                Acc
                        end
                    end,
                    [],
                    AdjacentClusters
                ),

                % Rimuove duplicati
                AdjacentLeadersWithSameColorUnique = lists:usort(AdjacentLeadersWithSameColor),

                % Rimuove il leader corrente dalla lista se presente
                SameColorLeadersWithoutSelf = lists:delete(LeaderPid, AdjacentLeadersWithSameColorUnique),

                case SameColorLeadersWithoutSelf of
                    [] ->
                        % io:format("Nessun leader adiacente con lo stesso colore per il leader ~p~n", [LeaderPid]),
                        ok; % Nessuna azione se non ci sono leader adiacenti con lo stesso colore
                    SameColorLeaders ->
                        io:format("~n~nCI SONO CLUSTER ADIACENTI CON STESSO COLORE: ~p per il leader ~p~n", [SameColorLeaders, LeaderPid]),
                                            
                        % Crea un evento di cambio colore
                        Color = maps:get(color, maps:get(LeaderPid, LeadersData)),
                        Event = event:new(color, utils:normalize_color(Color), self()),

                        io:format("SERVER : invio ~p ! {~p, ~p}~n",
                            [LeaderPid , change_color_request, Event]
                        ),
                        
                        % Invia un messaggio al leader selezionato
                        LeaderPid ! {change_color_request, Event}
                end
            end,
            LeaderPids
        ),

        io:format("SALVO~n"),

        % Salva la configurazione aggiornata
        JsonData = save_leader_configuration_json(UpdatedLeadersData),
        file:write_file("../data/leaders_data.json", JsonData),

        % Continua il loop con i dati aggiornati
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
    % io:format("SETUP COMPLETATO PER TUTTI I NODI~n"),
    % io:format("Chiedo a tutti i nodi di salvare le loro informazioni su DB locali~n"),

    % Ottieni i PID di tutti i leader e invia loro il messaggio di salvataggio
    LeaderPids = maps:keys(LeadersData),

    % io:format("Leader Pids : ~p", [LeaderPids]),

    lists:foreach(
        fun(LeaderPid) ->
            % Invia il messaggio di salvataggio includendo il PID del server per l'ACK
            % io:format("Chiedo a ~p di salvare i dati. ~n", [LeaderPid]),
            LeaderPid ! {save_to_db, self()}
        end,
        LeaderPids
    ),
    % io:format("LeadersData : ~p", [LeadersData]),

    StartSystemPid ! {finih_setup, LeaderPids},

    server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid).


%% Saves the leader configuration as JSON data.
%% @doc Serializes LeadersData to JSON format and writes it to file.
%% @spec save_leader_configuration_json(map()) -> string()
%% @param LeadersData A map containing leader configurations.
%% @return Returns the JSON data string.
save_leader_configuration_json(LeadersData) ->
    LeaderPids = maps:keys(LeadersData),
    JsonString = lists:map(fun(Pid) -> leader_to_json(LeadersData, Pid) end, LeaderPids),
    JsonData = "[" ++ string:join(JsonString, ",") ++ "]",
    file:write_file("leaders_data.json", JsonData),
    JsonData.

%% Converts a leader's data to a JSON string.
%% @doc Serializes a single leader's configuration data to JSON.
%% @spec leader_to_json(map(), pid()) -> string()
%% @param LeadersData A map with all leader data.
%% @param LeaderPid The PID of the leader to serialize.
%% @return JSON string representing the leader's configuration.
leader_to_json(LeadersData, LeaderPid) ->
    Cluster = maps:get(LeaderPid, LeadersData),
    AdjacentClustersJson = adjacent_clusters_to_json(maps:get(adjacent_clusters, Cluster)),
    Color = atom_to_string(maps:get(color, Cluster)),
    NodesJson = nodes_to_json(maps:get(nodes, Cluster)),
    LeaderPidStr = pid_to_string(LeaderPid),

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
%% - Nessun output diretto; scrive il messaggio su "../data/server_log.txt" e lo stampa su console
% log_operation (Message) ->
    % Apre il file di log "../data/server_log.txt" in modalità append (aggiunta in fondo)
    % {ok, File} = file:open("../data/server_log.txt", [append]),
    % Scrive il messaggio di log nel file, seguito da una nuova linea
    % io:format(File, "~s~n", [Message]),
    % Chiude il file di log
    % file:close(File),
    % Stampa il messaggio di log sulla console per monitoraggio immediato
    % io:format("LOG: ~s~n", [Message]).

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

    % io:format("Leader rimanenti: ~p", [RemainingLeaders]),
    % Seleziona i PID dei leader non processati
    case maps:keys(RemainingLeaders) of
        % Se non ci sono leader rimanenti, Fase 2 completata
        [] ->
            % io:format("~n~n ------------------------------------- ~n"),
            % io:format("Phase 2 completed. All leaders have been processed.~n"),
            % io:format("~n ------------------------------------- ~n~n"),
            % io:format("Final Overlay Network Data~n~p~n", [LeadersData]),
            % Converte e salva i dati finali dei leader in formato JSON
            JsonData = save_leader_configuration_json(LeadersData),
            file:write_file("../data/leaders_data.json", JsonData),
            % io:format("Dati dei leader salvati in ../data/leaders_data.json ~n"),
            finish_setup(Nodes, ProcessedNodes, LeadersData, StartSystemPid);
        % Se ci sono leader rimanenti, processa il primo PID rimanente
        [LeaderPid | _] ->
            % Ottiene le informazioni del leader corrente dal dizionario LeadersData
            LeaderInfo = maps:get(LeaderPid, LeadersData),
            NodesInCluster = maps:get(nodes, LeaderInfo),

            % Log di avvio della Fase 2 per il leader corrente
            % io:format("~n ------------------------------------- ~n"),
            % io:format("~n Server starting Phase 2 for Leader PID: ~p~n", [LeaderPid]),
            % io:format("~n ------------------------------------- ~n"),
            % io:format("Server sending start_phase2 to Leader PID: ~p with nodes: ~p~n", [
            %     LeaderPid, NodesInCluster
            % ]),

            % Invia il messaggio di avvio della Fase 2 al leader corrente
            LeaderPid ! {start_phase2, NodesInCluster},

            % Attende la risposta dal leader
            receive
                % Gestisce la risposta di completamento della Fase 2 dal leader
                {LeaderPid, phase2_complete, _LeaderID, AdjacentClusters} ->
                    % Aggiorna `LeadersData` con le informazioni sui cluster adiacenti ricevute dal leader
                    UpdatedLeaderInfo = maps:put(adjacent_clusters, AdjacentClusters, LeaderInfo),
                    UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

                    % Log delle informazioni dei cluster adiacenti ricevute dal leader
                    % io:format(
                    %     "Server received adjacent clusters info from Leader PID: ~p with clusters: ~p~n",
                    %     [LeaderPid, AdjacentClusters]
                    % ),

                    % io:format(
                    %     "Per il momento ho: ~p~n",
                    %     [UpdatedLeadersData]
                    % ),

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
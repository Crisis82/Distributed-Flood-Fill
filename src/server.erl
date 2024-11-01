%% server.erl
-module(server).
-export([
    start_server/0,
    server_loop/3,
    log_operation/1,
    start_phase2_for_all_leaders/2,
    save_leader_configuration_json/1
]).
-include("node.hrl").

%% Avvia il processo del server e registra l'inizio nel log
%% Output:
%% - Restituisce il PID del server appena creato
start_server() ->
    log_operation("Server started."),
    % Avvia il server e il ciclo principale server_loop con dati iniziali vuoti
    ServerPid = spawn(fun() -> server_loop([], [], #{}) end),
    io:format("Server started with PID: ~p~n", [ServerPid]),
    ServerPid.

%% Ciclo principale del server che gestisce i messaggi e mantiene lo stato
%% Input:
%% - Nodes: lista dei nodi da configurare
%% - ProcessedNodes: lista dei nodi già configurati
%% - LeadersData: mappa dei leader e relativi dati di configurazione
server_loop(Nodes, ProcessedNodes, LeadersData) ->
    receive
        %% Gestione del messaggio {start_setup, NewNodes} per iniziare la configurazione dei nodi
        {start_setup, NewNodes} ->
            log_operation("Received request to start node setup."),
            case NewNodes of
                % Nessun nodo da processare
                [] ->
                    log_operation("No nodes to process");
                % Processa il primo nodo e passa al resto
                [#leader{node = Node} = Leader | Rest] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(Rest, ProcessedNodes ++ [Leader], LeadersData)
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
                    start_phase2_for_all_leaders(LeadersData1, []);
                % Passa al prossimo nodo da configurare
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData1)
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
                    start_phase2_for_all_leaders(LeadersData, []);
                % Passa al prossimo nodo da configurare
                [#leader{node = Node} = Leader | RestNodes] ->
                    Node#node.pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [Leader], LeadersData)
            end;
        %% Gestione dei messaggi non previsti
        _Other ->
            log_operation("Received unhandled message."),
            server_loop(Nodes, ProcessedNodes, LeadersData)
    end.
finish_setup(LeadersData) ->
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
    ).

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
start_phase2_for_all_leaders(LeadersData, ProcessedLeaders) ->
    % Filtra i leader non ancora processati nella Fase 2
    RemainingLeaders = maps:filter(
        fun(Key, _) -> not lists:member(Key, ProcessedLeaders) end, LeadersData
    ),
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
            finish_setup(LeadersData);
        % Se ci sono leader rimanenti, processa il primo PID rimanente
        [LeaderPid | _] ->
            % Ottiene le informazioni del leader corrente dal dizionario LeadersData
            LeaderInfo = maps:get(LeaderPid, LeadersData),
            NodesInCluster = maps:get(nodes, LeaderInfo),

            % Log di avvio della Fase 2 per il leader corrente
            io:format("~n ------------------------------------- ~n"),
            io:format("~n Server starting Phase 2 for Leader PID: ~p~n", [LeaderPid]),
            io:format("~n ------------------------------------- ~n"),
            io:format("Server sending start_phase2 to Leader PID: ~p with nodes: ~p~n", [
                LeaderPid, NodesInCluster
            ]),

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
                    io:format(
                        "Server received adjacent clusters info from Leader PID: ~p with clusters: ~p~n",
                        [LeaderPid, AdjacentClusters]
                    ),

                    io:format(
                        "Per il momento ho: ~p~n",
                        [UpdatedLeadersData]
                    ),

                    % Richiama `start_phase2_for_all_leaders` per continuare con il prossimo leader
                    start_phase2_for_all_leaders(UpdatedLeadersData, [LeaderPid | ProcessedLeaders])
            after 5000 ->
                % Timeout: nessuna risposta dal leader entro 5 secondi
                io:format("Timeout waiting for Phase 2 completion from Leader PID: ~p~n", [
                    LeaderPid
                ]),
                % Riprova con il leader successivo mantenendo invariato `LeadersData`
                start_phase2_for_all_leaders(LeadersData, ProcessedLeaders)
            end
    end.

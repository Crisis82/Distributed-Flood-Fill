-module(server).
-export([
    start_server/0,
    server_loop/3,
    log_operation/1,
    start_phase2_for_all_leaders/2,
    save_leader_configuration_json/1
]).

start_server() ->
    log_operation("Server started."),
    ServerPid = spawn(fun() -> server_loop([], [], #{}) end),
    io:format("Server started with PID: ~p~n", [ServerPid]),
    ServerPid.

server_loop(Nodes, ProcessedNodes, LeadersData) ->
    receive
        {start_setup, NewNodes} ->
            log_operation("Received request to start node setup."),
            case NewNodes of
                [] ->
                    log_operation("No nodes to process");
                [{_, _, Pid} | Rest] ->
                    Pid ! {setup_server_request, self()},
                    server_loop(Rest, ProcessedNodes ++ [Pid], LeadersData)
            end;
        {FromNode, node_setup_complete, CombinedPIDs, Color} ->
            log_operation(
                io_lib:format("Node ~p has completed setup with nodes: ~p", [FromNode, CombinedPIDs])
            ),
            %% Update LeadersData
            LeadersData1 = maps:put(
                FromNode, #{color => Color, nodes => CombinedPIDs}, LeadersData
            ),
            case Nodes of
                [] ->
                    log_operation("Setup completed for all nodes."),
                    io:format("Setup Phase 1 completed. LeadersData: ~p~n", [LeadersData1]),
                    %% Avvia la Fase 2 su tutti i leader
                    start_phase2_for_all_leaders(LeadersData1, []);
                [NextNode | RestNodes] ->
                    {_, _, Pid} = NextNode,
                    Pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [FromNode], LeadersData1)
            end;
        {FromNode, node_already_visited} ->
            log_operation(
                io_lib:format("Node ~p has already completed setup previously.", [FromNode])
            ),
            case Nodes of
                [] ->
                    log_operation("Setup completed for all nodes."),
                    io:format("Setup Phase 1 completed. LeadersData: ~p~n", [LeadersData]),
                    start_phase2_for_all_leaders(LeadersData, []);
                [NextNode | RestNodes] ->
                    {_, _, Pid} = NextNode,
                    Pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [FromNode], LeadersData)
            end;
        _Other ->
            log_operation("Received unhandled message."),
            server_loop(Nodes, ProcessedNodes, LeadersData)
    end.

% Funzione principale che converte l'intera struttura LeadersData in JSON manualmente.
save_leader_configuration_json(LeadersData) ->
    LeaderPids = maps:keys(LeadersData),
    JsonString = lists:map(fun(Pid) -> leader_to_json(LeadersData, Pid) end, LeaderPids),
    % Combina le stringhe dei leader in formato JSON array-like.
    "{" ++ string:join(JsonString, ",") ++ "}".

% Funzione per convertire i dati di un leader in una stringa JSON.
leader_to_json(LeadersData, LeaderPid) ->
    Cluster = maps:get(LeaderPid, LeadersData),
    AdjacentClustersJson = adjacent_clusters_to_json(maps:get(adjacent_clusters, Cluster)),
    Color = atom_to_string(maps:get(color, Cluster)),
    NodesJson = nodes_to_json(maps:get(nodes, Cluster)),
    % Convertiamo il LeaderPid in stringa
    LeaderPidStr = pid_to_string(LeaderPid),
    
    % Costruiamo la stringa JSON del leader.
    io_lib:format("\"~s\": {\"adjacent_clusters\": ~s, \"color\": \"~s\", \"nodes\": ~s}",
                  [LeaderPidStr, AdjacentClustersJson, Color, NodesJson]).

% Converte i cluster adiacenti in una lista JSON.
adjacent_clusters_to_json(AdjacentClusters) ->
    AdjacentJson = [io_lib:format("{\"~s\": \"~s\"}", [pid_to_string(Pid), atom_to_string(Color)]) || {Pid, Color} <- AdjacentClusters],
    "[" ++ string:join(AdjacentJson, ",") ++ "]".

% Converte la lista dei nodi in una stringa JSON array.
nodes_to_json(Nodes) ->
    NodesJson = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    "[" ++ string:join(NodesJson, ",") ++ "]".

% Funzione per convertire un PID in una stringa.
pid_to_string(Pid) ->
    erlang:pid_to_list(Pid).

% Funzione per convertire un atomo in una stringa JSON-compatibile.
atom_to_string(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
atom_to_string(Other) -> 
    Other.



%% Function to log all server operations
log_operation(Message) ->
    {ok, File} = file:open("server_log.txt", [append]),
    io:format(File, "~s~n", [Message]),
    file:close(File),
    io:format("LOG: ~s~n", [Message]).

%% Function to start Phase 2 for all leaders
start_phase2_for_all_leaders(LeadersData, ProcessedLeaders) ->
    RemainingLeaders = maps:filter(
        fun(Key, _) -> not lists:member(Key, ProcessedLeaders) end, LeadersData
    ),
    case maps:keys(RemainingLeaders) of
        [] ->
            io:format("Phase 2 completed. All leaders have been processed.~n"),
            io:format("Final Overlay Network Data~n~p~n", [LeadersData]),
            %% Salva la configurazione finale dei leader in JSON
            JsonData = save_leader_configuration_json(LeadersData),
            file:write_file("leaders_data.json", JsonData),
            %% Notifica il server loop che la fase 2 è completa
            self() ! phase2_done;
        [LeaderPid | _] ->
            LeaderInfo = maps:get(LeaderPid, LeadersData),
            NodesInCluster = maps:get(nodes, LeaderInfo),
            io:format("~n ------------------------------------- ~n"),
            io:format("~n Server starting Phase 2 for Leader PID: ~p~n", [LeaderPid]),
            io:format("~n ------------------------------------- ~n"),
            io:format("Server sending start_phase2 to Leader PID: ~p with nodes: ~p~n", [
                LeaderPid, NodesInCluster
            ]),
            LeaderPid ! {start_phase2, NodesInCluster, self()},
            receive
                {LeaderPid, phase2_complete, _LeaderID, AdjacentClusters} ->
                    UpdatedLeaderInfo = maps:put(adjacent_clusters, AdjacentClusters, LeaderInfo),
                    UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),
                    io:format(
                        "Server received adjacent clusters info from Leader PID: ~p with clusters: ~p~n",
                        [LeaderPid, AdjacentClusters]
                    ),
                    start_phase2_for_all_leaders(UpdatedLeadersData, [LeaderPid | ProcessedLeaders])
            after 5000 ->
                io:format("Timeout waiting for Phase 2 completion from Leader PID: ~p~n", [
                    LeaderPid
                ]),
                start_phase2_for_all_leaders(LeadersData, ProcessedLeaders)
            end
    end.

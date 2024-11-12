-module(server).

%% --------------------------------------------------------------------
%% Module: server
%% Description:
%% This module implements the server process for managing and coordinating
%% a distributed system of nodes and clusters. The server’s main responsibilities
%% include initializing node setup, handling leader monitoring, managing cluster
%% color consistency, and saving system state to a JSON file for persistence.
%%
%% Key Responsibilities:
%% - **Node Setup:** Manages the initialization of nodes by initiating the setup
%%   requests, assigning leaders, and updating system state.
%%
%% - **Leader Monitoring and Failover:** Monitors the state of each leader in the
%%   system, promoting new leaders if an existing leader becomes inactive or fails.
%%
%% - **Cluster Color Consistency:** Ensures adjacent clusters have unique colors
%%   by identifying adjacent clusters with the same color and triggering color-change
%%   requests as needed.
%%
%% - **Data Persistence:** Periodically saves the server’s state, including node and
%%   leader configurations, as JSON files. This provides a snapshot of the system's
%%   current state for analysis and recovery.
%%
%% Main Functions:
%% - `start_server/1`:
%%   Starts the server process, initializing it with empty data structures for
%%   tracking nodes, processed nodes, and leader data, and launching the main
%%   server loop.
%%
%% - `server_loop/4`:
%%   The main loop that handles incoming messages, including setup requests, leader
%%   updates, color-change requests, and adjacency updates. It includes a timeout
%%   mechanism to periodically verify leader activity, handle dead leaders, and
%%   ensure color uniqueness.
%%
%% - `start_phase2_for_all_leaders/5`:
%%   Initiates Phase 2 for all leaders in the system, gathering adjacency information
%%   for each leader and saving the final configuration.
%%
%% - `collect_leader_responses/3`:
%%   Collects responses from leaders within a specified timeout to confirm their
%%   active status in the system.
%%
%% - `finish_setup/4`:
%%   Concludes the setup phase by instructing each leader to save its configuration
%%   locally and notifying the initiating process of completion.
%%
%% - `save_leader_configuration_json/1`:
%%   Converts leader configurations into JSON format and writes them to a file for
%%   persistence.
%%
%% - `notify_adjacent_clusters_to_remove_cluster/2` and
%%   `notify_adjacent_clusters_about_new_leader/3`:
%%   Handle adjacency updates, notifying adjacent clusters to remove references to
%%   a dead leader or update references to a newly promoted leader.
%%
%% Usage:
%% - This module is typically started by calling `start_server/1`, which initializes
%%   the server and begins handling distributed system setup, monitoring, and consistency
%%   tasks.
%%
%% Notes:
%% - This module relies on several utility functions for tasks like normalizing colors
%%   and converting data to JSON format.
%% - The module regularly saves its data to `../data/leaders_data.json` for debugging
%%   and recovery purposes.
%% --------------------------------------------------------------------


-export([
    start_server/1
]).

-include("includes/node.hrl").
-include("includes/event.hrl").

%% --------------------------------------------------------------------
%% Function: start_server/1
%% Description:
%% Initializes and starts the server process for the distributed system.
%% This function spawns a new server process, which will handle the main
%% server loop and manage the system state and communications.
%%
%% Input:
%% - StartSystemPid: The PID of the process that initiated the server setup.
%%
%% Preconditions:
%% - The StartSystemPid must be a valid PID for communication purposes.
%%
%% Output:
%% - Returns the PID of the newly spawned server process.
%%
%% Usage:
%% - This function is typically called once at the beginning of the system's
%%   setup to start the server loop. The server will then manage and coordinate
%%   interactions among nodes.
%% --------------------------------------------------------------------
start_server(StartSystemPid) ->
    %% Spawn the server process, initializing it with empty lists for node
    %% and cluster data, an empty map for configurations, and the StartSystemPid.
    ServerPid = spawn(fun() -> server_loop([], [], #{}, StartSystemPid) end),

    %% Return the PID of the newly spawned server process.
    ServerPid.

%% --------------------------------------------------------------------
%% Module: server_loop
%% Description:
%% This module implements the main server loop for managing a distributed
%% system of nodes and clusters. The server is responsible for initiating
%% node setup, monitoring leader states, handling cluster color changes,
%% and managing adjacent cluster data. It ensures that each cluster has a
%% leader and handles cases where leaders are lost or nodes need to be
%% reassigned.
%%
%% Key Responsibilities:
%% - Node Setup: Initiates setup for newly added nodes by managing setup
%%   requests and updating the server’s state with node configurations.
%% - Leader Monitoring: Periodically checks if all leaders are active and
%%   promotes new leaders if a current leader is no longer alive.
%% - Cluster Color Management: Detects adjacent clusters with the same
%%   color and triggers color change events to ensure color uniqueness
%%   among neighboring clusters.
%% - State Persistence: Saves the current state of the system to a JSON
%%   file after every significant change, allowing for recovery and analysis.

%% Key Functions:
%% - start_server/1:
%%   Starts the server process and initializes the server loop with empty
%%   data structures for tracking nodes, processed nodes, and leader data.
%%
%% - server_loop/4:
%%   The main loop that handles incoming messages for setup, leader updates,
%%   color change requests, and system state persistence.
%%   * Handles {start_setup, NewNodes, StartSystemPid}:
%%     Initiates setup for a list of nodes passed in `NewNodes`.
%%   * Handles {FromNode, node_setup_complete, CombinedPIDs, Color}:
%%     Updates server state when a node completes setup, including the
%%     nodes in the cluster and their assigned color.
%%   * Handles {change_color_complete, LeaderPid, Leader}:
%%     Updates server state with new color and adjacency data after a color
%%     change.
%%   * Handles {remove_myself_from_leaders, LeaderPid}:
%%     Removes a leader from the `LeadersData` if it terminates.
%%   * Timeout Check (every 5 seconds):
%%     Identifies dead leaders, promotes new leaders, and verifies color
%%     uniqueness among adjacent clusters.
%%
%% Usage:
%% - This module is invoked by calling `start_server/1`, which starts the
%%   server loop to manage distributed setup, leader monitoring, and cluster
%%   consistency tasks.
%% - Each function includes timeout handling to maintain responsiveness
%%   and periodic checks to ensure system consistency.
%%
%% Notes:
%% - The module relies on utility functions such as `utils:normalize_color/1`
%%   and `save_leader_configuration_json/1` for various tasks.
%% - State is saved periodically to `../data/leaders_data.json` for
%%   persistence and debugging purposes.
%%
%% --------------------------------------------------------------------

server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid) ->
    receive
        %% Handles {start_setup, NewNodes} to initiate node setup
        %% @doc Initiates setup for nodes passed in NewNodes.
        %% @param NewNodes A list of leader nodes to be configured.
        %% - If NewNodes is empty, no nodes need setup, so the server loop continues.
        %% - If NewNodes contains nodes, processes the first node and recurses for the remaining.
        {start_setup, NewNodes, StartSystemPid} ->
            case NewNodes of
                % No nodes to process; continue loop
                [] ->
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
                % All nodes configured; proceed to Phase 2
                [] ->
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
        {_FromNode, node_already_visited} ->
            case Nodes of
                % All nodes configured; proceed to Phase 2
                [] ->
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

            ValidNodesInCluster =
                case is_list(NodesInCluster) of
                    true -> NodesInCluster;
                    false -> []
                end,
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{
                color => undefined, adjacent_clusters => [], nodes => []
            }),
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

            ValidNodesInCluster =
                case is_list(NodesInCluster) of
                    true -> NodesInCluster;
                    false -> []
                end,

            % Retrieve existing LeaderInfo
            LeaderInfo = maps:get(LeaderPid, LeadersData, #{
                color => undefined, adjacent_clusters => [], nodes => []
            }),
            % io:format("Before update: LeaderInfo for ~p: ~p~n", [LeaderPid, LeaderInfo]),

            % Update the color in LeaderInfo
            LeaderInfo1 = maps:put(color, Color, LeaderInfo),
            % io:format("After color update: LeaderInfo1: ~p~n", [LeaderInfo1]),

            % Update the adjacent clusters in LeaderInfo
            LeaderInfo2 = maps:put(adjacent_clusters, AdjC, LeaderInfo1),
            % io:format("After adjClusters update: LeaderInfo2: ~p~n", [LeaderInfo2]),

            % Update the nodes in LeaderInfo
            UpdatedLeaderInfo = maps:put(nodes, ValidNodesInCluster, LeaderInfo2),
            % io:format("Final UpdatedLeaderInfo: ~p~n", [UpdatedLeaderInfo]),

            % Update LeadersData with the new LeaderInfo
            UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),
            % io:format("UpdatedLeadersData: ~p~n", [UpdatedLeadersData]),

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
    after 8000 ->
        %% Checks for dead leaders every 5 seconds
        %% @doc Identifies and removes dead leaders, promotes new leaders as needed.
        %% Preconditions:
        %% - LeadersData is a map containing active leaders.
        %% Postconditions:
        %% - Updates LeadersData by removing dead leaders and promoting new ones where needed.
        LeaderPids = maps:keys(LeadersData),
        DeadLeaders = [Pid || Pid <- LeaderPids, not erlang:is_process_alive(Pid)],

        %% Invio del messaggio {still_leader} a ogni leader attivo
        AliveLeaders = lists:subtract(LeaderPids, DeadLeaders),
        lists:foreach(
            fun(LeaderPid) ->
                LeaderPid ! {still_leader, self()}
            end,
            AliveLeaders
        ),

        %% Raccolta delle risposte dai leader

        % Attende fino a 1000 ms
        Responses = collect_leader_responses(AliveLeaders, [], 1000),

        %% Identifica i leader che non sono più leader
        NotLeaders = [LeaderPid || {LeaderPid, false} <- Responses],

        %% Identifica i leader che non hanno risposto
        RespondedLeaderPids = [LeaderPid || {LeaderPid, _} <- Responses],
        NonRespondingLeaders = lists:subtract(AliveLeaders, RespondedLeaderPids),

        %% Combina i leader morti e quelli che non sono più leader
        _DefunctLeaders = DeadLeaders ++ NotLeaders ++ NonRespondingLeaders,

        %% Updates LeadersData by handling dead leaders in the system.
        %% This fold function iterates over each DeadPid in DeadLeaders, removing the dead leader
        %% from LeadersData or promoting a new leader from the remaining nodes in the cluster.
        UpdatedLeadersData = lists:foldl(
            fun(DeadPid, AccLeadersData) ->
                %% Retrieve the cluster information for the dead leader.
                ClusterInfo = maps:get(DeadPid, AccLeadersData),
                %% Extract the list of nodes in the cluster, the cluster's color,
                %% and adjacent clusters associated with the dead leader.
                NodesInCluster = maps:get(nodes, ClusterInfo, []),
                Color = maps:get(color, ClusterInfo),
                AdjacentClusters = maps:get(adjacent_clusters, ClusterInfo, []),

                %% Remove the dead leader from the list of nodes in the cluster.
                NodesWithoutDeadLeader = lists:delete(DeadPid, NodesInCluster),

                %% Check if there are any nodes left in the cluster.
                case NodesWithoutDeadLeader of
                    [] ->
                        %% No nodes left in the cluster, so remove the cluster from LeadersData.
                        NewLeadersData = maps:remove(DeadPid, AccLeadersData),
                        %% Notify adjacent clusters to remove references to this cluster.
                        notify_adjacent_clusters_to_remove_cluster(AdjacentClusters, DeadPid),
                        NewLeadersData;
                    _ ->
                        %% Promote a new leader from the remaining nodes.
                        NewLeaderPid = hd(NodesWithoutDeadLeader),
                        %% Send a message to the new leader with the updated cluster details.
                        NewLeaderPid !
                            {new_leader_elected, self(), Color, NodesWithoutDeadLeader,
                                AdjacentClusters},

                        %% Update the cluster information with the new leader PID and remaining nodes.
                        UpdatedClusterInfo = ClusterInfo#{
                            leader_pid => NewLeaderPid,
                            nodes => NodesWithoutDeadLeader
                        },
                        %% Remove the dead leader from LeadersData and insert the new leader.
                        NewLeadersData1 = maps:remove(DeadPid, AccLeadersData),
                        NewLeadersData = maps:put(
                            NewLeaderPid, UpdatedClusterInfo, NewLeadersData1
                        ),

                        %% Notify adjacent clusters about the new leader.
                        notify_adjacent_clusters_about_new_leader(
                            AdjacentClusters, NewLeaderPid, UpdatedClusterInfo
                        ),

                        %% Update all nodes in the cluster with the new leader information.
                        update_cluster_nodes_about_new_leader(NodesWithoutDeadLeader, NewLeaderPid),

                        %% Return the updated LeadersData map.
                        NewLeadersData
                end
            end,
            %% Initial map of leader data.
            LeadersData,
            %% List of dead leader PIDs to process.
            DeadLeaders
        ),

        % io:format("~nVERIFICO SE CI SONO CLUSTER ADIACENTI CON STESSO COLORE!~n~n"),

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
                                if
                                    NeighborColor == Color ->
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
                SameColorLeadersWithoutSelf = lists:delete(
                    LeaderPid, AdjacentLeadersWithSameColorUnique
                ),

                case SameColorLeadersWithoutSelf of
                    [] ->
                        % io:format("Nessun leader adiacente con lo stesso colore per il leader ~p~n", [LeaderPid]),

                        % Nessuna azione se non ci sono leader adiacenti con lo stesso colore
                        ok;
                    SameColorLeaders ->
                        io:format(
                            "~n~nCI SONO CLUSTER ADIACENTI CON STESSO COLORE: ~p per il leader ~p~n",
                            [SameColorLeaders, LeaderPid]
                        ),

                        % Crea un evento di cambio colore
                        Color = maps:get(color, maps:get(LeaderPid, LeadersData)),
                        Event = event:new(color, utils:normalize_color(Color), self()),

                        io:format(
                            "SERVER : invio ~p ! {~p, ~p}~n",
                            [LeaderPid, change_color_request, Event]
                        ),

                        % Invia un messaggio al leader selezionato
                        LeaderPid ! {change_color_request, Event}
                end
            end,
            LeaderPids
        ),

        % io:format("SALVO~n"),

        % Salva la configurazione aggiornata
        JsonData = save_leader_configuration_json(UpdatedLeadersData),
        file:write_file("../data/leaders_data.json", JsonData),

        % Continua il loop con i dati aggiornati
        server_loop(Nodes, ProcessedNodes, UpdatedLeadersData, StartSystemPid)
    end.

%% --------------------------------------------------------------------
%% Function: collect_leader_responses/3
%% Description:
%% Collects responses from leaders within a specified timeout. Each
%% leader is expected to send a response indicating whether it is still
%% active as a leader. This function aggregates responses until the
%% timeout is reached or all responses are received.
%%
%% Input:
%% - LeaderPids: List of PIDs of leaders to await responses from.
%% - AccResponses: Accumulator for storing responses from leaders in the format `{LeaderPid, IsStillLeader}`.
%% - Timeout: The maximum time (in milliseconds) to wait for responses.
%%
%% Output:
%% - Returns a list of responses gathered within the given timeout.
%% --------------------------------------------------------------------
collect_leader_responses(_LeaderPids, AccResponses, 0) ->
    %% Base case: Return accumulated responses when the timeout reaches zero.
    AccResponses;
collect_leader_responses(LeaderPids, AccResponses, Timeout) ->
    receive
        {still_leader_response, LeaderPid, IsStillLeader} ->
            %% Accumulate each leader response and continue receiving.
            collect_leader_responses(
                LeaderPids, [{LeaderPid, IsStillLeader} | AccResponses], Timeout
            )
    after 100 ->
        %% Reduce the timeout by 100 ms and retry if no response is received.
        NewTimeout = Timeout - 100,
        collect_leader_responses(LeaderPids, AccResponses, NewTimeout)
    end.

%% --------------------------------------------------------------------
%% Function: notify_adjacent_clusters_to_remove_cluster/2
%% Description:
%% Sends a message to each unique adjacent leader, instructing them to
%% remove the cluster associated with a specified dead leader. This is
%% used to update adjacency relationships after a leader failure.
%%
%% Input:
%% - AdjacentClusters: List of tuples `{Pid, Color, LeaderID}` representing adjacent clusters.
%% - DeadLeaderPid: The PID of the leader that is no longer active.
%%
%% Output:
%% - No return value. Sends a message to each unique adjacent leader.
%% --------------------------------------------------------------------
notify_adjacent_clusters_to_remove_cluster(AdjacentClusters, DeadLeaderPid) ->
    %% Extract unique LeaderIDs from adjacent clusters and remove duplicates.
    UniqueLeaderIDs = lists:usort([LeaderID || {_, _, LeaderID} <- AdjacentClusters]),

    %% Notify each unique adjacent leader to remove the dead leader from their adjacency list.
    lists:foreach(
        fun(LeaderID) ->
            LeaderID ! {remove_adjacent_cluster, DeadLeaderPid}
        end,
        UniqueLeaderIDs
    ).

%% --------------------------------------------------------------------
%% Function: notify_adjacent_clusters_about_new_leader/3
%% Description:
%% Notifies adjacent clusters about a newly promoted leader. This allows
%% adjacent leaders to update their adjacency records with the new
%% leader information.
%%
%% Input:
%% - AdjacentClusters: List of tuples `{Pid, Color, LeaderID}` representing adjacent clusters.
%% - NewLeaderPid: The PID of the newly promoted leader.
%% - UpdatedClusterInfo: The updated cluster information, which includes the new leader data.
%%
%% Output:
%% - No return value. Sends an update message to each adjacent leader.
%% --------------------------------------------------------------------
notify_adjacent_clusters_about_new_leader(AdjacentClusters, NewLeaderPid, UpdatedClusterInfo) ->
    %% Send an update message to each adjacent leader with the new leader information.
    lists:foreach(
        fun({AdjPid, _Color, _LeaderID}) ->
            AdjPid ! {update_adjacent_cluster, NewLeaderPid, UpdatedClusterInfo}
        end,
        AdjacentClusters
    ).

%% --------------------------------------------------------------------
%% Function: update_cluster_nodes_about_new_leader/2
%% Description:
%% Sends a leader update message to each node in a cluster (excluding
%% the new leader itself). This notifies all nodes within the cluster
%% of the identity of their new leader.
%%
%% Input:
%% - Nodes: List of PIDs of nodes within the cluster.
%% - NewLeaderPid: The PID of the newly promoted leader.
%%
%% Output:
%% - No return value. Sends a leader update message to each node in the cluster.
%% --------------------------------------------------------------------
update_cluster_nodes_about_new_leader(Nodes, NewLeaderPid) ->
    %% Exclude the new leader from the list of nodes to update.
    NodesWithoutLeader = lists:delete(NewLeaderPid, Nodes),

    %% Notify each node about the new leader.
    lists:foreach(
        fun(NodePid) ->
            NodePid ! {leader_update, NewLeaderPid}
        end,
        NodesWithoutLeader
    ).

%% --------------------------------------------------------------------
%% Function: finish_setup/4
%% Description:
%% Finalizes the setup process by instructing each leader node to save its
%% data to local storage and notifying the StartSystemPid of the completion.
%%
%% Input:
%% - Nodes: List of nodes in the system.
%% - ProcessedNodes: List of nodes that have already been processed.
%% - LeadersData: Map containing data for each leader node.
%% - StartSystemPid: PID of the process that initiated the setup phase.
%%
%% Output:
%% - No return value. Initiates data saving for each leader and
%%   sends a completion message to the StartSystemPid.
%% --------------------------------------------------------------------
finish_setup(Nodes, ProcessedNodes, LeadersData, StartSystemPid) ->
    %% Retrieve all leader PIDs from the LeadersData map.
    LeaderPids = maps:keys(LeadersData),

    %% Request each leader to save its data locally.
    lists:foreach(
        fun(LeaderPid) ->
            %% Send a message to each leader to save data and acknowledge completion.
            LeaderPid ! {save_to_db, self()}
        end,
        LeaderPids
    ),

    %% Notify the StartSystemPid that setup is complete.
    StartSystemPid ! {finish_setup, LeaderPids},

    %% Continue the server loop with updated data.
    server_loop(Nodes, ProcessedNodes, LeadersData, StartSystemPid).

%% --------------------------------------------------------------------
%% Function: save_leader_configuration_json/1
%% Description:
%% Serializes the configuration of all leaders in LeadersData into JSON format
%% and writes it to a file. This allows the current state of leaders to be
%% saved and reviewed later.
%%
%% Input:
%% - LeadersData: A map containing configuration data for each leader.
%%
%% Output:
%% - Returns the JSON string created from LeadersData.
%% --------------------------------------------------------------------
save_leader_configuration_json(LeadersData) ->
    %% Retrieve the PIDs of all leaders in the system.
    LeaderPids = maps:keys(LeadersData),

    %% Convert each leader’s data to JSON format.
    JsonString = lists:map(fun(Pid) -> leader_to_json(LeadersData, Pid) end, LeaderPids),

    %% Concatenate all JSON strings into a JSON array format.
    JsonData = "[" ++ string:join(JsonString, ",") ++ "]",

    %% Write the JSON data to a file.
    file:write_file("leaders_data.json", JsonData),

    %% Return the JSON data as a string for further processing if needed.
    JsonData.

%% --------------------------------------------------------------------
%% Function: leader_to_json/2
%% Description:
%% Converts a single leader’s configuration data from LeadersData into
%% JSON format, enabling easy storage and retrieval.
%%
%% Input:
%% - LeadersData: A map containing configuration data for all leaders.
%% - LeaderPid: The PID of the leader whose data will be converted to JSON.
%%
%% Output:
%% - A JSON string representing the leader’s configuration.
%% --------------------------------------------------------------------
leader_to_json(LeadersData, LeaderPid) ->
    %% Retrieve the leader's cluster information from LeadersData.
    Cluster = maps:get(LeaderPid, LeadersData),

    %% Convert the list of adjacent clusters to JSON format.
    AdjacentClustersJson = adjacent_clusters_to_json(maps:get(adjacent_clusters, Cluster)),

    %% Convert the leader’s color to a string representation.
    Color = atom_to_string(maps:get(color, Cluster)),

    %% Convert the list of nodes in the cluster to JSON format.
    NodesJson = nodes_to_json(maps:get(nodes, Cluster)),

    %% Convert the leader PID to a string for JSON compatibility.
    LeaderPidStr = pid_to_string(LeaderPid),

    %% Format the leader's configuration data into JSON.
    io_lib:format(
        "{\"leader_id\": \"~s\", \"adjacent_clusters\": ~s, \"color\": \"~s\", \"nodes\": ~s}",
        [LeaderPidStr, AdjacentClustersJson, Color, NodesJson]
    ).

%% --------------------------------------------------------------------
%% Function: adjacent_clusters_to_json/1
%% Description:
%% Converts a list of adjacent clusters into a JSON string. Each adjacent
%% cluster is represented with its PID, color, and leader ID in JSON format.
%%
%% Input:
%% - AdjacentClusters: A list of tuples `{Pid, Color, LeaderID}`, where
%%   each tuple represents an adjacent cluster with its process ID, color,
%%   and leader ID.
%%
%% Output:
%% - A JSON array string representing the adjacent clusters.
%% --------------------------------------------------------------------
adjacent_clusters_to_json(AdjacentClusters) ->
    %% Remove duplicate clusters and convert each to a JSON object.
    UniqueClusters = lists:usort(AdjacentClusters),
    ClustersJson = [
        io_lib:format(
            "{\"pid\": \"~s\", \"color\": \"~s\", \"leader_id\": \"~s\"}",
            [pid_to_string(Pid), atom_to_string(Color), pid_to_string(LeaderID)]
        )
     || {Pid, Color, LeaderID} <- UniqueClusters
    ],
    %% Join the individual JSON objects into a JSON array format.
    "[" ++ string:join(ClustersJson, ",") ++ "]".

%% --------------------------------------------------------------------
%% Function: nodes_to_json/1
%% Description:
%% Converts a list of node PIDs into a JSON array string. Each PID in the
%% list is formatted as a JSON string element.
%%
%% Input:
%% - Nodes: A list of process IDs representing nodes in a cluster.
%%
%% Output:
%% - A JSON array string containing the PIDs of the nodes.
%% --------------------------------------------------------------------
nodes_to_json(Nodes) ->
    %% Convert each PID to a JSON-compatible string format.
    NodesJson = [io_lib:format("\"~s\"", [pid_to_string(NodePid)]) || NodePid <- Nodes],
    %% Join the individual JSON strings into a JSON array format.
    "[" ++ string:join(NodesJson, ",") ++ "]".

%% --------------------------------------------------------------------
%% Function: pid_to_string/1
%% Description:
%% Converts an Erlang PID to a string, making it JSON-compatible.
%%
%% Input:
%% - Pid: An Erlang process ID.
%%
%% Output:
%% - A string representation of the PID.
%% --------------------------------------------------------------------
pid_to_string(Pid) ->
    %% Convert the PID to a string using Erlang's built-in `pid_to_list` function.
    erlang:pid_to_list(Pid).

%% --------------------------------------------------------------------
%% Function: atom_to_string/1
%% Description:
%% Converts an atom to a JSON-compatible string format. If the input is not
%% an atom, it returns the input unmodified.
%%
%% Input:
%% - Atom: The atom to convert to a string, or any other term.
%%
%% Output:
%% - A string representation of the atom, or the original term if it is not an atom.
%% --------------------------------------------------------------------
atom_to_string(Atom) when is_atom(Atom) ->
    %% Convert the atom to a string if it is an atom.
    atom_to_list(Atom);
atom_to_string(Other) ->
    %% Return the term unmodified if it is not an atom.
    Other.

%% --------------------------------------------------------------------
%% Function: start_phase2_for_all_leaders/5
%% Description:
%% Initiates Phase 2 for all leaders in the distributed system. During Phase 2,
%% each leader is tasked with discovering and reporting its adjacent clusters.
%% This function processes each leader sequentially and updates `LeadersData`
%% with the adjacency information obtained from each leader. Once all leaders
%% have completed Phase 2, the data is saved to a JSON file.
%%
%% Input:
%% - Nodes: List of all nodes in the system.
%% - ProcessedNodes: List of nodes that have already completed Phase 2.
%% - LeadersData: Map containing data for each leader, including its PID and nodes in its cluster.
%% - ProcessedLeaders: List of leaders that have already been processed in Phase 2.
%% - StartSystemPid: PID of the process that initiated the system setup.
%%
%% Output:
%% - No direct output. Updates `LeadersData` with adjacency information and
%%   saves the final data to a JSON file when Phase 2 is complete.
%% --------------------------------------------------------------------
start_phase2_for_all_leaders(Nodes, ProcessedNodes, LeadersData, ProcessedLeaders, StartSystemPid) ->
    %% Filter out leaders that have already been processed in Phase 2.
    RemainingLeaders = maps:filter(
        fun(Key, _) -> not lists:member(Key, ProcessedLeaders) end, LeadersData
    ),

    %% Check if there are any remaining leaders to process.
    case maps:keys(RemainingLeaders) of
        %% If no leaders remain, Phase 2 is complete.
        [] ->
            %% Convert `LeadersData` to JSON and save to file.
            JsonData = save_leader_configuration_json(LeadersData),
            file:write_file("../data/leaders_data.json", JsonData),

            %% Notify the system setup process that Phase 2 is complete.
            finish_setup(Nodes, ProcessedNodes, LeadersData, StartSystemPid);
        %% If there are leaders remaining, process the first one in the list.
        [LeaderPid | _] ->
            %% Retrieve the information for the current leader.
            LeaderInfo = maps:get(LeaderPid, LeadersData),
            NodesInCluster = maps:get(nodes, LeaderInfo),

            %% Send a message to the current leader to start Phase 2.
            LeaderPid ! {start_phase2, NodesInCluster},

            %% Wait for the Phase 2 completion response from the leader.
            receive
                {LeaderPid, phase2_complete, _LeaderID, AdjacentClusters} ->
                    %% Update `LeadersData` with the adjacency information from the leader.
                    UpdatedLeaderInfo = maps:put(adjacent_clusters, AdjacentClusters, LeaderInfo),
                    UpdatedLeadersData = maps:put(LeaderPid, UpdatedLeaderInfo, LeadersData),

                    %% Recursively call `start_phase2_for_all_leaders` to continue with the next leader.
                    start_phase2_for_all_leaders(
                        Nodes,
                        ProcessedNodes,
                        UpdatedLeadersData,
                        [LeaderPid | ProcessedLeaders],
                        StartSystemPid
                    )
            end
    end.

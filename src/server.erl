%% server.erl
-module(server).
-export([start_server/0, server_loop/3, log_operation/1]).

start_server() ->
    log_operation("Server started."),
    ServerPid = spawn(fun() -> server_loop([], [], #{}) end),
    io:format("Server started with PID: ~p~n", [ServerPid]),
    ServerPid.

server_loop(Nodes, ProcessedNodes, LeadersData) ->
    receive
        {start_setup, NewNodes} ->
            log_operation("Received request to start node setup."),
            %% Start the setup with the first node
            case NewNodes of
                [] ->
                    log_operation("No nodes to process.");
                [{_, _, Pid} | Rest] ->
                    Pid ! {setup_server_request, self()},
                    server_loop(Rest, ProcessedNodes ++ [Pid], LeadersData)
            end;

        {FromNode, node_setup_complete, CombinedPIDs, Color} ->
            log_operation(io_lib:format("Node ~p has completed setup with nodes: ~p", [FromNode, CombinedPIDs])),
            %% Update LeadersData
            LeadersData1 = maps:put(FromNode, #{color => Color, nodes => CombinedPIDs}, LeadersData),
            %% Proceed to the next node in the list
            case Nodes of
                [] ->
                    log_operation("Setup completed for all nodes."),
                    %% Now print the collected data
                    log_operation(io_lib:format("Leaders Data: ~p", [LeadersData1]));
                [NextNode | RestNodes] ->
                    %% Extract the Pid from the NextNode tuple
                    {_, _, Pid} = NextNode,
                    %% Send setup to the next node
                    Pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [FromNode], LeadersData1)
            end;

        {FromNode, node_already_visited} ->
            log_operation(io_lib:format("Node ~p has already completed setup previously.", [FromNode])),
            %% Proceed to the next node in the list
            case Nodes of
                [] ->
                    log_operation("Setup completed for all nodes."),
                    %% Now print the collected data
                    log_operation(io_lib:format("Leaders Data: ~p", [LeadersData]));
                [NextNode | RestNodes] ->
                    %% Extract the Pid from the NextNode tuple
                    {_, _, Pid} = NextNode,
                    %% Send setup to the next node
                    Pid ! {setup_server_request, self()},
                    server_loop(RestNodes, ProcessedNodes ++ [FromNode], LeadersData)
            end;

        _Other ->
            log_operation("Received unhandled message."),
            server_loop(Nodes, ProcessedNodes, LeadersData)
    end.

%% Function to log all server operations
log_operation(Message) ->
    {ok, File} = file:open("server_log.txt", [append]),
    io:format(File, "~s~n", [Message]),
    file:close(File),
    io:format("LOG: ~s~n", [Message]).

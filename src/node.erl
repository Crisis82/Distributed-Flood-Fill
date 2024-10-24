%% node.erl
-module(node).
-export([create_node/3, node_loop/6, node_loop_propagate/9]).

%% Creation of a node
create_node({X, Y}, Color, StartSystemPid) ->
    %% Create the leaderID as a formatted string "X_Y"
    LeaderID = io_lib:format("~p_~p", [X, Y]),
    %% Initialize the node with leaderID set to itself
    Pid = spawn(fun() -> node_loop(X, Y, Color, StartSystemPid, false, LeaderID) end),
    io:format("Node (~p, ~p) created with color: ~p, PID: ~p, LeaderID: ~s~n", [X, Y, Color, Pid, LeaderID]),
    {X, Y, Pid}.

%% Main loop of the node
node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID) ->
    receive
        {neighbors, Neighbors} ->
            io:format("Node (~p, ~p) received neighbors: ~p~n", [X, Y, Neighbors]),
            %% Send ACK to the start_system process
            StartSystemPid ! {ack_neighbors, self()},
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);
        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [X, Y]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID)
    end.

node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors) ->
    receive
        {setup_server_request, FromPid} ->
            if Visited == true ->
                io:format("Node (~p, ~p) receives setup_server_request, already visited, responding to server.~n", [X, Y]),
                FromPid ! {self(), node_already_visited},
                node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);
            true ->
                io:format("Node (~p, ~p) receives setup_server_request, not visited, starting propagation of my leaderID: ~s.~n", [X, Y, LeaderID]),
                UpdatedVisited = true,
                %% Start propagation and indicate that this node is the initiator
                ServerPid = FromPid,
                node_loop_propagate(X, Y, Color, StartSystemPid, UpdatedVisited, Neighbors, LeaderID, ServerPid, initiator)
            end;

        {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
            if Visited == false andalso Color == SenderColor ->
                %% The node has the same color: propagate and collect neighbors of the same color
                io:format("Node (~p, ~p) has the same color as the requesting node.~n", [X, Y]),
                UpdatedVisited = true,
                %% Update LeaderID to the propagated one
                UpdatedLeaderID = PropagatedLeaderID,
                node_loop_propagate(X, Y, Color, StartSystemPid, UpdatedVisited, Neighbors, UpdatedLeaderID, FromPid, non_initiator);
            Visited == true ->
                %% Node has already been visited
                io:format("Node (~p, ~p) has already been visited, responding accordingly.~n", [X, Y]),
                FromPid ! {self(), node_already_visited},
                node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);
            true ->
                %% The node has a different color: sends only confirmation of receipt
                io:format("Node (~p, ~p) has a different color, sends only received.~n", [X, Y]),
                FromPid ! {self(), ack_propagation_different_color},
                node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors)
            end;

        _Other ->
            io:format("Node (~p, ~p) received an unhandled message.~n", [X, Y]),
            node_loop(X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors)
    end.

%% Function to propagate and manage the cascade
node_loop_propagate(X, Y, Color, StartSystemPid, Visited, Neighbors, PropagatedLeaderID, FromPid, InitiatorFlag) ->
    io:format("Node (~p, ~p) is propagating as leader with ID: ~s and color: ~p.~n", [X, Y, PropagatedLeaderID, Color]),

    %% Exclude FromPid from Neighbors using =/=
    NeighborsToSend = [N || N <- Neighbors, N =/= FromPid],
    io:format("Node (~p, ~p) will send messages to neighbors: ~p~n", [X, Y, NeighborsToSend]),

    %% Send setup_node_request to neighbors including the leaderID
    lists:foreach(fun(NeighborPid) ->
        io:format("Node (~p, ~p) is propagating leaderID: ~s and color: ~p, towards ~p.~n",
                  [X, Y, PropagatedLeaderID, Color, NeighborPid]),
        NeighborPid ! {setup_node_request, Color, PropagatedLeaderID, self()}
    end, NeighborsToSend),

    io:format("Waiting for ACKs for Node (~p, ~p).~n", [X, Y]),
    %% Wait for each neighbor to respond and collect their PIDs
    {ok, AccumulatedPIDs} = wait_for_ack_from_neighbors(NeighborsToSend, [], X, Y, Color, StartSystemPid, Visited, PropagatedLeaderID, Neighbors),
    io:format("Finished receiving ACKs for Node (~p, ~p).~n", [X, Y]),
    %% Combine AccumulatedPIDs with own PID
    CombinedPIDs = lists:append(AccumulatedPIDs, [self()]),
    io:format("Node (~p, ~p) invierà ~p come nodi sotto di lui.~n", [X, Y, CombinedPIDs]),
    %% If this node is the initiator, send the combined PIDs back to the server
    case InitiatorFlag of
        initiator ->
            io:format("Node (~p, ~p) is the initiator and sends combined PIDs to the server.~n", [X, Y]),
            io:format("Nodo (~p, ~p) con PID ~p invia a ~p: {~p,~p,~p,~p}.~n",
                      [X, Y,self(),FromPid,self(), node_setup_complete, CombinedPIDs, Color]),
                      FromPid ! {self(), node_setup_complete, CombinedPIDs, Color};
        non_initiator ->
            %% Send the combined PIDs to FromPid (the node that sent the setup_node_request)
            FromPid ! {self(), ack_propagation_same_color, CombinedPIDs}
    end,

    %% Continue node loop
    node_loop(X, Y, Color, StartSystemPid, Visited, PropagatedLeaderID, Neighbors).

%% Helper function to wait for ACKs from neighbors and collect PIDs
wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors) ->
    if NeighborsToWaitFor == [] ->
        {ok, AccumulatedPIDs};
    true ->
        receive
            {FromNeighbor, ack_propagation_same_color, NeighborPIDs} ->
                io:format("ACK -- Received ACK from neighbor with same color, PID: ~p, neighbors: ~p~n",
                          [FromNeighbor, NeighborPIDs]),
                RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                NewAccumulatedPIDs = lists:append(AccumulatedPIDs, NeighborPIDs),
                wait_for_ack_from_neighbors(RemainingNeighbors, NewAccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);
            {FromNeighbor, ack_propagation_different_color} ->
                io:format("ACK -- Received ACK from neighbor with different color: ~p~n", [FromNeighbor]),
                RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                wait_for_ack_from_neighbors(RemainingNeighbors, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);
            {FromNeighbor, node_already_visited} ->
                io:format("ACK -- Received node_already_visited from node: ~p.~n", [FromNeighbor]),
                RemainingNeighbors = lists:delete(FromNeighbor, NeighborsToWaitFor),
                wait_for_ack_from_neighbors(RemainingNeighbors, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);

            %% Handle other messages while waiting
            {setup_node_request, SenderColor, PropagatedLeaderID, FromPid} ->
                %% Process the setup_node_request
                if Visited == false andalso Color == SenderColor ->
                    io:format("Node (~p, ~p) has the same color as the requesting node while waiting.~n", [X, Y]),
                    UpdatedVisited = true,
                    UpdatedLeaderID = PropagatedLeaderID,
                    %% Start a new propagation
                    node_loop_propagate(X, Y, Color, StartSystemPid, UpdatedVisited, Neighbors, UpdatedLeaderID, FromPid, non_initiator);
                Visited == true ->
                    io:format("Node (~p, ~p) has already been visited, responding accordingly while waiting.~n", [X, Y]),
                    FromPid ! {self(), node_already_visited};
                true ->
                    io:format("Node (~p, ~p) has a different color, sends only received while waiting.~n", [X, Y]),
                    FromPid ! {self(), ack_propagation_different_color}
                end,
                wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);

            {setup_server_request, FromPid} ->
                %% Process the setup_server_request
                if Visited == true ->
                    io:format("Node (~p, ~p) receives setup_server_request, already visited, responding to server while waiting.~n", [X, Y]),
                    FromPid ! {self(), node_already_visited};
                true ->
                    io:format("Node (~p, ~p) receives setup_server_request, not visited, starting propagation while waiting.~n", [X, Y]),
                    UpdatedVisited = true,
                    node_loop_propagate(X, Y, Color, StartSystemPid, UpdatedVisited, Neighbors, LeaderID, FromPid, initiator)
                end,
                wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors);

            _Other ->
                io:format("Node (~p, ~p) received an unhandled message while waiting.~n", [X, Y]),
                wait_for_ack_from_neighbors(NeighborsToWaitFor, AccumulatedPIDs, X, Y, Color, StartSystemPid, Visited, LeaderID, Neighbors)
        after 5000 ->
            io:format("Timeout while waiting for ACKs from neighbors: ~p~n", [NeighborsToWaitFor]),
            {ok, AccumulatedPIDs}
        end
    end.

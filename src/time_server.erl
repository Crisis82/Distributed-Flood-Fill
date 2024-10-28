%% time-server.erl
-module(time_server).
-export([start/1]).

start(Nodes) ->
    spawn(fun() -> sync_time(Nodes) end).

sync_time(Nodes) ->
    Time = time(),
    lists:foreach(
        fun({_, _, Pid}) -> Pid ! {time, Time} end,
        Nodes
    ),
    %% 3 minuti
    Timeout = 3 * 60 * 1000,
    timer:sleep(Timeout),

    sync_time(Nodes).

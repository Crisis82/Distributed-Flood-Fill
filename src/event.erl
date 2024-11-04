%% event.erl
-module(event).
-export([new/0, greater/2]).
-include("event.hrl").

new() ->
    #event{timestamp = erlang:time(), id = erlang:unique_integer([monotonic])}.

greater(T1, T2) ->
    if
        T1#event.timestamp > T2#event.timestamp ->
            true;
        T1#event.timestamp == T2#event.timestamp ->
            T1#event.id > T2#event.id;
        true ->
            false
    end.

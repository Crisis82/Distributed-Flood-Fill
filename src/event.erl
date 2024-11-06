%% event.erl
-module(event).
-export([new/3, greater/2]).
-include("event.hrl").

new(Type, Color, LeaderID) ->
    #event{
        timestamp = erlang:time(),
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

greater(T1, T2) ->
    if
        T1#event.timestamp > T2#event.timestamp ->
            false;
        T1#event.timestamp =:= T2#event.timestamp ->
            T1#event.id > T2#event.id;
        true ->
            true
    end.

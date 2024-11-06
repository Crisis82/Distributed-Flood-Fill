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

%% Checks if T1 is more recent than T2
greater(T1, T2) ->
    if
        % If timestamps are equal (concurrent operation), check priority by id
        T1#event.timestamp =:= T2#event.timestamp ->
            T1#event.id > T2#event.id;
        true ->
            T1#event.timestamp > T2#event.timestamp
    end.

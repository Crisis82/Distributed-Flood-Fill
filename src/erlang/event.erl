-module(event).
-export([new/3, new_with_timestamp/4, greater/2]).
-include("includes/event.hrl").

% Funzione originale per creare un evento con timestamp automatico
new(Type, Color, LeaderID) ->
    #event{
        timestamp = erlang:time(),
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

% Nuova funzione per creare un evento con un timestamp specifico
new_with_timestamp(Type, Color, LeaderID, Timestamp) ->
    #event{
        timestamp = Timestamp,
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
            T2#event.id > T1#event.id;
        true ->
            true
    end.

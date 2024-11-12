-module(event).

%% Module Description:
%% This module provides functions to create and compare event records.
%% Events are represented with timestamps, unique IDs, types, colors, and origins.
%% Functions include creating events with automatic and specified timestamps, 
%% as well as comparing two events to determine temporal order.

%% Creates a new event with an automatically generated timestamp
%% @doc Creates a new event with a current system-generated timestamp.
%% @spec new(atom(), atom(), pid()) -> #event{}
%% @param Type The event type (atom).
%% @param Color The color associated with the event (atom).
%% @param LeaderID The PID of the leader that created this event.
%% @return Returns an #event{} record with populated fields.
%%
%% Preconditions:
%% - Type must be a valid atom representing an event type.
%% - Color must be a valid atom representing a color.
%% - LeaderID must be a PID representing an active leader.
%%
%% Postconditions:
%% - Returns an #event{} record with a unique ID and current timestamp.

-export([new/3, new_with_timestamp/4, greater/2]).
-include("includes/event.hrl").

new(Type, Color, LeaderID) ->
    #event{
        timestamp = erlang:time(),
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

%% Creates a new event with a specified timestamp
%% @doc Creates an event with a user-specified timestamp, useful for testing or event restoration.
%% @spec new_with_timestamp(atom(), atom(), pid(), erlang:time()) -> #event{}
%% @param Type The event type (atom).
%% @param Color The color associated with the event (atom).
%% @param LeaderID The PID of the leader that created this event.
%% @param Timestamp A specific timestamp for the event.
%% @return Returns an #event{} record with populated fields.
%%
%% Preconditions:
%% - Type must be a valid atom representing an event type.
%% - Color must be a valid atom representing a color.
%% - LeaderID must be a PID representing an active leader.
%% - Timestamp must be a valid timestamp tuple in the form {MegaSecs, Secs, MicroSecs}.
%%
%% Postconditions:
%% - Returns an #event{} record with a unique ID and the specified timestamp.
new_with_timestamp(Type, Color, LeaderID, Timestamp) ->
    #event{
        timestamp = Timestamp,
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

%% Compares two events by timestamp and ID to determine temporal order
%% @doc Determines if event T1 is temporally "less than" event T2 based on timestamp and ID.
%% @spec greater(#event{}, #event{}) -> boolean()
%% @param T1 The first event to compare.
%% @param T2 The second event to compare.
%% @return true if T2 is more recent or, if timestamps are equal, T2’s ID is greater; false otherwise.
%%
%% Preconditions:
%% - T1 and T2 must be #event{} records with `timestamp` and `id` fields defined.
%%
%% Postconditions:
%% - Returns true if T2 is temporally "greater" than T1 based on timestamp and ID logic.
%% - Returns false if T1 is "greater" than T2.
greater(T1, T2) ->
    if
        T1#event.timestamp > T2#event.timestamp ->
            false;
        T1#event.timestamp =:= T2#event.timestamp ->
            T2#event.id > T1#event.id;
        true ->
            true
    end.

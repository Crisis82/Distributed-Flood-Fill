-module(event).

%% --------------------------------------------------------------------
%% Module: event
%% Description:
%% The `event` module defines functions for creating, managing, and comparing
%% event records in a distributed system. Events represent system actions or
%% changes and are used to ensure consistency across distributed components.
%% Each event includes a timestamp, unique ID, type, associated color, and the
%% originating leader's PID.
%%
%% Key Responsibilities:
%% - **Event Creation:** Provides functions to create events with either the
%%   current system timestamp or a specified timestamp, ensuring flexibility for
%%   real-time operations and testing.
%%
%% - **Event Comparison:** Implements a function to compare two events, allowing
%%   the system to determine temporal order based on timestamp and unique ID.
%%
%% Functions:
%% - `new/3`: Creates a new event with a current timestamp and a unique ID.
%% - `new_with_timestamp/4`: Allows creation of an event with a specified timestamp,
%%   useful for testing or event history reconstruction.
%% - `greater/2`: Compares two events to determine temporal order, returning `true`
%%   if the second event is more recent or if it has a higher ID when timestamps are equal.
%%
%% Usage:
%% - Use `new/3` for creating real-time events, and `new_with_timestamp/4` for events
%%   that require a predefined timestamp.
%% - `greater/2` is used in situations where temporal ordering of events is needed,
%%   such as conflict resolution in distributed operations.
%%
%% Notes:
%% - This module relies on Erlang’s monotonic integer generation and the current
%%   system time to uniquely identify and timestamp each event.
%% - Events are defined in an `#event{}` record structure, typically included from
%%   an external header file.
%%
%% --------------------------------------------------------------------

-export([new/3, new_with_timestamp/4, greater/2]).
-include("includes/event.hrl").

%% --------------------------------------------------------------------
%% Function: new/3
%% Description:
%% Creates a new event record with an automatically generated timestamp.
%% Each event includes a unique ID, type, associated color, and the PID
%% of the leader that originated the event. This function is used for real-time
%% event creation within the system.
%%
%% Input:
%% - Type: An atom representing the type of event (e.g., `update`, `merge`).
%% - Color: An atom representing the color associated with the event.
%% - LeaderID: The PID of the leader process that created this event.
%%
%% Preconditions:
%% - Type must be a valid atom representing an event type.
%% - Color must be a valid atom representing a color.
%% - LeaderID must be a valid PID representing an active leader.
%%
%% Output:
%% - Returns an #event{} record with the current timestamp, a unique ID,
%%   and the specified type, color, and origin (LeaderID).
%%
%% Usage:
%% - This function is typically called when a new event needs to be recorded
%%   with the current system time, ensuring a unique timestamp and ID.
%% --------------------------------------------------------------------
new(Type, Color, LeaderID) ->
    #event{
        timestamp = erlang:time(),
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

%% --------------------------------------------------------------------
%% Function: new_with_timestamp/4
%% Description:
%% Creates a new event record with a specified timestamp. This function
%% is useful for testing or event restoration purposes, where precise control
%% over the timestamp is required.
%%
%% Input:
%% - Type: An atom representing the type of event (e.g., `update`, `merge`).
%% - Color: An atom representing the color associated with the event.
%% - LeaderID: The PID of the leader process that created this event.
%% - Timestamp: A user-specified timestamp in the form {MegaSecs, Secs, MicroSecs}.
%%
%% Preconditions:
%% - Type must be a valid atom representing an event type.
%% - Color must be a valid atom representing a color.
%% - LeaderID must be a valid PID representing an active leader.
%% - Timestamp must be a valid tuple in the form {MegaSecs, Secs, MicroSecs}.
%%
%% Output:
%% - Returns an #event{} record with the specified timestamp, a unique ID,
%%   and the specified type, color, and origin (LeaderID).
%%
%% Usage:
%% - Use this function when creating events with controlled timestamps, such
%%   as for testing or recreating historical events.
%% --------------------------------------------------------------------
new_with_timestamp(Type, Color, LeaderID, Timestamp) ->
    #event{
        timestamp = Timestamp,
        id = erlang:unique_integer([monotonic]),
        type = Type,
        color = Color,
        from = LeaderID
    }.

%% --------------------------------------------------------------------
%% Function: greater/2
%% Description:
%% Compares two events, T1 and T2, to determine their temporal order
%% based on timestamp and ID. If T1 has an earlier timestamp than T2,
%% it is considered "less than." If timestamps are equal, the unique ID
%% is used to break the tie.
%%
%% Input:
%% - T1: The first event record (#event{}) to compare.
%% - T2: The second event record (#event{}) to compare.
%%
%% Preconditions:
%% - T1 and T2 must be #event{} records, each containing `timestamp` and `id` fields.
%%
%% Output:
%% - Returns `true` if T2 is temporally "greater" than T1, i.e., T2 is either more recent
%%   (later timestamp) or, if timestamps are equal, has a greater ID than T1.
%% - Returns `false` if T1 is temporally "greater" than T2.
%%
%% Usage:
%% - This function is useful for determining the correct ordering of events in a
%%   distributed system, ensuring consistent event processing.
%% --------------------------------------------------------------------
greater(T1, T2) ->
    if
        T1#event.timestamp > T2#event.timestamp -> false;
        T1#event.timestamp =:= T2#event.timestamp -> T2#event.id > T1#event.id;
        true -> true
    end.

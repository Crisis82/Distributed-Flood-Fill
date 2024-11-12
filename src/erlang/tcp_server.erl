%% --------------------------------------------------------------------
%% Module: tcp_server
%% Description:
%% The `tcp_server` module implements a TCP server that listens for incoming client 
%% connections to control a distributed node system. It processes commands received from 
%% clients, such as changing a node’s color or terminating a node, by parsing the incoming 
%% data and dispatching messages to the appropriate process.
%%
%% Key Features:
%% - Starts a TCP server and listens on an available port.
%% - Processes client commands to change node colors or terminate nodes.
%% - Validates and converts incoming message parameters to Erlang PIDs and color atoms.
%% - Supports real-time interaction with nodes for dynamic control.
%%
%% Preconditions:
%% - The node and event systems should be initialized and able to process messages.
%% - `grid_visualizer.py` script should be ready to handle visualization commands.
%%
%% Postconditions:
%% - Incoming client messages are processed, and nodes receive appropriate control commands.
%% - A command output is sent back to the client to indicate success or failure.
%%
%% Usage:
%% Use this module to set up a TCP server and control nodes in real-time, 
%% either by changing node colors or terminating specific nodes based on client input.
%% --------------------------------------------------------------------

-module(tcp_server).
-export([start/0, listen/1, loop/1]).

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white]).

%% --------------------------------------------------------------------
%% Function: start/0
%% Description:
%% Starts the TCP server and opens a listening socket on an available port. It spawns 
%% a process to handle each incoming connection and prints the port number for reference.
%%
%% Preconditions:
%% - Network should allow TCP connections on the selected port.
%%
%% Output:
%% - The server listens on a dynamically allocated port and spawns processes 
%%   to handle each connection.
%% --------------------------------------------------------------------
start() ->
    spawn(fun() -> 
        {ok, ListenSocket} = gen_tcp:listen(0, [binary, {packet, 0}, {active, false}]),
        {ok, Port} = inet:port(ListenSocket),
        io:format("Server listening on port ~p~n", [Port]),
        io:format("Command to run: ~n python3 grid_visualizer.py --debug True --port ~p", [Port]),
        listen(ListenSocket)
    end).

%% --------------------------------------------------------------------
%% Function: listen/1
%% Description:
%% Listens for incoming TCP connections and spawns a new process for each client 
%% connection, allowing concurrent client handling.
%%
%% Input:
%% - ListenSocket: The main socket on which the server listens for new connections.
%%
%% Preconditions:
%% - The listening socket must be successfully created and bound to a port.
%%
%% Output:
%% - Spawns a process to handle each client and keeps listening for further connections.
%% --------------------------------------------------------------------
listen(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(fun() -> loop(Socket) end),
    listen(ListenSocket).

%% --------------------------------------------------------------------
%% Function: loop/1
%% Description:
%% Main loop for handling incoming messages from a connected client. Reads 
%% messages from the socket, processes them, and sends responses back to the client.
%%
%% Input:
%% - Socket: The socket connected to the client.
%%
%% Preconditions:
%% - A valid, open socket connected to a client.
%%
%% Output:
%% - Processes the client message, executes the appropriate action, 
%%   and sends a response. Closes the socket when done.
%% --------------------------------------------------------------------
loop(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, BinData} ->
            Data = binary_to_list(BinData),
            CleanData = string:trim(Data),
            Parts = string:split(CleanData, ",", all),
            handle_message(Parts, Socket),
            gen_tcp:close(Socket);
        {error, _Reason} ->
            gen_tcp:close(Socket)
    end.

%% --------------------------------------------------------------------
%% Function: handle_message/2
%% Description:
%% Processes a client message by parsing command parameters and performing actions 
%% such as changing a node's color or terminating a node based on the parsed data.
%%
%% Input:
%% - Message parts as a list, containing a command and its arguments.
%% - Socket: The client socket for sending response messages.
%%
%% Preconditions:
%% - Message parts should conform to expected format for recognized commands.
%%
%% Output:
%% - Sends a response back to the client indicating "ok" for success 
%%   or "error" for invalid commands or parameters.
%% --------------------------------------------------------------------

%% Handle change color command with format: "change_color,ID,Color,HH,MM,SS"
handle_message(["change_color", IdStr, ColorStr, HH_str, MM_str, SS_str], Socket) ->
    case {convert_to_pid(IdStr), convert_to_color(ColorStr)} of
        {{ok, Pid}, {ok, Color}} ->
            Timestamp = parse_time(HH_str, MM_str, SS_str),
            Event = event:new_with_timestamp(color, utils:normalize_color(Color), Pid, Timestamp),
            Pid ! {change_color_request, Event},
            gen_tcp:send(Socket, "ok");
        {{error, _}, _} ->
            gen_tcp:send(Socket, "error");
        {_, {error, _}} ->
            gen_tcp:send(Socket, "error")
    end;

%% Handle kill command with format: "kill,ID,HH,MM,SS"
handle_message(["kill", IdStr, HH_str, MM_str, SS_str], Socket) ->
    case convert_to_pid(IdStr) of
        {ok, Pid} ->
            Timestamp = parse_time(HH_str, MM_str, SS_str),
            Event = event:new_with_timestamp(kill, undefined, Pid, Timestamp),
            Pid ! {kill},
            gen_tcp:send(Socket, "ok");
        {error, _} ->
            gen_tcp:send(Socket, "error")
    end;

%% Handle invalid or unrecognized command
handle_message(_InvalidMessage, Socket) ->
    gen_tcp:send(Socket, "error").

%% --------------------------------------------------------------------
%% Function: convert_to_pid/1
%% Description:
%% Converts a string representation of a PID to an Erlang PID, if valid.
%%
%% Input:
%% - IdStr: The string representation of the PID.
%%
%% Preconditions:
%% - IdStr must be a valid string format representing a PID.
%%
%% Output:
%% - {ok, Pid} if the conversion is successful, or {error, invalid_pid} otherwise.
%% --------------------------------------------------------------------
convert_to_pid(IdStr) ->
    try
        {ok, list_to_pid(IdStr)}
    catch
        error:_ -> {error, invalid_pid}
    end.

%% --------------------------------------------------------------------
%% Function: convert_to_color/1
%% Description:
%% Converts a string to an atom representing a color if it exists in the color palette.
%%
%% Input:
%% - ColorStr: The string representation of the color.
%%
%% Preconditions:
%% - ColorStr should match a valid color in the predefined palette.
%%
%% Output:
%% - {ok, ColorAtom} if the color is valid, or {error, invalid_color} otherwise.
%% --------------------------------------------------------------------
convert_to_color(ColorStr) ->
    ColorAtom = list_to_atom(ColorStr),
    case lists:member(ColorAtom, ?palette) of
        true -> {ok, ColorAtom};
        false -> {error, invalid_color}
    end.

%% --------------------------------------------------------------------
%% Function: parse_time/3
%% Description:
%% Parses strings for hours, minutes, and seconds into a timestamp tuple.
%%
%% Input:
%% - HH_str, MM_str, SS_str: String representations of hours, minutes, and seconds.
%%
%% Preconditions:
%% - Input strings must represent valid integers for time components.
%%
%% Output:
%% - {Hour, Minute, Second} tuple.
%% --------------------------------------------------------------------
parse_time(HH_str, MM_str, SS_str) ->
    {list_to_integer(HH_str), list_to_integer(MM_str), list_to_integer(SS_str)}.

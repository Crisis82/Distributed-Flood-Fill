-module(tcp_server).
-export([start/0, listen/1, loop/1]).

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white, grey]).

% Funzione di avvio del server TCP
start() ->
    spawn(fun() -> 
        {ok, ListenSocket} = gen_tcp:listen(8080, [binary, {packet, 0}, {active, false}]),
        io:format("Server in ascolto su porta 8080~n"),
        listen(ListenSocket)
    end).

% Funzione per ascoltare nuove connessioni
listen(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(fun() -> loop(Socket) end),
    listen(ListenSocket).

% Funzione principale per gestire i messaggi dei client
loop(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, BinData} ->
            Data = binary_to_list(BinData),
            % Rimuove eventuali caratteri di nuova linea o ritorno a capo
            CleanData = string:trim(Data),
            % Divide il messaggio in parti separate da virgola
            Parts = string:split(CleanData, ",", all),
            handle_message(Parts, Socket),
            gen_tcp:close(Socket);
        {error, _Reason} ->
            gen_tcp:close(Socket)
    end.

% Funzione per gestire i diversi tipi di messaggi
handle_message(["change_color", IdStr, ColorStr], Socket) ->
    io:format("Ricevuto comando di cambio colore per ID: ~p e colore: ~p~n", [IdStr, ColorStr]),
    case {convert_to_pid(IdStr), convert_to_color(ColorStr)} of
        {{ok, Pid}, {ok, Color}} ->
            Event = event:new(color, utils:normalize_color(Color), Pid),
            io:format("TCP_SERVER : Invio messaggio {change_color_request, ~p} a ~p~n", [Event, Pid]),
            Pid ! {change_color_request, Event},
            gen_tcp:send(Socket, "ok");
        {{error, _}, _} ->
            io:format("Errore: formato PID non valido ~p~n", [IdStr]),
            gen_tcp:send(Socket, "error");
        {_, {error, _}} ->
            io:format("Errore: colore non valido ~p~n", [ColorStr]),
            gen_tcp:send(Socket, "error")
    end;

handle_message(["kill", IdStr], Socket) ->
    io:format("Ricevuto comando di kill per ID: ~p~n", [IdStr]),
    case convert_to_pid(IdStr) of
        {ok, Pid} ->
            Event = event:new(kill, undefined, Pid),
            io:format("TCP_SERVER : Invio messaggio {kill, ~p} a ~p~n", [Pid, Event]),
            Pid ! {kill},
            gen_tcp:send(Socket, "ok");
        {error, _} ->
            io:format("Errore: formato PID non valido ~p~n", [IdStr]),
            gen_tcp:send(Socket, "error")
    end;

handle_message(_InvalidMessage, Socket) ->
    io:format("Errore: messaggio non riconosciuto~n"),
    gen_tcp:send(Socket, "error").

% Funzione per convertire una stringa in un PID
convert_to_pid(IdStr) ->
    try
        {ok, list_to_pid(IdStr)}
    catch
        error:_ -> {error, invalid_pid}
    end.

% Funzione per convertire una stringa in un colore atomo, verificando che sia nella palette
convert_to_color(ColorStr) ->
    ColorAtom = list_to_atom(ColorStr),
    case lists:member(ColorAtom, ?palette) of
        true -> {ok, ColorAtom};
        false -> {error, invalid_color}
    end.

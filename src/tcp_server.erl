-module(tcp_server).
-export([start/0, listen/1, loop/1]).

-define(palette, [red, green, blue, yellow, orange, purple, pink, brown, black, white]).

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
            case string:split(Data, ",", all) of
                [IdStr, ColorStr] ->
                    io:format("~n~n~nHo ricevuto l'ID: ~p e colore: ~p~n", [IdStr, ColorStr]),
                    case {convert_to_pid(IdStr), convert_to_color(ColorStr)} of
                        {{ok, Pid}, {ok, Color}} ->
                            Pid ! {change_color_request, Color},
                            gen_tcp:send(Socket, "ok");
                        {{error, _}, _} ->
                            io:format("Errore: formato PID non valido ~p~n", [IdStr]),
                            gen_tcp:send(Socket, "error");
                        {_, {error, _}} ->
                            io:format("Errore: colore non valido ~p~n", [ColorStr]),
                            gen_tcp:send(Socket, "error")
                    end;
                _ ->
                    io:format("Errore nella struttura dei dati ricevuti~n"),
                    gen_tcp:send(Socket, "error")
            end,
            gen_tcp:close(Socket);
        {error, _} ->
            gen_tcp:close(Socket)
    end.

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

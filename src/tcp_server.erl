-module(tcp_server).
-export([start/0, loop/1]).

% Funzione di avvio del server TCP

start() ->
    {ok, ListenSocket} = gen_tcp:listen(8080, [binary, {packet, 0}, {active, false}]),
    io:format("Server in ascolto su porta 8080~n"),
    accept(ListenSocket).

accept(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(fun() -> loop(Socket) end),
    accept(ListenSocket).

loop(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, BinData} ->
            Data = binary_to_list(BinData),
            case string:split(Data, ",", all) of
                [IdStr, Color] ->
                    io:format("~n~n~nHo ricevuto l'ID: ~p e colore: ~p~n", [IdStr, Color]),
                    case convert_to_pid(IdStr) of
                        {ok, Pid} ->
                            Pid ! {change_color, Color},
                            gen_tcp:send(Socket, "ok");
                        error ->
                            io:format("Errore: formato PID non valido ~p~n", [IdStr]),
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
        error:_ -> error
    end.
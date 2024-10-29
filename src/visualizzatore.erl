-module(visualizzatore).
-export([start/0, loop/1]).

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
            case binary_to_list(BinData) of
                Data ->
                    %io:format("Ho ricevuto il messaggio: ~p~n", [Data]),

                    % Dividi il messaggio in PidStr e Color
                    [PidStr, Color] = string:split(Data, ",", all),
                    %io:format("Ho ricevuto il messaggio: ~p e ~p~n", [PidStr, Color]),

                    % Converte la stringa PidStr in PID
                    try
                        Pid = list_to_pid(PidStr),
                        io:format("Ho ricevuto il PID: ~p e colore: ~p~n", [Pid, Color]),
                        % Invia il messaggio al PID
                        % Pid ! {change_color, Color},
                        gen_tcp:send(Socket, "ok")
                    catch
                        _:_ -> 
                            io:format("Errore nella conversione del PID~n"),
                            gen_tcp:send(Socket, "error")
                    end;
                _ ->
                    gen_tcp:send(Socket, "error")
            end,
            gen_tcp:close(Socket);
        {error, _} ->
            gen_tcp:close(Socket)
    end.

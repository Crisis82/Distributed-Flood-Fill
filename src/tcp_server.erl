-module(tcp_server).
-export([start/0, loop/1]).

% Funzione di avvio del server TCP
% La funzione start/0 apre una porta TCP (8080) in ascolto e accetta connessioni
start() ->
    % Crea un socket in ascolto sulla porta 8080, configurato per ricevere dati in modalità binaria
    {ok, ListenSocket} = gen_tcp:listen(8080, [binary, {packet, 0}, {active, false}]),
    io:format("Server in ascolto su porta 8080~n"),
    % Chiama la funzione di accettazione delle connessioni
    accept(ListenSocket).

% Funzione di accettazione delle connessioni TCP
% Accetta nuove connessioni in modo ricorsivo e avvia un processo separato per gestirle
accept(ListenSocket) ->
    % Attende una nuova connessione in arrivo
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    % Spawna un nuovo processo per gestire la connessione accettata, chiamando la funzione loop/1
    spawn(fun() -> loop(Socket) end),
    % Continua ad accettare altre connessioni
    accept(ListenSocket).

% Funzione loop/1 per la gestione di una singola connessione
% Riceve un messaggio, lo elabora e invia una risposta al client
loop(Socket) ->
    % Riceve i dati dal socket; attende fino a quando i dati non arrivano
    case gen_tcp:recv(Socket, 0) of
        {ok, BinData} ->
            % Converte i dati binari ricevuti in una lista di caratteri
            Data = binary_to_list(BinData),
            % Divide il messaggio ricevuto (formato "PID,Color") in due parti: PidStr e Color
            case string:split(Data, ",", all) of
                [PidStr, Color] ->
                    % Tenta di convertire la stringa del PID in un PID Erlang
                    try
                        Pid = list_to_pid(PidStr),
                        io:format("Ho ricevuto il PID: ~p e colore: ~p~n", [Pid, Color]),

                        % Invia un messaggio di conferma al client
                        % (Qui è commentato, ma si potrebbe inviare un messaggio al PID)
                        % Pid ! {change_color, Color},

                        % Conferma con "ok" al client
                        gen_tcp:send(Socket, "ok")
                    catch
                        % Gestisce eventuali errori di conversione del PID
                        _:_ ->
                            io:format("Errore nella conversione del PID~n"),
                            % Invia "error" al client in caso di fallimento
                            gen_tcp:send(Socket, "error")
                    end;
                _ ->
                    io:format("Errore nella struttura dei dati ricevuti~n"),
                    % Invio "error" se il formato è errato
                    gen_tcp:send(Socket, "error")
            end,
            % Chiude il socket dopo aver inviato la risposta
            gen_tcp:close(Socket);
        {error, _} ->
            % Gestisce errori di ricezione dei dati e chiude il socket in caso di errore
            gen_tcp:close(Socket)
    end.

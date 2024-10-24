%% visualizer.erl
-module(visualizer).
-export([start_visualizer/1]).

%% Avvio del visualizzatore
start_visualizer(_ServerPid) ->
    %% Inizia il monitoraggio dei cambiamenti nel file nodes_status.txt
    io:format("Visualizer inizia a monitorare il file nodes_status.txt per eventuali cambiamenti...~n"),
    check_for_updates("").

%% Funzione che controlla periodicamente i cambiamenti nel file nodes_status.txt
check_for_updates(PreviousContent) ->
    io:format("Inizio a cercare cambiamenti...~n"),
    %% Leggi il file nodes_status.txt
    case file:read_file("nodes_status.txt") of
        {ok, NewContent} ->
            %% Se il contenuto è cambiato, stampa le nuove informazioni
            if NewContent =/= PreviousContent ->
                io:format("Aggiornamento trovato nel file nodes_status.txt:~n"),
                %% Stampa ogni riga del nuovo contenuto
                Lines = binary:split(NewContent, [<<"\n">>], [global, trim]),
                lists:foreach(fun(Line) ->
                    io:format("~s~n", [Line])
                end, Lines),
                %% Chiama ricorsivamente con il nuovo contenuto
                timer:sleep(2000),  %% Attendi 2 secondi prima di controllare di nuovo
                check_for_updates(NewContent);
            true ->
                %% Se non ci sono cambiamenti, continua a monitorare
                timer:sleep(2000),  %% Attendi 2 secondi prima di controllare di nuovo
                check_for_updates(PreviousContent)
            end;
        {error, _Reason} ->
            io:format("Errore nella lettura del file nodes_status.txt.~n"),
            timer:sleep(2000),  %% Attendi 2 secondi prima di controllare di nuovo
            check_for_updates(PreviousContent)
    end.

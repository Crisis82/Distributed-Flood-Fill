%% time-server.erl
-module(time_server).
-export([start/1]).
-include("node.hrl").

%% start/1
%% Inizia la sincronizzazione del tempo per tutti i nodi in Nodes.
%% Nodes: lista che può contenere sia record 'leader' che record 'node'
start(Nodes) ->
    spawn(fun() -> sync_time(Nodes) end).

%% sync_time/1
%% Invio del messaggio di sincronizzazione del tempo a ciascun nodo o leader
%% - Nodes: lista di elementi che possono essere record 'leader' o 'node'
sync_time(Nodes) ->
    % Ottieni l'ora corrente
    Time = time(),

    % Itera su ogni elemento in Nodes e invia il messaggio di sincronizzazione del tempo
    lists:foreach(
        fun(Element) ->
            % Controlla il tipo di record e ottieni il PID appropriato
            case Element of
                #leader{} ->
                    % Se è un leader, prendi il PID dal nodo interno
                    Pid = Element#leader.node#node.pid;
                #node{} ->
                    % Se è un nodo normale, prendi direttamente il PID
                    Pid = Element#node.pid
            end,
            Pid ! {time, Time}
        end,
        Nodes
    ),

    % Intervallo di timeout di 3 minuti
    Timeout = 3 * 60 * 1000,
    timer:sleep(Timeout),

    % Richiama ricorsivamente per continuare la sincronizzazione
    sync_time(Nodes).


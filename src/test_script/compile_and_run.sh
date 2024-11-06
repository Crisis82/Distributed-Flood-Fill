#!/bin/bash

# Controlla se sono stati forniti esattamente 3 argomenti
if [ "$#" -ne 3 ]; then
    echo "Utilizzo: $0 <N> <M> <from_file>"
    echo "Esempio: $0 7 7 true"
    exit 1
fi

# Assegna gli argomenti alle variabili
N=$1
M=$2
FROM_FILE=$3

# Crea la directory beam_files se non esiste
mkdir -p ../beam_files

# Compila e salva i file .beam in beam_files
erlc -o ../beam_files ../erlang/*.erl

# Avvia la shell Erlang ed esegui il comando start_system:start(N, M, FROM_FILE)
erl -pa ../beam_files -eval "start_system:start($N, $M, $FROM_FILE)."

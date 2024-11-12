#!/bin/bash

# Controlla se è stato fornito esattamente un argomento per la porta
if [ "$#" -ne 1 ]; then
    echo "Utilizzo: $0 <port>"
    echo "Esempio: $0 43935"
    exit 1
fi

# Assegna l'argomento alla variabile PORT
PORT=$1

# Esegui il comando Python con la porta specificata
echo "Eseguendo il comando: python3 grid_visualizer.py --debug False --port $PORT --leaders_file "../data/leaders_data.json" --nodes_file "../data/nodes_data.json" --img_path "../data/static/matrix.png" --notebook_path "../data/history_log.ipynb" --snapshots_folder "../data/static/default_test/snapshots""
python3 ../data/grid_visualizer.py --debug False --port $PORT --leaders_file "../data/leaders_data.json" --nodes_file "../data/nodes_data.json" --img_path "../data/static/matrix.png" --notebook_path "../data/history_log.ipynb" --snapshots_folder "../data/static/default_test/snapshots"

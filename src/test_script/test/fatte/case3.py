import argparse
import json
import os
import socket
import time
import random
import psutil
import shutil
from datetime import datetime

# Percorso della directory principale


def elimina_DB():
    db_dir = os.path.join(os.path.dirname(__file__), "..", "DB")
    # Verifica che la directory esista
    if os.path.exists(db_dir):
        # Scorri tutte le directory all'interno di ../DB
        for directory in os.listdir(db_dir):
            dir_path = os.path.join(db_dir, directory)
            # Rimuovi solo se è una directory
            if os.path.isdir(dir_path):
                shutil.rmtree(dir_path)
                print(f"Rimossa la directory: {dir_path}")
        print("Tutte le directory all'interno di ../DB sono state rimosse.")
    else:
        print("La directory ../DB non esiste.")


# Percorsi relativi ai file JSON
LEADERS_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "leaders_data.json")
NODES_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "nodes_data.json")
# Server Erlang
HOST = 'localhost'
PORT = 8080

# Lista di colori disponibili per il test
COLORS = ["red", "green", "blue", "yellow", "purple"]

TAVOLOZZA = [
    "red",
    "blue",
    "yellow",
    "red",
    "purple",
    "purple",
    "blue",
    "purple",
    "yellow",
    "blue",
    "purple",
    "yellow",
    "yellow",
    "green",
    "purple",
    "yellow",
    "yellow",
    "red",
    "yellow",
    "blue",
    "blue",
    "yellow",
    "red",
    "purple",
    "purple"
]

# Funzione per generare un file colori per una matrice NxM
def generate_colors_file(N, M, random):
    
    if random:
        colors = [random.choice(COLORS) for _ in range(N * M)]
    else:
        colors = TAVOLOZZA
    colors_filepath = os.path.join(os.path.dirname(__file__), "..", "config", "colors.txt")
    with open(colors_filepath, "w") as file:
        file.write("\n".join(colors))
    print(f"File colors.txt generato con {N}*{M} colori.")
    
    print("\nPrima di eseguire lo script assicurati di eseguire su un altro terminale:\n")
    
    print(f"./compile_and_run.sh {N} {M} true")
    
    print("\nE poi esegui su un altro terminale il seguente comando:\n")
    print("./start_visualizer.sh")
    
    input("\nPremi Invio una volta completati i comandi nel terminale Erlang per continuare...")

# Funzione per caricare i dati dei leader da un file JSON
def load_leaders_data():
    try:
        with open(LEADERS_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Errore nel caricamento del file JSON dei leader.")
        return []

# Funzione per caricare i dati dei nodi da un file JSON
def load_nodes_data():
    try:
        with open(NODES_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Errore nel caricamento del file JSON dei nodi.")
        return []

# Funzione per inviare una richiesta di cambio colore al server Erlang tramite TCP
def send_color_change_request(pid, color, time):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            
            
            message = f"change_color,{pid},{color},{time.hour},{time.minute},{time.second}"
            print(f"Inviando il messaggio di cambio colore: {message}")
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            print(f"Risposta dal server: {response}")
            return response == "ok"
    except Exception as e:
        print(f"Errore durante l'invio del comando: {e}")
        return False

# Funzione per inviare una richiesta di kill al server Erlang tramite TCP
def send_kill_request(pid):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            message = f"kill,{pid}"
            print(f"Inviando il messaggio di kill: {message}")
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            print(f"Risposta dal server: {response}")
            return response == "ok"
    except Exception as e:
        print(f"Errore durante l'invio del comando: {e}")
        return False

# Funzione per eseguire operazioni multiple di cambio colore e kill
def perform_multiple_operations(num_color_changes, num_kills, interval):
    nodes_data = load_nodes_data()

    # Ottieni l'orario corrente come tripla (Hour, Minute, Second)
    time1 = datetime.now()
    time2 = datetime.now()

    for _ in range(num_color_changes + num_kills):  # Esegue il numero totale di operazioni
        # Seleziona un nodo casuale
        node = random.choice(nodes_data)
        pid = node["pid"]

        # Esegui operazioni di cambio colore o di kill
        if num_color_changes > 0 and (random.choice(["change_color", "kill"]) == "change_color" or num_kills == 0):
            color = random.choice(COLORS)
            success = send_color_change_request(pid, color, time)
            if success:
                print(f"Colore cambiato per PID {pid} a {color}")
            else:
                print(f"Errore nel cambio colore per PID {pid}")
            num_color_changes -= 1
        elif num_kills > 0:
            success = send_kill_request(pid)
            if success:
                print(f"Nodo {pid} terminato con successo")
            else:
                print(f"Errore nella terminazione del nodo {pid}")
            num_kills -= 1

        # Pausa tra le operazioni
        time.sleep(2)


# Funzione per eseguire operazioni multiple di cambio colore e kill
def perform_multiple_operations(interval):
    nodes_data = load_nodes_data()
    
    time1 = datetime.now()
    time.sleep(1)
    time2 = datetime.now()
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time2),
        (get_pid_by_coordinates(nodes_data, 1, 3), "green", time1),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(1)


def get_pid_by_coordinates(data, x, y):
    # Supponendo che il `pid` desiderato sia presente nei nodi o nei cluster adiacenti
    for node in data:
        node_x, node_y = node["x"] , node["y"]
        if node_x == x and node_y == y:
            return node["pid"]

    return None  # Se non trovato


# Funzione principale
def main(N, M, num_color_changes, num_kills, interval):
    # Utilizza la funzione per liberare la porta 8080
    if kill_process_on_port(8080):
        print("Porta 8080 liberata con successo.")
    else:
        print("La porta 8080 era già libera o il processo non può essere terminato.")

    elimina_DB()

    # Genera il file colors.txt
    generate_colors_file(N, M, False)

    # Esegui le operazioni una volta che l'utente conferma di aver avviato Erlang
    # perform_multiple_operations(num_color_changes, num_kills, interval)
    perform_multiple_operations(interval)


def kill_process_on_port(port):
    # Cerca tutti i processi che utilizzano le porte
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            for conn in proc.net_connections(kind='inet'):
                if conn.laddr.port == port:
                    print(f"Trovato processo '{proc.info['name']}' con PID {proc.info['pid']} sulla porta {port}. Terminando il processo.")
                    proc.terminate()
                    proc.wait(timeout=3)
                    return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    print(f"Nessun processo trovato sulla porta {port}.")
    return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Script per gestire nodi e leader in Erlang")
    parser.add_argument("N", type=int, help="Numero di righe della matrice")
    parser.add_argument("M", type=int, help="Numero di colonne della matrice")
    parser.add_argument("num_color_changes", type=int, help="Numero di richieste di cambio colore")
    parser.add_argument("num_kills", type=int, help="Numero di richieste di kill")
    parser.add_argument("interval", type=float, help="Intervallo di tempo tra le operazioni, in secondi")

    args = parser.parse_args()
    main(args.N, args.M, args.num_color_changes, args.num_kills, args.interval)

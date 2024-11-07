import json
import os
import socket
import time
import random
import psutil
import shutil
from datetime import datetime, timedelta

# Percorso della directory principale

def elimina_DB():
    db_dir = os.path.join(os.path.dirname(__file__), "..", "DB")
    if os.path.exists(db_dir):
        for directory in os.listdir(db_dir):
            dir_path = os.path.join(db_dir, directory)
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
    colors_filepath = os.path.join(os.path.dirname(__file__), "..", "..", "config", "colors.txt")
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
def send_color_change_request(pid, color, timestamp):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            message = f"change_color,{pid},{color},{timestamp.hour},{timestamp.minute},{timestamp.second}"
            print(f"Inviando il messaggio di cambio colore: {message}")
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            print(f"Risposta dal server: {response}")
            return response == "ok"
    except Exception as e:
        print(f"Errore durante l'invio del comando: {e}")
        return False

def get_pid_by_coordinates(data, x, y):
    # Supponendo che il `pid` desiderato sia presente nei nodi o nei cluster adiacenti
    for node in data:
        node_x, node_y = node["x"] , node["y"]
        if node_x == x and node_y == y:
            return node["pid"]

    return None  # Se non trovato

# Funzione per liberare la porta
def kill_process_on_port(port):
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


def too_old():
    nodes_data = load_nodes_data()
    
    time1 = datetime.now()
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time1),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1 - timedelta(milliseconds=5000)),
    ]

    for i in range(len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid, color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(1)

# Funzione per eseguire operazioni multiple di cambio colore e kill
def case1():
    nodes_data = load_nodes_data()
    
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(4)

# Funzione per eseguire operazioni multiple di cambio colore e kill
def case2():
    nodes_data = load_nodes_data()
    
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "pink", time1),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(4)

# Funzione per eseguire operazioni multiple di cambio colore e kill
def case3():
    nodes_data = load_nodes_data()
    
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
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

def merge_successivo():
    nodes_data = load_nodes_data()
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 1, 1), "pink", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 2, 2), "pink", datetime.now()),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(0.5)

def change_color_during_merge():
    nodes_data = load_nodes_data()
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 3, 4), "purple", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 5), "pink", datetime.now() + timedelta(milliseconds=1000)),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(0.5)    


# DA FINIRE

"""
def change_color_before_merge():
    nodes_data = load_nodes_data()
    
    operations =[
        (get_pid_by_coordinates(nodes_data, 3, 4), "purple", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 5), "pink", datetime.now() - timedelta(milliseconds=100)),
    ]

    for i in range(0, len(operations)):  # Esegue il numero totale di operazioni
        operation = operations[i]
        pid , color, t = operation
        send_color_change_request(pid, color, t)
        # Pausa tra le operazioni
        time.sleep(0.1)    
"""

def main():
    N, M = 5, 5  # Dimensioni della matrice
    if kill_process_on_port(8080):
        print("Porta 8080 liberata con successo.")
    else:
        print("La porta 8080 era già libera o il processo non può essere terminato.")

    elimina_DB()

    # Genera il file colors.txt
    generate_colors_file(N, M, False)

    # Chiede all'utente quale funzione eseguire
    print("Scegli un'operazione da eseguire:")
    print("1. too_old")
    print("2. case1")
    print("3. case2")
    print("4. case3")
    print("5. merge_successivo")
    print("6. change_color_during_merge")

    choice = input("Inserisci il numero dell'operazione desiderata: ")

    if choice == "1":
        too_old()
    elif choice == "2":
        case1()
    elif choice == "3":
        case2()
    elif choice == "4":
        case3()
    elif choice == "5":
        merge_successivo()
    elif choice == "6":
        change_color_during_merge()
    else:
        print("Scelta non valida. Uscita dal programma.")

if __name__ == "__main__":
    main()

if __name__ == "__main__":
    main()

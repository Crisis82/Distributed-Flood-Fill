import json
import os
import socket
import time
import random

# Percorsi relativi ai file JSON
LEADERS_FILE = os.path.join(os.path.dirname(__file__), "..","data", "leaders_data.json")
NODES_FILE = os.path.join(os.path.dirname(__file__), "..", "data","nodes_data.json")

# Server Erlang
HOST = 'localhost'
PORT = 8080

# Lista di colori disponibili per il test
COLORS = ["red", "green", "blue", "yellow", "purple", "grey"]

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
def send_color_change_request(pid, color):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            message = f"change_color,{pid},{color}"
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
def perform_multiple_operations():
    nodes_data = load_nodes_data()

    for _ in range(10):  # Esegue 10 operazioni casuali
        # Seleziona un nodo casuale
        node = random.choice(nodes_data)
        pid = node["pid"]

        # Alterna tra `change_color` e `kill`
        if random.choice(["change_color", "kill"]) == "change_color":
            color = random.choice(COLORS)
            success = send_color_change_request(pid, color)
            if success:
                print(f"Colore cambiato per PID {pid} a {color}")
            else:
                print(f"Errore nel cambio colore per PID {pid}")
        else:
            success = send_kill_request(pid)
            if success:
                print(f"Nodo {pid} terminato con successo")
            else:
                print(f"Errore nella terminazione del nodo {pid}")

        # Pausa tra le operazioni
        time.sleep(0.2)

# Chiama la funzione per eseguire operazioni miste
if __name__ == "__main__":
    perform_multiple_operations()

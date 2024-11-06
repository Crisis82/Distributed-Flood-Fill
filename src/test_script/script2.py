import json
import os
import socket
import time
import random
import psutil
import shutil

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
LEADERS_FILE = os.path.join(os.path.dirname(__file__), "..","data", "leaders_data.json")
NODES_FILE = os.path.join(os.path.dirname(__file__), "..", "data","nodes_data.json")

# Server Erlang
HOST = 'localhost'
PORT = 8080

# Lista di colori disponibili per il test
COLORS = ["red", "green", "blue", "yellow", "purple", "grey"]

# Funzione per generare un file colori per una matrice NxM
def generate_colors_file(N, M):
    colors = [random.choice(COLORS) for _ in range(N * M)]
    colors_filepath = os.path.join(os.path.dirname(__file__), ".." , "config" , "colors.txt")
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

# Funzione principale
def main():
    # Utilizza la funzione per liberare la porta 8080
    if kill_process_on_port(8080):
        print("Porta 8080 liberata con successo.")
    else:
        print("La porta 8080 era già libera o il processo non può essere terminato.")

    elimina_DB()

    # Chiedi all'utente di inserire i valori di N e M
    N = int(input("Inserisci il numero di righe (N): "))
    M = int(input("Inserisci il numero di colonne (M): "))

    # Genera il file colors.txt
    generate_colors_file(N, M)

    # Esegui le operazioni una volta che l'utente conferma di aver avviato Erlang
    perform_multiple_operations()


def kill_process_on_port(port):
    # Cerca tutti i processi che utilizzano le porte
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            for conn in proc.net_connections(kind='inet'):  # Usa net_connections() al posto di connections()
                # Se trova la porta 8080 in uso, termina il processo
                if conn.laddr.port == port:
                    print(f"Trovato processo '{proc.info['name']}' con PID {proc.info['pid']} sulla porta {port}. Terminando il processo.")
                    proc.terminate()  # Prova a terminare il processo
                    proc.wait(timeout=3)  # Attendi che il processo termini
                    return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    print(f"Nessun processo trovato sulla porta {port}.")
    return False




# Esegue il programma principale
if __name__ == "__main__":
    main()

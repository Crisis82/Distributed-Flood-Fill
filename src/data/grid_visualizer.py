from flask import Flask, render_template_string, send_file, request, redirect, url_for
from flask_socketio import SocketIO
from matplotlib.figure import Figure
from matplotlib.patches import Rectangle
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import json
import numpy as np
import os
import threading
from matplotlib.colors import rgb_to_hsv
import socket
import numpy as np
import hashlib
import nbformat
from nbformat.v4 import new_notebook, new_code_cell, new_markdown_cell
import time
from IPython.display import Image

# Path del notebook
notebook_path = "history_log.ipynb"

# Variabile per memorizzare l'hash dei leader data precedenti
last_leader_data_hash = None

def hash_data(data):
    """Calcola un hash unico per i dati dati."""
    return hashlib.md5(json.dumps(data, sort_keys=True).encode()).hexdigest()

# Funzione per pulire il notebook all'avvio
def clear_notebook():
    """Svuota il file history_log.ipynb all'avvio dello script."""
    empty_notebook = new_notebook()
    nbformat.write(empty_notebook, notebook_path)
    print(f"Notebook {notebook_path} pulito.")

# Funzione per loggare il cambiamento nel notebook
def log_change_notebook(pid, color, image_path):
    # Crea una stringa con timestamp, comando e il percorso dell’immagine
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    markdown_text = f"### Cambiamento: {timestamp}\n- **PID**: {pid}\n- **Color**: {color}\n- **Image Path**: `{image_path}`"

    # Carica o crea il notebook
    try:
        notebook = nbformat.read(notebook_path, as_version=4)
    except FileNotFoundError:
        notebook = new_notebook()

    # Aggiungi una cella di importazione solo se non è già presente
    if not any("from IPython.display import display, Image" in cell.source for cell in notebook.cells):
        import_cell = new_code_cell("from IPython.display import display, Image")
        notebook.cells.insert(0, import_cell)

    # Aggiungi una cella Markdown per descrivere il cambiamento
    notebook.cells.append(new_markdown_cell(markdown_text))

    # Aggiungi una cella di codice per visualizzare l'immagine
    code_text = f"display(Image(filename='{image_path}'))"
    notebook.cells.append(new_code_cell(code_text))

    # Salva il notebook aggiornato
    nbformat.write(notebook, notebook_path)
    print(f"Cambiamento registrato nel notebook: {notebook_path}")

def custom_rgb_to_hsv(rgb):
    r, g, b = rgb
    max_c = max(r, g, b)
    min_c = min(r, g, b)
    delta = max_c - min_c

    # Hue calculation
    if delta == 0:
        h = 0
    elif max_c == r:
        h = (g - b) / delta % 6
    elif max_c == g:
        h = (b - r) / delta + 2
    elif max_c == b:
        h = (r - g) / delta + 4
    h *= 60  # Convert to degrees

    # Saturation calculation
    s = 0 if max_c == 0 else delta / max_c

    # Value calculation
    v = max_c

    return np.array([h, s, v])

def is_dark_color(rgb):
    if rgb == (0, 0, 1):  # Caso speciale per il blu scuro
        return True
    else:
        hsv = custom_rgb_to_hsv(rgb)
        return hsv[2] < 0.9  # Luminosità sotto 0.9 è considerata scura


# Inizializza l'app Flask e configura il supporto WebSocket con SocketIO
app = Flask(__name__)
socketio = SocketIO(app)  # SocketIO supporta aggiornamenti in tempo reale

# Percorsi dei file
LEADERS_FILE = "leaders_data.json"  # File JSON con i dati dei leader dei cluster
NODES_FILE = "nodes_data.json"      # File JSON con i dati dei nodi
IMG_PATH = "static/matrix.png"      # Percorso per salvare l'immagine della matrice

# Funzione per caricare i dati dei leader da un file JSON
# Output:
# - Restituisce un dizionario con le informazioni sui leader e i loro nodi.
def load_leaders_data():
    try:
        with open(LEADERS_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Errore nel caricamento del file JSON dei leader.")
        return []


# Funzione per caricare i dati dei nodi da un file JSON
# Output:
# - Restituisce un dizionario con le informazioni sui nodi, incluse coordinate e pid.
def load_nodes_data():
    try:
        with open(NODES_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Errore nel caricamento del file JSON dei nodi.")
        return []

# Funzione per ottenere il colore di un nodo basato sul suo leader
# Input:
# - pid: ID del nodo di cui vogliamo conoscere il colore
# - leaders_data: dizionario che contiene i leader e i nodi associati
# Output:
# - Restituisce il colore (stringa) del nodo se associato a un leader, altrimenti "grey".
def get_node_color(pid, leaders_data):
    # Cerca il nodo per il PID e restituisce il suo colore
    for leader_data in leaders_data:
        if leader_data["leader_id"] == pid:
            return leader_data["color"]
        for node_pid in leader_data["nodes"]:
            if node_pid == pid:
                return leader_data["color"]
    return "grey"  # Default a grigio se il nodo non è trovato

import sys

# Controlla se il programma è avviato in modalità debug
DEBUG_MODE = "--debug" in sys.argv

def draw_matrix(output_path=IMG_PATH):
    
    global last_leader_data_hash
    
    # Carica i dati dei leader e dei nodi
    leaders_data = load_leaders_data()
    
    # Calcola l'hash dei dati dei leader
    current_leader_data_hash = hash_data(leaders_data)
    
    # Controlla se i dati sono cambiati
    if current_leader_data_hash == last_leader_data_hash:
        print("I dati dei leader non sono cambiati. Salto il disegno della matrice.")
        return  # Esci dalla funzione senza disegnare
    
    # Aggiorna l'hash dell'ultimo leader_data
    last_leader_data_hash = current_leader_data_hash
    
    nodes_data = load_nodes_data()
    
    output_path = f"static/default_test/snapshots/matrix_{time.strftime('%Y%m%d_%H%M%S')}.png"
    print(f"Disegno matrice in {output_path}!")
    
    
    # Creiamo un set dei PID dei leader
    leader_pids = {leader_data["leader_id"] for leader_data in leaders_data}
    
    # Trova le dimensioni massime della griglia
    max_x = max(node["x"] for node in nodes_data)
    max_y = max(node["y"] for node in nodes_data)

    # Crea la figura di Matplotlib
    fig = Figure(figsize=(8, 8))
    ax = fig.add_subplot(111)
    
    # Configura i tick per la griglia
    ax.set_xticks(np.arange(0, max_y + 1, 1))
    ax.set_yticks(np.arange(0, max_x + 1, 1))
    ax.tick_params(left=False, bottom=False, labelleft=False, labelbottom=False)
    ax.grid(False)
    
    # Crea una mappa di posizione per i nodi
    position_map = {(node["x"], node["y"]): node["pid"] for node in nodes_data}

    # Disegna ogni nodo
    for node in nodes_data:
        x, y, pid = node["x"], node["y"], node["pid"]
        color = get_node_color(pid, leaders_data)
        rgb = color_to_rgb(color)

        # Aggiunge un rettangolo per il nodo
        ax.add_patch(Rectangle((y - 1, max_x - x), 1, 1, color=rgb, ec="black"))
        
        # Disegna connessioni tra nodi dello stesso cluster
        draw_cluster_connections(ax, x, y, pid, position_map, leaders_data, max_x, max_y)

        # Determina il colore del testo
        text_color = "white" if is_dark_color(rgb) else "black"

        # Aggiunge le coordinate del nodo
        ax.text(y - 0.5, max_x - x + 0.3, f"({x},{y})", ha="center", va="center", color=text_color, fontsize=8, weight="bold")

        # Aggiunge il PID in modalità debug
        if DEBUG_MODE:
            ax.text(y - 0.5, max_x - x + 0.7, f"{pid}", ha="center", va="center", color=text_color, fontsize=8, weight="bold")

        # **Aggiunge la "L" se il nodo è un leader**
        if pid in leader_pids:
            label_color = "white" if is_dark_color(rgb) else "black"
            ax.text(y - 0.5, max_x - x + 0.5, "L", ha="center", va="center", color=label_color, fontsize=14, weight="bold")

    # Imposta i limiti della griglia
    ax.set_xlim(0, max_y)
    ax.set_ylim(0, max_x)
    
    # Salva l'immagine della matrice
    fig.savefig(output_path, bbox_inches='tight', pad_inches=0)
    fig.savefig("static/matrix.png", bbox_inches='tight', pad_inches=0)
    fig.clear()
    
    # Logga il cambiamento nel notebook solo se l'immagine è stata creata
    log_change_notebook(pid="leader_pid", color="color", image_path=output_path)  # Passa pid e color effettivi se disponibili

    
    return fig

# Funzione per trovare il leader di un nodo basato sul suo pid
# Input:
# - pid: ID del nodo di cui si desidera trovare il leader
# - leaders_data: dizionario contenente i leader e i nodi di ciascun cluster
# Output:
# - Restituisce il pid del leader se il nodo è associato a un leader; None se non associato
def find_leader(pid, leaders_data):
    for leader_data in leaders_data:
        if leader_data["leader_id"] == pid:
            return leader_data["leader_id"]
        if pid in leader_data["nodes"]:
            return leader_data["leader_id"]
    return None




# Funzione per disegnare linee tra nodi adiacenti dello stesso cluster
# Input:
# - ax: oggetto Axes di Matplotlib su cui disegnare le linee di connessione
# - x, y: coordinate del nodo corrente
# - pid: ID del nodo corrente
# - position_map: dizionario che mappa le coordinate (x, y) ai rispettivi pid
# - leaders_data: dizionario con i dati dei leader e dei nodi in ciascun cluster
# - max_x, max_y: dimensioni massime della griglia per il posizionamento verticale
# Output:
# - La funzione disegna linee di connessione tra nodi adiacenti appartenenti allo stesso cluster
def draw_cluster_connections(ax, x, y, pid, position_map, leaders_data, max_x, max_y):
    adjacent_positions = [
        (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
        (x - 1, y - 1), (x - 1, y + 1), (x + 1, y - 1), (x + 1, y + 1)
    ]
    
    leader_pid = find_leader(pid, leaders_data)
    x_center, y_center = y - 0.5, max_x - x + 0.5

    for pos in adjacent_positions:
        if pos in position_map:
            neighbor_pid = position_map[pos]
            neighbor_leader_pid = find_leader(neighbor_pid, leaders_data)
            if leader_pid == neighbor_leader_pid:  # Solo disegna linee per nodi con lo stesso leader
                neighbor_x_center, neighbor_y_center = pos[1] - 0.5, max_x - pos[0] + 0.5
                ax.plot(
                    [x_center, neighbor_x_center],
                    [y_center, neighbor_y_center],
                    color="white", linewidth=2
                )
                ax.plot(
                    [x_center, neighbor_x_center],
                    [y_center, neighbor_y_center],
                    color="black", linewidth=0.5
                )

# Funzione per convertire nomi di colori in valori RGB
# Input:
# - color: nome del colore (stringa) da convertire in RGB
# Output:
# - Una tupla (R, G, B) che rappresenta il colore in formato RGB;
#   restituisce il bianco (1, 1, 1) per colori non riconosciuti
def color_to_rgb(color):
    colors = {
        "red": (1, 0, 0), "green": (0, 1, 0), "blue": (0, 0, 1),
        "yellow": (1, 1, 0), "black": (0, 0, 0), "white": (1, 1, 1),
        "brown": (0.6, 0.3, 0.1), "orange": (1, 0.5, 0),
        "purple": (0.5, 0, 0.5), "pink": (1, 0.75, 0.8),
        "grey": (0.9, 0.9, 0.9)
    }
    return colors.get(color, (1, 1, 1))  # Ritorna bianco se il colore non è definito

# Classe di gestione degli eventi per monitorare i cambiamenti nei file
# Questo permette di aggiornare automaticamente l'immagine quando i dati dei leader cambiano.
class LeadersDataHandler(FileSystemEventHandler):
    # Metodo per gestire modifiche ai file monitorati
    # Input:
    # - event: oggetto evento che contiene il percorso del file modificato
    # Output:
    # - Nessun output diretto, ma invia un aggiornamento ai client tramite WebSocket
    def on_modified(self, event):
        if event.src_path.endswith(LEADERS_FILE):
            draw_matrix()  # Ridisegna la matrice con i nuovi dati
            socketio.emit('refresh')  # Invia un aggiornamento WebSocket ai client per ricaricare

# Configura l'osservatore per monitorare i cambiamenti nei file leader
observer = Observer()
observer.schedule(LeadersDataHandler(), path=".", recursive=False)
observer.start()

# Endpoint HTTP per notificare aggiornamenti da Erlang e inviare un messaggio WebSocket
# Input:
# - Richiesta HTTP POST (nessun dato specifico richiesto)
# Output:
# - Risposta HTTP 204 (No Content) per confermare la ricezione della richiesta
@app.route('/notify_refresh', methods=['POST'])
def notify_refresh():
    # draw_matrix()  # Ridisegna la matrice dei nodi
    
    # Definisci un percorso unico per l'immagine
    #image_path = f"static/matrix_{time.strftime('%Y%m%d_%H%M%S')}.png"
    
    # Disegna la matrice e salva l'immagine con il nuovo percorso
    #fig = draw_matrix(image_path)

    # Logga il cambiamento nel notebook
    # log_change_notebook(pid, color, image_path)
    socketio.emit('refresh')  # Notifica ai client di aggiornare la visualizzazione
    return '', 204  # Restituisce una risposta vuota con codice di stato 204

# Route per visualizzare l'immagine della matrice
# Output:
# - Restituisce l'immagine PNG della matrice come risposta HTTP
@app.route('/matrix')
def matrix():
    return send_file(IMG_PATH, mimetype='image/png')

# Homepage dell'applicazione con aggiornamento automatico e WebSocket
# Output:
# - Restituisce una pagina HTML con una visualizzazione dell'immagine e un modulo per cambiare colore
@app.route('/')
def home():
    # Carica i dati dei nodi e determina le dimensioni della griglia
    nodes_data = load_nodes_data()
    max_x = max(node["x"] for node in nodes_data)
    max_y = max(node["y"] for node in nodes_data)
    
    # Genera la pagina HTML con un modulo per cambiare il colore del nodo e l'immagine della matrice
    return render_template_string("""
        <!-- HTML per la visualizzazione della matrice e modulo di cambio colore -->
        <html lang="it">
        <head>
            <title>Matrice dei Nodi</title>
            <style>
                /* Stile CSS per il layout e gli elementi */
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f5f5f5;
                    color: #333;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                }
                h1 {
                    font-size: 24px;
                    color: #333;
                }
                p {
                    font-size: 14px;
                    color: #666;
                    text-align: center;
                }
                .matrix-container {
                    display: inline-block;
                    position: relative;
                    margin-top: 20px;
                    background-color: #ffffff;
                    box-shadow: 0px 4px 8px rgba(0, 0, 0, 0.1);
                }
                .grid-overlay {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    display: grid;
                    grid-template-columns: repeat({{max_y}}, 1fr);
                    grid-template-rows: repeat({{max_x}}, 1fr);
                }
                .node {
                    border: 1px solid transparent;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: background-color 0.3s;
                }
                .node:hover {
                    background-color: #ddd;
                }
                form {
                    margin-top: 20px;
                    padding: 10px;
                    background-color: #ffffff;
                    border: 1px solid #ddd;
                    box-shadow: 0px 4px 8px rgba(0, 0, 0, 0.1);
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    font-size: 14px;
                }
                form label, form select, form input {
                    margin: 5px 0;
                }
                #colorForm button {
                    margin-top: 10px;
                    padding: 8px 12px;
                    border: none;
                    background-color: #007bff;
                    color: white;
                    font-weight: bold;
                    cursor: pointer;
                    border-radius: 4px;
                    transition: background-color 0.3s;
                }
                #colorForm button:hover {
                    background-color: #0056b3;
                }
            </style>
        </head>
        
        <body>
            <h1>Matrice dei Nodi</h1>
            <p>Aggiornata automaticamente ogni 30 secondi o quando rileva modifiche.</p>

            <div class="matrix-container">
                <img src="/matrix" alt="Matrix" style="display: block;">
                <div class="grid-overlay">
                    {% for node in nodes_data %}
                        <div class="node" onclick="selectNode('{{ node.pid }}', {{ node.x }}, {{ node.y }})"></div>
                    {% endfor %}
                </div>
            </div>

            <form method="POST" action="/change_color" id="colorForm">
                <label>PID Selezionato:</label>
                <input type="text" id="selection_pid" name="pid" readonly>


                <label>Coordinate Selezionate:</label>
                <input type="text" id="selection_coordinates" name="selection_coordinates" readonly>

                <label for="color">Colore:</label>
                <select id="color" name="color">
                    <option value="red">Rosso</option>
                    <option value="green">Verde</option>
                    <option value="blue">Blu</option>
                    <option value="yellow">Giallo</option>
                    <option value="black">Nero</option>
                    <option value="white">Bianco</option>
                    <option value="brown">Marrone</option>
                    <option value="orange">Arancione</option>
                    <option value="purple">Viola</option>
                    <option value="pink">Rosa</option>
                </select>
                
                <button type="submit">Cambia Colore</button>
            </form>

            <script src="//cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.1/socket.io.min.js"></script>
            <script>
                const socket = io.connect();
                socket.on('refresh', function() {
                    window.location.reload();
                });

                const selectionPidInput = document.getElementById('selection_pid');
                const selectionCoordinatesInput = document.getElementById('selection_coordinates');
                
                function selectNode(pid, x, y) {
                    selectionPidInput.value = pid;  // Imposta il PID
                    selectionCoordinatesInput.value = `(${x},${y})`;  // Imposta le coordinate
                }

                setTimeout(function(){
                    window.location.reload(1);
                }, 30000);
            </script>
        </body>

        
        </html>
    """, nodes_data=nodes_data, max_x=max_x, max_y=max_y, debug_mode=DEBUG_MODE)


# Funzione per inviare una richiesta di cambio colore al server Erlang tramite TCP
# Input:
# - pid: ID del nodo il cui colore deve essere cambiato
# - color: nuovo colore da impostare per il nodo
# Output:
# - Restituisce True se la comunicazione con Erlang è riuscita e ha confermato il cambio colore con "ok"
# - Restituisce False se si verifica un errore di connessione o Erlang non conferma con "ok"
def send_color_change_request(node_id, color):

    if node_id is None:
        print("Errore: node_id è None, impossibile inviare la richiesta")
        return False

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect(('localhost', 8080))  # Assicurati che l'host e la porta siano corretti
            message = f"change_color,{node_id},{color}"  # Usa node_id al posto di pid
            print(f"Inviando il messaggio: {message}")  # Debug
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            return response == "ok"
    except Exception as e:
        print(f"Errore nella comunicazione con Erlang: {e}")
        return False


# Endpoint HTTP per gestire il cambio colore di un nodo
# Input:
# - Richiesta HTTP POST con parametri "pid" (ID del nodo) e "color" (nuovo colore da impostare)
# Output:
# - Se la comunicazione con Erlang ha successo, invia un evento WebSocket per aggiornare la vista
#   e reindirizza l'utente alla pagina principale con l'immagine aggiornata.
# - Se la comunicazione fallisce, restituisce un messaggio di errore e codice di stato 500.

@app.route('/change_color', methods=['POST'])
def change_color():
    # Estrae i parametri "pid" e "color" dalla richiesta POST
    pid = request.form.get('pid')
    color = request.form.get('color')

    print(f"ricevo {pid} e {color}")

    # Invia la richiesta di cambio colore al server Erlang tramite TCP
    if send_color_change_request(pid, color):
        # Notifica i client WebSocket e aggiorna la visualizzazione
        socketio.emit('refresh')
        return redirect(url_for('home'))

    else:
        # Restituisce un messaggio di errore HTTP 500 in caso di problemi
        return "Errore nel cambio colore", 500

# Funzione per avviare il server Flask con SocketIO per aggiornamenti in tempo reale
def run_server():
    clear_snapshots_folder()  # Elimina i file nella cartella snapshots all'avvio
    draw_matrix()  # Disegna inizialmente la matrice
    socketio.run(app, debug=True)

# Funzione per eliminare tutti i file nella cartella snapshots
def clear_snapshots_folder(folder_path="static/default_test/snapshots"):
    if os.path.exists(folder_path):
        for filename in os.listdir(folder_path):
            file_path = os.path.join(folder_path, filename)
            try:
                if os.path.isfile(file_path):
                    os.remove(file_path)
            except Exception as e:
                print(f"Errore durante l'eliminazione del file {file_path}: {e}")
    else:
        os.makedirs(folder_path)  # Crea la cartella se non esiste

# Avvio del server
if __name__ == "__main__":
    clear_snapshots_folder()  # Elimina i file nella cartella snapshots
    clear_notebook()          # Pulisce il notebook all'avvio
    draw_matrix()             # Disegna la matrice all'avvio del server
    socketio.run(app, debug=True, use_reloader=False)
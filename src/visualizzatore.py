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

# Funzione per determinare se un colore è scuro
def is_dark_color(rgb):
    if rgb == (0, 0, 1):
        return True
    else:
        hsv = rgb_to_hsv(rgb)
        return hsv[2] < 0.9  # Se la luminosità (valore) è inferiore a 0.5, è scuro


app = Flask(__name__)
socketio = SocketIO(app)  # Inizializza il supporto WebSocket

# Percorsi dei file
LEADERS_FILE = "leaders_data.json"
NODES_FILE = "nodes_data.json"
IMG_PATH = "static/matrix.png"

# Carica i dati dai file
def load_leaders_data():
    with open(LEADERS_FILE, "r") as file:
        return json.load(file)

def load_nodes_data():
    with open(NODES_FILE, "r") as file:
        return json.load(file)

# Funzione per ottenere il colore di un nodo in base al suo leader
def get_node_color(pid, leaders_data):
    if pid in leaders_data:
        return leaders_data[pid]["color"]
    for leader_pid, cluster_data in leaders_data.items():
        if pid in cluster_data["nodes"]:
            return cluster_data["color"]
    return "grey"

# Funzione per disegnare la matrice
def draw_matrix():
    leaders_data = load_leaders_data()
    nodes_data = load_nodes_data()
    
    max_x = max(node["x"] for node in nodes_data)
    max_y = max(node["y"] for node in nodes_data)

    fig = Figure(figsize=(8, 8))
    ax = fig.add_subplot(111)
    
    # Sistema i tick in base alle dimensioni della griglia
    ax.set_xticks(np.arange(0, max_y + 1, 1))
    ax.set_yticks(np.arange(0, max_x + 1, 1))
    ax.tick_params(left=False, bottom=False, labelleft=False, labelbottom=False)
    ax.grid(False)
    
    position_map = {(node["x"], node["y"]): node["pid"] for node in nodes_data}

    for node in nodes_data:
        x, y, pid = node["x"], node["y"], node["pid"]
        color = get_node_color(pid, leaders_data)
        rgb = color_to_rgb(color)

        # Aggiustiamo la posizione per centrare le celle sulla griglia
        ax.add_patch(Rectangle((y - 1, max_x - x), 1, 1, color=rgb, ec="black"))

        

        # Disegna linee tra nodi adiacenti dello stesso cluster
        draw_cluster_connections(ax, x, y, pid, position_map, leaders_data, max_x, max_y)

        # Testo per le coordinate, PID e "L" per i leader
        # Determina il colore del testo (bianco su sfondi scuri, nero su sfondi chiari)
        text_color = "white" if is_dark_color(rgb) else "black"
        ax.text(y - 0.5, max_x - x + 0.3, f"({x},{y})", ha="center", va="center", color=text_color, fontsize=8, weight="bold")
        ax.text(y - 0.5, max_x - x + 0.7, f"{pid}", ha="center", va="center", color=text_color, fontsize=8, weight="bold")
        
        if pid in leaders_data:
            label_color = "white" if is_dark_color(rgb) else "black"
            ax.text(y - 0.5, max_x - x + 0.5, "L", ha="center", va="center", color=label_color, fontsize=14, weight="bold")

    ax.set_xlim(0, max_y)
    ax.set_ylim(0, max_x)
    # Salva l'immagine senza margini e bordi visibili
    fig.savefig(IMG_PATH, bbox_inches='tight', pad_inches=0)
    fig.clear()



# Funzione per trovare il leader di un nodo dato il suo PID
def find_leader(pid, leaders_data):
    # Se il nodo è un leader, restituisce se stesso
    if pid in leaders_data:
        return pid
    # Cerca il leader nei cluster
    for leader_pid, cluster_data in leaders_data.items():
        if pid in cluster_data["nodes"]:
            return leader_pid
    return None



# Funzione per disegnare linee tra nodi adiacenti dello stesso cluster
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
            if leader_pid == neighbor_leader_pid:
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

# Mappa i colori a RGB
def color_to_rgb(color):
    colors = {
        "red": (1, 0, 0), "green": (0, 1, 0), "blue": (0, 0, 1),
        "yellow": (1, 1, 0), "black": (0, 0, 0), "white": (1, 1, 1),
        "brown": (0.6, 0.3, 0.1), "orange": (1, 0.5, 0),
        "purple": (0.5, 0, 0.5), "pink": (1, 0.75, 0.8),
        "grey": (0.9, 0.9, 0.9)
    }
    return colors.get(color, (1, 1, 1))

# Handler per il monitoraggio dei cambiamenti
class LeadersDataHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if event.src_path.endswith(LEADERS_FILE):
            draw_matrix()
            socketio.emit('refresh')  # Invia un messaggio di aggiornamento a tutti i client WebSocket

observer = Observer()
observer.schedule(LeadersDataHandler(), path=".", recursive=False)
observer.start()

# Endpoint per ricevere la notifica di Erlang e inviare il messaggio WebSocket
@app.route('/notify_refresh', methods=['POST'])
def notify_refresh():
    draw_matrix()
    socketio.emit('refresh')
    return '', 204

# Route per visualizzare l'immagine
@app.route('/matrix')
def matrix():
    return send_file(IMG_PATH, mimetype='image/png')

# Homepage con aggiornamento automatico e WebSocket
# Homepage con aggiornamento automatico e WebSocket
@app.route('/')
def home():
    nodes_data = load_nodes_data()
    max_x = max(node["x"] for node in nodes_data)
    max_y = max(node["y"] for node in nodes_data)
    
    return render_template_string("""
        <html lang="it">
        <head>
            <title>Matrice dei Nodi</title>
            <style>
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
                        <div class="node" onclick="selectNode('{{ node.pid }}')"></div>
                    {% endfor %}
                </div>
            </div>

            <form method="POST" action="/change_color" id="colorForm">
                <label for="pid">PID Selezionato:</label>
                <input type="text" id="pid" name="pid" readonly>

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
                    <option value="grey">Grigio</option>
                </select>
                
                <button type="submit">Cambia Colore</button>
            </form>

            <script src="//cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.1/socket.io.min.js"></script>
            <script>
                const socket = io.connect();
                socket.on('refresh', function() {
                    window.location.reload();
                });

                const pidInput = document.getElementById('pid');
                function selectNode(pid) {
                    pidInput.value = pid;
                }

                setTimeout(function(){
                   window.location.reload(1);
                }, 30000);
            </script>
        </body>
        </html>
    """, nodes_data=nodes_data, max_x=max_x, max_y=max_y)


import socket

# Funzione per inviare una richiesta di cambio colore al server Erlang tramite TCP
def send_color_change_request(pid, color):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect(('localhost', 8080))  # Configura l'host e la porta di Erlang
            message = f"{pid},{color}"
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            return response == "ok"
    except Exception as e:
        print(f"Errore nella comunicazione con Erlang: {e}")
        return False

# Endpoint modificato per il cambio colore
@app.route('/change_color', methods=['POST'])
def change_color():
    pid = request.form.get('pid')
    color = request.form.get('color')

    # Invia la richiesta tramite TCP
    if send_color_change_request(pid, color):
        socketio.emit('refresh')  # Notifica aggiornamento se la richiesta ha successo
        return redirect(url_for('home'))
    else:
        return "Errore nel cambio colore", 500

def run_server():
    draw_matrix()
    socketio.run(app, debug=True)

if __name__ == "__main__":
    draw_matrix()  # Disegna inizialmente la matrice
    socketio.run(app, debug=True, use_reloader=False)

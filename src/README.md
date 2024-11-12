# Implementazione Distribuita dell'Algoritmo Flood-Fill

## Descrizione del Progetto

Questo progetto implementa un sistema distribuito per la gestione e visualizzazione di una matrice di nodi, dove ciascun nodo rappresenta un pixel in una griglia bidimensionale. Ogni nodo può cambiare colore tramite comandi di cambio-colore inviati dall'interfaccia frontend sviluppata in **Python** con **Flask**. Il backend distribuito è implementato in **Erlang**, che gestisce la comunicazione e la consistenza dei colori dei nodi in tempo reale.

### Funzionalità Principali

- **Visualizzazione della Matrice di Nodi**: La matrice mostra una griglia di nodi connessi tra loro e colorati, dove ogni colore rappresenta un cluster.
- **Gestione dei Cambiamenti di Colore in Tempo Reale**: Gli utenti possono cambiare il colore di un nodo direttamente dall'interfaccia web; il backend Erlang si occupa di propagare e sincronizzare i cambiamenti.
- **Resilienza ai Fallimenti**: Il sistema rileva e gestisce automaticamente i fallimenti dei nodi, garantendo continuità operativa tramite rielezione dei leader e ristrutturazione dei cluster.
- **Aggiornamenti in Tempo Reale con WebSocket**: Utilizzando Flask-SocketIO, i cambiamenti di stato dei nodi vengono aggiornati in tempo reale nell'interfaccia.
- **Logging e Backup dei Cambiamenti**: Ogni cambiamento di colore è salvato in un notebook Jupyter (`history_log.ipynb`), con un'immagine aggiornata della matrice.

### Struttura del Progetto

#### Backend (Erlang)

- **`start_system.erl`**: Modulo principale che avvia il sistema, gestisce la configurazione dei nodi e il server centrale.
- **`node.erl`**: Definisce il comportamento dei nodi nella griglia. Ogni nodo gestisce le richieste di cambio colore e il proprio stato.
- **`server.erl`**: Coordina le operazioni globali e la comunicazione con il frontend. Supervisiona i nodi e assegna i vicini.
- **`tcp_server.erl`**: Implementa un server TCP che riceve le richieste di cambio colore dal server Flask e le instrada ai nodi.
- **`event.erl`**: Gestisce gli eventi di cambio colore e merge dei cluster.
- **`utils.erl`**: Contiene funzioni di utilità per manipolare le liste, formattare JSON, ecc.

#### Frontend (Python)

- **`server.py`**: Avvia il server Flask che fornisce l'interfaccia utente e gestisce le richieste di cambio colore.
- **`grid_visualizer.py`**: Implementa la visualizzazione grafica della griglia e si connette tramite WebSocket per aggiornare in tempo reale.
- **`matrix_utils.py`**: Funzioni di supporto per gestire colori e calcoli per la visualizzazione.
- **`change_color_requests.py`**: Gestisce l'invio delle richieste di cambio colore dal frontend.
- **`notebook_logger.py`**: Registra i cambiamenti di colore nel file Jupyter `history_log.ipynb`.

### Struttura dei File

Il sistema utilizza diversi file di log e di dati per mantenere lo stato dei nodi:

- **`nodes_data.json`**: Memorizza informazioni di base sui nodi (PID, coordinate, leaderID).
- **`leaders_data.json`**: Memorizza informazioni sui leader dei cluster e sui cluster adiacenti.
- **`server_log.txt`**: Log di tutte le operazioni effettuate dal server.
- **`nodes_status.txt`**: Stato corrente di ciascun nodo (coordinate, colore, leaderID).
- **`static/matrix.png`**: Immagine aggiornata della griglia dei nodi.

## Requisiti

- **Erlang/OTP 24+**
- **Python 3.7+**
- **Librerie Python**: Flask, Flask-SocketIO, Matplotlib, Watchdog, nbformat

### Installazione delle Dipendenze

Per installare tutte le dipendenze necessarie, esegui:

```bash
pip install flask flask-socketio matplotlib watchdog numpy ipython nbformat psutil
```
## Guida all'Uso

### 1. Avviare il Sistema Erlang

Prima di avviare il server Flask, assicurati di aver avviato il backend Erlang per gestire le richieste di cambio colore. Puoi avviarlo eseguendo lo script `compile_and_run.sh` con le dimensioni desiderate della matrice (esempio 5x5):

```bash
./compile_and_run.sh 5 5 true
```

### 2. Avvio del Server Flask

Una volta attivato Erlang, avvia il server Flask che ospita l'interfaccia di gestione della matrice e permette le modifiche del colore.

```bash
python grid_visualizer.py --port <PORTA> --debug <True/False>
```

### 3. Visualizzazione della Matrice

Apri il tuo browser e visita `http://localhost:<PORTA>` per visualizzare la matrice.

### 4. Cambiare il Colore dei Nodi

Nell'interfaccia, seleziona il nodo che desideri cambiare e scegli il colore desiderato dal menu a tendina. Il server invierà la richiesta al backend Erlang e aggiornerà la visualizzazione in tempo reale.

## Dettagli dei Moduli Erlang

### `start_system.erl`

Modulo principale di setup del sistema:

- Avvia il server e i nodi nella griglia specificata.
- Assegna a ciascun nodo i vicini in base alla posizione.
- Esegue il setup per il monitoraggio e la gestione dei nodi e leader.

### `node.erl`

Definisce il comportamento di ogni nodo:

- Risponde ai messaggi di cambio colore.
- Comunica con altri nodi per le richieste di merge.
- Gestisce lo stato di vicinato e sincronizzazione con il server.

### `server.erl`

Gestisce il coordinamento globale:

- Assegna vicini a ciascun nodo.
- Supervisiona lo stato del sistema e gestisce le richieste di cambio colore globali.
- Comunica con Flask per aggiornamenti in tempo reale.

### `visualizer.erl`

Interfaccia per il monitoraggio e visualizzazione:

- Collega il sistema Erlang con il frontend.
- Gestisce i WebSocket e invia aggiornamenti al server Flask.

### `tcp_server.erl`

Server TCP che gestisce le richieste di cambio colore dal frontend:

- Riceve richieste da Flask.
- Interpreta e indirizza le richieste verso i nodi corrispondenti.

### `utils.erl`

Modulo di utilità:

- Contiene funzioni per rimuovere duplicati, formattare JSON e normalizzare colori.
- Gestisce operazioni comuni come controllo della validità dei PID e conversioni.

## Comandi di Esempio

### Per eseguire il server Flask:

```bash
python grind_visualizer.py --port 8080 --debug True
```

### Per generare una matrice di nodi e inizializzare i colori

```bash
python3 generate_changes_rand.py --rows 5 --columns 5 --operations 10

```


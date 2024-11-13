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

- **`grid_visualizer.py`**: Implementa la visualizzazione grafica della griglia e si connette tramite WebSocket per aggiornare in tempo reale.

### Struttura dei File

Il sistema utilizza diversi file di log e di dati per mantenere lo stato dei nodi:

- **`nodes_data.json`**: Memorizza informazioni di base sui nodi (PID, coordinate, leaderID).
- **`leaders_data.json`**: Memorizza informazioni sui leader dei cluster e sui cluster adiacenti.
- **`server_log.txt`**: Log di tutte le operazioni effettuate dal server.
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

## Guida all'Uso del Sistema

Questa guida dettagliata ti accompagnerà nell’utilizzo del sistema distribuito per la gestione e visualizzazione della matrice di nodi. Di seguito troverai tutte le informazioni su come configurare e avviare i componenti necessari, compreso il backend in **Erlang** e il frontend in **Python/Flask**, e su come eseguire test automatici per verificarne il funzionamento.

### Prerequisiti

Prima di iniziare, assicurati di avere installato:

- **Erlang/OTP 24 o superiore**: necessario per eseguire il backend distribuito. Erlang è stato scelto per le sue capacità native di gestione della concorrenza e di tolleranza ai guasti, essenziali per garantire la consistenza e la resilienza del sistema distribuito.
- **Python 3.7 o superiore**: richiesto per eseguire il frontend Flask e altre operazioni di supporto. Flask è stato selezionato per la sua semplicità e flessibilità, permettendo di costruire rapidamente un’interfaccia web reattiva e integrabile con Erlang attraverso comunicazioni TCP.

### Istruzioni Passo-Passo

1. **Avvio del Backend Erlang**
    
    Il backend in Erlang gestisce le operazioni distribuite sui nodi della matrice, inclusi i cambiamenti di colore e la sincronizzazione dello stato dei nodi. È progettato per supportare una gestione efficiente dei messaggi tra i nodi, consentendo di rilevare e recuperare eventuali fallimenti dei nodi e dei leader.
    
    - **Comando**:
        
        ```bash
        ./compile_and_run.sh <ROWS> <COLUMNS> <FROM_FILE>
        ```
        
        - **`<ROWS> <COLUMNS>`**: Specifica le dimensioni della griglia (ad esempio, 7x7 per una griglia di 49 nodi). Questi valori definiscono la topologia del sistema, stabilendo quanti nodi indipendenti saranno gestiti dal backend.
        - **`FROM_FILE`**: Flag per determinare se i colori dei nodi devono essere assegnati casualmente o caricati da un file (`True` per leggere da file). Questo consente flessibilità nel setup della griglia: puoi partire da una configurazione predefinita oppure generare una configurazione randomica per testare il comportamento del sistema.
    
    **Nota**: Lo script `compile_and_run.sh` si occupa di compilare il codice Erlang e avviare il backend, assegnando automaticamente una porta per la comunicazione con il server Flask. Questa separazione dei compiti tra script facilita la gestione dell'infrastruttura di rete e semplifica il debugging.
    
2. **Avvio del Server Flask**
    
    Il server Flask rappresenta il frontend dell’applicazione, gestendo l’interfaccia web che permette all’utente di interagire con la griglia e inviare comandi di cambio colore. Flask è integrato con Flask-SocketIO per aggiornamenti in tempo reale della griglia, così da riflettere immediatamente ogni modifica del backend.
    
    - **Comando**:
        
        ```bash
        python3 grid_visualizer.py --debug True --port <PORTA>
        ```
        
        - **`-debug`**: Impostato su `True` per l’output di debug, utile durante lo sviluppo e la risoluzione dei problemi. Può essere impostato su `False` in produzione per migliorare la sicurezza e le performance.
        - **`-port <PORTA>`**: Porta assegnata automaticamente dal backend; sostituisci `<PORTA>` con il numero specificato dall’output di `compile_and_run.sh`.
    
    **Nota**: L'uso di Flask-SocketIO consente di mantenere sincronizzato il frontend con il backend in tempo reale. Ogni volta che un nodo cambia colore nel backend, l’interfaccia viene aggiornata automaticamente, offrendo un feedback visivo immediato per l’utente.
    
3. **Visualizzare la Matrice**
    
    Una volta avviati sia il backend che il frontend, puoi visualizzare la griglia e interagire con i nodi direttamente nel browser. Naviga all’indirizzo seguente:
    
    ```
    http://localhost:<PORTA>
    ```
    
    **Motivazione**: Centralizzare le operazioni sull’interfaccia web semplifica l’uso del sistema, rendendolo accessibile anche agli utenti meno esperti. La matrice, mostrata come griglia di nodi, riflette visivamente lo stato del sistema distribuito, facilitando il monitoraggio delle operazioni e dei cambiamenti.
    
4. **Interazione e Cambiamento di Colore dei Nodi**
    
    Nell’interfaccia web:
    
    - Seleziona un nodo.
    - Scegli un nuovo colore dal menu.
    - Conferma l’operazione.
    
    Ogni richiesta di cambio colore viene inoltrata dal frontend al backend, che si occupa di propagare il cambiamento in modo sicuro ed efficiente tra i nodi coinvolti. Questa propagazione utilizza i meccanismi di gestione della concorrenza di Erlang per garantire che ogni nodo riceva l’aggiornamento senza conflitti.
    
    **Nota**: Il sistema è stato progettato per supportare aggiornamenti di colore in modo atomico. L'implementazione assicura che anche in caso di cambi multipli simultanei, il sistema riesca a gestire correttamente i conflitti grazie a un modello di eventi ordinati per timestamp.
    

---

## Automazione e Test

Per supportare scenari di testing complessi e verificare la stabilità del sistema in condizioni diverse, è possibile utilizzare script di automazione per generare configurazioni e operazioni casuali.

### Generazione di Matrice con Colori e Operazioni Casuali

Utilizzando lo script `generate_changes_rand.py`, puoi creare una matrice con colori casuali e un set di operazioni di cambio colore casuali. Questo approccio è utile per simulare un’ampia varietà di scenari e testare la robustezza e la reattività del sistema in situazioni diverse.

- **Comando**:
    
    ```bash
    python3 generate_changes_rand.py --rows <ROWS> --columns <COLUMNS> --operations <NUMBER_OPERATIONS>
    ```
    
    - **`-rows` e `-columns`**: Definiscono la dimensione della griglia, allineandola a quella del backend.
    - **`-operations`**: Numero di cambi di colore casuali che verranno applicati durante il test. Ogni operazione è concepita per verificare la gestione dei cambiamenti distribuiti.
    
    **Note**:
    
    - Il file `colors.txt` generato da questo script può essere utilizzato nel comando `compile_and_run.sh` impostando `FROM_FILE=True` per testare configurazioni specifiche e ripetibili.
    - Lo script permette di simulare carichi di lavoro realistici, essenziali per identificare eventuali colli di bottiglia o problematiche di consistenza.

### Esecuzione di Test Automatici con `script.py`

Per verificare automaticamente l’intero ciclo operativo del sistema e confermare che il backend e il frontend rispondano correttamente a ciascun comando, utilizza lo script `script.py`.

- **Comando**:
    
    ```bash
    python3 script.py
    ```
    Questo script avvia automaticamente una sequenza di operazioni e verifica che i cambiamenti vengano propagati correttamente nell’interfaccia e nei log di sistema.
    
    **Nota**: I test automatici sono fondamentali per assicurare la coerenza e l’affidabilità del sistema. Questo script consente di eseguire verifiche rapide e ripetute, facilitando il debug e garantendo un comportamento corretto del sistema in diverse condizioni.
    

---

### Esecuzione in Shell Multiple

Per supportare la gestione di sessioni multiple e facilitare la configurazione e l’esecuzione del sistema in ambienti di sviluppo, puoi usare più terminali (o shell) per avviare i componenti in parallelo.

### Opzione 1: Due Shell (Uso Manuale)

1. **Avvia il Backend Erlang**:
    
    ```bash
    ./compile_and_run.sh <ROWS> <COLUMNS> <FROM_FILE>
    ```
    
2. **Avvia il Server Flask**:
    
    ```bash
    python3 grid_visualizer.py --debug False --port <PORTA>
    ```
    
    - Questa modalità è utile se si desidera controllare manualmente i componenti del sistema e verificare le interazioni.

### Opzione 2: Tre Shell (Uso con Test Automatici)

Questa configurazione permette di eseguire test automatici oltre al backend e al server Flask.

0. **Setup iniziale**
   ![image](https://github.com/user-attachments/assets/bf3012e0-ed48-4f8f-94b7-bcfd16542035)
    Aprire tre shell e recarsi in:
    - :~/Distributed-Flood-Fill/src/test_script
    - :~/Distributed-Flood-Fill/src/test_script/test
    - :~/Distributed-Flood-Fill/src/data
2. **Generare Operazioni Casuali**:

     ```bash
    python3 generate_changes_rand.py --rows <ROWS> --columns <COLUMNS> --operations <NUMBER_OPERATIONS>
    ```
     Ad esempio:

    ```bash
    python3 generate_changes_rand.py --rows 7 --columns 7 --operations 10
    ```
    ![image](https://github.com/user-attachments/assets/b00f2404-9eb0-43ac-b685-ddc05049f3dc)

    Questo genera colori per una matrice 7 x 7 e 10 operazioni di ricolorazione casuali.
    
1. **Backend Erlang**:
    
    ```bash
    ./compile_and_run.sh <ROWS> <COLUMNS> <FROM_FILE>
    ```
    Ad esempio:
   ```bash
    ./compile_and_run.sh 7 7 true
    ```
    ![image](https://github.com/user-attachments/assets/5e49f2a2-4209-489b-afd8-0c67b02b8850)
    Questo 
    
2. **Server Flask**:
    
    ```bash
    python3 grid_visualizer.py --debug False --port 50133
    ```
    ![image](https://github.com/user-attachments/assets/b91d7351-6e08-4b4d-bf0f-3f0a6c5d2fdf)

    Questo

    ![image](https://github.com/user-attachments/assets/b7fa7b08-6dab-4a8a-8c98-21eda3ece860)
    Andando su http://127.0.0.1:5000
    
4. **Eseguire i Test Automatici**:
    
    Per avviare i test, specifica la porta di connessione nello script `generate_changes_rand.py`.

    ![image](https://github.com/user-attachments/assets/1e3d7e0c-11c0-43fb-a02b-f90405dada64)

    La configurazione totale è la seguente:
    ![image](https://github.com/user-attachments/assets/26dcf32b-cb3c-4267-9182-3914eaa4fb07)

    

    

Questa configurazione permette di avviare un ambiente completo di testing automatizzato e monitoraggio, utile per verificare il comportamento del sistema in scenari realistici e per osservare la resilienza del sistema in condizioni di utilizzo intensivo.

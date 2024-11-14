# Implementazione Distribuita dell'Algoritmo Flood-Fill
![Esempio_Grafo_G (1)](https://github.com/user-attachments/assets/cde57cf8-b807-4266-b1a6-afbf402bdf86)

- [Implementazione Distribuita dell'Algoritmo Flood-Fill](#implementazione-distribuita-dell-algoritmo-flood-fill)
  * [Descrizione del Progetto](#descrizione-del-progetto)
    + [Funzionalità Principali](#funzionalit--principali)
    + [Struttura del Progetto](#struttura-del-progetto)
      - [Backend (Erlang)](#backend--erlang-)
      - [Frontend (Python)](#frontend--python-)
    + [Struttura dei File](#struttura-dei-file)
  * [Requisiti](#requisiti)
    + [Installazione delle Dipendenze](#installazione-delle-dipendenze)
  * [Guida all'Uso del Sistema](#guida-all-uso-del-sistema)
    + [Prerequisiti](#prerequisiti)
    + [Istruzioni Passo-Passo](#istruzioni-passo-passo)
  * [Automazione e Test](#automazione-e-test)
    + [Generazione di Matrice con Colori e Operazioni Casuali](#generazione-di-matrice-con-colori-e-operazioni-casuali)
    + [Esecuzione di Test Automatici con `script.py`](#esecuzione-di-test-automatici-con--scriptpy-)
- [Esempi di Esecuzione in Shell Multiple](#esempi-di-esecuzione-in-shell-multiple)
  * [Opzione 1: Due Shell (Uso Manuale)](#opzione-1--due-shell--uso-manuale-)
      - [0. **Setup Iniziale**](#0---setup-iniziale--)
      - [1. **Avviare il Backend Erlang**](#1---avviare-il-backend-erlang--)
      - [2. **Avviare il Server Flask**](#2---avviare-il-server-flask--)
      - [3. **Utilizzo dell'Interfaccia Web per Dare Comandi**](#3---utilizzo-dell-interfaccia-web-per-dare-comandi--)
  * [Opzione 2: Tre Shell (Uso con Test Automatici/Specifici)](#opzione-2--tre-shell--uso-con-test-automatici-specifici-)
    + [0. Setup Iniziale](#0-setup-iniziale)
    + [1. Avviare lo Script Python per i Test Automatici](#1-avviare-lo-script-python-per-i-test-automatici)
    + [2. Avviare il Backend Erlang](#2-avviare-il-backend-erlang)
    + [3. Avviare il Server Flask](#3-avviare-il-server-flask)
    + [4. Eseguire i Test Automatici](#4-eseguire-i-test-automatici)
  * [Opzione 3: Tre Shell (Uso con Test Casuali)](#opzione-3--tre-shell--uso-con-test-casuali-)
    + [0. Setup Iniziale](#0-setup-iniziale-1)
    + [1. Generare Operazioni Casuali](#1-generare-operazioni-casuali)
    + [2. Avviare il Backend Erlang](#2-avviare-il-backend-erlang-1)
    + [3. Avviare il Server Flask](#3-avviare-il-server-flask-1)
    + [4. Eseguire i Test Casuali](#4-eseguire-i-test-casuali)
    + [5. Risultati dei Test](#5-risultati-dei-test)
    + [Conclusione](#conclusione)
- [Descrizione dei Test](#descrizione-dei-test)
  * [Caso 1: Richiesta di Cambio Colore con Timestamp Anteriore che Richiede un Merge](#caso-1--richiesta-di-cambio-colore-con-timestamp-anteriore-che-richiede-un-merge)
  * [Caso 2: Richiesta di Cambio Colore con Timestamp Anteriore che Non Richiede un Merge](#caso-2--richiesta-di-cambio-colore-con-timestamp-anteriore-che-non-richiede-un-merge)
  * [Caso 3: Richiesta di Merge Ricevuta Durante un Cambio Colore con Timestamp Anteriore](#caso-3--richiesta-di-merge-ricevuta-durante-un-cambio-colore-con-timestamp-anteriore)
  * [Caso "Too Old": Gestione di una Richiesta con Timestamp Troppo Vecchio](#caso--too-old---gestione-di-una-richiesta-con-timestamp-troppo-vecchio)
  * [Caso "Change Color During Merge": Richiesta di Cambio Colore Ricevuta Durante un Merge](#caso--change-color-during-merge---richiesta-di-cambio-colore-ricevuta-durante-un-merge)
  * [Caso "Double Merge": Doppio Merge tra Cluster Adiacenti con Cambio Colore](#caso--double-merge---doppio-merge-tra-cluster-adiacenti-con-cambio-colore)




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
- **`DB/{X}_{Y}.json`**: Infomrmazioni locali di ciasun lono normale e leader.

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
    
    - **Preparazione**:

        Prima di eseguire il comando, assicurati che lo script abbia i permessi di esecuzione. Esegui:

        ```bash
        chmod +x ./compile_and_run.sh
        ```

        Se compare l’errore `bad interpreter: No such file or directory`, risolvi il problema con:

        ```bash
        sed -i 's/\r//' compile_and_run.sh
        ```

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
        
        - **`-debug`**: Impostato su `True` per l’output di debug, utile durante lo sviluppo e la risoluzione dei problemi. Può essere impostato su `False` in produzione per migliorare la performance e la visualizzazione quando ci sono tanti nodi.
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
    






# Esempi di Esecuzione in Shell Multiple

Questa guida ti aiuterà a configurare e avviare il sistema Distributed Flood-Fill utilizzando più terminali (o shell) per facilitare la gestione e l’esecuzione dei componenti in parallelo.

## Opzione 1: Due Shell (Uso Manuale)

#### 0. **Setup Iniziale**

Per cominciare, aprire due terminali (shell) e navigare nei seguenti percorsi:

- Primo terminale: `~/Distributed-Flood-Fill/src/test_script`
- Secondo terminale: `~/Distributed-Flood-Fill/src/data`

In questo modo, ogni terminale sarà pronto per l'avvio dei componenti necessari.

![Setup Iniziale](/media/2shell/setupIniziale.png)

#### 1. **Avviare il Backend Erlang**

Nel terminale posizionato nella directory `test_script`, è necessario avviare lo script di compilazione e avvio del sistema Erlang. Questo script compilerà il codice e avvierà il sistema con i parametri specificati.

Comando da eseguire:

```bash
./compile_and_run.sh <ROWS> <COLUMNS> <FROM_FILE>
```

Dove:
- `<ROWS>`: Numero di righe della griglia.
- `<COLUMNS>`: Numero di colonne della griglia.
- `<FROM_FILE>`: Specifica se caricare i dati da un file (`true` o `false`).

Esempio:

```bash
./compile_and_run.sh 7 7 false
```

![Avvio Backend](/media/2shell/compile.png)

#### 2. **Avviare il Server Flask**

Nel secondo terminale, situato nella directory `data`, è necessario avviare il server Flask per la visualizzazione della griglia.

Comando da eseguire:

```bash
python3 grid_visualizer.py --debug False --port <PORTA>
```

Dove:
- `--debug`: Modalità debug (True o False).
- `<PORTA>`: La porta sulla quale il server Flask sarà in ascolto.

Esempio:

```bash
python3 grid_visualizer.py --debug True --port 47171
```

![Avvio Server Flask](/media/2shell/serverFlask.png)

#### 3. **Utilizzo dell'Interfaccia Web per Dare Comandi**

Una volta che il server Flask è in esecuzione, è possibile accedere all'interfaccia web per interagire con il sistema.

Aprire un browser e navigare all'indirizzo:

```
http://127.0.0.1:5000
```

Nell'interfaccia web, sarà possibile selezionare un nodo della griglia e modificarne il colore attraverso il menu a tendina. Dopo aver selezionato il colore desiderato, cliccare su "Cambia Colore" per applicare la modifica.

<p align="center">
    <img src="/media/2shell/selezione_di_un_nodo.png" alt="Selezione di un Nodo" width="45%">
    <img src="/media/2shell/risultato.png" alt="Risultato Cambio Colore" width="45%">
</p>

Nell'immagine sopra, è mostrato un esempio di selezione di un nodo (a sinistra) e il risultato dell'operazione di cambio colore (a destra).



## Opzione 2: Tre Shell (Uso con Test Automatici/Specifici)

Questa configurazione permette di eseguire test creati ad-hoc per verificare casi specifici del progetto Distributed-Flood-Fill.

### 0. Setup Iniziale

Per iniziare, aprire tre terminali (shell) e navigare nei seguenti percorsi:

- **Primo terminale**: `~/Distributed-Flood-Fill/src/test_script`
- **Secondo terminale**: `~/Distributed-Flood-Fill/src/test_script/test`
- **Terzo terminale**: `~/Distributed-Flood-Fill/src/data`

In questo modo, ogni terminale sarà pronto per l'avvio dei componenti necessari.

![Setup Iniziale](/media/test/setupIniziale.png)

### 1. Avviare lo Script Python per i Test Automatici

Nel secondo terminale, eseguire il seguente comando:

```bash
python3 script.py
```

Questo script genererà inizialmente i colori per una matrice 5x5 che verrà utilizzata nei vari test.

![Esecuzione Script](/media/test/script.png)

### 2. Avviare il Backend Erlang

Nel primo terminale, eseguire:

```bash
./compile_and_run.sh 5 5 true
```

Questo comando compila ed esegue il backend Erlang per gestire i nodi della matrice.

![Compilazione Backend](/media/test/compila.png)

### 3. Avviare il Server Flask

Nel terzo terminale, utilizzare la porta indicata dal backend Erlang per avviare il server Flask. Eseguire il seguente comando (sostituendo `<PORTA>` con la porta effettiva):

```bash
python3 grid_visualizer.py --debug False --port <PORTA>
```

![Avvio Server Flask](/media/test/flask.png)

Visitando l'indirizzo [http://127.0.0.1:5000](http://127.0.0.1:5000), è possibile visualizzare la matrice di nodi creata, che rimarrà la stessa per tutti i test.

![Visualizzazione Matrice Web](/media/test/visualizzazione_matrice_web.png)

### 4. Eseguire i Test Automatici

Per avviare i test, specificare la porta di connessione nel file `generate_changes_rand.py` e selezionare il test desiderato da eseguire.

![Selezione Porta e Test](/media/test/porta_opzione.png)


## Opzione 3: Tre Shell (Uso con Test Casuali)

Questa configurazione permette di eseguire test casuali oltre al backend e al server Flask.

### 0. Setup Iniziale

Aprire tre terminali (shell) e navigare nei seguenti percorsi:

- Primo terminale: `~/Distributed-Flood-Fill/src/test_script`

- Secondo terminale: `~/Distributed-Flood-Fill/src/test_script/test`

- Terzo terminale: `~/Distributed-Flood-Fill/src/data`



### 1. Generare Operazioni Casuali

Nel primo terminale, eseguire il seguente comando per generare operazioni casuali:
```
python3 generate_changes_rand.py --rows <ROWS> --columns <COLUMNS> --operations <NUMBER_OPERATIONS>
```
Ad esempio:
```
python3 generate_changes_rand.py --rows 7 --columns 7 --operations 10
```
Questo comando genererà i colori per una matrice 7x7 e 10 operazioni di ricolorazione casuali.



### 2. Avviare il Backend Erlang

Nel secondo terminale, eseguire:
```
./compile_and_run.sh <ROWS> <COLUMNS> <FROM_FILE>
```
Ad esempio:
```
./compile_and_run.sh 7 7 true
```
Questo comando compila ed esegue il backend Erlang per gestire i nodi della matrice.



### 3. Avviare il Server Flask

Nel terzo terminale, utilizzare la porta indicata dal backend Erlang per avviare il server Flask. Eseguire il seguente comando (sostituendo <PORTA> con la porta effettiva):
```
python3 grid_visualizer.py --debug False --port <PORTA>
```


Visitando l'indirizzo http://127.0.0.1:5000, è possibile visualizzare la matrice di nodi creata.



### 4. Eseguire i Test Casuali

Per avviare i test casuali, specificare la porta di connessione nello script `generate_changes_rand.py` e selezionare il test da eseguire.



### 5. Risultati dei Test


I seguenti test sono stati eseguiti per valutare il comportamento del sistema con diverse dimensioni della matrice e numero di operazioni:

| Test File          | Dimensione Matrice | Numero Operazioni |
|--------------------|--------------------|-------------------|
| `rand_5_5_5.mkv`   | 5x5                | 5                 |
| `rand_5_5_10.mkv`  | 5x5                | 10                |
| `rand_5_5_15.mkv`  | 5x5                | 15                |
| `rand_7_7_5.mkv`   | 7x7                | 5                 |
| `rand_7_7_10.mkv`  | 7x7                | 10                |
| `rand_7_7_15.mkv`  | 7x7                | 15                |
| `rand_10_10_5.mkv` | 10x10              | 5                 |
| `rand_10_10_10.mkv`| 10x10              | 10                |
| `rand_10_10_15.mkv`| 10x10              | 15                |
| `rand_15_15_10.mkv`| 15x15              | 10                |
| `rand_15_15_15.mkv`| 15x15              | 15                |
| `rand_20_20_10.mkv`| 20x20              | 10                |
| `rand_20_20_15.mkv`| 20x20              | 15                |


Questi test hanno permesso di osservare il comportamento del sistema in diverse condizioni, fornendo un'analisi dettagliata delle prestazioni e della resilienza del sistema.



### Conclusione

Questa configurazione a tre shell permette di avviare un ambiente completo di testing automatizzato e monitoraggio, utile per verificare il comportamento del sistema in scenari realistici e per osservare la resilienza del sistema in condizioni di utilizzo intensivo.

Per vedere delle esecuzioni, recarsi nella cartella `/media/Video/randomTest`.




# Descrizione dei Test
Di seguito si elencano e si spiegano i test creati per definire come si comporta il sistema in determinate condizioni:
## Caso 1: Richiesta di Cambio Colore con Timestamp Anteriore che Richiede un Merge
**Condizione**: Dopo che è stata eseguita un’operazione di cambio colore con timestamp T2 arriva una nuova richiesta con timestamp T1 < T2che, all'epoca T1, avrebbe portato a un merge con un cluster adiacente.

**Comportamento Atteso**:

- Viene ripristinato lo stato al tempo T1 per tenere conto della nuova richiesta.
- Si esegue il merge tra i due cluster come richiesto al tempo T1. 
- Si applica il colore risultante dall’operazione più recente, assicurando la coerenza dello stato.

    ![Case 1](/media/sequence_diagram/caso1.png)

**Descrizione** della funzione case1(PORT):

```python
def case1(PORT):
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1),
    ]
    
    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(4)
```

1. Primo messaggio:
    - **Nodo** **target**: Coordinate (1, 1)
    - **PID**: Otteniuto con get_pid_by_coordinates(nodes_data, 1, 1)
    - **Colore**: "blue"
    - **Timestamp**: time2 (tempo attuale + 1 secondo)
    - **Azione**: Invio di una richiesta di cambio colore verso "blue" con un timestamp futuro.

2. Secondo messaggio (inviato dopo 4 secondi):
    - **Nodo target**: Stesso nodo alle coordinate (1, 1)
    - **PID**: Come sopra
    - **Colore**: "purple"
    - **Timestamp**: time1 (tempo attuale)
    - **Azione**: Invio di una richiesta di cambio colore con un timestamp precedente che avrebbe richiesto un merge.

**Scopo**: Simulare una richiesta più vecchia che arriva in ritardo e avrebbe causato un merge. Il sistema dovrebbe ripristinare lo stato al tempo T1, eseguire il merge, e riapplicare le operazioni successive per garantire consistenza.


![Case 1](/media/gif/case1.gif)


## Caso 2: Richiesta di Cambio Colore con Timestamp Anteriore che Non Richiede un Merge
**Condizione**: Una richiesta con timestamp T1 < T2 arriva dopo che l’operazione con timestamp T2 ha già effettuato un merge. Tuttavia, la richiesta originale con T1 non avrebbe generato un merge.

**Comportamento Atteso**:
- Poiché lo stato è già stato aggiornato con un merge che cambia la configurazione, la richiesta con timestamp T1 viene ignorata. Questo evita di eseguire operazioni ormai superate che non rispettano le condizioni attuali.

    ![Case 2](/media/sequence_diagram/caso2.png)

**Obiettivo**: Valutare il comportamento del sistema di fronte a una richiesta di cambio colore non necessaria, che arriva con timestamp anteriore.

**Funzione nel codice**: `case2(PORT)`

**Esempio di codice**:

```python
python
Copia codice
def case2(PORT):
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)

    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "pink", time1),
    ]

    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(4)

```

**Descrizione**:

1. **Primo messaggio**:
    - **Nodo target**: Coordinate `(1, 1)`
    - **PID**: Otteniuto con `get_pid_by_coordinates(nodes_data, 1, 1)`
    - **Colore**: `"blue"`
    - **Timestamp**: `time2` (tempo attuale + 1 secondo)
    - **Azione**: Cambio colore verso `"blue"`.
2. **Secondo messaggio** (inviato dopo 4 secondi):
    - **Nodo target**: Stesso nodo alle coordinate `(1, 1)`
    - **Colore**: `"pink"`
    - **Timestamp**: `time1` (tempo attuale)
    - **Azione**: Cambio colore non necessario, poiché il nodo è già in stato aggiornato.

**Scopo**: Verificare che il sistema ignori richieste obsolete che non richiedono modifiche allo stato attuale.

![Case 2](/media/gif/case2.gif)

## Caso 3: Richiesta di Merge Ricevuta Durante un Cambio Colore con Timestamp Anteriore
**Condizione**: Un leader riceve una richiesta di merge mentre è in attesa di completare un cambio colore con timestamp anteriore.

**Comportamento Atteso**:

- Il leader attende un periodo di tempo definito per ricevere eventuali altre richieste in ritardo.
Se dopo il timeout non arrivano ulteriori richieste, procede con l’operazione di merge.

- **Motivazione**: Questo approccio riduce il rischio di inconsistenze dovute a operazioni fuori ordine, garantendo che le richieste precedenti vengano elaborate in modo adeguato prima di procedere.

    ![Case 3](/media/sequence_diagram/caso3.png)

**Obiettivo**: Verificare come il sistema gestisce una richiesta di merge mentre un leader è in attesa di completare un cambio colore con timestamp precedente.

**Funzione nel codice**: `case3(PORT)`

**Esempio di codice**:

```python
python
Copia codice
def case3(PORT):
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)

    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time2),
        (get_pid_by_coordinates(nodes_data, 1, 3), "green", time1),
    ]

    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(1)

```

**Descrizione**:

1. **Primo messaggio**:
    - **Nodo target**: Coordinate `(1, 1)`
    - **PID**: `get_pid_by_coordinates(nodes_data, 1, 1)`
    - **Colore**: `"purple"`
    - **Timestamp**: `time2`
    - **Azione**: Cambio colore verso `"purple"`.
2. **Secondo messaggio** (dopo 1 secondo):
    - **Nodo target**: `(1, 3)`
    - **Colore**: `"green"`
    - **Timestamp**: `time1`
    - **Azione**: Richiesta di merge da un nodo vicino.

**Scopo**: Verificare che il leader attenda eventuali richieste ritardate prima di procedere col merge.

![Case 3](/media/gif/case3.gif)

## Caso "Too Old": Gestione di una Richiesta con Timestamp Troppo Vecchio
**Condizione**: Un leader riceve una richiesta di cambio colore o di merge che ha un timestamp troppo vecchio rispetto all'ultima operazione completata.

**Comportamento Atteso**:

- La richiesta viene ignorata ("droppata") poiché il suo stato è ormai superato rispetto alle operazioni recenti. Questo evita modifiche non più rilevanti che potrebbero introdurre inconsistenze.

    ![Too old](/media/sequence_diagram/too_old.png)

**Obiettivo**: Garantire che il sistema ignori le richieste con timestamp troppo vecchi rispetto allo stato attuale.

**Funzione nel codice**: `too_old(PORT)`

**Esempio di codice**:

```python
python
Copia codice
def too_old(PORT):
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time1),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1 - timedelta(milliseconds=5000)),
    ]
    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(1)

```

**Descrizione**:

1. **Primo messaggio**:
    - **Nodo target**: `(1, 1)`
    - **Colore**: `"blue"`
    - **Timestamp**: `time1`
    - **Azione**: Cambio colore a `"blue"`.
2. **Secondo messaggio**:
    - **Nodo target**: `(1, 1)`
    - **Colore**: `"purple"`
    - **Timestamp**: `time1 - 5000ms`
    - **Azione**: Richiesta obsoleta.

**Scopo**: Confermare che il sistema ignori la richiesta obsoleta per evitare inconsistenze.

![Too old](/media/gif/too_old.gif)

## Caso "Change Color During Merge": Richiesta di Cambio Colore Ricevuta Durante un Merge
**Condizione**: Mentre è in corso un merge, un leader riceve una richiesta di cambio colore o di merge che è successiva rispetto a quella in esecuzione.

**Comportamento Atteso**:

- La richiesta viene messa in coda ed eseguita successivamente, evitando di alterare lo stato attuale mentre il merge è in esecuzione.
    
    ![change_color_during_merge](/media/sequence_diagram/change_color_during_merge.png)

**Obiettivo**: Verificare la gestione di una richiesta di cambio colore durante un merge.

**Funzione nel codice**: `change_color_during_merge(PORT)`

**Esempio di codice**:

```python
python
Copia codice
def change_color_during_merge(PORT):
    nodes_data = load_nodes_data()
    operations = [
        (get_pid_by_coordinates(nodes_data, 3, 4), "purple", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 5), "pink", datetime.now() + timedelta(milliseconds=1000)),
    ]
    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(0.5)

```

**Descrizione**:

1. **Prima richiesta**:
    - **Nodo**: `(3, 4)` con colore `"purple"`.
2. **Seconda richiesta**:
    - **Nodo**: `(5, 5)` con colore `"pink"`, mentre il merge è ancora in corso.

**Scopo**: Confermare che il sistema metta in coda la nuova richiesta, evitando interferenze. 

![change_color_during_merge](/media/gif/change_color_during_merge.gif)

## Caso "Double Merge": Doppio Merge tra Cluster Adiacenti con Cambio Colore
**Condizione**: Due cluster adiacenti, inizialmente di colori diversi, ricevono una richiesta di cambio colore che porta entrambi a diventare dello stesso colore.

**Comportamento Atteso**:

- Si esegue un merge, unendo i cluster nel nuovo colore comune, creando un unico cluster più grande.

    
    ![Double merge](/media/sequence_diagram/doubleMerge.png)

**Obiettivo**: Verificare la gestione di due merge simultanei.

**Funzione nel codice**: `doubleMerge(PORT)`

**Esempio di codice**:

```python
python
Copia codice
def doubleMerge(PORT):
    nodes_data = load_nodes_data()
    operations = [
        (get_pid_by_coordinates(nodes_data, 3, 2), "green", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 3), "green", datetime.now()),
    ]
    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(0.1)

```

**Descrizione**:

1. **Nodo `(3, 2)`** con colore `"green"`.
2. **Nodo `(5, 3)`** con colore `"green"`.

**Scopo**: Simulare la fusione simultanea di due cluster adiacenti nello stesso colore, creando un singolo cluster.   
![Double merge](/media/gif/doubleMerge.gif)
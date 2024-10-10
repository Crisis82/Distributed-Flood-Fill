# Distributed-Flood-Fill

1) setup dimensione N x M, palette colori.
2) setup colore random per ogni nodo (inizializzati a leader)
3) merge iniziale dei cluster di colore (a 4 o 8?)
4) test random su colore e nodo

Ogni cluster e' una MST assestante (vedi algoritmi per creazione MST).
Approccio soluzione tramite leader per ogni MST.
Scelta leader ottimizzata per:
    - efficienza messaggi -> leader centrale al cluster
    - efficienza merge cluster -> leader sul bordo del cluser

Controllare capitolo su message broadcasting: la scelta del leader permette di evitare il locking, inoltre l'ordinamento dei messaggi puo' essere gestito tramite priorita' timestamp.

File offline, sincronizzati con una replica online del file struct per ridondanza. (necessario un versioning dei file?)

Fail-safe, come implementiamo?

Fasi implementazione:
    - decisione algoritmo di creazione mst
    - finalizzazione struct
    - scelta ottimizzazione per leader
    - costruzione sistema di broadcasting con timestamp (due strutture: node->leader e leader->leader)
    - implementazione meccanismo di sync e redundancy
    - implementazione di procedura Fail-safe
    - implementazione grafica interattiva

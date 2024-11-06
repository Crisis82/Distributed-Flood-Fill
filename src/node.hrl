%% Records' definition for node and leader
-record(node, {pid, x, y, leaderID, neighbors = []}).
-record(leader, {
    node, color, serverID, last_event, adj_clusters = [], cluster_nodes = []
}).

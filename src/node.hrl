%% Records' definition for node and leader
-record(node, {x, y, parent, children = [], time, leaderID, pid, neighbors = []}).
-record(leader, {
    node, color, serverID, last_event, adjClusters = [], nodes_in_cluster = []
}).

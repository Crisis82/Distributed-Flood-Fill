%% Records' definition for node and leader
-record(node, {x, y, parent, children = [], time, leaderID, pid, neighbors = []}).
-record(leader, {
    node, color, serverID, last_timestamp = 0, adjClusters = [], nodes_in_cluster = []
}).

"""
Distributed System Node Testing and Management Script

Description:
This Python script is designed to automate a variety of operations on nodes within a distributed system. 
It facilitates testing the behavior of nodes under different conditions, including color changes, 
merging scenarios, and conditions based on timing constraints. The script communicates with an Erlang server 
via TCP, sending requests to change node colors and reset database configurations, making it particularly 
useful for testing distributed cluster setups and ensuring stability across various operations.

Key Features:
1. **Database Reset**: The `elimina_DB` function removes all directories within the `DB` directory, 
   resetting the state of the node data for a fresh start.
2. **Color Configuration**: The `generate_colors_file` function generates a `colors.txt` file based on 
   specified matrix dimensions (NxM), either randomly or using a predefined palette.
3. **Node Operations**:
   - **case1, case2, case3**: Execute multiple color change operations on nodes with varied timing 
     to test the distributed system’s response to simultaneous updates.
   - **too_old**: Tests the scenario where an outdated timestamp is used, observing the system's response 
     to requests with a time constraint.
   - **merge_successivo**: Initiates color changes on nodes in close proximity to simulate cluster merging.
   - **change_color_during_merge**: Sends color change requests to two nodes while one is merging, 
     testing for consistency in dynamic merging situations.
   - **doubleMerge**: Tests the behavior of two nearby clusters merging into a single one.

4. **Helper Functions**:
   - `load_leaders_data` and `load_nodes_data` load data from JSON files to access information on 
     the current state of leaders and nodes.
   - `send_color_change_request` sends a TCP request to the Erlang server to initiate a color change 
     on a specified node with a specific timestamp.
   - `get_pid_by_coordinates` retrieves a node’s PID based on its x, y coordinates for targeted operations.

Usage:
- Run the script and follow the prompts to specify the matrix size, database reset, and port configuration.
- Choose one of the available test cases to execute and observe the distributed system’s response 
  to various color change scenarios.

    python3 script.py

Dependencies:
- Requires `psutil` for managing processes.
- Requires a running Erlang server to handle incoming TCP requests.
- JSON configuration files `leaders_data.json` and `nodes_data.json` are expected to be present in 
  the specified `data` directory.

Setup Instructions:
1. Ensure the Erlang server is compiled and running.
2. Start the visualization script (if applicable) on a separate terminal.
3. Run this Python script and follow the instructions provided in the terminal to execute specific test cases.

Note:
Each test scenario introduces a unique set of conditions to test the distributed system’s resilience, 
timing sensitivity, and response to simultaneous and sequential updates across clusters.
"""

import json
import os
import socket
import time
import random
import psutil
import shutil
from datetime import datetime, timedelta

# Main directory path

def elimina_DB():
    """
    Deletes all directories within the `DB` directory to reset node data.

    Preconditions:
    - The `DB` directory should exist within the project structure.

    Postconditions:
    - All subdirectories within `DB` are removed, resetting the node data storage.
    - Prints a message indicating the directories have been removed or that `DB` does not exist.
    """
    db_dir = os.path.join(os.path.dirname(__file__), "..", "DB")
    if os.path.exists(db_dir):
        for directory in os.listdir(db_dir):
            dir_path = os.path.join(db_dir, directory)
            if os.path.isdir(dir_path):
                shutil.rmtree(dir_path)
                print(f"Removed directory: {dir_path}")
        print("All directories within ../DB have been removed.")
    else:
        print("Directory ../DB does not exist.")

# Paths for JSON files
LEADERS_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "leaders_data.json")
NODES_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "nodes_data.json")

# Erlang server settings
HOST = 'localhost'

# List of available colors for testing
COLORS = ["red", "green", "blue", "yellow", "purple"]

# Default color palette for nodes
TAVOLOZZA = [
    "red", "blue", "yellow", "red", "purple", "purple", "blue", "purple", "yellow", "blue",
    "purple", "yellow", "yellow", "green", "purple", "yellow", "yellow", "red", "yellow", "blue",
    "blue", "yellow", "red", "purple", "purple"
]

def generate_colors_file(N, M, random_colors):
    """
    Generates a colors file for an NxM matrix and writes it to `colors.txt`.

    Preconditions:
    - `N` and `M` define the grid size.
    - `random_colors` is a boolean. If True, colors are chosen randomly; otherwise, a default palette is used.

    Postconditions:
    - A `colors.txt` file is generated containing colors for each cell in the grid.
    - Displays instructions for the user to continue setup.
    """
    if random_colors:
        colors = [random.choice(COLORS) for _ in range(N * M)]
    else:
        colors = TAVOLOZZA
    colors_filepath = os.path.join(os.path.dirname(__file__), "..", "..", "config", "colors.txt")
    with open(colors_filepath, "w") as file:
        file.write("\n".join(colors))
    print(f"File colors.txt generated with {N}*{M} colors.")

    print("\nEnsure you execute the following in another terminal:\n")
    print(f"./compile_and_run.sh {N} {M} true\n")
    
def load_leaders_data():
    """
    Loads leader data from the JSON file.

    Preconditions:
    - `LEADERS_FILE` exists and is a valid JSON file.

    Postconditions:
    - Returns a list of leader data if successful.
    - Prints an error if the JSON file cannot be loaded.
    """
    try:
        with open(LEADERS_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Error loading leaders JSON file.")
        return []

def load_nodes_data():
    """
    Loads node data from the JSON file.

    Preconditions:
    - `NODES_FILE` exists and is a valid JSON file.

    Postconditions:
    - Returns a list of node data if successful.
    - Prints an error if the JSON file cannot be loaded.
    """
    try:
        with open(NODES_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Error loading nodes JSON file.")
        return []

def send_color_change_request(pid, color, timestamp, PORT):
    """
    Sends a color change request for a specific PID to the Erlang server.

    Preconditions:
    - `pid` is a valid node identifier.
    - `color` is a valid color string.
    - `timestamp` is a datetime object.
    - `PORT` is the server's active listening port.

    Postconditions:
    - Sends a TCP request to change the node's color and prints the server's response.
    - Returns True if the operation is successful, otherwise False.
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            message = f"change_color,{pid},{color},{timestamp.hour},{timestamp.minute},{timestamp.second}"
            print(f"\nSending color change message: {message}")
            s.sendall(message.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            print(f"Server response: {response}")
            return response == "ok"
    except Exception as e:
        print(f"Error during command sending: {e}")
        return False

def get_pid_by_coordinates(data, x, y):
    """
    Retrieves the PID of a node based on coordinates.

    Preconditions:
    - `data` contains node information with coordinates and PIDs.
    - `x` and `y` are integer coordinates of the target node.

    Postconditions:
    - Returns the PID of the node at (x, y) if found, otherwise returns None.
    """
    for node in data:
        node_x, node_y = node["x"], node["y"]
        if node_x == x and node_y == y:
            return node["pid"]
    return None

def too_old(PORT):
    """
    Sends a color change request with an outdated timestamp for testing timestamp constraints.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends two color requests for the same node with differing timestamps, one outdated.
    """
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time1),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1 - timedelta(milliseconds=5000)),
    ]
    for pid, color, t in operations:
        send_color_change_request(pid, color, t, PORT)
        time.sleep(1)

# Function to execute multiple color change operations with delayed timestamps
def case1(PORT):
    """
    Sends two color change requests with overlapping timestamps for a single node.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends two color change requests with a 1-second delay between them for the same node.
    - A 4-second pause occurs between each operation.
    """
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time1),
    ]
    
    for operation in operations:
        pid, color, t = operation
        send_color_change_request(pid, color, t, PORT)
        time.sleep(4)

# Function to execute color changes with different timestamps and colors
def case2(PORT):
    """
    Sends two color change requests for a single node with different colors and timestamps.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends color change requests with differing colors and timestamps.
    - A 4-second pause occurs between each operation.
    """
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "blue", time2),
        (get_pid_by_coordinates(nodes_data, 1, 1), "pink", time1),
    ]
    
    for operation in operations:
        pid, color, t = operation
        send_color_change_request(pid, color, t, PORT)
        time.sleep(4)

# Function to execute color change operations across different nodes
def case3(PORT):
    """
    Sends color change requests for two different nodes with close timestamps.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends color change requests for two different nodes.
    - A 1-second pause occurs between each operation.
    """
    nodes_data = load_nodes_data()
    time1 = datetime.now()
    time2 = datetime.now() + timedelta(milliseconds=1000)
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 1, 1), "purple", time2),
        (get_pid_by_coordinates(nodes_data, 1, 3), "green", time1),
    ]
    
    for operation in operations:
        pid, color, t = operation
        send_color_change_request(pid, color, t, PORT)
        time.sleep(1)

# Function to execute color change during an ongoing merge operation
def change_color_during_merge(PORT):
    """
    Sends color change requests during an ongoing merge operation to test conflict handling.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends two color change requests, with the second delayed by 1 second, to test merge conflict resolution.
    - A 0.5-second pause occurs between each operation.
    """
    nodes_data = load_nodes_data()
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 3, 4), "purple", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 5), "pink", datetime.now() + timedelta(milliseconds=1000)),
    ]
    
    for operation in operations:
        pid, color, t = operation
        send_color_change_request(pid, color, t, PORT)
        time.sleep(0.5)

# Function to test two simultaneous merge operations
def doubleMerge(PORT):
    """
    Sends color change requests for two different nodes to initiate simultaneous merges.

    Preconditions:
    - `PORT` is the active server port.

    Postconditions:
    - Sends color change requests to trigger two simultaneous merges.
    - A 0.1-second pause occurs between each operation.
    """
    nodes_data = load_nodes_data()
    
    operations = [
        (get_pid_by_coordinates(nodes_data, 3, 2), "green", datetime.now()),
        (get_pid_by_coordinates(nodes_data, 5, 3), "green", datetime.now()),
    ]
    
    for operation in operations:
        pid, color, t = operation
        send_color_change_request(pid, color, t, PORT)
        time.sleep(0.1)




def main():
    """
    Main function for initializing tests based on user input.

    Preconditions:
    - User is prompted to specify the server port and desired test case.

    Postconditions:
    - Executes the selected test case based on user input.
    """
    N, M = 5, 5  # Dimensions of the matrix
    elimina_DB()
    generate_colors_file(N, M, False)
    PORT = int(input("Enter the port to use: "))
    print("Choose an operation to execute:")
    print("1. case1")
    print("2. case2")
    print("3. case3")
    print("4. too_old")
    print("5. change_color_during_merge")
    print("6. doubleMerge")

    choice = input("Enter the number of the desired operation: ")
    if choice == "1":
        case1(PORT)
    elif choice == "2":
        case2(PORT)
    elif choice == "3":
        case3(PORT)
    elif choice == "4":
        too_old(PORT)
    elif choice == "5":
        change_color_during_merge(PORT)
    elif choice == "6":
        doubleMerge(PORT)
    else:
        print("Invalid choice. Exiting program.")

if __name__ == "__main__":
    main()

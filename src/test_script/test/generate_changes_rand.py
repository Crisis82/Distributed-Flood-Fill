"""
Distributed System Node Color Change and Management Script

Description:
This Python script facilitates managing a distributed node system by generating color configurations, 
sending color change requests, and resetting or terminating processes when necessary. It is designed to interact 
with an Erlang server via TCP to change node colors and handle process control, providing a simple way to test and manage 
distributed cluster setups.

Features:
1. **Database Reset**: Deletes all directories within the main `DB` directory to reset the node data.
2. **Color File Generation**: Generates a `colors.txt` file with color assignments for a grid of nodes.
3. **Color Change Requests**: Sends color change commands to individual nodes on the Erlang server using a TCP socket connection.
4. **Process Termination**: Terminates any processes running on a specified port, helping with server management and setup.
5. **Batch Operations**: Executes multiple random operations, such as color changes and node kills, based on input parameters.

Usage:
- Run the script with the following optional arguments:
    * `--rows`: The number of rows (N) for the node matrix.
    * `--columns`: The number of columns (M) for the node matrix.
    * `--operations`: The number of operations to perform.

Example:
    ```
    python script_name.py --rows 5 --columns 5 --operations 10
    ```

Dependencies:
- Requires the `psutil` library for process management and termination.
- Configurations are stored in `../config/colors.txt`.
- The `data` and `DB` directories should be present in the parent directory structure for data handling and logging.

Setup:
1. Run `./compile_and_run.sh N M true` in an Erlang terminal.
2. Start the visualizer with `./start_visualizer.sh`.
3. Run this script once the above steps are completed.

Note:
Ensure that the Erlang server is running and the correct port is specified for communication. The script will prompt 
for the port number if not provided.
"""


import json
import os
import socket
import time
import random
import psutil
import shutil
from datetime import datetime, timedelta
import argparse
import sys

# Define the main DB directory path
DB_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "DB")
LEADERS_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "leaders_data.json")
NODES_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "data", "nodes_data.json")
HOST = 'localhost'  # Erlang server host

# Colors for testing and a custom palette for manual assignment
COLORS = ["red", "green", "blue", "yellow", "purple"]
TAVOLOZZA = [
    "red", "blue", "yellow", "red", "purple", "purple", "blue", "purple", 
    "yellow", "blue", "purple", "yellow", "yellow", "green", "purple", 
    "yellow", "yellow", "red", "yellow", "blue", "blue", "yellow", 
    "red", "purple", "purple"
]

def elimina_DB():
    """
    Deletes all directories within the main DB directory.
    If the DB directory exists, removes each subdirectory within it.
    """
    if os.path.exists(DB_DIR):
        for directory in os.listdir(DB_DIR):
            dir_path = os.path.join(DB_DIR, directory)
            if os.path.isdir(dir_path):
                shutil.rmtree(dir_path)
                print(f"Removed directory: {dir_path}")
        print("All directories within ../DB have been removed.")
    else:
        print("Directory ../DB does not exist.")

def generate_colors_file(N, M, random_colors):
    """
    Generates a colors.txt file for a matrix of dimensions NxM.
    - If random_colors is True, uses a random selection from COLORS.
    - If False, uses the preset TAVOLOZZA color list.
    """
    colors = [random.choice(COLORS) for _ in range(N * M)] if random_colors else TAVOLOZZA
    colors_filepath = os.path.join(os.path.dirname(__file__), "..", "..", "config", "colors.txt")
    
    with open(colors_filepath, "w") as file:
        file.write("\n".join(colors))
    print(f"Generated colors.txt with {N}x{M} colors.")

    print("\nBefore running the script, execute the following commands in separate terminals:\n")
    print(f"./compile_and_run.sh {N} {M} true")
    
    input("\nPress Enter once you've completed the commands in the Erlang terminal to continue...")

def load_leaders_data():
    """
    Loads leader data from the JSON file.
    Returns:
        List of leader data, or an empty list if loading fails.
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
    Returns:
        List of node data, or an empty list if loading fails.
    """
    try:
        with open(NODES_FILE, "r") as file:
            return json.load(file)
    except json.JSONDecodeError:
        print("Error loading nodes JSON file.")
        return []

def send_color_change_request(pid, color, timestamp, PORT):
    """
    Sends a color change request to the Erlang server via TCP.
    Arguments:
        pid: Process ID of the node.
        color: New color for the node.
        timestamp: Time for the color change request.
        PORT: Server port to connect to.
    Returns:
        True if the request was successful; False otherwise.
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
        print(f"Error sending command: {e}")
        return False

def perform_multiple_operations(num_operations, PORT):
    """
    Performs multiple random operations (color changes) on nodes.
    Arguments:
        num_operations: Number of color change requests to perform.
        PORT: Server port to connect to.
    """
    nodes_data = load_nodes_data()

    for _ in range(num_operations):
        node = random.choice(nodes_data)
        pid = node["pid"]
        color = random.choice(COLORS)

        # Add random variation to the current time
        variation = timedelta(milliseconds=0) if len(sys.argv) > 1 else timedelta(milliseconds=random.randint(-5000, 5000))
        timestamp = datetime.now() + variation

        success = send_color_change_request(pid, color, timestamp, PORT)
        if success:
            print(f"Color changed for PID {pid} to {color} at {timestamp}")
        else:
            print(f"Failed to change color for PID {pid} at {timestamp}")

        time.sleep(1)  # Pause between operations

def kill_process_on_port(port):
    """
    Finds and terminates the process using the specified port.
    Arguments:
        port: The port number to check.
    Returns:
        True if a process was terminated; False otherwise.
    """
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            for conn in proc.connections(kind='inet'):
                if conn.laddr.port == port:
                    print(f"Found process '{proc.info['name']}' with PID {proc.info['pid']} on port {port}. Terminating...")
                    proc.terminate()
                    proc.wait(timeout=3)
                    return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    print(f"No process found on port {port}.")
    return False

def main():
    """
    Main function to run color changes and process management.
    Configures from command-line arguments or user input.
    """
    parser = argparse.ArgumentParser(description="Execute color changes and process terminations on nodes")
    parser.add_argument('--rows', type=int, help="Number of rows (N)")
    parser.add_argument('--columns', type=int, help="Number of columns (M)")
    parser.add_argument('--operations', type=int, help="Number of operations to perform")
    args = parser.parse_args()

    N = args.rows if args.rows is not None else int(input("Enter number of rows (N): "))
    M = args.columns if args.columns is not None else int(input("Enter number of columns (M): "))
    num_operations = args.operations if args.operations is not None else int(input("Enter number of operations to perform: "))

    elimina_DB()
    generate_colors_file(N, M, True)
    PORT = int(input("Enter the port number to use: "))

    perform_multiple_operations(num_operations, PORT)

# Execute the main function if the script is run directly
if __name__ == "__main__":
    main()

import socket

def send_to_erlang(message):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect(('localhost', 8080))
        s.sendall(message.encode())
        s.close()

send_to_erlang("Cambio colore!")

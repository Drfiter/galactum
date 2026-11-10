#!/usr/bin/env python3
"""Healthcheck del SSS: abre una conexión WebSocket al puerto del servidor y
espera la respuesta 101 (Switching Protocols). Sale con 0 si responde."""
import base64
import os
import socket
import sys

port = int(os.environ.get("SSS_PORT", "9100"))
key = base64.b64encode(os.urandom(16)).decode()
request = (
    "GET / HTTP/1.1\r\n"
    f"Host: 127.0.0.1:{port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
)
try:
    with socket.create_connection(("127.0.0.1", port), timeout=4) as s:
        s.sendall(request.encode())
        reply = s.recv(256).decode(errors="replace")
    sys.exit(0 if " 101 " in reply.split("\r\n", 1)[0] + " " else 1)
except OSError:
    sys.exit(1)

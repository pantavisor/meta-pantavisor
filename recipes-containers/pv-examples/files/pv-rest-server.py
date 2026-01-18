#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import socket
import os

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/info':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = {
                "service": "network-manager-mock",
                "status": "online",
                "role": self.headers.get('X-PV-Role', 'unknown'),
                "client": self.headers.get('X-PV-Client', 'unknown')
            }
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

class UnixHTTPServer(HTTPServer):
    def server_bind(self):
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()

def run(socket_path='/run/nm/api.sock'):
    if os.path.exists(socket_path):
        os.remove(socket_path)
    os.makedirs(os.path.dirname(socket_path), exist_ok=True)
    
    server_address = socket_path
    httpd = UnixHTTPServer(server_address, SimpleHandler, bind_and_activate=False)
    httpd.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    httpd.server_bind()
    httpd.server_activate()
    
    print(f"Starting mock REST server on {socket_path}...")
    httpd.serve_forever()

if __name__ == '__main__':
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else '/run/nm/api.sock'
    run(path)

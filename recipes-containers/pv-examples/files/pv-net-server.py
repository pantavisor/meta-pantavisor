#!/usr/bin/env python3
"""
Simple HTTP server for IPAM network testing.
Listens on all interfaces and returns container info.
"""

import http.server
import json
import os
import socket
import sys

PORT = 8080

class NetworkTestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {'status': 'healthy'}
            self.wfile.write(json.dumps(response).encode())
        elif self.path == '/info':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                'hostname': socket.gethostname(),
                'addresses': self._get_addresses(),
                'container': os.environ.get('PV_CONTAINER_NAME', 'unknown')
            }
            self.wfile.write(json.dumps(response, indent=2).encode())
        else:
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'IPAM Network Test Server\n')
            self.wfile.write(f'Hostname: {socket.gethostname()}\n'.encode())

    def _get_addresses(self):
        addrs = []
        try:
            hostname = socket.gethostname()
            addrs = socket.gethostbyname_ex(hostname)[2]
        except:
            pass
        return addrs

    def log_message(self, format, *args):
        print(f"[net-server] {self.address_string()} - {format % args}")

def main():
    print(f"Starting network test server on port {PORT}")
    print(f"Hostname: {socket.gethostname()}")

    with http.server.HTTPServer(('', PORT), NetworkTestHandler) as httpd:
        print(f"Serving on 0.0.0.0:{PORT}")
        httpd.serve_forever()

if __name__ == '__main__':
    main()

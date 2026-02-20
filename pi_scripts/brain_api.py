#!/usr/bin/env python3
"""
Brain API - Simple HTTP server for controlling the headless Pi from the tablet app.
Run as a systemd service on the Pi.
"""

import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
import os

PORT = 8080
TOKEN = os.environ.get('BRAIN_TOKEN', 'brain')

class BrainHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _check_auth(self):
        token = self.headers.get('Authorization', '').replace('Bearer ', '')
        if token != TOKEN:
            self._send_json({'error': 'Unauthorized'}, 401)
            return False
        return True

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            if not self._check_auth():
                return
            try:
                # Get CPU temperature
                temp = subprocess.check_output(['vcgencmd', 'measure_temp']).decode().strip()
                temp = temp.replace("temp=", "").replace("'C", "")

                # Get uptime
                uptime = subprocess.check_output(['uptime', '-p']).decode().strip()

                # Get memory
                mem = subprocess.check_output(['free', '-h']).decode()
                mem_lines = mem.split('\n')[1].split()
                mem_used = mem_lines[2]
                mem_total = mem_lines[1]

                # Get IP
                ip = subprocess.check_output(['hostname', '-I']).decode().strip().split()[0]

                self._send_json({
                    'online': True,
                    'temperature': float(temp),
                    'uptime': uptime,
                    'memory': f'{mem_used}/{mem_total}',
                    'ip': ip
                })
            except Exception as e:
                self._send_json({'online': True, 'error': str(e)})
        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        if not self._check_auth():
            return

        if self.path == '/shutdown':
            self._send_json({'message': 'Shutting down...'})
            subprocess.Popen(['sudo', 'shutdown', '-h', 'now'])
        elif self.path == '/reboot':
            self._send_json({'message': 'Rebooting...'})
            subprocess.Popen(['sudo', 'shutdown', '-r', 'now'])
        else:
            self._send_json({'error': 'Not found'}, 404)

    def log_message(self, format, *args):
        print(f"[BrainAPI] {args[0]}")

if __name__ == '__main__':
    print(f"Brain API starting on port {PORT}")
    server = HTTPServer(('0.0.0.0', PORT), BrainHandler)
    server.serve_forever()

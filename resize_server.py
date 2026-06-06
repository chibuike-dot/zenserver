#!/usr/bin/env python3
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        if self.path == '/resize':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            w, h = body.get('width', 1280), body.get('height', 800)
            subprocess.run(['xrandr','--display',':1','--fb',f'{w}x{h}'])
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'ok': True}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a): pass

HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()

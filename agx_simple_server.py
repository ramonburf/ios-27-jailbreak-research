import http.server, socketserver
from pathlib import Path

PORT = 8081
PDF_DIR = Path('this repository/analysis/pdf')

INDEX_HTML = """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>AGX Probe Test</title></head>
<body style="background:#1a1a1a;color:#0f0;font-family:monospace;padding:2rem;">
  <h1>&#x2705; Server Reachable</h1>
  <p>If you can see this, the HTTP server is working from your iPhone.</p>
  <p><strong>PC IP:</strong> 127.0.0.1</p>
  <p><strong>Port:</strong> 8081</p>
  <h2>PDF Probes:</h2>
  <ul>
    <li><a href="/pdf/type5_devicen4.pdf">type5_devicen4.pdf</a> (control - 4 components)</li>
    <li><a href="/pdf/type5_devicen8.pdf">type5_devicen8.pdf</a> (probe - 8 components)</li>
    <li><a href="/pdf/type5_devicen16.pdf">type5_devicen16.pdf</a> (probe - 16 components)</li>
    <li><a href="/pdf/type5_devicen32.pdf">type5_devicen32.pdf</a> (probe - 32 components)</li>
  </ul>
  <p><em>Open each PDF in Safari. Watch for crashes, resprings, or reboots.</em></p>
</body>
</html>"""

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print("%s - %s" % (self.address_string(), format % args))
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            body = INDEX_HTML.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == '/status':
            import json
            body = json.dumps({'server': 'agx-probe-server', 'port': PORT}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path.startswith('/pdf/'):
            name = self.path[5:]
            p = PDF_DIR / name
            if p.exists() and p.suffix.lower() == '.pdf':
                data = p.read_bytes()
                self.send_response(200)
                self.send_header('Content-Type', 'application/pdf')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

print(f'Serving on 0.0.0.0:{PORT}')
print(f'iPhone URL: http://127.0.0.1:{PORT}/')
print(f'PDF: http://127.0.0.1:{PORT}/pdf/type5_devicen8.pdf')
import sys
sys.stdout.flush()

with socketserver.TCPServer(('0.0.0.0', PORT), H) as httpd:
    httpd.serve_forever()

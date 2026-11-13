import http.server, socketserver
from pathlib import Path

PORT = 8081
PDF_DIR = Path('this repository/analysis/pdf')

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print("%s - %s" % (self.address_string(), format % args))
    def do_GET(self):
        if self.path == '/status':
            body = b'{"server":"agx-probe-server","port":8081}'
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
print(f'iPhone URL: http://127.0.0.1:{PORT}/status')
print(f'PDF: http://127.0.0.1:{PORT}/pdf/type5_devicen8.pdf')
import sys
sys.stdout.flush()

with socketserver.TCPServer(('0.0.0.0', PORT), H) as httpd:
    httpd.serve_forever()

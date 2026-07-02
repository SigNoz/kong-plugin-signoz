"""Minimal OTLP/HTTP sink: accepts any POST, dumps path + printable body bytes.

Protobuf payloads keep attribute keys as plain strings in the wire bytes,
so assertions can grep this output regardless of encoder.
"""
import http.server
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('content-length', 0) or 0)
        body = self.rfile.read(n)
        sys.stdout.write("== POST %s ct=%s len=%d\n" % (
            self.path, self.headers.get('content-type'), n))
        sys.stdout.write(
            ''.join(chr(b) if 32 <= b < 127 else '.' for b in body) + "\n")
        sys.stdout.flush()
        self.send_response(200)
        self.send_header('content-length', '0')
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(('0.0.0.0', 4318), Handler).serve_forever()

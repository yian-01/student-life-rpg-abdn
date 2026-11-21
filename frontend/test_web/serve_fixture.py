import argparse
import mimetypes
import ssl
import subprocess
import tempfile
import threading
from socketserver import ThreadingMixIn
from pathlib import Path
from wsgiref.simple_server import WSGIRequestHandler, WSGIServer, make_server

from sync_server import SyncApp

parser = argparse.ArgumentParser()
parser.add_argument('web_root', type=Path)
parser.add_argument('--web-port', type=int, default=0)
parser.add_argument('--api-port', type=int, help='Serve API on a separate HTTPS origin')
args = parser.parse_args()
web_root = args.web_root.resolve()

class Quiet(WSGIRequestHandler):
    def log_message(self, fmt, *args):
        pass

class ThreadedServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    cert = root / 'fixture.pem'
    key = root / 'fixture.key'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1',
                    '-keyout', str(key), '-out', str(cert), '-days', '1'],
                   check=True, capture_output=True)
    def app(environ, start_response):
        path = environ['PATH_INFO']
        if path.startswith('/v1/') or path == '/healthz':
            if args.api_port is not None:
                start_response('404 Not Found', [('Content-Length', '0')])
                return [b'']
            environ['wsgi.url_scheme'] = 'https'
            return sync(environ, start_response)
        if path == '/storage-fixture':
            data = b'<html><script src="/student_life_browser.js"></script></html>'
            start_response('200 OK', [('Content-Type', 'text/html'), ('Content-Length', str(len(data)))])
            return [data]
        file = (web_root / path.lstrip('/')).resolve()
        if not file.is_relative_to(web_root):
            start_response('404 Not Found', [])
            return [b'']
        if not file.is_file():
            file = web_root / 'index.html'
        data = file.read_bytes()
        content_type = mimetypes.guess_type(file)[0] or 'application/octet-stream'
        start_response('200 OK', [('Content-Type', content_type), ('Content-Length', str(len(data)))])
        return [data]
    with make_server('127.0.0.1', args.web_port, app, server_class=ThreadedServer, handler_class=Quiet) as server:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        origin = f'https://127.0.0.1:{server.server_port}'
        sync = SyncApp(root / 'database.sqlite3', signup_code='student-life-fixture',
                       allowed_origins=[origin] if args.api_port is not None else [])
        def api(environ, start_response):
            environ['wsgi.url_scheme'] = 'https'
            return sync(environ, start_response)
        api_server = None
        try:
            if args.api_port is not None:
                api_server = make_server('127.0.0.1', args.api_port, api,
                                         server_class=ThreadedServer, handler_class=Quiet)
                api_server.socket = context.wrap_socket(api_server.socket, server_side=True)
                threading.Thread(target=api_server.serve_forever, daemon=True).start()
            print(origin, flush=True)
            print(f'https://127.0.0.1:{api_server.server_port}' if api_server else origin, flush=True)
            server.serve_forever()
        finally:
            if api_server:
                api_server.shutdown()
                api_server.server_close()

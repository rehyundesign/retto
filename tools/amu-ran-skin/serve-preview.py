"""Loopback-only review server with image caching and no per-frame request log."""
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
import argparse
root=Path(__file__).resolve().parent
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(root),**kwargs)
 def log_message(self,*args):pass
 def end_headers(self):
  self.send_header('Cache-Control','public,max-age=86400' if self.path.partition('?')[0].endswith(('.png','.gif','.webp')) else 'no-store')
  super().end_headers()
parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8773);args=parser.parse_args()
server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
print(f'http://127.0.0.1:{server.server_port}/preview-full.html',flush=True)
server.serve_forever()

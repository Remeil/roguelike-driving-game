import http.server
import ssl
import socketserver
import os
import subprocess

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
exports_dir = os.path.join(base_dir, "exports")
cert_path = os.path.join(exports_dir, "cert.pem")
key_path = os.path.join(exports_dir, "key.pem")
web_dir = os.path.join(exports_dir, "Web")

if not os.path.exists(cert_path) or not os.path.exists(key_path):
    print("Generating self-signed SSL certificate...")
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "365", "-nodes", "-subj", "/CN=localhost"
    ], check=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

os.chdir(web_dir)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=cert_path, keyfile=key_path)

PORT = 5173
with socketserver.TCPServer(('', PORT), Handler) as httpd:
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    print(f"🔒 Secure Context HTTPS Server running!")
    print(f"   Local:  https://localhost:{PORT}/ProjectInterceptor.html")
    print(f"   LAN:    https://<YOUR-LOCAL-IP>:{PORT}/ProjectInterceptor.html")
    print("\n(Tip: When opening on another device, click 'Advanced -> Proceed' to accept the self-signed cert.)")
    httpd.serve_forever()

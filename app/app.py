from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os

PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"healthy")
            return

        if self.path == "/":
            body = {
                "application": "secure-eks-demo",
                "status": "running",
                "platform": "Amazon EKS"
            }

            response = json.dumps(body).encode()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response)
            return

        self.send_response(404)
        self.end_headers()


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib
import hmac
import json
import os

WEBHOOK_SECRET = os.getenv("ZGITEA_WEBHOOK_SECRET", "dev-secret")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        signature = self.headers.get("X-Hub-Signature-256", "")

        expected = "sha256=" + hmac.new(
            WEBHOOK_SECRET.encode("utf-8"), body, hashlib.sha256
        ).hexdigest()

        if not hmac.compare_digest(signature, expected):
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"invalid signature")
            return

        event = json.loads(body.decode("utf-8") or "{}")
        self.send_response(202)
        self.end_headers()
        self.wfile.write(
            json.dumps({"accepted": True, "ref": event.get("ref", "unknown")}).encode("utf-8")
        )


def run() -> None:
    port = int(os.getenv("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"edge-router listening on :{port}")
    server.serve_forever()


if __name__ == "__main__":
    run()

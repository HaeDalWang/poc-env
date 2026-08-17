"""Normalize Alertmanager JSON-RPC payloads and forward them asynchronously."""

import json
import os
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KAGENT_A2A_URL = os.environ["KAGENT_A2A_URL"]
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "1800"))


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)

        try:
            body = json.loads(raw)
        except json.JSONDecodeError as error:
            response = {"error": f"invalid JSON from sender: {error}"}
            self._respond(400, json.dumps(response).encode())
            return

        body["jsonrpc"] = "2.0"
        fixed = json.dumps(body).encode()

        threading.Thread(target=self._forward, args=(fixed,), daemon=True).start()
        self._respond(202, json.dumps({"status": "accepted"}).encode())

    def _forward(self, fixed: bytes) -> None:
        request = urllib.request.Request(
            KAGENT_A2A_URL,
            data=fixed,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                print(f"forwarded to kagent: HTTP {response.status}", flush=True)
        except urllib.error.HTTPError as error:
            print(
                f"kagent rejected forwarded alert: HTTP {error.code}: {error.read()!r}",
                flush=True,
            )
        except Exception as error:
            print(f"failed to reach kagent: {error}", flush=True)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._respond(200, b"OK")
        else:
            self._respond(404, b"not found")

    def _respond(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, message_format: str, *args: object) -> None:
        print(
            f"{self.address_string()} - {message_format % args}",
            flush=True,
        )


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print(
        f"kagent-alert-relay listening on :8080, forwarding to {KAGENT_A2A_URL}",
        flush=True,
    )
    server.serve_forever()

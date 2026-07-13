"""Dad joke agent for Amazon Bedrock AgentCore Runtime.

Implements the AgentCore HTTP protocol contract (POST /invocations, GET /ping)
using only the Python standard library, so no dependency packaging/arm64
cross-compilation is needed for direct code deployment.
"""
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DAD_JOKE_BASE_URL = "https://icanhazdadjoke.com/"
USER_AGENT = os.environ.get(
    "DAD_JOKE_USER_AGENT",
    "Bedrock AgentCore Dad Joke Agent (https://github.com/)",
)


def fetch_dad_joke(term: str | None) -> dict:
    if term:
        url = f"{DAD_JOKE_BASE_URL}search?limit=1&term={urllib.parse.quote(term)}"
    else:
        url = DAD_JOKE_BASE_URL

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        body = json.loads(response.read().decode("utf-8"))

    if term:
        results = body.get("results") or []
        if not results:
            return {"joke": f"Couldn't find a dad joke about '{term}'.", "id": None}
        return {"joke": results[0]["joke"], "id": results[0]["id"]}

    return {"joke": body["joke"], "id": body["id"]}


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ping":
            self._send_json(200, {"status": "Healthy"})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path != "/invocations":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(length) if length else b"{}"

        try:
            payload = json.loads(raw_body or b"{}")
        except json.JSONDecodeError:
            self._send_json(400, {"error": "Request body must be JSON."})
            return

        term = payload.get("term") or payload.get("prompt")
        term = term.strip() if isinstance(term, str) and term.strip() else None

        try:
            joke = fetch_dad_joke(term)
        except Exception as exc:  # noqa: BLE001 - surface any upstream failure to the caller
            self._send_json(502, {"error": f"Failed to fetch dad joke: {exc}"})
            return

        self._send_json(200, {"output": joke})

    def log_message(self, format, *args):  # noqa: A002 - match BaseHTTPRequestHandler signature
        print(f"{self.address_string()} - {format % args}")


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()

"""Dad joke agent for Amazon Bedrock AgentCore Runtime.

Implements the AgentCore HTTP protocol contract (POST /invocations, GET /ping).
An LLM (via Bedrock's Converse API) decides whether/what to search for and
phrases the reply; fetch_dad_joke is the only tool it can call.
"""
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

DAD_JOKE_BASE_URL = "https://icanhazdadjoke.com/"
USER_AGENT = os.environ.get(
    "DAD_JOKE_USER_AGENT",
    "Bedrock AgentCore Dad Joke Agent (https://github.com/)",
)
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-3-5-haiku-20241022-v1:0")
REGION = os.environ.get("BEDROCK_REGION", "us-east-1")
MAX_TOOL_TURNS = 3

bedrock = boto3.client("bedrock-runtime", region_name=REGION)

SYSTEM_PROMPT = (
    "You are a dad joke bot. If the user's message is asking for a joke "
    "(with or without a topic), call get_dad_joke to fetch one - never make "
    "a joke up yourself - passing any topic they mentioned as the term "
    "argument, then share the joke back conversationally in a sentence or "
    "two. If the message isn't asking for a joke (e.g. a greeting or an "
    "unrelated question), just respond directly without calling the tool."
)

TOOL_CONFIG = {
    "tools": [
        {
            "toolSpec": {
                "name": "get_dad_joke",
                "description": "Fetch a dad joke from icanhazdadjoke.com, optionally about a topic.",
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {
                            "term": {
                                "type": "string",
                                "description": "Optional topic to search a joke for, e.g. 'chicken'.",
                            }
                        },
                    }
                },
            }
        }
    ]
}


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


def run_agent(user_message: str) -> str:
    messages = [{"role": "user", "content": [{"text": user_message}]}]

    for _ in range(MAX_TOOL_TURNS):
        response = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=messages,
            toolConfig=TOOL_CONFIG,
        )
        output_message = response["output"]["message"]
        messages.append(output_message)

        if response["stopReason"] != "tool_use":
            return "".join(block["text"] for block in output_message["content"] if "text" in block)

        tool_results = []
        for block in output_message["content"]:
            tool_use = block.get("toolUse")
            if not tool_use or tool_use["name"] != "get_dad_joke":
                continue
            try:
                result = fetch_dad_joke(tool_use["input"].get("term"))
            except Exception as exc:  # noqa: BLE001 - hand the failure back to the model as a tool error
                tool_results.append(
                    {
                        "toolResult": {
                            "toolUseId": tool_use["toolUseId"],
                            "content": [{"text": f"Failed to fetch a joke: {exc}"}],
                            "status": "error",
                        }
                    }
                )
                continue
            tool_results.append(
                {
                    "toolResult": {
                        "toolUseId": tool_use["toolUseId"],
                        "content": [{"json": result}],
                    }
                }
            )
        messages.append({"role": "user", "content": tool_results})

    return "Sorry, I couldn't come up with a joke right now."


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

        prompt = payload.get("prompt") or "Tell me a dad joke."

        try:
            reply = run_agent(prompt)
        except Exception as exc:  # noqa: BLE001 - surface any model/tool failure to the caller
            self._send_json(502, {"error": f"Agent failed: {exc}"})
            return

        self._send_json(200, {"output": {"message": reply}})

    def log_message(self, format, *args):  # noqa: A002 - match BaseHTTPRequestHandler signature
        print(f"{self.address_string()} - {format % args}")


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()

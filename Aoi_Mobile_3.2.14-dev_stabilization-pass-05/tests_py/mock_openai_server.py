"""Stdlib mock of an OpenAI-compatible provider (models + streaming chat) with the failure modes free tiers really have.
Keyword in the LAST user message picks the behaviour: ERR401 ERR429 ERR429ALL ERR500 EMPTY EMPTYALL SPLIT MIDERR T402 SLOW STALL NATIVE_TOOL NATIVE_TOOL_NONSTREAM
Models:  GET /v1/models  (OpenRouter-like pricing rows)  or /g/v1/models (Google-like 'models/..' ids)
Everything is recorded at GET /__log so tests can assert what the app actually sent.
"""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = []
GOOD_KEY = "good-key"

MODELS_OR = {"data": [
    {"id": "meta-llama/llama-3.3-70b-instruct:free", "context_length": 131072, "pricing": {"prompt": "0", "completion": "0"}},
    {"id": "cohere/north-mini-code:free", "context_length": 65536, "pricing": {"prompt": "0", "completion": "0"}},
    {"id": "nvidia/nemotron-3.5-super-vl:free", "context_length": 262144, "pricing": {"prompt": "0", "completion": "0"}},
    {"id": "openai/gpt-4o", "context_length": 128000, "pricing": {"prompt": "0.0000025", "completion": "0.00001"}},
    {"id": "intfloat/e5-embed", "context_length": 512, "pricing": {"prompt": "0", "completion": "0"}}]}
MODELS_G = {"data": [{"id": "models/gemini-2.5-flash", "inputTokenLimit": 1048576}, {"id": "models/gemini-2.5-pro", "inputTokenLimit": 1048576},
                     {"id": "models/text-embedding-004"}, {"id": "models/imagen-3.0"}]}
MODELS_PUTER = {"models": [
    {"id": "gpt-5.4-nano", "puterId": "azure:openai/gpt-5.4-nano", "name": None, "context": 400000,
     "costs_currency": "usd-cents", "costs": {"tokens": 1000000, "prompt_tokens": 20, "completion_tokens": 125}},
    {"id": "meta-llama/llama-3.3-free", "puterId": "meta-llama:meta-llama/llama-3.3-free", "name": "Llama Free", "context": 100000,
     "costs_currency": "usd-cents", "costs": {"tokens": 1000000, "prompt_tokens": 0, "completion_tokens": 0}},
]}

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def handle(self):
        try: super().handle()
        except (BrokenPipeError, ConnectionResetError): pass   # the app hung up (stop button / cancel): expected
    def _send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.send_header("Connection", "close"); self.end_headers(); self.wfile.write(b)
    def _auth_ok(self): return self.headers.get("Authorization", "") == f"Bearer {GOOD_KEY}"
    def do_GET(self):
        if self.path.startswith("/__log"): return self._send(200, LOG)
        LOG.append({"m": "GET", "p": self.path})
        if not self._auth_ok(): return self._send(401, {"error": {"message": "invalid api key"}})
        if self.path.startswith("/p/v1/models"): return self._send(200, MODELS_PUTER)
        if self.path.startswith("/g/v1/models"): return self._send(200, MODELS_G)
        if self.path.startswith("/v1/models"): return self._send(200, MODELS_OR)
        self._send(404, {"error": {"message": "not found"}})
    def _sse(self, obj):
        self.wfile.write(("data: " + (obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)) + "\n\n").encode()); self.wfile.flush()
    def _chunk(self, text): return {"choices": [{"delta": {"content": text}}]}
    def _start_stream(self):
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close"); self.end_headers()
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        messages = body.get("messages", [])
        LOG.append({"m": "POST", "p": self.path, "model": body.get("model"), "stream": body.get("stream"), "max_tokens": body.get("max_tokens"),
                    "max_completion_tokens": body.get("max_completion_tokens"), "n_messages": len(messages),
                    "tools_count": len(body.get("tools", [])), "parallel_tool_calls": body.get("parallel_tool_calls"),
                    "tool_result_count": sum(1 for item in messages if item.get("role") == "tool"),
                    "compatibility_hint": any("AOI TEXT-TOOL COMPATIBILITY MODE" in str(item.get("content", "")) for item in messages if item.get("role") == "system"),
                    "auth": self._auth_ok()})
        if not self._auth_ok(): return self._send(401, {"error": {"message": "invalid api key"}})
        user = ""
        for m in reversed(body.get("messages", [])):
            if m.get("role") == "user": user = str(m.get("content", "")); break
        model = str(body.get("model", ""))
        stream = bool(body.get("stream"))
        if "ERR401" in user: return self._send(401, {"error": {"message": "bad key"}})
        if "PUTER403" in user: return self._send(403, {"error": {"message": "app_or_api_token_required"}})
        if "ERR404" in user and "llama" in model: return self._send(404, {"error": {"message": "model route not found"}})
        if "ERR429ALL" in user: return self._send(429, {"error": {"message": "rate limited"}})
        if "ERR429" in user and "llama" in model: return self._send(429, {"error": {"message": "rate limited"}})
        if "ERR500" in user and "llama" in model: return self._send(503, {"error": {"message": "overloaded"}})
        if "T402" in user and (body.get("max_tokens") or 0) > 1000:
            return self._send(402, {"error": {"message": "This request requires more credits, or fewer max_tokens. You requested up to %s tokens, but can only afford 900." % body.get("max_tokens")}})
        if "EMPTYALL" in user:
            if not stream: return self._send(200, {"choices": [{"message": {"content": ""}}]})
            self._start_stream(); return self._sse("[DONE]")
        if "EMPTY" in user and "llama" in model:
            if not stream: return self._send(200, {"choices": [{"message": {"content": ""}}]})
            self._start_stream(); self._sse({"choices": [{"delta": {"role": "assistant"}}]}); return self._sse("[DONE]")
        has_tool_result = any(item.get("role") == "tool" for item in body.get("messages", []))
        if "TOOL_UNSUPPORTED" in user and body.get("tools"):
            return self._send(400, {"error": {"message": "This model does not support function tools."}})
        if "TOOL_UNSUPPORTED" in user and not body.get("tools"):
            marker = '[[AOI_TOOL_CALL]]{"name":"knowledge.search","query":"compatibility test"}[[/AOI_TOOL_CALL]]'
            if not stream: return self._send(200, {"choices": [{"message": {"content": marker}}]})
            self._start_stream(); self._sse(self._chunk(marker)); return self._sse("[DONE]")
        if "NATIVE_TOOL" in user and body.get("tools") and not has_tool_result:
            native_call = {"id": "call_aoi_001", "type": "function", "function": {"name": "aoi_project__inspect", "arguments": "{}"}}
            if not stream:
                return self._send(200, {"choices": [{"message": {"content": None, "tool_calls": [native_call]}, "finish_reason": "tool_calls"}]})
            self._start_stream()
            if "NATIVE_TOOL_NONSTREAM" in user:
                return self._sse("[DONE]")
            self._sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "call_aoi_001", "type": "function", "function": {"name": "aoi_project__inspect", "arguments": "{"}}]}}]})
            self._sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "}"}}]}}]})
            return self._sse("[DONE]")
        if not stream:
            content = "tool_result_received" if has_tool_result else f"[{model}] " + (user[:60] or "ok")
            return self._send(200, {"choices": [{"message": {"content": content}}]})
        self._start_stream()
        if "SLOW" in user: time.sleep(2.0)
        if "STALL" in user:
            self._sse(self._chunk("partial ")); time.sleep(8); return
        if "SPLIT" in user:
            data = ("data: " + json.dumps(self._chunk("naïve 日本語 🙂 ok"), ensure_ascii=False) + "\n\n").encode("utf-8")
            for i in range(0, len(data), 3): self.wfile.write(data[i:i + 3]); self.wfile.flush(); time.sleep(0.005)
            return self._sse("[DONE]")
        if "MIDERR" in user:
            self._sse(self._chunk("The answer starts ")); return self._sse({"error": {"message": "upstream exploded"}})
        reply = "tool_result_received" if has_tool_result else f"[{model}] You said: {user}"
        for i in range(0, len(reply), 9):
            self._sse(self._chunk(reply[i:i + 9])); time.sleep(0.01)
        self._sse("[DONE]")

def serve(port):
    s = ThreadingHTTPServer(("127.0.0.1", port), H); s.daemon_threads = True; s.serve_forever()
if __name__ == "__main__":
    serve(int(sys.argv[1]) if len(sys.argv) > 1 else 18100)

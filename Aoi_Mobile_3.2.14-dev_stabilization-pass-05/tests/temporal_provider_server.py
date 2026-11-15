#!/usr/bin/env python3
"""Deterministic local OpenAI-compatible fixture for Aoi's real chat/tool loop.

This is a test fixture, not a production provider. Run only on loopback. It emits
real SSE chunks, native function-call deltas and one final clean response so the
Godot LLM -> ChatScreen -> ToolRunner pipeline is exercised without API keys.
"""
from __future__ import annotations
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8199

PROJECT_GODOT = '''config_version=5

[application]
config/name="Neon Collector"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.8", "GL Compatibility")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
'''

MAIN_SCENE = '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/Main.gd" id="1"]

[node name="NeonCollector" type="Node2D"]
script = ExtResource("1")
'''

MAIN_SCRIPT = r'''extends Node2D

const VIEW := Vector2(1280.0, 720.0)
var player_position := Vector2(640, 548)
var coin_positions: Array[Vector2] = [Vector2(220, 190), Vector2(500, 300), Vector2(820, 170), Vector2(1080, 360), Vector2(690, 480)]
var score := 0
var _pulse := 0.0

func _ready() -> void:
	get_window().title = "Neon Collector"
	queue_redraw()

func _process(delta: float) -> void:
	_pulse += delta
	var direction := Input.get_axis("ui_left", "ui_right")
	player_position.x = clampf(player_position.x + direction * 420.0 * delta, 56.0, 1224.0)
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept"):
		player_position.y = 460.0
	if Input.is_action_just_released("ui_up") or Input.is_action_just_released("ui_accept"):
		player_position.y = 548.0
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().reload_current_scene()
	collect_nearest_coin()
	queue_redraw()

func collect_nearest_coin() -> bool:
	for index in range(coin_positions.size() - 1, -1, -1):
		if player_position.distance_to(coin_positions[index]) < 54.0:
			coin_positions.remove_at(index)
			score += 1
			return true
	return false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("#0c1018"))
	for y in range(70, 720, 65):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.20, 0.38, 0.55, 0.13), 1.0)
	for x in range(0, 1280, 64):
		draw_line(Vector2(x, 120), Vector2(x, 720), Color(0.20, 0.38, 0.55, 0.09), 1.0)
	for i in range(12):
		var bx := float(i) * 112.0
		var bh := 80.0 + float((i * 37) % 170)
		draw_rect(Rect2(Vector2(bx, 610.0 - bh), Vector2(72, bh)), Color("#151f2c"))
		draw_rect(Rect2(Vector2(bx + 12, 625.0 - bh), Vector2(7, 7)), Color("#3bd6c6"))
		draw_rect(Rect2(Vector2(bx + 34, 625.0 - bh), Vector2(7, 7)), Color("#3bd6c6"))
	draw_rect(Rect2(Vector2(0, 630), Vector2(1280, 90)), Color("#111a25"))
	draw_line(Vector2(0, 630), Vector2(1280, 630), Color("#3bd6c6"), 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(58, 74), "NEON COLLECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("#f5f8ff"))
	draw_string(font, Vector2(60, 108), "COLLECT THE LIGHT  /  MOVE WITH ← →  /  JUMP WITH ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#8ca6be"))
	draw_string(font, Vector2(1060, 76), "SCORE  %02d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#3bd6c6"))
	for index in coin_positions.size():
		var center := coin_positions[index]
		var pulse := 6.0 + sin(_pulse * 3.0 + float(index)) * 2.0
		draw_circle(center, 22.0 + pulse, Color(0.12, 0.88, 0.78, 0.14))
		draw_circle(center, 13.0, Color("#42e1c9"))
		draw_circle(center, 6.0, Color("#effffb"))
	# Player: a compact capsule with a bright visor and a trailing motion line.
	draw_line(player_position + Vector2(-44, 8), player_position + Vector2(-75, 8), Color(0.22, 0.85, 0.78, 0.45), 5.0)
	draw_circle(player_position, 28.0, Color("#f4f7fb"))
	draw_rect(Rect2(player_position + Vector2(-20, -9), Vector2(40, 17)), Color("#1e3342"), true, 8.0)
	draw_rect(Rect2(player_position + Vector2(-12, -5), Vector2(24, 8)), Color("#42e1c9"), true, 4.0)
	draw_string(font, Vector2(60, 686), "ESC  RESTART", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#607b91"))
	draw_string(font, Vector2(1000, 686), "NEON DISTRICT   •   01", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#607b91"))
'''

SMOKE_TEST = '''extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		push_error("NEON_COLLECTOR_SMOKE_FAIL: main scene could not load")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	if not game.has_method("collect_nearest_coin"):
		push_error("NEON_COLLECTOR_SMOKE_FAIL: collection behavior missing")
		quit(1)
		return
	var coins: Array = game.get("coin_positions")
	if coins.is_empty():
		push_error("NEON_COLLECTOR_SMOKE_FAIL: no collectibles spawned")
		quit(1)
		return
	game.set("player_position", coins[0])
	var before := int(game.get("score"))
	var collected := bool(game.call("collect_nearest_coin"))
	var after := int(game.get("score"))
	if not collected or after != before + 1:
		push_error("NEON_COLLECTOR_SMOKE_FAIL: collection did not increase score")
		quit(1)
		return
	print("NEON_COLLECTOR_SMOKE_PASS: scene loads, collectibles spawn, collection increases score")
	quit(0)
'''

RUN_TESTS = '''#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path "$ROOT" --script res://tests/game_smoke.gd --quit-after 120 --log-file "$ROOT/.aoi_studio/smoke.log"
'''


def tool_call(name: str, args: dict) -> bytes:
    call = {
        "choices": [{"index": 0, "delta": {"tool_calls": [{
            "index": 0,
            "id": "temporal_" + name.replace(".", "_") + "_call",
            "type": "function",
            "function": {"name": "aoi_" + name.replace(".", "__"), "arguments": json.dumps(args, separators=(",", ":"))},
        }]}}]
    }
    return sse(call)


def sse(obj: dict) -> bytes:
    payload = "data: " + json.dumps(obj, separators=(",", ":")) + "\n\n" + "data: [DONE]\n\n"
    return payload.encode("utf-8")


def content_reply(text: str) -> bytes:
    return sse({"choices": [{"index": 0, "delta": {"content": text}}]})


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "AoiTemporalFixture/1.0"

    def log_message(self, fmt, *args):
        print("[Temporal] " + fmt % args, flush=True)

    def _respond(self, code: int, body: bytes, content_type: str = "application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            body = json.dumps({"object": "list", "data": [{"id": "clean-reply", "object": "model", "owned_by": "aoi-temporal"}]}).encode()
            self._respond(200, body)
            return
        self._respond(404, b'{"error":"not found"}')

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._respond(404, b'{"error":"not found"}')
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(size) or b"{}")
        except Exception as exc:
            self._respond(400, json.dumps({"error": str(exc)}).encode())
            return
        messages = payload.get("messages", [])
        latest_user = ""
        tool_results = []
        for item in messages:
            if item.get("role") == "user":
                latest_user = str(item.get("content", ""))
            elif item.get("role") == "tool":
                try:
                    tool_results.append(json.loads(str(item.get("content", "{}"))))
                except Exception:
                    tool_results.append({"tool": "unknown", "ok": False})
        tools = payload.get("tools", [])
        allowed = {str(t.get("function", {}).get("name", "")) for t in tools if isinstance(t, dict)}

        def emit_call(tool_name: str, args: dict):
            native_name = "aoi_" + tool_name.replace(".", "__")
            if native_name not in allowed:
                self._respond(200, content_reply("I couldn't continue because the app did not expose the required connected action: " + tool_name).replace(b"text/event-stream", b"application/json"), "text/event-stream")
                return
            self._respond(200, tool_call(tool_name, args), "text/event-stream")

        if latest_user.startswith("Temporal turn "):
            match = re.search(r"Temporal turn (\d+)", latest_user)
            number = int(match.group(1)) if match else 0
            replies = {
                1: "Temporal response 1: I have the request and will keep the answer concise.",
                2: "Temporal response 2: The conversation context is still available.",
                3: "Temporal response 3: I can use earlier messages without repeating them.",
                4: "Temporal response 4: The response stream is arriving as normal chat text.",
                5: "Temporal response 5: The five-turn conversation is complete; the next request can use tools.",
            }
            self._respond(200, content_reply(replies.get(number, "Temporal response: received.")), "text/event-stream")
            return

        if "Neon Collector" in latest_user or "playable arcade game" in latest_user.lower():
            created = next((r for r in tool_results if r.get("tool") == "workspace.create_project" and r.get("ok")), None)
            remote = next((r for r in tool_results if r.get("tool") == "Create game workspace" and r.get("ok")), None)
            writes = {str(r.get("path", "")) for r in tool_results if r.get("tool") == "project.write_file" and r.get("ok")}
            has_test = any(r.get("tool") == "Godot test" and r.get("ok") for r in tool_results)
            has_run = any(r.get("tool") == "Godot run" and r.get("ok") for r in tool_results)
            has_capture = any(r.get("tool") == "Godot capture" and r.get("ok") for r in tool_results)
            project_id = str(created.get("project_id", "")) if created else ""
            if not created:
                emit_call("workspace.create_project", {"title": "Neon Collector", "goal": "A compact playable arcade game. Collect neon orbs, move with arrow keys, jump, score points and restart.", "kind": "game"})
                return
            if not remote:
                emit_call("godot.create", {"project_id": project_id, "name": "Neon Collector", "goal": "A small arcade collection game with keyboard controls, scoring and restart."})
                return
            files = [
                ("project.godot", PROJECT_GODOT),
                ("scenes/Main.tscn", MAIN_SCENE),
                ("scripts/Main.gd", MAIN_SCRIPT),
                ("tests/game_smoke.gd", SMOKE_TEST),
                ("run_tests.sh", RUN_TESTS),
            ]
            for path, content in files:
                if path not in writes:
                    emit_call("project.write_file", {"project_id": project_id, "path": path, "content": content})
                    return
            if not has_test:
                emit_call("godot.test", {"path": str(remote.get("path", ""))})
                return
            if not has_run:
                emit_call("godot.run", {"path": str(remote.get("path", ""))})
                return
            if not has_capture:
                emit_call("godot.capture", {"path": str(remote.get("path", ""))})
                return
            self._respond(200, content_reply("Clean reply — Neon Collector is built and running in your connected cloud workspace. Aoi created the project, synced the game files, ran the project's gameplay smoke test, launched the game and captured its actual running window. Open the preview below to inspect the result."), "text/event-stream")
            return

        self._respond(200, content_reply("Clean reply: received your message and preserved the conversation context."), "text/event-stream")


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Temporal provider listening at http://{HOST}:{PORT}/v1", flush=True)
    server.serve_forever()

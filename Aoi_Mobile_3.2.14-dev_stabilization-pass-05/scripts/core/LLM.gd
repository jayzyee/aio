extends Node
## Direct HTTPS client for OpenAI-compatible providers (Google AI Studio, OpenRouter, Groq ...).
## Streams tokens (SSE), and survives the usual free-tier problems: empty replies (retry non-stream),
## rate limits / timeouts / overload (fall back to another model), 402 "can only afford N tokens"
## (retry with fewer), idle connections, cancel.

const Sse = preload("res://scripts/core/Sse.gd")
const Catalog = preload("res://scripts/core/Catalog.gd")

signal models_loaded(provider_id: String, ok: bool, payload: Variant)   # payload = rows or an error string
signal chat_delta(text: String)
signal chat_notice(text: String)
signal chat_finished(result: Dictionary)   # {ok, text, error, model, provider, truncated, cancelled}

const IDLE_TIMEOUT := 45.0
const NONSTREAM_TIMEOUT := 60.0
const LOCAL_MODEL_IDLE_TIMEOUT := 240.0
const CONNECT_TIMEOUT := 20.0
const MAX_ATTEMPTS := 3

var busy := false
var idle_timeout := IDLE_TIMEOUT      # tests shorten it
var models_cache: Dictionary = {}     # provider id -> rows
var _model_request_generation: Dictionary = {} # provider id -> latest list request

var _job: Dictionary = {}
var _http := HTTPClient.new()
var _sse = Sse.new()
var _phase := 0            # 0 idle, 1 connecting, 2 waiting for response, 3 reading body
var _code := 0
var _err_buf := PackedByteArray()
var _text := ""
var _stream_error := ""
var _last_rx := 0.0
var _tool_calls: Array = []
var _retry_pending := false
var _retry_at_msec := 0
var _chat_generation := 0


func _ready() -> void:
	set_process(false)


# ------------------------------------------------------------------ models
func list_models(provider_id: String, key_override: String = "", base_url_override: String = "") -> void:
	# A candidate key is verified before it replaces the user's existing key.
	# This prevents a typo or temporary provider outage from disconnecting a
	# previously working account.
	var key := key_override if key_override != "" else Store.get_key(provider_id)
	var endpoint := base_url_override.strip_edges().trim_suffix("/") if base_url_override.strip_edges() != "" else Catalog.base_url(provider_id)
	var name := str(Catalog.by_id(provider_id).get("name", provider_id))
	var generation := int(_model_request_generation.get(provider_id, 0)) + 1
	_model_request_generation[provider_id] = generation
	if key == "":
		models_loaded.emit(provider_id, false, "Paste your %s key first." % name)
		return
	if endpoint == "":
		models_loaded.emit(provider_id, false, "Set an API base URL before testing %s." % name)
		return
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		# Ignore stale responses from an earlier key or a superseded refresh.
		if int(_model_request_generation.get(provider_id, -1)) != generation:
			return
		if key_override == "" and Store.get_key(provider_id) != key:
			return
		if result != HTTPRequest.RESULT_SUCCESS:
			models_loaded.emit(provider_id, false, "Can't reach %s. Check your internet connection." % name)
			return
		var response_text := body.get_string_from_utf8()
		if code >= 400:
			models_loaded.emit(provider_id, false, explain(provider_id, code, _error_message(response_text)))
			return
		var rows := Catalog.normalize_models(provider_id, JSON.parse_string(response_text))
		if rows.is_empty():
			models_loaded.emit(provider_id, false, "%s connected but lists no chat models." % name)
			return
		models_cache[provider_id] = rows
		models_loaded.emit(provider_id, true, rows))
	var models_url := Catalog.models_url(provider_id)
	if base_url_override.strip_edges() != "":
		models_url = base_url_override.strip_edges().trim_suffix("/") + "/models"
	var err := req.request(models_url, _headers(provider_id, key, false), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		if int(_model_request_generation.get(provider_id, -1)) == generation:
			models_loaded.emit(provider_id, false, "Could not start the request (error %d)." % err)


func invalidate_model_list(provider_id: String) -> void:
	_model_request_generation[provider_id] = int(_model_request_generation.get(provider_id, 0)) + 1


# -------------------------------------------------------------------- chat
func chat(visible_model: String, messages: Array, opts: Dictionary = {}) -> void:
	if busy: return
	var parts := Catalog.split_visible(visible_model)
	var pid := str(parts[0])
	var raw := str(parts[1])
	if pid == "" or not Store.has_key(pid):
		chat_finished.emit({"ok": false, "text": "", "error": "Connect a provider first (Setup tab).", "model": visible_model, "provider": pid})
		return
	var api_key := Store.get_key(pid)
	var candidates: Array = [raw]
	for fb in _fallbacks(pid, raw): candidates.append(fb)
	var requested_tools: Variant = opts.get("tools", [])
	var tools: Array = requested_tools if requested_tools is Array else []
	_chat_generation += 1
	_job = {"provider": pid, "models": candidates, "idx": 0, "messages": messages,
		"max_tokens": int(opts.get("max_tokens", 2048)), "tools": tools,
		"no_tools": false, "swap": false, "lowered": false, "nonstream": false, "attempts": 1,
		"generation": _chat_generation, "catalog_refreshed": false, "api_key": api_key,
		"idle_timeout": _idle_timeout_for_provider(pid)}
	busy = true
	_start_stream()


func cancel() -> void:
	if not busy: return
	var partial := _text
	_retry_pending = false
	_http.close()
	_phase = 0
	_finish({"ok": false, "cancelled": true, "text": partial, "error": ""})


func _fallbacks(pid: String, current: String) -> Array:
	var rows: Array = models_cache.get(pid, [])
	var out: Array = []
	for r in rows:
		if str(r["model"]) == current: continue
		var m := str(r["model"]).to_lower()
		if "-vl" in m or "vision" in m or "image" in m: continue
		if bool(r["free"]): out.append(str(r["model"]))
		if out.size() >= MAX_ATTEMPTS - 1: break
	return out


func _idle_timeout_for_provider(pid: String) -> float:
	if idle_timeout != IDLE_TIMEOUT:
		return idle_timeout
	if pid != "custom":
		return idle_timeout
	var endpoint := Catalog.base_url(pid).to_lower().trim_suffix("/")
	var parsed_endpoint := _split_url(endpoint)
	if endpoint.begins_with("http://") and str(parsed_endpoint.get("host", "")) in ["localhost", "127.0.0.1", "::1"]:
		return LOCAL_MODEL_IDLE_TIMEOUT
	return idle_timeout


func _nonstream_timeout_for_provider(pid: String) -> float:
	return maxf(NONSTREAM_TIMEOUT, _idle_timeout_for_provider(pid))


func _current_model() -> String:
	return str((_job["models"] as Array)[int(_job["idx"])])


func _start_stream() -> void:
	_retry_pending = false
	_text = ""
	_tool_calls.clear()
	_code = 0
	_err_buf = PackedByteArray()
	_stream_error = ""
	_sse = Sse.new()
	_phase = 1
	_last_rx = Time.get_ticks_msec() / 1000.0
	var u := _split_url(Catalog.base_url(str(_job["provider"])))
	_http.close()
	var err := _http.connect_to_host(str(u["host"]), int(u["port"]), TLSOptions.client() if bool(u["tls"]) else null)
	if err != OK:
		_retryable_fail("Could not start the connection (error %d)." % err)
		return
	set_process(true)


func _split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.left(slash)
	var path := "" if slash < 0 else rest.substr(slash)
	var host := host_port
	var port := 443 if tls else 80
	if host_port.begins_with("["):
		var closing_bracket := host_port.find("]")
		if closing_bracket >= 0:
			host = host_port.substr(1, closing_bracket - 1)
			var port_suffix := host_port.substr(closing_bracket + 1)
			if port_suffix.begins_with(":"):
				port = int(port_suffix.substr(1))
	elif ":" in host_port:
		var separator := host_port.rfind(":")
		host = host_port.left(separator)
		port = int(host_port.substr(separator + 1))
	return {"tls": tls, "host": host, "port": port, "path": path}


func _body(stream: bool) -> String:
	var request_messages: Array = (_job.get("messages", []) as Array).duplicate(true)
	var tools: Array = _job.get("tools", [])
	var compatibility_mode := bool(_job.get("no_tools", false)) and not tools.is_empty()
	if compatibility_mode:
		var compatibility_instruction := "AOI TEXT-TOOL COMPATIBILITY MODE: This provider rejected native function calling for this model. If an advertised tool is necessary, return exactly one complete [[AOI_TOOL_CALL]] JSON marker matching an advertised example, with its exact tool name and flat JSON argument fields. Do not use Markdown fences or expose any other internal syntax. If no tool is needed, answer normally. Wait for the actual tool result before continuing."
		var first_message: Variant = request_messages[0] if not request_messages.is_empty() else null
		if first_message is Dictionary and str(first_message.get("role", "")) == "system":
			var system_message: Dictionary = first_message
			system_message["content"] = str(system_message.get("content", "")) + "\n\n" + compatibility_instruction
			request_messages[0] = system_message
		else:
			request_messages.push_front({"role":"system", "content":compatibility_instruction})
	var d := {"model": _current_model(), "messages": request_messages, "stream": stream}
	d["max_completion_tokens" if bool(_job["swap"]) else "max_tokens"] = int(_job["max_tokens"])
	if not bool(_job.get("no_tools", false)) and not tools.is_empty():
		d["tools"] = tools
		d["tool_choice"] = "auto"
		d["parallel_tool_calls"] = false
	return JSON.stringify(d)


func _headers(pid: String, key: String, stream: bool) -> PackedStringArray:
	var h := PackedStringArray(["Authorization: Bearer " + key, "Content-Type: application/json",
		"Accept: " + ("text/event-stream" if stream else "application/json"), "User-Agent: AoiMobile/1.0"])
	if pid == "openrouter":
		h.append("HTTP-Referer: https://aoi.app")
		h.append("X-Title: Aoi Mobile")
	return h


func _process(_d: float) -> void:
	if _retry_pending:
		if Time.get_ticks_msec() < _retry_at_msec:
			return
		_retry_pending = false
		_start_stream()
		return
	if _phase == 0:
		set_process(false)
		return
	_http.poll()
	var st := _http.get_status()
	var now := Time.get_ticks_msec() / 1000.0
	var pid := str(_job["provider"])
	var request_idle_timeout := float(_job.get("idle_timeout", idle_timeout))
	match st:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			if now - _last_rx > CONNECT_TIMEOUT: _retryable_fail("Could not connect. Check your internet connection.")
		HTTPClient.STATUS_CONNECTED:
			if _phase == 1:
				var u := _split_url(Catalog.base_url(pid))
				var err := _http.request(HTTPClient.METHOD_POST, str(u["path"]) + "/chat/completions", _headers(pid, str(_job.get("api_key", "")), true), _body(true))
				if err != OK:
					_retryable_fail("Could not send the request (error %d)." % err)
					return
				_phase = 2
				_last_rx = now
			elif _phase == 2:
				if _http.has_response():   # headers only, no body
					_code = _http.get_response_code()
					_phase = 3
					_on_stream_end()
			elif _phase == 3:
				_on_stream_end()
		HTTPClient.STATUS_REQUESTING:
			if now - _last_rx > request_idle_timeout: _retryable_fail("The model took too long to start answering.")
		HTTPClient.STATUS_BODY:
			if _phase == 2:
				_phase = 3
				_code = _http.get_response_code()
			while _http.get_status() == HTTPClient.STATUS_BODY:   # reading outside BODY is an engine error
				var chunk := _http.read_response_body_chunk()
				if chunk.size() == 0: break
				_last_rx = now
				_on_chunk(chunk)
			if _phase == 3 and _http.get_status() == HTTPClient.STATUS_BODY and now - _last_rx > idle_timeout:
				_retryable_fail("The model stopped answering (no data for %d seconds)." % int(idle_timeout))
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR:
			# A server that answers and then closes the socket makes Godot report CONNECTION_ERROR even though the
			# whole response arrived. If we already have headers, that is simply the end of the body.
			if _phase == 3:
				_on_stream_end()
			elif _phase == 2 and _http.has_response():
				_code = _http.get_response_code()
				_phase = 3
				_on_stream_end()
			elif _phase > 0:
				_retryable_fail("The connection closed unexpectedly.")
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_retryable_fail("Can't reach %s. Check your internet connection." % str(Catalog.by_id(pid).get("name", pid)))


func _on_chunk(chunk: PackedByteArray) -> void:
	if _code >= 400:
		_err_buf.append_array(chunk)
		return
	for payload in _sse.feed(chunk): _on_payload(str(payload))


func _on_payload(p: String) -> void:
	if p == "[DONE]": return
	var obj: Variant = JSON.parse_string(p)
	if not obj is Dictionary: return
	if (obj as Dictionary).has("error"):
		var e: Variant = (obj as Dictionary)["error"]
		_stream_error = str(e.get("message", "")) if e is Dictionary else str(e)
		if _stream_error == "": _stream_error = "The provider reported an error."
		return
	var choices: Variant = (obj as Dictionary).get("choices")
	if not choices is Array or (choices as Array).is_empty(): return
	var choice: Dictionary = (choices as Array)[0] if (choices as Array)[0] is Dictionary else {}
	var delta: Variant = choice.get("delta", {})
	if delta is Dictionary:
		var content: Variant = (delta as Dictionary).get("content")
		if content is String and str(content) != "":
			var chunk_text := str(content)
			_text += chunk_text
			chat_delta.emit(chunk_text)
		var calls: Variant = (delta as Dictionary).get("tool_calls", [])
		if calls is Array:
			for call_delta in calls:
				if call_delta is Dictionary:
					_merge_tool_call_delta(call_delta)


func _merge_tool_call_delta(call_delta: Dictionary) -> void:
	var index := maxi(0, int(call_delta.get("index", 0)))
	while _tool_calls.size() <= index:
		_tool_calls.append({"id":"", "type":"function", "function":{"name":"", "arguments":""}})
	var current: Dictionary = _tool_calls[index]
	var call_id := str(call_delta.get("id", ""))
	if call_id != "": current["id"] = call_id
	var call_type := str(call_delta.get("type", ""))
	if call_type != "": current["type"] = call_type
	var fn_delta: Variant = call_delta.get("function", {})
	if fn_delta is Dictionary:
		var fn: Dictionary = current.get("function", {})
		var fn_name := str(fn_delta.get("name", ""))
		if fn_name != "": fn["name"] = str(fn.get("name", "")) + fn_name
		var arguments := str(fn_delta.get("arguments", ""))
		if arguments != "": fn["arguments"] = str(fn.get("arguments", "")) + arguments
		current["function"] = fn
	_tool_calls[index] = current


func _on_stream_end() -> void:
	_phase = 0
	_http.close()
	for p in _sse.flush(): _on_payload(str(p))
	if _code >= 400:
		_handle_http_error(_code, _error_message(_err_buf.get_string_from_utf8()))
		return
	if _stream_error != "":
		if _text != "": _finish({"ok": true, "text": _text, "truncated": true, "error": _stream_error})
		else: _retryable_fail(_stream_error)
		return
	if _text.strip_edges() == "" and _tool_calls.is_empty():
		if not bool(_job["nonstream"]):
			_job["nonstream"] = true
			_nonstream()
		else:
			_retryable_fail("%s returned nothing." % _current_model())
		return
	_finish({"ok": true, "text": _text, "tool_calls": _completed_tool_calls()})


func _handle_http_error(code: int, msg: String) -> void:
	var pid := str(_job["provider"])
	if code == 402 and not bool(_job["lowered"]):
		var n := _afford(msg)
		if n - 64 >= 256 and n - 64 < int(_job["max_tokens"]):
			_job["lowered"] = true
			_job["max_tokens"] = n - 64
			_start_stream()
			return
	if code == 400 and not bool(_job["swap"]) and "max_tokens" in msg and "max_completion_tokens" in msg:
		_job["swap"] = true
		_start_stream()
		return
	if code == 400 and not bool(_job.get("no_tools", false)) and not (_job.get("tools", []) as Array).is_empty():
		var lower_msg := msg.to_lower()
		if ("tool" in lower_msg or "function" in lower_msg or "parallel_tool_calls" in lower_msg) and ("unsupported" in lower_msg or "not support" in lower_msg or "unknown" in lower_msg or "invalid" in lower_msg or "unrecognized" in lower_msg or "not available" in lower_msg):
			_job["no_tools"] = true
			chat_notice.emit("This model rejected native tools. Retrying with Aoi's text-tool compatibility mode…")
			_start_stream()
			return
	var text := explain(pid, code, msg)
	# A 404 for a selected model/route is not a transient transport failure.
	# Do not spend retries on the same unavailable model: advance immediately
	# to a model already verified in this provider's catalogue, if one exists.
	if code == 404:
		_try_next_model(text)
		return
	if code == 401 or code == 403:
		_finish({"ok": false, "text": "", "error": text, "http_status":code})
	elif code == 429 or code == 408 or code == 425 or code >= 500:
		_retryable_fail(text)
	elif code == 402:
		_finish({"ok":false,"text":"","error":text,"http_status":code})
	else:
		_finish({"ok": false, "text": "", "error": text, "http_status":code})


func _try_next_model(reason: String) -> void:
	if not busy:
		return
	_phase = 0
	_http.close()
	_retry_pending = false
	var models: Array = _job.get("models", [])
	var next_index := int(_job.get("idx", 0)) + 1
	if next_index < models.size():
		_job["idx"] = next_index
		_job["attempts"] = 1
		_job["nonstream"] = false
		_job["lowered"] = false
		_job["swap"] = false
		_job["no_tools"] = false
		chat_notice.emit("That model is unavailable. Trying a configured backup model…")
		_start_stream()
		return
	if not bool(_job.get("catalog_refreshed", false)):
		_refresh_catalog_after_404(reason)
		return
	_finish({"ok": false, "text": "", "error": reason + " No other verified model is available in the refreshed provider catalogue. Refresh the model list or choose another model in Setup."})


func _refresh_catalog_after_404(reason: String) -> void:
	var pid := str(_job.get("provider", ""))
	var generation := int(_job.get("generation", -1))
	_job["catalog_refreshed"] = true
	chat_notice.emit("Checking the provider's current model list for a working alternative…")
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		# A delayed catalogue response must never mutate a later chat started with
		# the same provider. Cancellation alone is not a sufficient ownership check.
		if not busy or int(_job.get("generation", -1)) != generation or str(_job.get("provider", "")) != pid:
			return
		if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
			_finish({"ok": false, "text": "", "error": reason + " Aoi couldn't refresh the model list. Check the provider connection or choose another model in Setup."})
			return
		var rows := Catalog.normalize_models(pid, JSON.parse_string(body.get_string_from_utf8()))
		models_cache[pid] = rows
		var models: Array = _job.get("models", [])
		var previous_size := models.size()
		for row in rows:
			if not row is Dictionary or not bool(row.get("free", false)):
				continue
			var candidate := str(row.get("model", ""))
			if candidate == "" or candidate in models:
				continue
			models.append(candidate)
			if models.size() - previous_size >= MAX_ATTEMPTS - 1:
				break
		if models.size() == previous_size:
			_finish({"ok": false, "text": "", "error": reason + " The refreshed catalogue contains no other eligible model. Choose another model in Setup."})
			return
		_job["models"] = models
		_job["idx"] = previous_size
		_job["attempts"] = 1
		_job["nonstream"] = false
		_job["lowered"] = false
		_job["swap"] = false
		_job["no_tools"] = false
		chat_notice.emit("Found another available model. Retrying with that model…")
		_start_stream())
	var err := req.request(Catalog.models_url(pid), _headers(pid, str(_job.get("api_key", "")), false), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		if busy and int(_job.get("generation", -1)) == generation:
			_finish({"ok": false, "text": "", "error": reason + " Aoi couldn't refresh the model list (error %d)." % err})


func _afford(msg: String) -> int:
	var re := RegEx.new()
	re.compile("can only afford (\\d+)")
	var m := re.search(msg)
	return int(m.get_string(1)) if m != null else 0


func _nonstream() -> void:
	var pid := str(_job["provider"])
	var generation := int(_job.get("generation", -1))
	var req := HTTPRequest.new()
	req.timeout = _nonstream_timeout_for_provider(pid)
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if not busy or int(_job.get("generation", -1)) != generation: return
		if result != HTTPRequest.RESULT_SUCCESS:
			_retryable_fail("The connection dropped while waiting for the answer.")
			return
		var text := body.get_string_from_utf8()
		if code >= 400:
			_handle_http_error(code, _error_message(text))
			return
		var obj: Variant = JSON.parse_string(text)
		var out := ""
		var calls: Array = []
		if obj is Dictionary and (obj as Dictionary).get("choices") is Array and not ((obj as Dictionary)["choices"] as Array).is_empty():
			var choice: Variant = ((obj as Dictionary)["choices"] as Array)[0]
			var msg: Variant = (choice as Dictionary).get("message", {}) if choice is Dictionary else {}
			if msg is Dictionary:
				out = _content_to_text((msg as Dictionary).get("content", "")).strip_edges()
				var returned_calls: Variant = (msg as Dictionary).get("tool_calls", [])
				if returned_calls is Array: calls = returned_calls.duplicate(true)
				elif (msg as Dictionary).get("function_call") is Dictionary:
					var old_call: Dictionary = (msg as Dictionary)["function_call"]
					calls.append({"id":"legacy_function_call", "type":"function", "function":old_call.duplicate(true)})
		if out == "" and calls.is_empty():
			# We already tried this model twice: once as SSE and once as JSON.
			# Spend the next retry slot on a different known model instead of
			# repeating the same empty response a third time.
			if int(_job.get("idx", 0)) + 1 < (_job.get("models", []) as Array).size():
				_job["attempts"] = MAX_ATTEMPTS - 1
			_retryable_fail("%s returned nothing after a non-stream retry." % _current_model())
			return
		_text = out
		if out != "": chat_delta.emit(out)
		_tool_calls = calls
		_finish({"ok": true, "text": out, "tool_calls": _completed_tool_calls()}))
	var url := Catalog.base_url(pid) + "/chat/completions"
	var err := req.request(url, _headers(pid, str(_job.get("api_key", "")), false), HTTPClient.METHOD_POST, _body(false))
	if err != OK:
		req.queue_free()
		_retryable_fail("Could not send the request (error %d)." % err)


func _retryable_fail(msg: String) -> void:
	if not busy: return
	_phase = 0
	_http.close()
	if _text != "":
		_finish({"ok": true, "text": _text, "truncated": true, "error": msg})
		return
	var attempts := int(_job.get("attempts", 1))
	if attempts < MAX_ATTEMPTS:
		var next_attempt := attempts + 1
		var current_model := _current_model()
		# Retry the selected model once before moving to a known free fallback on
		# the final attempt. Never spin indefinitely on a single dead endpoint.
		if next_attempt == MAX_ATTEMPTS:
			var models: Array = _job.get("models", [])
			var current_index := int(_job.get("idx", 0))
			if current_index + 1 < models.size():
				_job["idx"] = current_index + 1
		_job["attempts"] = next_attempt
		_job["nonstream"] = false
		_job["lowered"] = false
		_job["retry_pending"] = true
		_retry_pending = true
		_retry_at_msec = Time.get_ticks_msec() + (650 if next_attempt == 2 else 1250)
		set_process(true)
		var retry_target := _current_model()
		if retry_target == current_model:
			chat_notice.emit("A brief connection issue. Trying again (%d/%d)…" % [next_attempt, MAX_ATTEMPTS])
		else:
			chat_notice.emit("That model is unavailable. Trying a backup (%d/%d)…" % [next_attempt, MAX_ATTEMPTS])
		return
	_finish({"ok": false, "text": "", "error": msg})


func _content_to_text(value: Variant) -> String:
	if value is String: return str(value)
	if value is Array:
		var parts: Array[String] = []
		for part in value:
			if part is Dictionary and str(part.get("type", "")) == "text":
				parts.append(str(part.get("text", "")))
		return "".join(parts)
	return ""


func _completed_tool_calls() -> Array:
	var out: Array = []
	for item in _tool_calls:
		if not item is Dictionary: continue
		var call: Dictionary = item as Dictionary
		var function_value: Variant = call.get("function", {})
		if not function_value is Dictionary: continue
		var function_data: Dictionary = function_value
		# Preserve identifiable but incomplete calls so ChatScreen can return a
		# matching, safe tool error instead of silently dropping protocol state.
		var has_payload := str(call.get("id", "")) != "" or str(function_data.get("name", "")) != "" or str(function_data.get("arguments", "")) != ""
		if has_payload:
			out.append(call.duplicate(true))
	return out


func _finish(result: Dictionary) -> void:
	if not busy: return
	busy = false
	_retry_pending = false
	_phase = 0
	set_process(false)
	var pid := str(_job.get("provider", ""))
	if pid == "puter":
		var saved_status: Variant = Store.status.get(pid, {})
		var puter_status: Dictionary = saved_status.duplicate(true) if saved_status is Dictionary else {}
		if bool(result.get("ok", false)):
			puter_status["credential_verified"] = true
			puter_status["verified_at"] = Time.get_unix_time_from_system()
			Store.status[pid] = puter_status
			Store.save_settings()
		elif int(result.get("http_status", 0)) in [401, 403]:
			puter_status["credential_verified"] = false
			puter_status.erase("verified_at")
			Store.status[pid] = puter_status
			Store.save_settings()
	result["provider"] = pid
	result["model"] = Catalog.visible_id(pid, _current_model()) if not _job.is_empty() else ""
	chat_finished.emit(result)


# ------------------------------------------------------------------ errors
static func _error_message(body: String) -> String:
	var obj: Variant = JSON.parse_string(body)
	if obj is Dictionary:
		var e: Variant = (obj as Dictionary).get("error", (obj as Dictionary).get("message", ""))
		if e is Dictionary: return str((e as Dictionary).get("message", ""))
		if e is String: return e
	if obj is Array and not (obj as Array).is_empty() and (obj as Array)[0] is Dictionary:   # Google style [{"error": {...}}]
		var e2: Variant = ((obj as Array)[0] as Dictionary).get("error", {})
		if e2 is Dictionary: return str((e2 as Dictionary).get("message", ""))
	return body.strip_edges().left(240)


static func explain(provider_id: String, code: int, msg: String) -> String:
	var name := str(Catalog.by_id(provider_id).get("name", provider_id))
	if provider_id == "puter":
		var lower_msg := msg.to_lower()
		if code == 401:
			return "Puter rejected this API token (HTTP 401). Create a new full-access API token in the Puter dashboard and replace the saved token."
		if code == 403:
			if "account session token" in lower_msg or "app_or_api_token_required" in lower_msg:
				return "Puter needs a full-access API token for native Aoi chat. Create one in Puter Dashboard → Account → API Token; an account session token will not work."
			return "Puter denied this request (HTTP 403). Check account verification and the saved API token."
		if code == 402:
			if "subscription_required" in lower_msg or "paid plan" in lower_msg:
				return "Puter's native OpenAI-compatible API requires a paid Puter plan. The browser Puter.js workspace remains available for the user-pays flow."
			return "Puter could not cover this request from your account allowance or credits. Check the Puter usage dashboard or choose a lower-cost model."
	match code:
		401, 403: return "%s rejected your key (HTTP %d). Open Setup and paste it again." % [name, code]
		429: return "%s is rate limiting you (HTTP 429). Wait a minute or pick another model." % name
		402: return "%s says this model needs credit (HTTP 402). Pick a free model (★)." % name
		404: return "That model isn't available on %s right now (HTTP 404). Pick another." % name
		408: return "%s timed out. Try again." % name
	if code >= 500: return "%s is having problems (HTTP %d). Try again or pick another model." % [name, code]
	return "%s error (HTTP %d)%s" % [name, code, (": " + msg.left(160)) if msg != "" else ""]

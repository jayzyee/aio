extends Node
# Real LLM client (HTTPClient streaming) against tests_py/mock_openai_server.py
const OR := "openrouter/meta-llama/llama-3.3-70b-instruct:free"
const Catalog = preload("res://scripts/core/Catalog.gd")
var results: Array = []
var deltas: Array = []
var notices: Array = []

func _ready() -> void:
	Store.set_root("user://e2e_%d/" % Time.get_ticks_msec())
	LLM.chat_delta.connect(func(t): deltas.append(t))
	LLM.chat_notice.connect(func(t): notices.append(t))
	Store.set_integration("custom_provider", {"base_url":"http://127.0.0.1:11434/v1"})
	_check("L0a_local_custom_model_gets_longer_first_token_window", LLM._idle_timeout_for_provider("custom") == 240.0)
	Store.set_integration("custom_provider", {"base_url":"http://[::1]:11434/v1"})
	var ipv6_endpoint := LLM._split_url(Catalog.base_url("custom"))
	_check("L0b_ipv6_loopback_endpoint_is_parsed_and_gets_local_timeout", ipv6_endpoint.get("host") == "::1" and int(ipv6_endpoint.get("port", 0)) == 11434 and str(ipv6_endpoint.get("path", "")) == "/v1" and LLM._idle_timeout_for_provider("custom") == 240.0)
	Store.set_integration("custom_provider", {"base_url":"https://api.example.com/v1"})
	_check("L0c_remote_custom_provider_keeps_standard_timeout", LLM._idle_timeout_for_provider("custom") == 45.0)
	Store.set_integration("custom_provider", {"base_url":"http://localhost:11434/v1"})
	LLM.idle_timeout = 2.0
	_check("L0d_test_timeout_override_is_preserved", LLM._idle_timeout_for_provider("custom") == 2.0)
	_check("L0e_nonstream_local_fallback_keeps_minimum_timeout", LLM._nonstream_timeout_for_provider("custom") == 60.0)
	LLM.idle_timeout = LLM.IDLE_TIMEOUT
	_check("L0f_nonstream_local_fallback_uses_extended_timeout", LLM._nonstream_timeout_for_provider("custom") == 240.0)
	Store.set_integration("custom_provider", {"base_url":"https://api.example.com/v1"})
	_check("L0g_nonstream_remote_provider_keeps_standard_timeout", LLM._nonstream_timeout_for_provider("custom") == 60.0)
	LLM.idle_timeout = 2.0
	Store.set_key("openrouter", "bad-key")
	var r = await _models("openrouter")
	_check("L1a_bad_key_is_explained", not r[1] and "rejected your key" in str(r[2]))
	Store.set_key("openrouter", "good-key"); Store.set_key("google_ai", "good-key")
	r = await _models("openrouter")
	var ids: Array = []
	for row in r[2]: ids.append(row["id"])
	_check("L1b_openrouter_models_and_free_flags", r[1] and ids.has(OR) and not ids.has("openrouter/intfloat/e5-embed") and _row(r[2], "openrouter/openai/gpt-4o")["free"] == false and _row(r[2], OR)["free"] == true)
	r = await _models("google_ai")
	_check("L1c_google_models_filtered", r[1] and r[2].size() == 2 and r[2][0]["id"].begins_with("google_ai/gemini-2.5"))
	Store.set_key("puter", "good-key")
	r = await _models("puter")
	var puter_model := Catalog.default_model("puter", r[2]) if r[1] else ""
	Store.status["puter"] = {"models_count": r[2].size(), "credential_verified": false}
	_check("L1d_puter_model_details_catalogue", r[1] and r[2].size() == 2 and puter_model == "puter/meta-llama:meta-llama/llama-3.3-free" and _row(r[2], "puter/azure:openai/gpt-5.4-nano")["cost_label"].contains("$0.20"))
	var puter_denied := await _chat(puter_model, "PUTER403 invalid credential scope")
	_check("L1e_puter_403_is_explained_and_does_not_mark_token_verified", not puter_denied["ok"] and "full-access API token" in puter_denied["error"] and not Store.status["puter"]["credential_verified"])
	var puter_reply := await _chat(puter_model, "native Puter chat")
	var puter_log := await _log()
	var puter_request: Dictionary = {}
	for item in puter_log:
		if str(item.get("p", "")) == "/p/v1/chat/completions": puter_request = item
	_check("L1f_puter_chat_uses_canonical_model_and_marks_successful_credential", puter_reply["ok"] and "native Puter chat" in puter_reply["text"] and puter_request.get("model", "") == "meta-llama:meta-llama/llama-3.3-free" and Store.status["puter"]["credential_verified"])
	var res = await _chat(OR, "hello world")
	_check("L2_streams_incrementally", res["ok"] and deltas.size() > 3 and "You said: hello world" in res["text"] and res["text"] == "".join(deltas))
	res = await _chat(OR, "SPLIT please")
	_check("L3_utf8_split_across_packets", res["ok"] and res["text"] == "naïve 日本語 🙂 ok")
	res = await _chat("google_ai/gemini-2.5-flash", "hi gemini")
	var log = await _log()
	_check("L4_google_sends_raw_model_name", res["ok"] and "You said: hi gemini" in res["text"] and str(log[log.size() - 1]["model"]) == "gemini-2.5-flash")
	var before = (await _log()).size()
	res = await _chat(OR, "ERR401 now")
	log = await _log()
	_check("L5_bad_key_stops_without_fallback", not res["ok"] and "rejected your key" in res["error"] and log.size() == before + 1, [res, log.size() - before])
	res = await _chat(OR, "ERR429 try")
	_check("L6_rate_limit_falls_back_to_next_free_model", res["ok"] and notices.size() >= 1 and "cohere/north-mini-code:free" in res["text"] and not "nemotron" in res["text"], [res, notices])
	before = (await _log()).size()
	res = await _chat(OR, "ERR404 unavailable model")
	log = await _log()
	var not_found_seq: Array = []
	for e in log.slice(before): not_found_seq.append(str(e["model"]))
	_check("L6b_model_404_skips_dead_model_and_uses_verified_fallback", res["ok"] and not_found_seq == ["meta-llama/llama-3.3-70b-instruct:free", "cohere/north-mini-code:free"] and notices.size() >= 1, [res, not_found_seq, notices])
	before = (await _log()).size()
	res = await _chat(OR, "EMPTY reply")
	log = await _log()
	var seq: Array = []
	for e in log.slice(before): seq.append(str(e["model"]) + ("|stream" if e["stream"] else "|plain"))
	_check("L7_empty_reply_retries_nonstream_then_other_model", res["ok"] and "cohere" in res["text"] and seq == ["meta-llama/llama-3.3-70b-instruct:free|stream", "meta-llama/llama-3.3-70b-instruct:free|plain", "cohere/north-mini-code:free|stream"], [res, seq])
	res = await _chat(OR, "ERR429ALL x")
	_check("L8_all_models_limited_gives_human_error", not res["ok"] and "rate limiting" in res["error"], res)
	res = await _chat(OR, "EMPTYALL x")
	_check("L9_nothing_anywhere_gives_error_not_silence", not res["ok"] and res["error"] != "" and res["text"] == "", res)
	before = (await _log()).size()
	res = await _chat(OR, "T402 credits")
	log = await _log()
	_check("L10_402_retries_with_affordable_tokens", res["ok"] and int(log[before]["max_tokens"]) == 2048 and int(log[before + 1]["max_tokens"]) == 836, [res, log.slice(before)])
	res = await _chat(OR, "MIDERR")
	_check("L11_midstream_error_keeps_partial_text", res["ok"] and res.get("truncated", false) and res["text"] == "The answer starts " and "upstream exploded" in res["error"], res)
	res = await _chat(OR, "STALL forever")
	_check("L12_stalled_stream_times_out_with_partial", res.get("truncated", false) and "partial" in res["text"] and "stopped answering" in res["error"], res)
	var native_tools := [{"type":"function", "function":{"name":"aoi_project__inspect", "description":"Inspect selected project", "parameters":{"type":"object", "properties":{}, "required":[], "additionalProperties":false}}}]
	res = await _chat_with_tools(OR, "NATIVE_TOOL inspect", native_tools)
	var native_calls: Array = res.get("tool_calls", [])
	var native_log := await _log()
	var native_request: Dictionary = native_log[native_log.size() - 1] if not native_log.is_empty() else {}
	_check("L12A_streamed_native_tool_call_is_parsed", res.get("ok", false) and native_calls.size() == 1 and str(native_calls[0].get("id", "")) == "call_aoi_001" and str(native_calls[0].get("function", {}).get("name", "")) == "aoi_project__inspect" and JSON.parse_string(str(native_calls[0].get("function", {}).get("arguments", ""))) is Dictionary, [res, native_request])
	_check("L12B_native_tool_schema_is_sent", int(native_request.get("tools_count", 0)) == 1 and native_request.get("parallel_tool_calls", true) == false)
	var native_history: Array = [{"role":"system", "content":"sys"}, {"role":"user", "content":"NATIVE_TOOL round trip"},
		{"role":"assistant", "content":null, "tool_calls":native_calls}, {"role":"tool", "tool_call_id":"call_aoi_001", "content":"{\"ok\":true}"}]
	res = await _chat_history_with_tools(OR, native_history, native_tools)
	var roundtrip_log := await _log()
	var roundtrip_request: Dictionary = roundtrip_log[roundtrip_log.size() - 1] if not roundtrip_log.is_empty() else {}
	_check("L12C_native_tool_result_round_trips_with_call_id", res.get("ok", false) and "tool_result_received" in str(res.get("text", "")) and int(roundtrip_request.get("tool_result_count", 0)) == 1)
	res = await _chat_with_tools(OR, "NATIVE_TOOL_NONSTREAM inspect", native_tools)
	native_calls = res.get("tool_calls", [])
	_check("L12D_nonstream_native_tool_call_is_parsed", res.get("ok", false) and native_calls.size() == 1 and str(native_calls[0].get("id", "")) == "call_aoi_001", res)
	before = (await _log()).size()
	res = await _chat_with_tools(OR, "TOOL_UNSUPPORTED compatibility fallback", native_tools)
	var compatibility_log := await _log()
	var compatibility_requests := compatibility_log.slice(before)
	var fallback_request: Dictionary = compatibility_requests[1] if compatibility_requests.size() > 1 else {}
	_check("L12E_native_unsupported_model_retries_without_tools", res.get("ok", false) and "[[AOI_TOOL_CALL]]" in str(res.get("text", "")) and compatibility_requests.size() == 2 and int(compatibility_requests[0].get("tools_count", 0)) == 1 and int(fallback_request.get("tools_count", -1)) == 0)
	_check("L12F_text_compatibility_instruction_is_request_scoped", bool(fallback_request.get("compatibility_hint", false)) and not bool(compatibility_requests[0].get("compatibility_hint", true)))
	var saved_tool_calls: Array = LLM._tool_calls.duplicate(true)
	LLM._tool_calls = [{"id":"call_partial", "type":"function", "function":{"name":"", "arguments":"{"}}]
	var partial_calls: Array = LLM._completed_tool_calls()
	_check("L12G_identifiable_partial_tool_calls_are_preserved_for_safe_rejection", partial_calls.size() == 1 and str(partial_calls[0].get("id", "")) == "call_partial")
	LLM._tool_calls = saved_tool_calls
	deltas.clear()
	var cap: Array = []   # lambdas capture by value: collect into an Array instead of reassigning a local
	LLM.chat_finished.connect(func(x): cap.append(x), CONNECT_ONE_SHOT)
	LLM.chat(OR, [{"role": "user", "content": "SLOW start"}])
	await get_tree().create_timer(0.6).timeout
	LLM.cancel()
	await get_tree().process_frame
	var cres: Dictionary = cap[0] if not cap.is_empty() else {}
	_check("L13_cancel_midflight", cres.get("cancelled", false) and not LLM.busy, cres)
	res = await _chat(OR, "after cancel")
	_check("L14_chat_works_after_cancel", res["ok"] and "after cancel" in res["text"], res)
	var ncap: Array = []
	LLM.chat_finished.connect(func(x): ncap.append(x), CONNECT_ONE_SHOT)
	LLM.chat("groq/llama-3.3-70b-versatile", [{"role": "user", "content": "x"}])
	await get_tree().process_frame
	var nres: Dictionary = ncap[0] if not ncap.is_empty() else {}
	_check("L15_unconnected_provider_message", not nres.get("ok", true) and "Connect a provider" in str(nres.get("error", "")), nres)
	var bad := 0
	for x in results: if not x[1]: bad += 1
	print("E2E_LLM_SUMMARY ", results.size() - bad, "/", results.size(), " passed")
	get_tree().quit(1 if bad > 0 else 0)

func _models(pid: String) -> Array:
	LLM.list_models(pid)
	return await LLM.models_loaded

func _chat(model: String, text: String) -> Dictionary:
	deltas.clear(); notices.clear()
	LLM.chat(model, [{"role": "system", "content": "sys"}, {"role": "user", "content": text}])
	return await LLM.chat_finished

func _chat_with_tools(model: String, text: String, tools: Array) -> Dictionary:
	deltas.clear(); notices.clear()
	LLM.chat(model, [{"role":"system", "content":"sys"}, {"role":"user", "content":text}], {"tools":tools})
	return await LLM.chat_finished

func _chat_history_with_tools(model: String, messages: Array, tools: Array) -> Dictionary:
	deltas.clear(); notices.clear()
	LLM.chat(model, messages, {"tools":tools})
	return await LLM.chat_finished

func _row(rows: Array, id: String) -> Dictionary:
	for r in rows: if r["id"] == id: return r
	return {}

func _log() -> Array:
	var req := HTTPRequest.new(); add_child(req)
	req.request("http://127.0.0.1:%s/__log" % OS.get_environment("MOCK_PORT"))
	var out = await req.request_completed
	req.queue_free()
	return JSON.parse_string((out[3] as PackedByteArray).get_string_from_utf8())

func _check(n: String, ok: bool, detail: Variant = null) -> void:
	results.append([n, ok]); print("E2E_", n, " ", "PASS" if ok else "FAIL", "" if ok or detail == null else " :: " + JSON.stringify(detail))

extends RefCounted
## Providers and chat modes. Providers are data: adding one is one entry (all speak the OpenAI-compatible API).

const PROVIDERS := [
	{"id": "google_ai", "name": "Google AI Studio", "tagline": "Gemini models · free tier, easiest to start",
	 "base_url": "https://generativelanguage.googleapis.com/v1beta/openai", "signup_url": "https://aistudio.google.com/apikey",
	 "key_hint": "AIza…", "free_note": "Free tier with daily limits.", "free": true},
	{"id": "puter", "name": "Puter AI", "tagline": "Chat with models from multiple providers using your Puter account",
	 "base_url": "https://api.puter.com/puterai/openai/v1", "models_url": "https://api.puter.com/puterai/chat/models/details",
	 "signup_url": "https://puter.com/dashboard", "key_hint": "full-access Puter API token", "get_label": "Open Puter dashboard", "free_note": "Native chat uses Puter's OpenAI-compatible API, which requires a paid Puter plan. Model usage uses your Puter account allowance or credits.",
	 "plan_label": "Paid plan required", "free": false, "verify_on_first_use": true,
	 "setup_note": "Create a full-access API token from Puter Dashboard → Account → API Token. This grants broad account access; keep it private and revoke it from the dashboard if exposed. Aoi loads the public model list without spending credits. Puter validates the token and plan on your first chat request, which may use account credit."},
	{"id": "openrouter", "name": "OpenRouter", "tagline": "Many models, lots of them free",
	 "base_url": "https://openrouter.ai/api/v1", "signup_url": "https://openrouter.ai/keys",
	 "key_hint": "sk-or-…", "free_note": "Models ending in :free cost nothing; free models are rate limited.", "free": true},
	{"id": "groq", "name": "Groq", "tagline": "Very fast open models · free tier",
	 "base_url": "https://api.groq.com/openai/v1", "signup_url": "https://console.groq.com/keys",
	 "key_hint": "gsk_…", "free_note": "Free tier with per-minute limits.", "free": true},
]

static func all_providers() -> Array:
	var rows: Array = PROVIDERS.duplicate(true)
	# An opt-in deterministic provider used only by the Godot runtime acceptance
	# harness. It is not visible or selectable in production builds.
	if OS.get_environment("AOI_TEMPORAL_PROVIDER") == "1":
		rows.append({"id":"temporal","name":"Temporal Test Provider","tagline":"Local deterministic provider for end-to-end acceptance runs",
			"base_url":"http://127.0.0.1:8199/v1","signup_url":"","key_hint":"Local test only","free_note":"Runs on this machine. No external API key or network service.","free":true})
	return rows

const NON_CHAT := "(embed|whisper|tts|speech|audio|transcri|moderation|guard|rerank|imagen|veo|image-gen|aqa|dall-e|stable-diffusion|orpheus|playai)"

const MODES := {
	"chat": {"name": "Chat", "hint": "Ask anything"},
	"build": {"name": "Build", "hint": "Make an app or game from your phone"},
	"money": {"name": "Money", "hint": "Find a realistic way to earn"},
}

const SUGGESTIONS := {
	"chat": ["Explain something simply", "Help me plan my week", "Summarise this text for me"],
	"build": ["Make a tiny Godot game I can finish in one day", "Teach me GDScript step by step on my phone", "Design a simple app idea and its first screen"],
	"money": ["Plan a side project I can start this week with no money", "What can I sell online using only my phone?", "Turn my skills into a first paying customer"],
}

const BASE_PROMPT := "You are Aoi, a capable, warm and practical AI assistant. Be respectful and non-judgmental; never scold or shame. Answer the user's actual question first, then add only useful context. Match the requested depth: concise for quick questions, thorough and organized for complex work. Use clear, natural language in the user's language. Be transparent about uncertainty, assumptions and tool limits. Never claim you browsed, ran code, changed files or verified results unless a listed tool actually did so and returned evidence. Use only tools explicitly listed later, follow their scopes and wait for real results. Use Markdown lightly."

const MODE_PROMPTS := {
	"chat": "",
	"build": "\n\nMODE: Builder. Own implementation outcomes, not only suggestions. First inspect the active project's files, manifest, constraints and available runtimes/tools. Preserve existing work and choose the best supported language and runtime for this project; do not assume Godot or a phone-only workflow. For substantial requests, briefly plan, then implement the requested experience end-to-end where tools allow. Create cohesive, runnable deliverables with complete core flows and appropriate UI, assets/data, persistence, accessibility and recovery states; avoid toy-only stubs and placeholder TODOs. Use the project's available languages and scripts, but never claim an unsupported runtime was executed. Verify real output and inspect logs or screenshots when available. Report what is finished, what remains, and concrete blockers. If project-writing tools are unavailable, say so and provide usable files and exact steps. Ask focused questions only for truly blocking ambiguity; otherwise state reasonable assumptions and proceed.",
	"money": "\n\nMODE: Income coach. Help the user find realistic ways to earn with a phone and little or no money: freelance services, digital products, content, reselling, local services. Prefer ideas that can reach a first paying customer within days. Give a concrete plan for THIS WEEK as a checklist using '- [ ] ' items. Be honest about how long first income usually takes; never promise earnings; steer away from scams and get-rich-quick schemes; mention taxes, platform rules and age limits when relevant. Ask at most two clarifying questions, only if truly needed.",
}


static func by_id(id: String) -> Dictionary:
	if id == "custom":
		var config := Store.get_integration("custom_provider")
		return {"id":"custom", "name":str(config.get("name", "Custom endpoint")),
			"tagline":"Any OpenAI-compatible chat API · models are discovered automatically",
			"base_url":str(config.get("base_url", "")), "signup_url":"", "key_hint":"API key",
			"free_note":"Use an HTTPS API root with /models and /chat/completions. HTTP is allowed only for localhost.", "free":false}
	for p in all_providers():
		if str(p["id"]) == id: return p
	return {}


static func base_url(id: String) -> String:
	var env := OS.get_environment("AOI_MOBILE_BASE_" + id.to_upper())   # test/dev override (e.g. local mock server)
	if env != "": return env.rstrip("/")
	if id == "custom": return str(Store.get_integration("custom_provider").get("base_url", "")).rstrip("/")
	return str(by_id(id).get("base_url", "")).rstrip("/")


static func models_url(id: String) -> String:
	var override := OS.get_environment("AOI_MOBILE_BASE_" + id.to_upper())
	if override != "":
		return override.rstrip("/") + "/models"
	var configured := str(by_id(id).get("models_url", "")).strip_edges()
	return configured if configured != "" else base_url(id) + "/models"


static func is_safe_custom_base_url(value: String) -> bool:
	var url := value.strip_edges().trim_suffix("/")
	if url == "" or url.contains(" ") or url.contains("\\") or url.contains("?") or url.contains("#"):
		return false
	var separator := url.find("://")
	if separator <= 0: return false
	var scheme := url.left(separator).to_lower()
	if scheme not in ["https", "http"]: return false
	var remainder := url.substr(separator + 3)
	var path_start := remainder.find("/")
	var authority := remainder if path_start < 0 else remainder.left(path_start)
	var path := "" if path_start < 0 else remainder.substr(path_start)
	var authority_pattern := RegEx.new()
	if authority_pattern.compile("^([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?$") != OK: return false
	var match := authority_pattern.search(authority)
	if match == null: return false
	var host := match.get_string(1).to_lower()
	if host.begins_with(".") or host.ends_with(".") or ".." in host: return false
	for label in host.split("."):
		if label.begins_with("-") or label.ends_with("-"): return false
	if scheme == "http" and host not in ["localhost", "127.0.0.1"]: return false
	var port_text := match.get_string(2)
	if port_text != "" and (int(port_text) < 1 or int(port_text) > 65535): return false
	var path_pattern := RegEx.new()
	if path_pattern.compile("^(/[A-Za-z0-9._~!$&'()*+,;=:@%-/]*)?$") != OK: return false
	return path_pattern.search(path) != null


static func system_prompt(mode: String, project: Dictionary = {}) -> String:
	var s: String = BASE_PROMPT + str(MODE_PROMPTS.get(mode, ""))
	if not project.is_empty():
		s += "\n\nCURRENT PROJECT: %s\nGoal: %s" % [str(project.get("title", "")), str(project.get("goal", ""))]
		var notes := str(project.get("notes", "")).strip_edges()
		if notes != "": s += "\nNotes so far:\n" + notes.left(3000)
		var open: Array = []
		for t in project.get("tasks", []):
			if t is Dictionary and not bool(t.get("done", false)): open.append("- " + str(t.get("text", "")))
		if not open.is_empty(): s += "\nOpen tasks:\n" + "\n".join(open.slice(0, 20))
	var project_id := str(project.get("id", ""))
	if project_id != "":
		var flow := AgentFlow.get_flow(project_id)
		if not flow.is_empty():
			s += "\n\nSHARED PROJECT MEMORY (persistent across project conversations)\nWorkflow phase: %s\nPlan: %s" % [str(flow.get("phase", "brief")), str(flow.get("summary", "No plan"))]
			var decisions: Array = flow.get("decisions", [])
			if not decisions.is_empty():
				var decision_text: Array[String] = []
				for decision in decisions.slice(0, 10): decision_text.append("- " + str(decision.get("text", "")))
				s += "\nRecorded decisions (treat as constraints unless the user changes them):\n" + "\n".join(decision_text)
			var workflow_tasks: Array = flow.get("tasks", [])
			if not workflow_tasks.is_empty():
				var task_text: Array[String] = []
				for task in workflow_tasks.slice(0, 18): task_text.append("- [%s] %s (owner: %s)" % [str(task.get("status", "todo")), str(task.get("title", "")), str(task.get("role", "Engineer"))])
				s += "\nAgent workflow tasks:\n" + "\n".join(task_text)
			var knowledge: Array = flow.get("knowledge", [])
			if not knowledge.is_empty():
				var note_text: Array[String] = []
				for note in knowledge.slice(0, 6): note_text.append("- %s: %s" % [str(note.get("title", "Knowledge note")), str(note.get("content", "")).left(420)])
				s += "\nRelevant saved knowledge:\n" + "\n".join(note_text)
			var playbooks: Array = flow.get("playbooks", [])
			if not playbooks.is_empty():
				var procedures: Array[String] = []
				for book in playbooks.slice(0, 4): procedures.append("- %s (use when: %s)\n%s" % [str(book.get("title", "Playbook")), str(book.get("trigger", "relevant")), str(book.get("steps", "")).left(1100)])
				s += "\nPROJECT PLAYBOOKS (follow when applicable; ask before any privileged/external action):\n" + "\n\n".join(procedures)
	return s


static func visible_id(provider_id: String, model: String) -> String:
	return provider_id + "/" + (model.trim_prefix("models/"))


static func split_visible(visible: String) -> Array:
	var i := visible.find("/")
	if i < 0: return ["", visible]
	var head := visible.substr(0, i)
	return [head, visible.substr(i + 1)] if not by_id(head).is_empty() else ["", visible]


## OpenAI-style {"data":[{"id":..}]} -> chat-capable rows, largest context first.
static func normalize_models(provider_id: String, payload: Variant) -> Array:
	var rows_in: Array = []
	if payload is Dictionary and (payload as Dictionary).get("data") is Array: rows_in = (payload as Dictionary).get("data")
	elif payload is Dictionary and (payload as Dictionary).get("models") is Array: rows_in = (payload as Dictionary).get("models")
	elif payload is Array: rows_in = payload
	var skip := RegEx.new()
	skip.compile("(?i)" + NON_CHAT)
	var out: Array = []
	var seen := {}
	for item in rows_in:
		var mid := str(item.get("puterId", item.get("id", ""))) if provider_id == "puter" and item is Dictionary else (str(item.get("id", "")) if item is Dictionary else str(item))
		if mid == "" or seen.has(mid) or skip.search(mid) != null: continue
		seen[mid] = true
		var ctx := 0
		var free := false
		var label := mid.trim_prefix("models/")
		var cost_rank := 1.0e20
		var cost_label := ""
		if item is Dictionary:
			ctx = int(item.get("context_length", item.get("context_window", item.get("inputTokenLimit", item.get("context", 0)))))
			var pr: Variant = item.get("pricing")
			if pr is Dictionary: free = str(pr.get("prompt", "x")) in ["0", "0.0"] and str(pr.get("completion", "x")) in ["0", "0.0"]
			if provider_id == "puter":
				var raw_name: Variant = item.get("name", "")
				label = str(raw_name).strip_edges() if raw_name is String else ""
				if label == "": label = str(item.get("id", mid))
				var raw_costs: Variant = item.get("costs", item.get("cost", {}))
				if raw_costs is Dictionary:
					var input_value: Variant = raw_costs.get("prompt_tokens", raw_costs.get("input", null))
					var output_value: Variant = raw_costs.get("completion_tokens", raw_costs.get("output", null))
					if input_value != null and output_value != null:
						var input_cost := float(input_value)
						var output_cost := float(output_value)
						cost_rank = input_cost + output_cost
						free = input_cost == 0.0 and output_cost == 0.0
						var token_count := maxi(1, int(raw_costs.get("tokens", 1000000)))
						var currency := str(item.get("costs_currency", raw_costs.get("currency", "")))
						if currency == "usd-cents":
							var scale := 1000000.0 / float(token_count) / 100.0
							cost_label = "$%.2f in / $%.2f out per 1M tokens" % [input_cost * scale, output_cost * scale]
				var provider_id_value := str(item.get("id", ""))
				if provider_id_value.ends_with(":free") or mid.ends_with(":free"): free = true
		if provider_id == "openrouter":
			var openrouter_price: Variant = item.get("pricing", {}) if item is Dictionary else {}
			if openrouter_price is Dictionary and not openrouter_price.is_empty():
				free = str(openrouter_price.get("prompt", "x")) in ["0", "0.0"] and str(openrouter_price.get("completion", "x")) in ["0", "0.0"]
			else:
				free = mid.ends_with(":free")
		elif provider_id != "puter":
			free = bool(by_id(provider_id).get("free", false))
		out.append({"id": visible_id(provider_id, mid), "model": mid, "label": label, "free": free, "context_length": ctx, "provider": provider_id, "cost_rank": cost_rank, "cost_label": cost_label})
	out.sort_custom(func(a, b): return int(a["context_length"]) > int(b["context_length"]) or (int(a["context_length"]) == int(b["context_length"]) and str(a["label"]) < str(b["label"])))
	return out


## Sensible default: a fast general model, not a vision-only or tiny one.
static func default_model(provider_id: String, rows: Array) -> String:
	if provider_id == "puter":
		for row in rows:
			if row is Dictionary and bool(row.get("free", false)):
				return str(row.get("id", ""))
		var sorted_rows := rows.duplicate(true)
		for row in sorted_rows:
			if row is Dictionary and str(row.get("model", "")) in ["azure:openai/gpt-5.4-nano", "gpt-5.4-nano"]:
				return str(row.get("id", ""))
		sorted_rows.sort_custom(func(a, b):
			if not a is Dictionary: return false
			if not b is Dictionary: return true
			if bool(a.get("free", false)) != bool(b.get("free", false)): return bool(a.get("free", false))
			var a_cost := float(a.get("cost_rank", 1.0e20))
			var b_cost := float(b.get("cost_rank", 1.0e20))
			if a_cost != b_cost: return a_cost < b_cost
			return str(a.get("label", "")).naturalnocasecmp_to(str(b.get("label", ""))) < 0)
		for row in sorted_rows:
			if row is Dictionary and not str(row.get("model", "")).is_empty(): return str(row.get("id", ""))
	var prefer := {"google_ai": ["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash", "gemini-1.5-flash"],
		"groq": ["llama-3.3-70b-versatile", "openai/gpt-oss-120b", "llama-3.1-8b-instant"], "openrouter": []}
	for want in prefer.get(provider_id, []):
		for r in rows: if str(r["model"]) == want: return str(r["id"])
	var best := ""
	for r in rows:
		var m := str(r["model"]).to_lower()
		if bool(r["free"]) and not ("-vl" in m or "vision" in m or "image" in m or "embed" in m):
			best = str(r["id"]); break
	if best == "" and not rows.is_empty(): best = str((rows[0] as Dictionary)["id"])
	return best

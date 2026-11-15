extends RefCounted
## Turns the flat model list from the server into provider groups for pickers.
## Shared by the composer picker and the Setup hub so both always agree.
## Pure functions (no scene access) so it is unit-tested in tests/model_groups_probe.gd.

const PROVIDER_NAMES := {
	"gemini": "Google Gemini", "deepseek": "DeepSeek", "google_ai": "Google AI Studio", "groq": "Groq",
	"cerebras": "Cerebras", "mistral": "Mistral", "openrouter": "OpenRouter", "ollama": "Ollama",
	"lmstudio": "LM Studio", "custom": "Custom endpoint", "puter": "Puter AI",
}
const PROVIDER_ORDER := ["gemini", "deepseek", "google_ai", "groq", "cerebras", "mistral", "puter", "openrouter", "ollama", "lmstudio", "custom"]
const MAX_PER_GROUP := 200


static func provider_of(id: String, meta: Dictionary) -> String:
	var m: Variant = meta.get(id, {})
	if m is Dictionary and str((m as Dictionary).get("provider", "")) != "":
		var p := str((m as Dictionary).get("provider"))
		return "openrouter" if p == "gateway" else p
	# No metadata (older server): guess from the id.
	var head := id.get_slice("/", 0)
	if PROVIDER_NAMES.has(head) and "/" in id: return head
	if id.begins_with("gemini-"): return "gemini"
	if id.begins_with("deepseek-"): return "deepseek"
	if id.ends_with(":free") or "/" in id: return "openrouter"
	return "other"


static func is_free(id: String, meta: Dictionary) -> bool:
	var m: Variant = meta.get(id, {})
	if m is Dictionary and (m as Dictionary).has("free"): return bool((m as Dictionary).get("free"))
	return id.ends_with(":free")


static func provider_name(provider: String) -> String:
	return str(PROVIDER_NAMES.get(provider, provider.capitalize() if provider != "" else "Other"))


static func label_of(id: String, meta: Dictionary) -> String:
	var provider := provider_of(id, meta)
	var m: Variant = meta.get(id, {})
	var label := str((m as Dictionary).get("label", "")) if m is Dictionary else ""
	if label == "":
		label = id
		if label.begins_with(provider + "/"): label = label.trim_prefix(provider + "/")
	label = label.trim_suffix(":free")
	return label.replace("/", " · ")


## Hide duplicates that only confuse people: web/cookie variants of a model that also exists plainly,
## council ids, and (unless asked) paid OpenRouter models.
static func visible_ids(ids: Array, meta: Dictionary, show_paid := false, keep := "") -> Array:
	var have := {}
	for i in ids: have[str(i)] = true
	var out: Array = []
	for raw in ids:
		var id := str(raw)
		if id.begins_with("council-"): continue
		if id == keep:
			out.append(id)   # the user's current choice is always listed, even if normally hidden
			continue
		var provider := provider_of(id, meta)
		if (provider == "gemini" or provider == "deepseek"):
			if id == "gemini-web": continue
			var base := id
			if id.ends_with("_web"): base = id.trim_suffix("_web")
			elif id.ends_with("_c"): base = id.trim_suffix("_c")
			if base != id and have.has(base): continue
		if provider == "openrouter" and not show_paid and not is_free(id, meta): continue
		out.append(id)
	return out


## -> [{provider, name, items: [{id, label, free}]}] in a stable, friendly order.
static func group(ids: Array, meta: Dictionary, show_paid := false, keep := "") -> Array:
	var buckets := {}
	for id in visible_ids(ids, meta, show_paid, keep):
		var p := provider_of(str(id), meta)
		if not buckets.has(p): buckets[p] = []
		var model_meta: Variant = meta.get(str(id), {})
		var cost_label := str(model_meta.get("cost_label", "")) if model_meta is Dictionary else ""
		(buckets[p] as Array).append({"id": str(id), "label": label_of(str(id), meta), "free": is_free(str(id), meta), "cost_label": cost_label})
	var order: Array = []
	for p in PROVIDER_ORDER:
		if buckets.has(p): order.append(p)
	var rest: Array = []
	for p in buckets.keys():
		if not order.has(p): rest.append(p)
	rest.sort()
	order.append_array(rest)
	var out: Array = []
	for p in order:
		var items: Array = buckets[p]
		items.sort_custom(func(a, b):
			if a["free"] != b["free"]: return a["free"]
			return str(a["label"]).naturalnocasecmp_to(str(b["label"])) < 0)
		if items.size() > MAX_PER_GROUP: items = items.slice(0, MAX_PER_GROUP)
		out.append({"provider": p, "name": provider_name(p), "items": items})
	return out


## Fill an OptionButton with grouped items (section headers are separators; metadata = model id).
## Returns the index of `selected_id` (or the first real item), -1 when there are no items.
static func fill_option_button(ob: OptionButton, groups: Array, selected_id: String) -> int:
	ob.clear()
	var selected := -1
	var first := -1
	for g in groups:
		ob.add_separator(str(g["name"]))
		for it in g["items"]:
			ob.add_item(("★ " if it["free"] else "") + str(it["label"]))
			var idx := ob.item_count - 1
			ob.set_item_metadata(idx, str(it["id"]))
			if first < 0: first = idx
			if str(it["id"]) == selected_id: selected = idx
	if selected < 0: selected = first
	if selected >= 0: ob.select(selected)
	return selected

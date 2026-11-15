extends ScrollContainer
## Plugins & tools directory. Cards clearly separate native AI-callable tools from browser destinations.
const Ui = preload("res://scripts/ui/Ui.gd")
const Sheet = preload("res://scripts/ui/Sheet.gd")

signal request_setup
signal request_piston_config
signal request_linux_config
signal request_github_connect
signal github_connection_finished(success: bool, account: String, message: String)
signal request_huggingface_connect
signal toast(text: String)

var _body: VBoxContainer
var _search: LineEdit
var _results: VBoxContainer
var _category := "All"
var _search_query := ""
var _show_external_services := false
var _category_buttons: Dictionary = {}
var _category_select: OptionButton
var _detail_sheet: Control
var _runner_language := "python"
var _runner_code: TextEdit
var _runner_output: Label
var _run_button: Button
var _github_request: HTTPRequest
var _brave_request: HTTPRequest
var _hf_request: HTTPRequest
var _linux_command_edit: TextEdit
var _linux_output: Label
var _linux_run_button: Button
var _linux_test_button: Button
var _manual_target := "piston"

const CATEGORIES := ["All", "AI & media", "Research", "Developer", "Workspaces", "Productivity", "Design"]
const INTEGRATIONS := [
	{"id":"android_productivity", "name":"Android alarms and calendar", "eyebrow":"DEVICE PRODUCTIVITY TOOLS", "category":"Productivity", "description":"Ask Aoi to prepare an alarm in Android Clock or an event in your Calendar app from chat.", "detail":"AI-callable on the Android build · each action requires approval and opens the device app for confirmation · no calendar-reading or exact-alarm permission · Aoi cannot verify that you saved the item", "action":"How it works", "url":"", "icon":"calendar", "featured":true},
	{"id":"puter", "name":"Puter AI", "eyebrow":"MULTI-MODEL CREATIVE AI", "category":"AI & media", "description":"Use Puter.js in its browser workspace for user-pays chat and creative features, or connect a full-access API token for native Aoi text chat.", "detail":"Two separate routes · browser Puter.js uses its user-pays flow · native chat uses the OpenAI-compatible API and requires a paid Puter plan plus a full-access token · first chat may use account credit", "action":"Open Puter AI", "url":"https://puter.com", "icon":"sparkles", "featured":true},
	{"id":"pixverse", "name":"PixVerse", "eyebrow":"AI VIDEO GENERATION", "category":"AI & media", "description":"Create short clips from text prompts or reference images with a browser-based generation workflow.", "detail":"Browser destination · check current credits, watermark, queue and regional limits", "action":"Open PixVerse", "url":"https://app.pixverse.ai/", "icon":"video", "featured":true},
	{"id":"kling", "name":"Kling AI", "eyebrow":"CINEMATIC AI VIDEO", "category":"AI & media", "description":"Generate video from prompts and images, with camera and motion controls in the web workspace.", "detail":"Browser destination · access and generation limits vary by account and region", "action":"Open Kling AI", "url":"https://klingai.com/", "icon":"clapperboard", "featured":true},
	{"id":"hailuo", "name":"Hailuo AI", "eyebrow":"TEXT + IMAGE TO VIDEO", "category":"AI & media", "description":"Create short cinematic clips from a text description or a reference image.", "detail":"Browser destination · check current credits, watermark, queue and regional limits", "action":"Open Hailuo", "url":"https://hailuoai.video/", "icon":"video", "featured":true},
	{"id":"hf_spaces", "name":"Hugging Face Spaces", "eyebrow":"OPEN MODEL PLAYGROUND", "category":"AI & media", "description":"Explore community demos for image, audio, video, chat and other open-model experiments.", "detail":"Browser destination · some demos sleep, queue or require paid inference credits", "action":"Explore Spaces", "url":"https://huggingface.co/spaces", "icon":"layers", "featured":true},
	{"id":"huggingface_image", "name":"Hugging Face Image", "eyebrow":"NATIVE AI IMAGE GENERATION", "category":"AI & media", "description":"Generate and save images directly from chat with a connected inference provider.", "detail":"AI-callable · requires an Inference Providers token · provider credits or billing may apply", "action":"Connect image generation", "url":"https://huggingface.co/settings/tokens/new?tokenType=fineGrained", "icon":"image", "featured":true},
	{"id":"huggingface_video", "name":"Hugging Face Video", "eyebrow":"NATIVE AI VIDEO GENERATION", "category":"AI & media", "description":"Generate a short MP4 from a text prompt directly inside an Aoi conversation.", "detail":"AI-callable · uses the Fal AI Wan 2.2 video route · requires Inference Providers token permission · generation is metered and may cost money", "action":"Connect video generation", "url":"https://huggingface.co/settings/tokens/new?tokenType=fineGrained", "icon":"video", "featured":true},
	{"id":"ideogram", "name":"Ideogram", "eyebrow":"IMAGE + TYPOGRAPHY", "category":"AI & media", "description":"A focused image-generation workspace, especially useful for poster, logo and text-in-image concepts.", "detail":"Browser destination · free access and generation limits can change", "action":"Open Ideogram", "url":"https://ideogram.ai/", "icon":"image", "featured":false},
	{"id":"leonardo", "name":"Leonardo AI", "eyebrow":"ASSETS + CONCEPT ART", "category":"AI & media", "description":"Create concept art, illustrations, textures and game-asset explorations in a browser workspace.", "detail":"Browser destination · check current token allowances and commercial-use terms", "action":"Open Leonardo", "url":"https://leonardo.ai/", "icon":"palette", "featured":false},
	{"id":"github", "name":"GitHub", "eyebrow":"REPOSITORIES + SOURCE READING", "category":"Developer", "description":"Search public repositories, inspect source files and trees, and use scoped access to private repositories. Repository changes are handled through Aoi approval cards.", "detail":"AI-callable · public reads and search can work without a token · fine-grained token for private repositories and higher rate limits · remote mutations require approval", "action":"Connect GitHub", "url":"https://github.com/settings/personal-access-tokens/new", "icon":"github", "featured":true},
	{"id":"piston", "name":"Piston Runner", "eyebrow":"SANDBOXED CODE EXECUTION", "category":"Developer", "description":"Run Python, JavaScript and Bash when you connect a Piston API server you own or are authorised to use. Aoi can invoke it only when code execution is requested.", "detail":"Native AI tool · remote execution on your configured server · public hosted API is not generally free for new users", "action":"Configure runner", "url":"https://github.com/engineer-man/piston", "icon":"play", "featured":true},
	{"id":"replit", "name":"Replit", "eyebrow":"CLOUD IDE + APP HOSTING", "category":"Developer", "description":"Open a browser coding environment for prototyping and running projects without installing a desktop IDE.", "detail":"Browser destination · free features, usage quotas and deployment limits vary", "action":"Open Replit", "url":"https://replit.com/", "icon":"code", "featured":false},
	{"id":"stackblitz", "name":"StackBlitz", "eyebrow":"INSTANT WEB IDE", "category":"Developer", "description":"Launch web projects in a browser-based development environment, useful for front-end prototypes and JavaScript experiments.", "detail":"Browser destination · best suited to web projects rather than a full Linux environment", "action":"Open StackBlitz", "url":"https://stackblitz.com/", "icon":"code", "featured":false},
	{"id":"codespaces", "name":"GitHub Codespaces", "eyebrow":"CLOUD LINUX WORKSPACE", "category":"Workspaces", "description":"Launch a cloud development container with a Linux terminal, editor and repository access.", "detail":"Browser destination · eligible personal accounts include limited monthly compute and storage quotas", "action":"Open Codespaces", "url":"https://github.com/codespaces", "icon":"terminal", "featured":true},
	{"id":"colab", "name":"Google Colab", "eyebrow":"PYTHON NOTEBOOKS", "category":"Workspaces", "description":"Run Python notebooks for data analysis, machine learning and experiments without setting up a local environment.", "detail":"Browser destination · free runtimes exist, but duration, GPU and availability are not guaranteed", "action":"Open Colab", "url":"https://colab.research.google.com/", "icon":"notebook", "featured":true},
	{"id":"kaggle", "name":"Kaggle Notebooks", "eyebrow":"DATASETS + NOTEBOOKS", "category":"Workspaces", "description":"Work with public datasets, Python notebooks and competitions in a hosted environment.", "detail":"Browser destination · account required · compute and accelerator quotas apply", "action":"Open Kaggle", "url":"https://www.kaggle.com/code", "icon":"chart", "featured":true},
	{"id":"jupyterlite", "name":"JupyterLite", "eyebrow":"PYTHON IN YOUR BROWSER", "category":"Workspaces", "description":"Try Python notebooks directly in the browser without creating a cloud server or installing a runtime.", "detail":"Browser destination · package support and memory are limited compared with hosted Linux workspaces", "action":"Open JupyterLite", "url":"https://jupyterlite.github.io/demo/", "icon":"notebook", "featured":false},
	{"id":"linux_bridge", "name":"Cloud Linux workspace", "eyebrow":"REMOTE PROJECT RUNTIME", "category":"Workspaces", "description":"Connect Aoi to a remote Linux machine such as GitHub Codespaces. Run Godot projects in the cloud and return real runtime logs and captures without using your personal computer as the host.", "detail":"HTTPS bridge · workspace-scoped files · Codespaces quota applies · shell commands run as the remote workspace user", "action":"Connect cloud workspace", "url":"", "icon":"terminal", "featured":true},
	{"id":"canva", "name":"Canva", "eyebrow":"DESIGN + VIDEO EDITING", "category":"Design", "description":"Create thumbnails, posters, presentations, social graphics and simple video edits from a browser or phone.", "detail":"Browser destination · free and paid features are separated by Canva's current plan", "action":"Open Canva", "url":"https://www.canva.com/", "icon":"palette", "featured":false},
	{"id":"wikipedia", "name":"Wikipedia Research", "eyebrow":"NATIVE RESEARCH TOOL", "category":"Research", "description":"Aoi can search public encyclopedia articles and retrieve a concise article extract directly in chat. No account or API key is required.", "detail":"AI-callable public API · background information only · use official sources for current or technical decisions", "action":"Open Wikipedia", "url":"https://www.wikipedia.org/", "icon":"notebook", "featured":true},
	{"id":"brave_search", "name":"Brave Search · Agent Research", "eyebrow":"EVIDENCE-GROUNDED WEB RESEARCH", "category":"Research", "description":"Give Aoi access to current web research with extracted source passages and source metadata. Aoi uses it to study references, feedback, official documentation, technical risks and production needs before planning substantial work.", "detail":"Native research tool · API key stored encrypted on this device · metered API usage · only invoked for substantial project research", "action":"Connect Brave Search", "url":"https://api-dashboard.search.brave.com/", "icon":"search", "featured":true},
	{"id":"luma", "name":"Luma Dream Machine", "eyebrow":"AI VIDEO GENERATION", "category":"AI & media", "description":"Create cinematic video clips from text and image prompts in a browser workspace.", "detail":"Browser destination · account, credits and availability vary", "action":"Open Luma", "url":"https://lumalabs.ai/dream-machine", "icon":"video", "featured":true},
	{"id":"pika", "name":"Pika", "eyebrow":"GENERATIVE VIDEO STUDIO", "category":"AI & media", "description":"Create and transform short-form videos with browser-based generative effects and image-to-video workflows.", "detail":"Browser destination · check current plan limits and watermarks", "action":"Open Pika", "url":"https://pika.art/", "icon":"video", "featured":true},
	{"id":"runway", "name":"Runway", "eyebrow":"AI VIDEO + CREATIVE TOOLS", "category":"AI & media", "description":"Use a browser-based creative suite for generative video, image and editing workflows.", "detail":"Browser destination · free credits and features are subject to plan limits", "action":"Open Runway", "url":"https://runwayml.com/", "icon":"clapperboard", "featured":false},
	{"id":"firefly", "name":"Adobe Firefly", "eyebrow":"GENERATIVE DESIGN", "category":"AI & media", "description":"Explore image, vector and creative generation tools from Adobe in the browser.", "detail":"Browser destination · generative credits and commercial terms depend on the account", "action":"Open Firefly", "url":"https://firefly.adobe.com/", "icon":"palette", "featured":false},
	{"id":"deepnote", "name":"Deepnote", "eyebrow":"COLLABORATIVE PYTHON NOTEBOOKS", "category":"Workspaces", "description":"Run Python notebooks, connect data sources and collaborate in a hosted workspace.", "detail":"Browser destination · free tier and compute limits may change", "action":"Open Deepnote", "url":"https://deepnote.com/", "icon":"notebook", "featured":false},
	{"id":"gitlab", "name":"GitLab", "eyebrow":"REPOSITORIES + CI/CD", "category":"Developer", "description":"Browse code repositories, issues and CI pipelines in a browser-based development platform.", "detail":"Browser destination · Aoi does not currently make authenticated GitLab API calls", "action":"Open GitLab", "url":"https://gitlab.com/", "icon":"code", "featured":false},
	{"id":"excalidraw", "name":"Excalidraw", "eyebrow":"DIAGRAMS + WHITEBOARDS", "category":"Design", "description":"Sketch system architecture, flows and project ideas on a lightweight collaborative canvas.", "detail":"Browser destination · useful for architecture boards and quick diagrams", "action":"Open Excalidraw", "url":"https://excalidraw.com/", "icon":"layers", "featured":false},
	{"id":"penpot", "name":"Penpot", "eyebrow":"OPEN-SOURCE UI DESIGN", "category":"Design", "description":"Design interfaces and prototypes in an open-source browser-based design workspace.", "detail":"Browser destination · self-hosting and cloud options are available", "action":"Open Penpot", "url":"https://penpot.app/", "icon":"palette", "featured":false}
]



func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: pad.add_theme_constant_override("margin_" + side, 18)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 36)
	add_child(pad)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 13)
	pad.add_child(_body)
	ToolRunner.manual_completed.connect(_on_manual_completed)
	ToolRunner.state_changed.connect(_on_runner_state_changed)
	render()


func _exit_tree() -> void:
	for request in [_github_request, _brave_request, _hf_request]:
		if request != null and is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_github_request = null
	_brave_request = null
	_hf_request = null


func render() -> void:
	for child in _body.get_children():
		child.queue_free()
	_category_buttons.clear()
	_search = null
	_results = null
	_runner_code = null
	_runner_output = null
	_run_button = null
	_linux_command_edit = null
	_linux_output = null
	_linux_run_button = null
	_linux_test_button = null
	_build_header()
	_build_search()
	_build_categories()
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 16)
	_body.add_child(_results)
	_render_results()


func _build_header() -> void:
	# The main app bar already identifies the destination as Explore. Keep this
	# page heading task-oriented rather than repeating the navigation title.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 2)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(Ui.lbl("Native tools first. External services open separately.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	




func _build_search() -> void:
	_search = Ui.line("Find a connection")
	_search.custom_minimum_size.y = 54
	_search.text = _search_query
	_search.text_changed.connect(func(value: String):
		_search_query = value
		_render_results())
	_body.add_child(_search)


func _build_categories() -> void:
	# A single filter control avoids a second row of chips on narrow phones.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var label := Ui.lbl("Category", Ui.FS_SMALL, Ui.MUTED, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_category_select = OptionButton.new()
	_category_select.custom_minimum_size = Vector2(210, 46)
	_category_select.focus_mode = Control.FOCUS_ALL
	_category_select.add_theme_font_size_override("font_size", 16)
	_category_select.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Color.WHITE, 12, Ui.BORDER, 1), 13, 7))
	_category_select.add_theme_stylebox_override("hover", Ui.pad(Ui.box(Color("#f6f6f6"), 12, Ui.BORDER, 1), 13, 7))
	_category_select.add_theme_stylebox_override("pressed", Ui.pad(Ui.box(Color("#eeeeee"), 12, Ui.BORDER, 1), 13, 7))
	_category_select.add_theme_color_override("font_color", Ui.TEXT)
	_category_select.add_theme_color_override("font_hover_color", Ui.TEXT)
	_category_select.add_theme_color_override("font_pressed_color", Ui.TEXT)
	for category in CATEGORIES:
		_category_select.add_item(str(category))
	_category_select.select(maxi(0, CATEGORIES.find(_category)))
	_category_select.item_selected.connect(func(index: int):
		_category = str(CATEGORIES[index])
		_render_results())
	row.add_child(_category_select)


func _render_results() -> void:
	if _results == null or not is_instance_valid(_results): return
	for child in _results.get_children(): child.queue_free()
	var query := _search_query.strip_edges().to_lower()
	var terms: Array[String] = []
	for raw_term in query.split(" ", false):
		var term := str(raw_term).strip_edges()
		if term != "": terms.append(term)
	var matches: Array[Dictionary] = []
	for item in INTEGRATIONS:
		if _category != "All" and str(item.category) != _category: continue
		var searchable := (str(item.name) + " " + str(item.description) + " " + str(item.eyebrow) + " " + str(item.category) + " " + str(item.detail)).to_lower()
		var matches_all_terms := true
		for term in terms:
			if not searchable.contains(term):
				matches_all_terms = false
				break
		if matches_all_terms: matches.append(item)

	if matches.is_empty():
		_results.add_child(_empty_results())
	else:
		if _category == "All" and query == "":
			var aoi_tools: Array[Dictionary] = []
			var browser_workspaces: Array[Dictionary] = []
			var native_ids := ["android_productivity", "github", "linux_bridge", "huggingface_image", "huggingface_video", "piston", "wikipedia", "brave_search"]
			for item in matches:
				if str(item.id) in native_ids:
					aoi_tools.append(item)
				else:
					browser_workspaces.append(item)
			_results.add_child(_section_heading("Available in Aoi", "%d" % aoi_tools.size()))
			for item in aoi_tools: _results.add_child(_integration_card(item))
			if not browser_workspaces.is_empty():
				_results.add_child(_section_heading("Opens in another service", "%d" % browser_workspaces.size()))
				if _show_external_services:
					for item in browser_workspaces: _results.add_child(_integration_card(item))
					var collapse := Ui.btn("Show fewer external services", "quiet")
					collapse.name = "CollapseExternalServices"
					collapse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					collapse.pressed.connect(func(): _show_external_services = false; _render_results())
					_results.add_child(collapse)
				else:
					var browse := Ui.btn("Browse %d external services" % browser_workspaces.size(), "ghost")
					browse.name = "BrowseExternalServices"
					browse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					browse.pressed.connect(func(): _show_external_services = true; _render_results())
					_results.add_child(browse)
		else:
			_results.add_child(_section_heading(_category if _category != "All" else "Search results", "%d results" % matches.size()))
			for item in matches: _results.add_child(_integration_card(item))

	# Connection and runner setup live behind the selected row. The directory
	# stays focused on discovery and does not stack independent configuration forms.
	_results.add_child(_privacy_note())

func _section_heading(title: String, meta: String = "") -> Control:
	var row := HBoxContainer.new()
	var label := Ui.lbl(title, Ui.FS + 1, Ui.TEXT, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if meta != "": row.add_child(Ui.lbl(meta, Ui.FS_SMALL - 2, Ui.MUTED))
	return row


static func _wrap_description(value: String, max_chars: int) -> String:
	var lines: Array[String] = []
	var current := ""
	for word in value.split(" ", false):
		if current != "" and current.length() + word.length() + 1 > max_chars:
			lines.append(current)
			current = word
		else:
			current = word if current == "" else current + " " + word
	if current != "": lines.append(current)
	return "\n".join(lines)


func _integration_card(item: Dictionary) -> Control:
	# Directory rows use the same quiet, monochrome visual language as Chat.
	# Services are not separate cards; one continuous list is easier to scan on a phone.
	var integration_id := str(item.get("id", ""))
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = 82
	wrapper.add_child(row)
	var icon := TextureRect.new()
	icon.texture = _explore_icon(str(item.get("icon", "sparkles")))
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Ui.TEXT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	var title := Ui.lbl(str(item.get("name", "Integration")), 19, Ui.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(title)
	var meta := Ui.lbl(_integration_subtitle(item), 13, Ui.MUTED)
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(meta)
	var state: Dictionary = _integration_state(item)
	var state_label := Ui.lbl(str(state.get("label", "Available")), 12, state.get("color", Ui.MUTED), true)
	state_label.clip_text = true
	state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(state_label)
	row.add_child(copy)
	var details := Ui.icon_btn("chevron_right", "quiet", 42)
	details.tooltip_text = "View details and setup"
	details.pressed.connect(func(): _show_integration_details(item))
	row.add_child(details)
	var rule := ColorRect.new()
	rule.color = Ui.BORDER
	rule.custom_minimum_size.y = 1
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(rule)
	return wrapper

func _explore_icon(icon_name: String) -> Texture2D:
	var monochrome_path := "res://assets/icons/monochrome/%s.svg" % icon_name
	if ResourceLoader.exists(monochrome_path):
		return load(monochrome_path) as Texture2D
	return Ui.icon(icon_name)


func _integration_subtitle(item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	var eyebrow := _readable_service_label(str(item.get("eyebrow", "")))
	if eyebrow == "": return category
	return "%s · %s" % [category, eyebrow]


func _readable_service_label(value: String) -> String:
	var acronyms := {
		"ai":"AI", "api":"API", "gpu":"GPU", "pc":"PC", "sdk":"SDK",
		"cli":"CLI", "ci/cd":"CI/CD", "mp4":"MP4", "linux":"Linux",
		"python":"Python", "javascript":"JavaScript", "github":"GitHub",
		"hugging":"Hugging", "face":"Face"
	}
	var words: PackedStringArray = value.to_lower().split(" ", false)
	var readable: Array[String] = []
	for index in range(words.size()):
		var word := str(words[index])
		if acronyms.has(word):
			readable.append(str(acronyms[word]))
		elif word.contains("-"):
			var hyphenated: Array[String] = []
			for segment in word.split("-", false):
				hyphenated.append(str(segment).capitalize())
			readable.append("-".join(hyphenated))
		elif word == "+":
			readable.append(word)
		else:
			readable.append(word.capitalize())
	return " ".join(readable)


func _integration_state(item: Dictionary) -> Dictionary:
	var integration_id := str(item.get("id", ""))
	var connected := false
	var label := "Browser workspace"
	var color := Ui.MUTED
	match integration_id:
		"github":
			var has_token := Store.has_secret("github")
			var account := str(Store.get_integration("github").get("login", "")).strip_edges()
			connected = ToolRunner.is_github_connected()
			label = ("Connected · @" + account) if connected else ("Token saved · verify connection" if has_token else "Public access · no token needed")
			color = Ui.GREEN if connected else (Ui.AMBER if has_token else Ui.MUTED)
		"piston":
			connected = str(Store.get_integration("piston").get("url", "")) != ""
			label = "Server configured" if connected else "Server not configured"
			color = Ui.GREEN if connected else Ui.AMBER
		"linux_bridge":
			var saved_key := Store.has_secret("linux_bridge")
			connected = ToolRunner.is_linux_connected()
			var bridge_cfg := Store.get_integration("linux_bridge")
			var verified_at := int(bridge_cfg.get("last_test_at", 0))
			var verified := bool(bridge_cfg.get("last_test_ok", false)) and verified_at > 0
			var age_seconds := maxi(0, int(Time.get_unix_time_from_system()) - verified_at) if verified else 0
			if connected and verified and age_seconds <= 120:
				if bool(bridge_cfg.get("godot_available", false)):
					label = "Cloud workspace ready" if age_seconds < 60 else "Ready · verified %d min ago" % maxi(1, roundi(age_seconds / 60.0))
					color = Ui.GREEN
				else:
					label = "Connected · Godot setup incomplete"
					color = Ui.AMBER
			elif connected and verified:
				label = "Last verified %s ago · retest" % _format_age(age_seconds)
				color = Ui.AMBER
			elif saved_key and str(bridge_cfg.get("last_test_error", "")) != "":
				label = "Saved · connection needs attention"
				color = Ui.AMBER
			elif saved_key:
				label = "Saved · test connection"
				color = Ui.MUTED
			else:
				label = "Optional · not connected"
				color = Ui.MUTED
		"huggingface_image", "huggingface_video":
			connected = Store.has_secret("huggingface")
			label = "Token connected" if connected else "Inference token needed"
			color = Ui.GREEN if connected else Ui.ACCENT
		"wikipedia":
			label = "Built into Aoi · no key required"
			color = Ui.GREEN
		"android_productivity":
			connected = OS.get_name() == "Android" and Engine.has_singleton("AoiAndroidActions")
			label = "Ready on this Android device" if connected else "Available in the Android app"
			color = Ui.GREEN if connected else Ui.MUTED
		"brave_search":
			connected = Store.has_secret("brave_search")
			label = "Connected · metered web research" if connected else "Optional · live source research"
			color = Ui.GREEN if connected else Ui.AMBER
	return {"label":label, "color":color, "connected":connected}


func _format_age(seconds: int) -> String:
	if seconds < 3600:
		return "%d min" % maxi(1, roundi(seconds / 60.0))
	if seconds < 86400:
		return "%d hr" % maxi(1, roundi(seconds / 3600.0))
	return "%d day" % maxi(1, roundi(seconds / 86400.0))


func _configured_integration_count() -> int:
	var total := 0
	for item in INTEGRATIONS:
		var state: Dictionary = _integration_state(item)
		if bool(state.get("connected", false)) or str(state.get("label", "")).begins_with("Built into Aoi"):
			total += 1
	return total


func _show_integration_details(item: Dictionary) -> void:
	if _detail_sheet != null and is_instance_valid(_detail_sheet):
		_detail_sheet.queue_free()
	var sheet := Sheet.new()
	_detail_sheet = sheet
	var scene := get_tree().current_scene
	if scene == null: scene = get_tree().root
	scene.add_child(sheet)
	sheet.open(str(item.get("name", "Integration")), 0.88)
	sheet.body.add_child(Ui.chip(str(item.get("category", "Tool")), Ui.ACCENT))
	sheet.body.add_child(Ui.lbl(str(item.get("description", "")), Ui.FS_SMALL + 1, Ui.TEXT, false, true))
	var state: Dictionary = _integration_state(item)
	var state_row := HBoxContainer.new()
	state_row.add_child(Ui.chip(str(state.get("label", "Available")), state.get("color", Ui.MUTED)))
	sheet.body.add_child(state_row)
	if str(item.get("detail", "")) != "":
		sheet.body.add_child(Ui.lbl("Access and limitations", Ui.FS_SMALL, Ui.TEXT, true))
		sheet.body.add_child(Ui.lbl(str(item.detail), Ui.FS_SMALL, Ui.MUTED, false, true))
	if str(item.get("id", "")) == "linux_bridge":
		sheet.body.add_child(Ui.lbl("Use a remote Linux machine", Ui.FS_SMALL, Ui.TEXT, true))
		var setup_text := "GitHub Codespaces is the recommended first host. This project includes a cloud environment that installs the matching Godot version, starts the Aoi bridge and forwards one connection port.\n\nCreate a private repository from this Aoi project. Generate a connection key in Aoi, add it to the repository's Settings → Secrets and variables → Codespaces as AOI_BRIDGE_TOKEN, then create or rebuild the Codespace. Open the Ports panel, set port 8765 to Public if GitHub has not done so, and copy its HTTPS URL into Aoi. The public port is protected by the 64-character key.\n\nPersonal GitHub Free accounts include 120 Codespaces core-hours and 15 GB-month storage. This is a usage-capped interactive machine, not an unlimited server. GitHub Actions provides temporary Linux jobs for builds, not a persistent bridge. Oracle Cloud Always Free can host a longer-running Linux VM, but needs separate setup and capacity is not guaranteed."
		sheet.body.add_child(Ui.lbl(setup_text, Ui.FS_SMALL, Ui.MUTED, false, true))
	var integration_id := str(item.get("id", ""))
	if integration_id == "brave_search":
		sheet.body.add_child(Ui.lbl("Connect evidence-based research", Ui.FS_SMALL, Ui.TEXT, true))
		sheet.body.add_child(Ui.lbl("Aoi will use this only during substantial project research. It retrieves extracted text and source URLs, then stores source IDs in the project's research record so the plan can cite evidence.", Ui.FS_SMALL, Ui.MUTED, false, true))
		sheet.body.add_child(Ui.lbl("Usage and billing", Ui.FS_SMALL, Ui.TEXT, true))
		sheet.body.add_child(Ui.lbl("Brave currently lists Search / LLM Context at $5 per 1,000 requests with $5 in monthly credits. A payment card is required to activate the API plan; credits and prices are controlled by Brave and can change. Aoi does not make background queries outside a project research phase.", Ui.FS_SMALL - 1, Ui.MUTED, false, true))
		var dashboard := Ui.btn("Open Brave API dashboard", "ghost", "external_link")
		dashboard.pressed.connect(func(): OS.shell_open("https://api-dashboard.search.brave.com/"))
		sheet.body.add_child(dashboard)
		var token_input := Ui.line("Paste Brave Search API key", true)
		sheet.body.add_child(token_input)
		var feedback := Ui.lbl("The key is stored in Aoi's encrypted local credential store and sent only to Brave when a research query runs.", Ui.FS_SMALL - 1, Ui.MUTED, false, true)
		feedback.name = "BraveResearchConnectionStatus"
		sheet.body.add_child(feedback)
		var verify := Ui.btn("Verify and connect", "primary", "check")
		verify.pressed.connect(func():
			var candidate := token_input.text.strip_edges()
			if candidate.length() < 12:
				feedback.text = "Paste the API key from your Brave dashboard first."
				return
			verify.disabled = true
			verify.text = "Verifying…"
			feedback.text = "Checking the key with a small test query…"
			_verify_brave_search(candidate, feedback, verify)
		)
		sheet.body.add_child(verify)
		if Store.has_secret("brave_search"):
			var disconnect := Ui.btn("Disconnect Brave Search", "danger", "x")
			disconnect.pressed.connect(func():
				Store.remove_secret("brave_search")
				sheet.close()
				render()
				toast.emit("Brave Search disconnected. Existing research records remain saved.")
			)
			sheet.body.add_child(disconnect)
		sheet.closed.connect(func(): if _detail_sheet == sheet: _detail_sheet = null)
		return
	var permission_note := "Opens an external service. Aoi does not receive account access or credentials when you open this link."
	match integration_id:
		"android_productivity":
			toast.emit("Ask Aoi in chat to set an alarm or add a calendar event. You confirm each item in Android Clock or Calendar.")
		"github":
			permission_note = "Public repository search and reads can work without a token. For private repositories, use a fine-grained personal access token (PAT) limited to selected repositories with Metadata = Read-only and Contents = Read-only. Add Contents = Read and write only when you need remote file edits; add Issues or Pull requests permissions only for those specific actions. Avoid Administration, Actions and unrelated permissions. GitHub-side changes remain approval-gated."
		"huggingface_image", "huggingface_video":
			permission_note = "Requires an Inference Providers token with the relevant inference permission. Generation uses provider credits or billing; check the selected model's availability and rate limits."
		"piston":
			permission_note = "Code runs on the Piston server you configure, not in an isolated on-device sandbox. Connect only a server you own or are authorized to use."
		"linux_bridge":
			permission_note = "The cloud bridge uses HTTPS port forwarding and a 64-character shared key. File operations stay inside its configured workspace; shell commands still run with the remote Codespaces user's permissions and are not an OS sandbox. Keep the repository private and never commit the key."
	if integration_id in ["github", "huggingface_image", "huggingface_video", "piston", "linux_bridge"]:
		sheet.body.add_child(Ui.lbl("Permissions and safety", Ui.FS_SMALL, Ui.TEXT, true))
		sheet.body.add_child(Ui.lbl(permission_note, Ui.FS_SMALL, Ui.MUTED, false, true))
	if integration_id == "linux_bridge" and Store.has_secret("linux_bridge"):
		var test := Ui.btn("Test connection", "ghost", "check_circle")
		test.name = "LinuxBridgeTestButton"
		_linux_test_button = test
		test.disabled = ToolRunner.busy
		test.pressed.connect(func():
			_manual_target = "linux_test"
			test.disabled = true
			test.text = "Checking…"
			if _linux_output != null and is_instance_valid(_linux_output): _linux_output.text = "Contacting the saved Linux bridge…"
			ToolRunner.test_linux_bridge())
		sheet.body.add_child(test)
		_linux_output = Ui.lbl("A connection test checks the saved URL and token against the bridge's /health endpoint.", Ui.FS_SMALL - 1, Ui.MUTED, false, true)
		_linux_output.name = "LinuxBridgeTestOutput"
		sheet.body.add_child(_linux_output)

	var action_text := str(item.get("action", "Open"))
	if integration_id == "github": action_text = "Manage GitHub connection" if Store.has_secret("github") else "Connect GitHub"
	elif integration_id in ["huggingface_image", "huggingface_video"]: action_text = "Manage AI media connection" if Store.has_secret("huggingface") else "Connect AI media"
	elif integration_id == "piston": action_text = "Manage code runner" if str(Store.get_integration("piston").get("url", "")) != "" else "Configure code runner"
	elif integration_id == "linux_bridge": action_text = "Connect cloud workspace"
	var action := Ui.btn(action_text, "primary", "forward")
	action.pressed.connect(func():
		sheet.close()
		_activate(integration_id, str(item.get("url", "")))
	)
	sheet.body.add_child(action)
	sheet.closed.connect(func(): if _detail_sheet == sheet: _detail_sheet = null)

func _verify_brave_search(token: String, feedback: Label, button: Button) -> void:
	if _brave_request != null and is_instance_valid(_brave_request):
		_brave_request.cancel_request()
		_brave_request.queue_free()
	_brave_request = null
	var request := HTTPRequest.new()
	request.timeout = 20.0
	request.accept_gzip = true
	_brave_request = request
	add_child(request)
	var url := "https://api.search.brave.com/res/v1/llm/context?q=Godot%20Engine%20official%20documentation&count=3&maximum_number_of_urls=3&maximum_number_of_tokens=1024&context_threshold_mode=strict"
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		var is_current := _brave_request == request
		if is_current:
			_brave_request = null
		if is_instance_valid(request):
			request.queue_free()
		if not is_current or not is_inside_tree():
			return
		if not is_instance_valid(feedback) or not is_instance_valid(button):
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		var grounding: Variant = payload.get("grounding", {}) if payload is Dictionary else {}
		var sources: Variant = grounding.get("generic", []) if grounding is Dictionary else []
		var valid: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200 and sources is Array and not (sources as Array).is_empty()
		button.disabled = false
		button.text = "Verify and connect"
		if valid:
			Store.set_secret("brave_search", token)
			feedback.text = "Connected. Aoi can now collect current web sources for project research."
			toast.emit("Brave Search connected. Research remains project-scoped and usage is metered.")
			render()
		else:
			var detail := ""
			if payload is Dictionary:
				var error_value: Variant = payload.get("error", {})
				if error_value is Dictionary: detail = str(error_value.get("detail", error_value.get("code", "")))
			var reason := "Could not reach Brave Search. Check the phone's internet connection." if result != HTTPRequest.RESULT_SUCCESS else "Brave Search did not return usable source results."
			feedback.text = "%s (HTTP %d). %s Check the key and API plan." % [reason, code, detail.left(220)]
	)
	var request_error := request.request(url, PackedStringArray(["Accept: application/json", "X-Subscription-Token: " + token]), HTTPClient.METHOD_GET)
	if request_error != OK:
		if _brave_request == request:
			_brave_request = null
		request.queue_free()
		if is_instance_valid(feedback): feedback.text = "Aoi could not start the connection check (error %d)." % request_error
		if is_instance_valid(button):
			button.disabled = false
			button.text = "Verify and connect"


func _activate(integration_id: String, url: String) -> void:
	match integration_id:
		"github":
			# The connection sheet also serves as the credential manager when connected.
			request_github_connect.emit()
		"huggingface_image", "huggingface_video":
			request_huggingface_connect.emit()
		"piston": request_piston_config.emit()
		"linux_bridge": request_linux_config.emit()
		_:
			if url.strip_edges() != "": OS.shell_open(url)
			else: toast.emit("This service does not have an active connection flow yet.")


func _disconnect_github() -> void:
	if _github_request != null and is_instance_valid(_github_request):
		_github_request.cancel_request()
		_github_request.queue_free()
		_github_request = null
	Store.remove_secret("github")
	Store.integrations.erase("github")
	Store.save_settings()
	toast.emit("GitHub disconnected")
	render()


func connect_github(raw_token: String) -> void:
	var clean := raw_token.strip_edges()
	if clean == "" or clean.contains(" ") or clean.contains("\n") or clean.contains("\r"):
		github_connection_finished.emit(false, "", "Paste a valid GitHub personal access token. Your current connection has not been changed.")
		return
	if _github_request != null and is_instance_valid(_github_request):
		_github_request.cancel_request()
		_github_request.queue_free()
		_github_request = null
	var request := HTTPRequest.new()
	request.timeout = 22.0
	request.accept_gzip = true
	_github_request = request
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _response_headers: PackedStringArray, body: PackedByteArray) -> void:
		var is_current := _github_request == request
		if is_current:
			_github_request = null
		if is_instance_valid(request):
			request.queue_free()
		if not is_current or not is_inside_tree():
			return
		var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS:
			github_connection_finished.emit(false, "", "GitHub could not be reached. Check internet access, device date/time and try again. Your saved token was not changed.")
			return
		if code != 200 or not payload is Dictionary:
			var detail := str(payload.get("message", "")) if payload is Dictionary else ""
			var message := "GitHub rejected this token (HTTP %d)." % code
			if code == 401:
				message = "GitHub rejected this token (401). Check that it was copied completely and has not expired."
			elif code == 403:
				message = "GitHub denied this token (403). Check organisation approval, token restrictions and rate limits."
			elif code == 404:
				message = "GitHub's account verification endpoint was not found (404). Check network filtering or proxy settings."
			if detail != "": message += " " + detail.left(180)
			github_connection_finished.emit(false, "", message + " Your saved token was not changed.")
			return
		var login := str(payload.get("login", "")).strip_edges()
		if login == "":
			github_connection_finished.emit(false, "", "GitHub returned an account response without a username. The token was not saved.")
			return
		Store.set_secret("github", clean)
		Store.set_integration("github", {
			"login": login,
			"avatar_url": str(payload.get("avatar_url", "")),
			"connected_at": Time.get_unix_time_from_system(),
			"token_sha256": ToolRunner._github_token_fingerprint(clean)
		})
		github_connection_finished.emit(true, login, "Connected to GitHub as @%s. Aoi verified the token with GitHub before saving it." % login)
		toast.emit("GitHub connected as @" + login)
		render()
	)
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"Authorization: Bearer " + clean,
		"X-GitHub-Api-Version: 2026-03-10",
		"User-Agent: AoiMobile/3.2.14"
	])
	var request_error := request.request("https://api.github.com/user", headers, HTTPClient.METHOD_GET)
	if request_error != OK:
		if _github_request == request:
			_github_request = null
		request.queue_free()
		github_connection_finished.emit(false, "", "Aoi could not start the GitHub connection check (request error %d). Check the phone's network connection and retry." % request_error)
		return


func connect_huggingface(token: String) -> void:
	var clean := token.strip_edges()
	if clean == "":
		toast.emit("Paste your Hugging Face token first.")
		return
	if _hf_request != null and is_instance_valid(_hf_request):
		_hf_request.cancel_request()
		_hf_request.queue_free()
		_hf_request = null
	var request := HTTPRequest.new()
	request.timeout = 25.0
	_hf_request = request
	add_child(request)
	toast.emit("Checking Hugging Face token…")
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		var is_current := _hf_request == request
		if is_current:
			_hf_request = null
		if is_instance_valid(request):
			request.queue_free()
		if not is_current or not is_inside_tree():
			return
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
			var username := str(payload.get("name", payload.get("fullname", "Hugging Face user"))) if payload is Dictionary else "Hugging Face user"
			Store.set_secret("huggingface", clean)
			Store.set_integration("huggingface", {"username": username, "model": "stabilityai/stable-diffusion-3-medium-diffusers"})
			toast.emit("Hugging Face connected as " + username + " · image and video tools enabled")
			render()
		else:
			var message := ""
			var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
			if payload is Dictionary: message = str(payload.get("error", payload.get("message", "")))
			toast.emit("Hugging Face could not verify this token (HTTP %d). %s" % [code, message.left(140)])
	)
	var error := request.request("https://huggingface.co/api/whoami-v2", PackedStringArray([
		"Accept: application/json",
		"User-Agent: AoiMobile/3.2.14",
		"Authorization: Bearer " + clean
	]), HTTPClient.METHOD_GET)
	if error != OK:
		if _hf_request == request:
			_hf_request = null
		request.queue_free()
		toast.emit("Could not start the Hugging Face request (error %d)." % error)


func _disconnect_huggingface() -> void:
	Store.remove_secret("huggingface")
	Store.integrations.erase("huggingface")
	Store.save_settings()
	toast.emit("Hugging Face image and video tools disconnected")
	render()


func _on_runner_state_changed(state: String, detail: String) -> void:
	if _manual_target == "linux" and _linux_run_button != null and is_instance_valid(_linux_run_button):
		match state:
			"running", "retrying": _linux_run_button.text = "Stop command"
			"cancelling": _linux_run_button.text = "Stopping…"; _linux_run_button.disabled = true
			"success", "error", "cancelled": _linux_run_button.text = "Run command"; _linux_run_button.disabled = false
	if _manual_target == "linux_test" and _linux_test_button != null and is_instance_valid(_linux_test_button):
		match state:
			"running", "retrying": _linux_test_button.text = "Checking…"
			"cancelling": _linux_test_button.text = "Stopping…"; _linux_test_button.disabled = true
			"success", "error", "cancelled": _linux_test_button.text = "Test connection"; _linux_test_button.disabled = false
	if _manual_target in ["linux", "linux_test"] and _linux_output != null and is_instance_valid(_linux_output) and state in ["running", "retrying", "cancelling"]:
		_linux_output.text = detail if state != "running" else "Waiting for the cloud workspace…"
	if _run_button != null and is_instance_valid(_run_button):
		match state:
			"running":
				_run_button.text = "Stop current run"
				_run_button.icon = Ui.icon("stop")
				_run_button.disabled = false
			"retrying":
				_run_button.text = "Stop retry"
				_run_button.icon = Ui.icon("stop")
				_run_button.disabled = false
			"cancelling":
				_run_button.text = "Stopping…"
				_run_button.disabled = true
			"success", "error", "cancelled":
				_run_button.text = "Run test"
				_run_button.icon = Ui.icon("play")
				_run_button.disabled = false
	if _runner_output != null and is_instance_valid(_runner_output):
		if state in ["running", "retrying", "cancelling"]:
			_runner_output.text = detail if state != "running" else "Running on the configured server…"
			_runner_output.add_theme_color_override("font_color", Ui.AMBER if state == "retrying" else Ui.MUTED)


func _runner_card() -> Control:
	var card := Ui.card(22)
	var content := Ui.card_body(card)
	content.add_theme_constant_override("separation", 14)
	var title_row := HBoxContainer.new()
	var heading := Ui.lbl("Aoi code runner", Ui.FS + 1, Ui.TEXT, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)
	title_row.add_child(Ui.chip("AI-CALLABLE", Ui.ACCENT))
	content.add_child(title_row)
	var endpoint := str(Store.get_integration("piston").get("url", "")).strip_edges()
	if endpoint == "":
		content.add_child(Ui.lbl("Connect a Piston API server you control. Once configured, Aoi can execute short Python, JavaScript and Bash snippets when you explicitly request a test or run.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
		var configure := Ui.btn("Connect a code runner", "primary", "terminal")
		configure.pressed.connect(func(): request_piston_config.emit())
		content.add_child(configure)
		return card
	content.add_child(Ui.chip("Connected · " + endpoint, Ui.GREEN))
	content.add_child(Ui.lbl("Try a small snippet before enabling AI-assisted execution. Code runs on the remote server you configured, not on this phone.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	var language_row := HBoxContainer.new()
	language_row.add_child(Ui.lbl("Language", Ui.FS_SMALL, Ui.MUTED))
	var select := OptionButton.new()
	select.add_item("Python", 0)
	select.add_item("JavaScript", 1)
	select.add_item("Bash", 2)
	select.custom_minimum_size = Vector2(0, 62)
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.add_theme_font_size_override("font_size", Ui.FS_SMALL)
	select.item_selected.connect(func(index: int): _runner_language = ["python", "javascript", "bash"][index])
	language_row.add_child(select)
	content.add_child(language_row)
	_runner_code = TextEdit.new()
	_runner_code.custom_minimum_size = Vector2(0, 205)
	_runner_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_runner_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_runner_code.add_theme_font_size_override("font_size", 20)
	_runner_code.add_theme_color_override("font_color", Ui.TEXT)
	_runner_code.add_theme_stylebox_override("normal", Ui.pad(Ui.box(Ui.CARD_HI, 18, Ui.BORDER, 1), 18, 12))
	_runner_code.add_theme_stylebox_override("focus", Ui.pad(Ui.box(Ui.CARD, 18, Ui.ACCENT, 2), 18, 12))
	_runner_code.text = "print('Hello from Aoi')"
	content.add_child(_runner_code)
	var run_row := HBoxContainer.new()
	_run_button = Ui.btn("Stop current tool" if ToolRunner.busy else "Run test", "primary", "stop" if ToolRunner.busy else "play")
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(_run_manual_code)
	run_row.add_child(_run_button)
	var edit := Ui.icon_btn("settings", "quiet", Ui.BTN_H)
	edit.tooltip_text = "Edit runner connection"
	edit.pressed.connect(func(): request_piston_config.emit())
	run_row.add_child(edit)
	content.add_child(run_row)
	_runner_output = Ui.lbl("Output will appear here.", Ui.FS_SMALL, Ui.MUTED, false, true)
	_runner_output.custom_minimum_size.y = 50
	content.add_child(_runner_output)
	return card


func _run_manual_code() -> void:
	_manual_target = "piston"
	if ToolRunner.busy:
		ToolRunner.cancel()
		if _runner_output != null: _runner_output.text = "Stopping the active tool request…"
		if _run_button != null: _run_button.disabled = true
		return
	if _runner_code == null or not is_instance_valid(_runner_code): return
	if _runner_output != null: _runner_output.text = "Running in your configured sandbox…"
	ToolRunner.run_manual(_runner_language, _runner_code.text)


func _on_manual_completed(result: Dictionary) -> void:
	if _manual_target in ["linux", "linux_test"]:
		if _manual_target == "linux" and _linux_run_button != null and is_instance_valid(_linux_run_button):
			_linux_run_button.disabled = false
			_linux_run_button.text = "Run command"
		if _manual_target == "linux_test" and _linux_test_button != null and is_instance_valid(_linux_test_button):
			_linux_test_button.disabled = false
			_linux_test_button.text = "Test connection"
		if _linux_output != null and is_instance_valid(_linux_output):
			var linux_text := str(result.get("output", ""))
			var linux_error := str(result.get("error", ""))
			_linux_output.text = (linux_text if linux_text != "" else (linux_error if linux_error != "" else "No output"))
			_linux_output.add_theme_color_override("font_color", Ui.GREEN if bool(result.get("ok", false)) else Ui.RED)
		if _manual_target == "linux_test":
			_render_results()
		return
	if _run_button != null and is_instance_valid(_run_button):
		_run_button.disabled = false
		_run_button.text = "Run test"
		_run_button.icon = Ui.icon("play")
	if _runner_output != null and is_instance_valid(_runner_output):
		var output := str(result.get("output", ""))
		var error_text := str(result.get("error", ""))
		_runner_output.text = (output if output != "" else "No output") + ("\n" + error_text if error_text != "" else "")
		_runner_output.add_theme_color_override("font_color", Ui.RED if not bool(result.get("ok", false)) else Ui.GREEN)
	else:
		toast.emit(str(result.get("error", "Code run finished.")))
	if bool(result.get("ok", false)): toast.emit("Code execution finished")


func _empty_results() -> Control:
	var card := Ui.card(26)
	var content := Ui.card_body(card)
	content.add_child(Ui.lbl("No matching tools", Ui.FS + 2, Ui.TEXT, true))
	content.add_child(Ui.lbl("Try another keyword or choose a different category.", Ui.FS_SMALL + 1, Ui.MUTED, false, true))
	return card


func _privacy_note() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Color("#f7f7f7"), 8), 22, 18))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.add_child(Ui.lbl("Know what is connected", Ui.FS_SMALL + 1, Ui.TEXT, true))
	content.add_child(Ui.lbl("GitHub reads are immediate; branch, file, issue and pull-request changes require individual approval. Piston executes code on the remote server you configure. Hugging Face Inference can generate images directly and saves the result locally, but provider credits or billing may apply. Browser cards only open external services; they do not silently grant Aoi access to those services. Review provider terms, quotas and costs before use.", 17, Ui.MUTED, false, true))
	card.add_child(content)
	return card

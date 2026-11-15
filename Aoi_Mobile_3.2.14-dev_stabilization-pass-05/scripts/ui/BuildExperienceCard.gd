extends PanelContainer
## A single, conversation-native creation card. The card is intentionally quiet:
## one headline, one live signal field, one human-readable status and real progress.

const Ui = preload("res://scripts/ui/Ui.gd")
const AoiPresence = preload("res://scripts/ui/AoiPresence.gd")
const AoiProgressRail = preload("res://scripts/ui/AoiProgressRail.gd")
const AoiSignalField = preload("res://scripts/ui/AoiSignalField.gd")
const STALE_AFTER_SECONDS := 100.0

signal open_project_requested(project_id: String)
signal continue_work_requested(project_id: String)
signal resume_job_requested(job_id: String)

var _project: Dictionary = {}
var _kind_label := "project"
var _stage := "planning"
var _detail := ""
var _presence: Control
var _eyebrow: Label
var _headline: Label
var _status_label: Label
var _progress_rail: Control
var _progress_pill: PanelContainer
var _progress_label: Label
var _signal_field: Control
var _preview_frame: PanelContainer
var _preview_texture: TextureRect
var _preview_path := ""
var _open_button: Button
var _continue_button: Button
var _progress_ratio := -1.0
var _completed_steps := 0
var _total_steps := 0
var _latest_job: Dictionary = {}
var _last_activity_at := 0.0
var _stalled := false
var _clock := 0.0
var _headline_tween: Tween
var _status_tween: Tween
var _has_connected_job_signal := false

func configure(project_data: Dictionary, stage: String = "planning", detail: String = "") -> void:
	_project = project_data.duplicate(true)
	_kind_label = _kind_name(str(_project.get("project_kind", _project.get("kind", "project"))))
	_stage = stage
	_detail = detail
	_progress_ratio = float(_project.get("aoi_work_progress", -1.0))
	_completed_steps = int(_project.get("aoi_work_completed_steps", 0))
	_total_steps = int(_project.get("aoi_work_total_steps", 0))
	_last_activity_at = _resolve_last_activity(_project)
	_enforce_truthful_ready_state()
	_build()
	_sync_job_state()
	_refresh_visual_state()
	_refresh_preview()
	if not JobRunner.jobs_changed.is_connected(_on_jobs_changed):
		JobRunner.jobs_changed.connect(_on_jobs_changed)
		_has_connected_job_signal = true
	var reduce_motion := Ui.reduced_motion_enabled()
	_presence.call("set_reduced_motion", reduce_motion)
	_signal_field.call("set_reduced_motion", reduce_motion)
	_progress_rail.call("set_reduced_motion", reduce_motion)
	set_process(true)


func _resolve_last_activity(project_data: Dictionary) -> float:
	var explicit_time := float(project_data.get("aoi_work_updated_at", 0.0))
	if explicit_time > 0.0:
		return explicit_time
	var events: Variant = project_data.get("aoi_work_events", [])
	if events is Array and not events.is_empty() and events.back() is Dictionary:
		var event_time := float(events.back().get("at", 0.0))
		if event_time > 0.0:
			return event_time
	return float(project_data.get("updated_at", project_data.get("updated", project_data.get("created_at", 0.0))))

func touch_activity(timestamp: float = -1.0) -> void:
	_last_activity_at = timestamp if timestamp > 0.0 else Time.get_unix_time_from_system()
	_stalled = false

func set_work_state(stage: String, detail: String = "", progress: float = -1.0, completed_steps: int = 0, total_steps: int = 0, project_data: Dictionary = {}) -> void:
	_stage = stage
	_detail = detail
	_progress_ratio = progress
	_completed_steps = completed_steps
	_total_steps = total_steps
	if not project_data.is_empty():
		_project = project_data.duplicate(true)
	_last_activity_at = _resolve_last_activity(_project)
	_stalled = false
	_enforce_truthful_ready_state()
	_sync_job_state()
	_refresh_visual_state()
	_refresh_preview()
	_animate_presence()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 2.0:
		return
	_clock = 0.0
	_evaluate_freshness(Time.get_unix_time_from_system())

func _exit_tree() -> void:
	if _has_connected_job_signal and JobRunner.jobs_changed.is_connected(_on_jobs_changed):
		JobRunner.jobs_changed.disconnect(_on_jobs_changed)

func _evaluate_freshness(now: float) -> void:
	if _stage not in ["planning", "building", "reviewing"]:
		return
	# Global busy flags belong to the whole app, not this project. Only this
	# project's saved request/tool ownership may suppress its stale-state timer.
	# LLM and ToolRunner are application-wide singletons. Their busy flags may
	# belong to a different chat or Studio action, so they cannot keep this
	# project's card alive. Active work refreshes the project heartbeat; the
	# freshness timeout handles a genuinely silent/stuck operation.
	_sync_job_state()
	var latest_state := str(_latest_job.get("state", ""))
	if latest_state in ["running", "queued"]:
		var job_heartbeat := float(_latest_job.get("heartbeat_at", _latest_job.get("updated_at", 0.0)))
		if job_heartbeat > 0.0:
			_last_activity_at = job_heartbeat
		if job_heartbeat > 0.0 and now - job_heartbeat < STALE_AFTER_SECONDS:
			return
		# A process that stopped sending heartbeats must not keep the card looking
		# active forever. Stop the stale runner, preserve its checkpoint, and let
		# the existing Resume action continue from that saved state.
		var stale_result := JobRunner.interrupt_stale_job(str(_latest_job.get("id", "")), STALE_AFTER_SECONDS)
		if bool(stale_result.get("ok", false)):
			_sync_job_state()
			_refresh_visual_state()
			return
	if _last_activity_at > 0.0 and now - _last_activity_at < STALE_AFTER_SECONDS:
		return
	if _stalled:
		return
	_stalled = true
	_stage = "stalled"
	_detail = "No recent progress has arrived. Your saved work and latest checkpoint are still here."
	_refresh_visual_state()

func _on_jobs_changed() -> void:
	_sync_job_state()
	_refresh_visual_state()

func _sync_job_state() -> void:
	_latest_job = {}
	var project_id := str(_project.get("id", ""))
	if project_id == "":
		return
	var jobs: Array = JobRunner.list_jobs(project_id)
	if jobs.is_empty() or not jobs[0] is Dictionary:
		return
	# Only the newest run owns this card. An older failed run must never
	# override the state of a newer completed run.
	var job: Dictionary = jobs[0].duplicate(true)
	_latest_job = job
	match str(job.get("state", "")):
		"running", "queued":
			if _stage != "building":
				_stage = "building"
				_detail = str(job.get("last_detail", "Aoi is continuing the saved work."))
				_stalled = false
			_last_activity_at = float(job.get("heartbeat_at", job.get("updated_at", Time.get_unix_time_from_system())))
		"paused":
			if bool(job.get("resumable", true)):
				_stage = "waiting"
				_detail = "Your work is paused at a saved step."
				_stalled = false
		"interrupted", "failed":
			var reason := str(job.get("error", "")).strip_edges()
			if bool(job.get("resumable", false)):
				_stage = "stalled"
				_detail = reason if reason != "" else "Aoi stopped before finishing. Your last checkpoint is saved."
				_stalled = true
			else:
				# A terminal failure must never leave the card looking like it is
				# still building. Preserve the project's saved files and say clearly
				# whether there is a recoverable checkpoint.
				_stage = "error"
				_detail = reason if reason != "" else "Aoi couldn't finish this run. Your saved project files are still here."
				_stalled = false
		"cancelled":
			_stage = "stalled"
			_detail = "Work was stopped. Your saved files and last checkpoint are still here."
			_stalled = true
		"completed":
			if _stage in ["planning", "building", "stalled", "waiting", "error"]:
				_stage = "reviewing"
				_detail = str(job.get("summary", "The saved result is ready for review."))
				_stalled = false
			_last_activity_at = float(job.get("finished_at", job.get("updated_at", Time.get_unix_time_from_system())))
		_:
			_latest_job = {}

func _enforce_truthful_ready_state() -> void:
	if _stage != "ready":
		return
	var plan_complete := _total_steps > 0 and _completed_steps >= _total_steps
	var project_kind := str(_project.get("project_kind", _project.get("kind", "general"))).to_lower()
	if project_kind == "game":
		var has_preview := _has_real_preview()
		# A live process is required when the capture is taken, not forever.
		# Stopping the game after a successful capture must not regress a finished card.
		var runtime_verified_at := float(_project.get("runtime_verified_at", 0.0))
		var preview_updated_at := float(_project.get("preview_updated_at", 0.0))
		var runtime_verified := runtime_verified_at > 0.0 and runtime_verified_at >= preview_updated_at
		if plan_complete and has_preview and runtime_verified:
			return
		_stage = "reviewing" if has_preview else "building"
		_detail = "The latest game capture is saved. Aoi is checking the live game and the remaining plan." if has_preview else "The project is still being built. A workspace or launch attempt is not a finished game."
		return
	# Non-game work also needs a completed run and a real result/report artifact.
	# A folder, preview image, or successful tool call alone is not a deliverable.
	var jobs: Array = JobRunner.list_jobs(str(_project.get("id", "")))
	if not jobs.is_empty() and jobs[0] is Dictionary:
		var latest: Dictionary = jobs[0]
		var job_id := str(latest.get("id", ""))
		var has_report := job_id != "" and (JobRunner.has_artifact(job_id, "report.md") or JobRunner.has_artifact(job_id, "result.json"))
		var has_plan := _total_steps > 0
		if str(latest.get("state", "")) == "completed" and has_report and (not has_plan or plan_complete):
			return
	_stage = "reviewing"
	_detail = "The work is saved. Aoi is checking the actual result before marking it ready."

func _build() -> void:
	name = "AoiCreationExperience"
	custom_minimum_size.y = 0
	var panel := Ui.box(Color(0, 0, 0, 0), 0)
	add_theme_stylebox_override("panel", panel)

	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 18)
	inset.add_theme_constant_override("margin_right", 18)
	inset.add_theme_constant_override("margin_top", 16)
	inset.add_theme_constant_override("margin_bottom", 16)
	add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	_presence = AoiPresence.new()
	_presence.name = "AoiCreationMark"
	_presence.custom_minimum_size = Vector2(42, 42)
	_presence.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_presence)
	var header_copy := VBoxContainer.new()
	header_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_copy.add_theme_constant_override("separation", 2)
	header.add_child(header_copy)
	_eyebrow = Ui.lbl("WORKING", 11, Ui.MUTED, true)
	_eyebrow.name = "CreationEyebrow"
	header_copy.add_child(_eyebrow)
	_headline = Ui.lbl("Working on your project", 24, Ui.TEXT, true, true)
	_headline.add_theme_font_override("font", Ui.display_font())
	_headline.name = "CreationHeadline"
	header_copy.add_child(_headline)

	_signal_field = AoiSignalField.new()
	_signal_field.name = "CreationSignalField"
	_signal_field.custom_minimum_size = Vector2(0, 216)
	_signal_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_signal_field)

	_status_label = Ui.lbl("Preparing the next step", 14, Ui.MUTED, true, true)
	_status_label.name = "CreationStatus"
	column.add_child(_status_label)

	var progress_row := HBoxContainer.new()
	progress_row.name = "CreationProgressRow"
	progress_row.add_theme_constant_override("separation", 10)
	progress_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(progress_row)
	_progress_rail = AoiProgressRail.new()
	_progress_rail.name = "CreationProgressRail"
	_progress_rail.custom_minimum_size = Vector2(0, 8)
	_progress_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.add_child(_progress_rail)
	_progress_pill = PanelContainer.new()
	_progress_pill.name = "CreationProgressPill"
	_progress_pill.add_theme_stylebox_override("panel", Ui.pad(Ui.box(Color("#f2f2f2"), 8), 13, 5))
	_progress_label = Ui.lbl("", 15, Ui.TEXT, true)
	_progress_label.name = "CreationProgressValue"
	_progress_pill.custom_minimum_size = Vector2(62, 34)
	_progress_pill.add_child(_progress_label)
	progress_row.add_child(_progress_pill)

	_preview_frame = PanelContainer.new()
	_preview_frame.name = "CreationPreviewFrame"
	_preview_frame.add_theme_stylebox_override("panel", Ui.box(Color("#f5f5f5"), 8))
	_preview_frame.clip_contents = true
	_preview_frame.custom_minimum_size = Vector2(0, 150)
	var preview_aspect := AspectRatioContainer.new()
	preview_aspect.ratio = 16.0 / 9.0
	preview_aspect.custom_minimum_size = Vector2(0, 150)
	preview_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_frame.add_child(preview_aspect)
	_preview_texture = TextureRect.new()
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_aspect.add_child(_preview_texture)
	_preview_frame.visible = false
	column.add_child(_preview_frame)

	var action_row := HBoxContainer.new()
	action_row.name = "CreationActionRow"
	column.add_child(action_row)
	_continue_button = Ui.btn("Continue work", "ghost", "regenerate")
	_continue_button.name = "ContinueProjectWork"
	_continue_button.custom_minimum_size.y = 48
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	action_row.add_child(_continue_button)
	_open_button = Ui.btn("Open project", "primary", "forward")
	_open_button.name = "OpenCreatedProject"
	_open_button.custom_minimum_size.y = 48
	_open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_button.visible = false
	_open_button.pressed.connect(func(): open_project_requested.emit(str(_project.get("id", ""))))
	action_row.add_child(_open_button)

	modulate.a = 0.0
	scale = Vector2(0.99, 0.99)
	var intro := create_tween()
	intro.set_parallel(true)
	intro.tween_property(self, "modulate:a", 1.0, 0.26)
	intro.tween_property(self, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _refresh_visual_state() -> void:
	if _headline == null or not is_instance_valid(_headline):
		return
	var eyebrow := "AOI  /  CREATING"
	var title := "Building your %s" % _kind_label
	var status := "Laying out the first world"
	var show_field := true
	match _stage:
		"planning":
			eyebrow = "AOI  /  IMAGINING"
			title = "Imagining your %s" % _kind_label
			status = "Shaping the first plan"
		"building", "running", "downloading":
			eyebrow = "AOI  /  CRAFTING"
			title = "Building your %s" % _kind_label
			status = _status_copy(_detail)
		"reviewing":
			eyebrow = "AOI  /  REFINING"
			title = "Polishing the details"
			status = "Checking the experience before sharing it"
		"waiting", "approval":
			eyebrow = "AOI  /  PAUSED"
			title = "One detail needs you"
			status = _detail if not _detail.strip_edges().is_empty() else "The rest of the work is safely paused"
		"retrying":
			eyebrow = "AOI  /  RECOVERING"
			title = "Picking up where we left off"
			status = "Recovering the last saved step"
		"error":
			eyebrow = "AOI  /  NEEDS ATTENTION"
			title = "Aoi hit a snag"
			status = _detail if not _detail.strip_edges().is_empty() else "Your latest work is still saved. Review the connection and try again."
		"stalled":
			eyebrow = "AOI  /  NEEDS ATTENTION"
			title = "Work may have paused"
			status = _detail if not _detail.strip_edges().is_empty() else "No recent progress has arrived. Your saved work is still here."
		"ready":
			eyebrow = "AOI  /  READY"
			title = "Your %s is ready" % _kind_label
			status = "Your result is ready to explore"
			show_field = false

	_eyebrow.text = eyebrow
	if _presence != null and is_instance_valid(_presence) and _presence.has_method("set_state"):
		_presence.call("set_state", _stage, _detail)
	if _headline.text != title:
		_headline.text = title
		if is_inside_tree():
			if _headline_tween and _headline_tween.is_valid(): _headline_tween.kill()
			_headline.modulate.a = 0.0
			_headline.scale = Vector2(0.985, 0.985)
			_headline.pivot_offset = Vector2(0.0, 12.0)
			_headline_tween = create_tween().set_parallel(true)
			_headline_tween.tween_property(_headline, "modulate:a", 1.0, 0.24)
			_headline_tween.tween_property(_headline, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _status_label.text != status:
		_status_label.text = status
		if is_inside_tree():
			if _status_tween and _status_tween.is_valid(): _status_tween.kill()
			_status_label.modulate.a = 0.0
			_status_label.scale = Vector2(0.99, 0.99)
			_status_label.pivot_offset = Vector2(0.0, 7.0)
			_status_tween = create_tween().set_parallel(true)
			_status_tween.tween_property(_status_label, "modulate:a", 1.0, 0.20)
			_status_tween.tween_property(_status_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_signal_field.visible = show_field
	if _signal_field.has_method("set_progress"):
		_signal_field.call("set_progress", _progress_ratio)
	if _signal_field.has_method("set_stage"):
		_signal_field.call("set_stage", _stage)
	if _progress_rail.has_method("set_progress"):
		_progress_rail.call("set_progress", _progress_ratio)
	var has_meaningful_progress := _total_steps > 0 and _progress_ratio >= 0.0 and _stage != "ready"
	_progress_pill.visible = has_meaningful_progress
	if has_meaningful_progress:
		_progress_label.text = "%d%%" % roundi(clampf(_progress_ratio, 0.0, 1.0) * 100.0)
	if _stage == "ready":
		_progress_pill.visible = false
		_progress_rail.visible = false
	else:
		_progress_rail.visible = true
	var preview_available := _has_real_preview()
	var runtime_verified_at := float(_project.get("runtime_verified_at", 0.0))
	var preview_updated_at := float(_project.get("preview_updated_at", 0.0))
	var game_runtime_verified := runtime_verified_at > 0.0 and runtime_verified_at >= preview_updated_at
	var can_open := _stage == "ready" and preview_available and (str(_project.get("project_kind", "")) != "game" or game_runtime_verified)
	_open_button.visible = can_open
	_continue_button.visible = _stage in ["stalled", "error"] or (_latest_job.size() > 0 and str(_latest_job.get("state", "")) in ["interrupted", "paused", "failed"] and bool(_latest_job.get("resumable", false)))
	if _continue_button.visible:
		var job_state := str(_latest_job.get("state", ""))
		var can_resume_job := job_state in ["interrupted", "paused", "failed"] and bool(_latest_job.get("resumable", false))
		_continue_button.text = "Resume saved step" if can_resume_job else "Continue work"
		_continue_button.icon = Ui.icon("play" if can_resume_job else "regenerate")

func _on_continue_pressed() -> void:
	var project_id := str(_project.get("id", ""))
	var job_state := str(_latest_job.get("state", ""))
	var can_resume_job := job_state in ["interrupted", "paused", "failed"] and bool(_latest_job.get("resumable", false))
	if can_resume_job:
		resume_job_requested.emit(str(_latest_job.get("id", "")))
	else:
		continue_work_requested.emit(project_id)

func _animate_presence() -> void:
	if _presence == null or not is_instance_valid(_presence):
		return
	_presence.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.tween_property(_presence, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _refresh_preview() -> void:
	if _preview_frame == null or not is_instance_valid(_preview_frame):
		return
	var path := str(_project.get("preview_path", "")).strip_edges()
	if path == "" or not FileAccess.file_exists(path):
		_preview_frame.visible = false
		return
	if path != _preview_path:
		var image := Image.new()
		if image.load(path) != OK or image.is_empty():
			_preview_frame.visible = false
			return
		_preview_texture.texture = ImageTexture.create_from_image(image)
		_preview_path = path
	# Keep a real capture visible while it is being reviewed; a screenshot alone
	# still does not unlock the ready/open action.
	_preview_frame.visible = _has_real_preview()

func _has_real_preview() -> bool:
	var path := str(_project.get("preview_path", "")).strip_edges()
	if path == "" or not FileAccess.file_exists(path):
		return false
	return str(_project.get("preview_kind", "")) == "paired_runtime_capture"

func _status_copy(detail: String) -> String:
	var value := detail.to_lower()
	if "scene" in value: return "Laying out the first world"
	if "script" in value or "code" in value: return "Giving the game its first playable rules"
	if "write" in value or "file" in value: return "Putting the pieces in place"
	if "test" in value or "run" in value: return "Trying the game and checking its feel"
	if "art" in value or "image" in value: return "Adding character and atmosphere"
	if "inspect" in value or "read" in value: return "Getting to know the project first"
	if "research" in value or "search" in value: return "Finding what the project needs"
	if "capture" in value: return "Taking a fresh look at the running result"
	return "Crafting the next part of the experience"

func _kind_name(raw_kind: String) -> String:
	match raw_kind.to_lower().strip_edges():
		"game": return "game"
		"app", "mobile_app": return "app"
		"website", "web": return "website"
		"ai", "model", "ai_project": return "AI project"
		"research": return "research project"
		_: return "project"

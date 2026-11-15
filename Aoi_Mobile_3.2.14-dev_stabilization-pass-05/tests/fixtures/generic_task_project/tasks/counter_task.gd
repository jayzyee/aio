extends RefCounted

func start(_context: Dictionary, parameters: Dictionary, checkpoint: Dictionary) -> Dictionary:
	var state := checkpoint.duplicate(true)
	if state.is_empty():
		state = {
			"current": 0,
			"limit": int(parameters.get("steps", 1000)),
			"sum": 0
		}
	return {"ok": true, "state": state, "detail": "Counter task initialized."}


func step(context: Dictionary, state: Dictionary, budget_units: int) -> Dictionary:
	var current := int(state.get("current", 0))
	var limit := int(state.get("limit", 0))
	var final_index := mini(current + budget_units, limit)
	while current < final_index:
		current += 1
		state["sum"] = int(state.get("sum", 0)) + current
	state["current"] = current
	var done := current >= limit
	var progress := float(current) / maxf(1.0, float(limit))
	if context.has("progress"):
		context.progress.call(progress, "Processed %d of %d steps." % [current, limit])
	var metrics := {"completed_steps": current, "expected_steps": limit, "sum": int(state.get("sum", 0))}
	if done:
		return {
			"ok": true,
			"state": state,
			"progress": 1.0,
			"detail": "All deterministic steps completed.",
			"done": true,
			"summary": "Completed %d steps; checksum %d." % [current, int(state.sum)],
			"result": {"checksum": int(state.sum)},
			"metrics": metrics,
			"artifacts": {"output.txt": "completed=%d\nchecksum=%d\n" % [current, int(state.sum)]}
		}
	return {"ok": true, "state": state, "progress": progress, "detail": "Processed %d/%d." % [current, limit], "done": false, "metrics": metrics}

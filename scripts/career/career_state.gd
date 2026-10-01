class_name CareerState
extends RefCounted

# The player's contracting business: bank balance, stars per job and the
# on-call counter. Saved to user:// as small JSON; anything unexpected in the
# file is ignored rather than trusted.

const PATH := "user://career.json"
const VERSION := 1

var path := PATH # tests point this elsewhere
var company := "Brick & Mortar Mechanical"
var money := 0.0
var results: Dictionary = {}  # job id -> {"stars", "payout", "best_comfort", "best_cost", "plays"}
var on_call_done := 0

func stars_for(job_id: String) -> int:
	return int(results.get(job_id, {}).get("stars", 0))

func total_stars() -> int:
	var total := 0
	for id in results:
		if not String(id).begins_with("oncall"): total += int(results[id].get("stars", 0))
	return total

func completed(job_id: String) -> bool:
	return stars_for(job_id) > 0

# Records a finished job. Pays the job's fee the first time, and on a replay
# only the share of the fee the new stars add, so replays are worth it for
# stars without turning into a money farm. Returns {"earned", "new_stars"}.
func record(job_id: String, stars: int, fee: float, stats: Dictionary = {}) -> Dictionary:
	var before: Dictionary = results.get(job_id, {})
	var old_stars := int(before.get("stars", 0))
	var earned := 0.0
	if stars > 0:
		if job_id.begins_with("oncall"):
			earned = fee
			on_call_done += 1
		elif old_stars == 0:
			earned = fee
		elif stars > old_stars:
			earned = fee * float(stars - old_stars) / 3.0
	money += earned
	var entry := before.duplicate()
	entry.stars = maxi(old_stars, stars)
	entry.plays = int(before.get("plays", 0)) + 1
	for key in ["comfort_pct", "cost_usd"]:
		if stats.has(key): entry["last_" + key] = float(stats[key])
	if not job_id.begins_with("oncall") or stars > 0:
		results[job_id] = entry
	save()
	return {"earned": earned, "new_stars": maxi(0, stars - old_stars)}

func to_dictionary() -> Dictionary:
	return {"version": VERSION, "company": company, "money": money, "results": results.duplicate(true), "on_call_done": on_call_done}

func from_dictionary(data: Dictionary) -> void:
	if data.get("company") is String and not String(data.company).strip_edges().is_empty():
		company = String(data.company).strip_edges().left(48)
	if (data.get("money") is float or data.get("money") is int) and is_finite(float(data.money)):
		money = clampf(float(data.money), -1.0e9, 1.0e9)
	if data.get("on_call_done") is float or data.get("on_call_done") is int:
		on_call_done = clampi(int(data.on_call_done), 0, 1000000)
	results.clear()
	if data.get("results") is Dictionary:
		for id in data.results:
			var entry: Variant = data.results[id]
			if not (id is String) or not entry is Dictionary or results.size() >= 500: continue
			var stars := int(entry.get("stars", 0)) if (entry.get("stars") is float or entry.get("stars") is int) else 0
			results[String(id)] = {"stars": clampi(stars, 0, 3), "plays": clampi(int(entry.get("plays", 1)) if (entry.get("plays") is float or entry.get("plays") is int) else 1, 0, 100000)}
			for key in ["last_comfort_pct", "last_cost_usd"]:
				if (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key])): results[String(id)][key] = float(entry[key])

func save() -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	if OS.has_feature("web"): JavaScriptBridge.force_fs_sync()
	return OK

static func load_or_new(from: String = PATH) -> CareerState:
	var state := CareerState.new()
	state.path = from
	if not FileAccess.file_exists(from): return state
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(from))
	if parsed is Dictionary: state.from_dictionary(parsed)
	return state

func reset() -> void:
	company = "Brick & Mortar Mechanical"
	money = 0.0
	results.clear()
	on_call_done = 0
	save()

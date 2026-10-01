class_name CareerJobs
extends RefCounted

# The career's contracts. Three kinds of work, each built on the same
# building simulation the sandbox runs:
#   install  an empty-of-HVAC building: design and build the system within a
#            budget, then commission it over a simulated day
#   service  a running building with hidden faults and complaint calls:
#            read the BAS, walk to the equipment, test it and fix it
#   tune     a building with wasteful BAS programming: re-program it to cut
#            a day's energy bill without making anyone uncomfortable
# Equipment and rooms are named as the starters name them ("AHU-1",
# "VAV-2 · Office", "Conference"); targets resolve when the job starts.
# Install budgets/energy targets and tune baselines come from the seeded
# reference designs (tests/career_mode.gd checks every job is winnable).

const RANKS := [[0, "Apprentice"], [4, "Technician"], [10, "Lead technician"], [17, "Controls engineer"], [24, "Master of the mechanical room"]]
const TIERS := [
	{"tier": 1, "name": "Apprentice calls", "stars": 0},
	{"tier": 2, "name": "Technician work", "stars": 4},
	{"tier": 3, "name": "Lead jobs", "stars": 10},
]
const TYPE_NAMES := {"install": "Install", "service": "Service call", "tune": "Tune-up"}
const TYPE_COLORS := {"install": Color("5fbf7f"), "service": Color("f0a64a"), "tune": Color("6fb7ff")}
# Rooms nobody is graded on: you don't have to condition (or comfort) these.
const UNGRADED_TYPES := ["corridor", "restroom", "storage", "mechanical"]
# Standard occupied setpoints, °F (cooling / heating).
const STANDARD_COOL_F := 73.0
const STANDARD_HEAT_F := 70.0
# The wasteful programming tune-ups start from.
const AS_FOUND := {"occupied_start_h": 4.0, "occupied_end_h": 22.0, "optimal_start": false, "sat_reset": false, "sat_fixed_c": 12.8,
	"static_reset": false, "static_fixed_pa": 400.0, "economizer": false, "dcv": false, "vav_min_fraction": 0.6}

const JOBS := [
	# --- Tier 1 -------------------------------------------------------------------------
	{
		"id": "t1_hot_office", "tier": 1, "type": "service", "title": "It's an oven in here",
		"client": "Corner Workshop Co.", "template": "studio", "scenario": "Hot afternoon",
		"arrive_h": 12.5, "deadline_h": 17.0, "fee": 900.0, "comfort_star": 70.0,
		"brief": "The owner says the little office has been sweltering since lunch while the workshop next door is fine. Find out why and fix it before they close at five.",
		"tickets": [{"room": "Office", "text": "\"It's an oven in here. The workshop is fine!\""}],
		"faults": [{"kind": "stuck_damper", "vav": "Office", "value": 0.08, "onset_h": 11.75}],
		"hints": [
			"Select the Office's VAV (Equipment view): its card shows the room temperature, airflow and damper. Compare the damper's command with its feedback in the trend.",
			"Press Tab to walk. Stand under the VAV and press E to service it: stroke the damper to test it.",
			"Replace the part that failed, then watch the room cool down and close out the job.",
		],
	},
	{
		"id": "t1_workshop_fitout", "tier": 1, "type": "install", "title": "Fit out the corner workshop",
		"client": "Corner Workshop Co.", "template": "studio", "scenario": "Normal weekday",
		"fee": 2400.0, "budget_factor": 1.35, "comfort_min": 90.0, "energy_usd": 5.0,
		"brief": "A new workshop with an office and a washroom and no HVAC at all yet. Put an air handler on the back pad, give each room air and a thermostat, then commission it over a working day.",
		"hints": [
			"Equipment view: place an Air handler on the concrete pad behind the building (it labels its outside-air intake and supply outlet).",
			"Then use Zone a room on the Workshop and the Office: each gets a VAV, diffusers, a thermostat and the ducts.",
			"When every room has air, press Run commissioning day and watch the day play out.",
		],
	},
	{
		"id": "t1_cold_start", "tier": 1, "type": "service", "title": "Cold start",
		"client": "Corner Workshop Co.", "template": "studio", "scenario": "Cold morning",
		"arrive_h": 7.5, "deadline_h": 13.0, "fee": 1100.0, "comfort_star": 55.0,
		"brief": "Freezing morning. The crew in the workshop are working in their coats and the office manager says her thermostat \"does nothing\". Two calls, maybe two problems.",
		"tickets": [{"room": "Workshop", "text": "\"Still 60 degrees in here at half seven.\""}, {"room": "Office", "text": "\"My thermostat does nothing.\""}],
		"faults": [{"kind": "reheat_stuck", "vav": "Workshop", "value": 0.0, "onset_h": 7.0}, {"kind": "setpoint", "room": "Office", "cool_f": 64.0, "heat_f": 62.0, "onset_h": 7.0}],
		"hints": [
			"On a cold morning the VAV's reheat coil warms the room. Look at the Workshop VAV's reheat command and its discharge air.",
			"Thermostats can be serviced too: walk up to the Office thermostat and press E.",
		],
	},
	# --- Tier 2 -------------------------------------------------------------------------
	{
		"id": "t2_office_tuneup", "tier": 2, "type": "tune", "title": "The office that never sleeps",
		"client": "Elm Street Properties", "template": "office", "scenario": "Economizer day",
		"fee": 2600.0, "baseline_usd": 13.09, "cut_min": 40.0, "cut_star": [60.0, 75.0], "comfort_min": 90.0, "air_min": 90.0,
		"setpoints_f": [71.0, 70.0],
		"brief": "The office's energy bill is nearly double its neighbours'. The building is comfortable, so nobody has looked at the BAS programming in years. Re-program it and prove the savings over a mild spring day.",
		"hints": [
			"Open BAS programming. Every setting here is a real sequence: occupied schedule, supply-air reset, static-pressure reset, economizer, demand ventilation, VAV minimums.",
			"People are in from 7:00 to 18:00 whatever the schedule says. Starting the air handlers late leaves them warm and stuffy.",
			"Run the verification day to measure a full 24 hours against the as-found bill.",
		],
	},
	{
		"id": "t2_conference_chill", "tier": 2, "type": "service", "title": "Meeting in a meat locker",
		"client": "Elm Street Properties", "template": "office", "scenario": "Normal weekday",
		"arrive_h": 9.0, "deadline_h": 16.0, "fee": 1700.0, "comfort_star": 85.0,
		"brief": "The conference room is freezing every afternoon, yet the BAS says it's sitting right on setpoint. The building engineer also wants the air handler looked at: an alarm keeps coming back.",
		"tickets": [{"room": "Conference", "text": "\"We're holding meetings in our jackets.\""}],
		"faults": [{"kind": "sensor_bias", "room": "Conference", "value": 3.6}, {"kind": "dirty_filter", "ahu": "AHU-1"}],
		"hints": [
			"A BAS only knows what its sensors tell it. If a room feels wrong but reads right, check the sensor itself.",
		],
	},
	{
		"id": "t2_office_buildout", "tier": 2, "type": "install", "title": "Neighborhood office build-out",
		"client": "Elm Street Properties", "template": "office", "scenario": "Hot afternoon",
		"fee": 5200.0, "budget_factor": 1.3, "comfort_min": 82.0, "energy_usd": 19.0,
		"brief": "A ten-room office, plant room ready, no HVAC yet. The tenant moves in during a heat spell, so the system has to hold the rooms through a hot afternoon. Size the air handler with care.",
		"hints": [
			"Air handler size is on the workbench (Edit components). A unit too small runs flat out and still falls behind on a hot afternoon; too big costs more and wastes fan energy.",
		],
	},
	# --- Tier 3 -------------------------------------------------------------------------
	{
		"id": "t3_heat_wave", "tier": 3, "type": "service", "title": "Heat wave emergency",
		"client": "Maple Street Elementary", "template": "school", "scenario": "Hot afternoon",
		"arrive_h": 10.0, "deadline_h": 16.0, "fee": 3400.0, "comfort_star": 40.0,
		"brief": "Summer school, 99 °F outside, and the whole building is warm. The principal has a list: classrooms, the gym, and a room that's worse than the rest. Triage and fix what you can before the buses.",
		"tickets": [{"room": "Classroom 103", "text": "\"Worst room in the building.\""}, {"room": "Gym", "text": "\"Gym is like a sauna.\""}],
		"faults": [{"kind": "chw_valve_stuck", "ahu": "AHU-1", "value": 0.0, "onset_h": 9.0}, {"kind": "oa_damper_stuck", "ahu": "AHU-2", "value": 1.0, "onset_h": 8.5}, {"kind": "stuck_damper", "vav": "Classroom 103", "value": 0.15, "onset_h": 8.0}],
	},
	{
		"id": "t3_school_audit", "tier": 3, "type": "tune", "title": "School energy audit",
		"client": "Maple Street Elementary", "template": "school", "scenario": "Cold morning",
		"fee": 4200.0, "baseline_usd": 63.68, "cut_min": 35.0, "cut_star": [45.0, 55.0], "comfort_min": 90.0, "air_min": 90.0,
		"setpoints_f": [72.0, 71.0],
		"brief": "The district wants the gas bill down before winter. Prove it on a frosty day: cold mornings are when bad programming burns the most hot water.",
	},
	{
		"id": "t3_school_build", "tier": 3, "type": "install", "title": "Maple Street Elementary",
		"client": "Maple Street Elementary", "template": "school", "scenario": "Normal weekday",
		"fee": 9000.0, "budget_factor": 1.3, "comfort_min": 90.0, "energy_usd": 31.0,
		"brief": "Fifteen rooms, a gym and a plant room, all yours to design. One air handler or two? Where does the main run? Keep every classroom comfortable through a full school day.",
	},
	{
		"id": "t3_final_inspection", "tier": 3, "type": "service", "title": "The final inspection",
		"client": "Maple Street Elementary", "template": "school", "scenario": "Cold morning",
		"arrive_h": 7.5, "deadline_h": 13.0, "fee": 4600.0, "comfort_star": 70.0,
		"brief": "The district's commissioning agent arrives at one. Before then: a library that's too hot, a classroom that won't stop heating, a cold gym and an alarm nobody can explain.",
		"tickets": [{"room": "Library", "text": "\"Library's roasting and the gas meter is spinning.\""}, {"room": "Gym", "text": "\"Gym's freezing.\""}],
		"faults": [{"kind": "reheat_stuck", "vav": "Library", "value": 1.0}, {"kind": "sensor_bias", "room": "Classroom 105", "value": -4.2}, {"kind": "fan_failure", "ahu": "AHU-2", "onset_h": 7.25}, {"kind": "dirty_filter", "ahu": "AHU-1"}],
	},
]

# Service calls the on-call board can generate, by tier.
const ON_CALL_FAULTS := {
	"studio": [["stuck_damper", "vav"], ["reheat_stuck", "vav"], ["sensor_bias", "room"], ["dirty_filter", "ahu"], ["fan_failure", "ahu"], ["setpoint", "room"], ["chw_valve_stuck", "ahu"]],
	"office": [["stuck_damper", "vav"], ["reheat_stuck", "vav"], ["sensor_bias", "room"], ["dirty_filter", "ahu"], ["fan_failure", "ahu"], ["setpoint", "room"], ["chw_valve_stuck", "ahu"], ["oa_damper_stuck", "ahu"]],
	"school": [["stuck_damper", "vav"], ["reheat_stuck", "vav"], ["sensor_bias", "room"], ["dirty_filter", "ahu"], ["fan_failure", "ahu"], ["setpoint", "room"], ["chw_valve_stuck", "ahu"], ["oa_damper_stuck", "ahu"]],
}

static func all() -> Array:
	return JOBS

static func find(job_id: String) -> Dictionary:
	for job in JOBS:
		if String(job.id) == job_id: return job
	return {}

static func tier_of(job: Dictionary) -> Dictionary:
	for tier in TIERS:
		if int(tier.tier) == int(job.get("tier", 1)): return tier
	return TIERS[0]

static func unlocked(job: Dictionary, stars: int) -> bool:
	return stars >= int(tier_of(job).stars)

static func rank(stars: int) -> String:
	var name := String(RANKS[0][1])
	for entry in RANKS:
		if stars >= int(entry[0]): name = String(entry[1])
	return name

static func next_rank(stars: int) -> Array:
	for entry in RANKS:
		if stars < int(entry[0]): return entry
	return []

# Rooms that count: occupied rooms (not corridors, restrooms, storage or plant).
static func graded_rooms(index: BuildingIndex) -> Array:
	var ids: Array = []
	for room in index.rooms:
		if String(room.get("type", "room")) not in UNGRADED_TYPES: ids.append(String(room.id))
	return ids

static func scenario_line(job: Dictionary) -> String:
	var weather: Array = DemoSimulation.WEATHER.get(String(job.scenario), DemoSimulation.WEATHER["Normal weekday"])
	return "%s · %s to %s outside" % [String(job.scenario), Units.degrees(float(weather[0])), Units.degrees(float(weather[1]))]

static func clock(hours: float) -> String:
	var minutes := roundi(hours * 60.0)
	return "%02d:%02d" % [floori(minutes / 60.0) % 24, minutes % 60]

# A random service call for the on-call board. Deterministic per serial so a
# call can be retried exactly. Harder buildings and more faults as you rank up.
static func on_call(serial: int, stars: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("brick-bas-on-call-%d" % serial)
	var templates := ["studio"]
	if stars >= int(TIERS[1].stars): templates.append("office")
	if stars >= int(TIERS[2].stars): templates.append("school")
	var template: String = templates[rng.randi() % templates.size()]
	var scenario: String = ["Normal weekday", "Hot afternoon", "Cold morning", "Economizer day"][rng.randi() % 4]
	var count := 1 + mini(2, rng.randi() % (2 + int(stars / 8.0)))
	var kinds: Array = ON_CALL_FAULTS[template].duplicate()
	var faults: Array = []
	var used: Dictionary = {}
	for attempt in range(20):
		if faults.size() >= count or kinds.is_empty(): break
		var pick: Array = kinds[rng.randi() % kinds.size()]
		var kind := String(pick[0])
		if used.has(kind): continue
		# Faults that need the weather to show: reheat on cold days, chilled water on warm ones.
		if kind == "reheat_stuck" and scenario != "Cold morning": continue
		if kind in ["chw_valve_stuck", "oa_damper_stuck"] and scenario in ["Cold morning", "Economizer day"]: continue
		used[kind] = true
		var fault := {"kind": kind, String(pick[1]): "*"}
		match kind:
			"stuck_damper": fault.value = [0.05, 0.1, 0.15][rng.randi() % 3]
			"reheat_stuck": fault.value = 0.0
			"sensor_bias": fault.value = (3.5 + rng.randf() * 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			"chw_valve_stuck": fault.value = 0.0
			"oa_damper_stuck": fault.value = 1.0
			"setpoint":
				fault.cool_f = 64.0 if scenario != "Cold morning" else 66.0
				fault.heat_f = 62.0
		fault.pick = rng.randi()
		faults.append(fault)
	var arrive := 8.0 + float(rng.randi() % 5)
	for fault in faults:
		if String(fault.kind) not in ["setpoint", "sensor_bias", "dirty_filter"]: fault.onset_h = arrive - 0.5 - rng.randf() * 1.5
	var names := {"studio": "Corner Workshop Co.", "office": "Elm Street Properties", "school": "Maple Street Elementary"}
	return {"id": "oncall_%d" % serial, "tier": 0, "type": "service", "title": "On-call #%d" % (serial + 1), "client": names[template],
		"template": template, "scenario": scenario, "arrive_h": arrive, "deadline_h": minf(arrive + 5.0, 18.0),
		"fee": 600.0 + 450.0 * faults.size() + (500.0 if template == "school" else (200.0 if template == "office" else 0.0)),
		"comfort_star": 55.0, "faults": faults, "tickets": [], "on_call": true,
		"brief": "Dispatch has a call from %s: \"Something's not right.\" No details. Find what's wrong from the BAS and fix it." % names[template]}

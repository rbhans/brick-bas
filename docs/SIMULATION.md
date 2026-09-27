# Demo building simulation

Updated 2026-09-25. `scripts/sim/demo_simulation.gd` (`DemoSimulation`) is the data source for the demo: it turns whatever the player built into BAS point data that animates equipment and feeds thermostats, readouts and alarms. It is a deterministic, sensible-heat **gameplay** model. The aim is data that runs and responds like a real building on a BAS front end. It is not an energy model, sizing tool, commissioning sequence or code-compliance claim.

## At a glance

- Fixed 1 s steps. 1× and 60× give bit-identical results, and so do two runs of the same inputs. There is no global RNG.
- The day starts at 06:30, so players see optimal start: the fan command leads, the VFD ramps, dampers stroke and the coils load up.
- The building comes from the game through `configure()`: rooms (zones), AHUs, VAVs and duct bottlenecks. It can be edited while running; state for surviving ids is kept.
- Zones are two thermal nodes: room air plus structural mass. Weather, sun on each façade, people, lights, plug loads, open doors and windows, partitions and supply air all act on them. CO₂ is tracked per zone.
- VAVs are pressure-independent with ASHRAE Guideline 36-style dual-maximum reheat. AHUs use:
  - duct-static VFD control and SAT trim & respond;
  - economizer first, then chilled water;
  - DCV minimum outdoor air.
- Only installed components act. No fan means no airflow; no cooling coil means no mechanical cooling; no OA damper means no economizer or outdoor air; a VAV without a heating coil has no reheat.
- Seven fault or special scenarios plus five weather scenarios. AlarmManager raises BAS-style alarms.
- Cost: about 0.36 ms per 1 s step for 40 zones, 8 AHUs and 40 VAVs (0.009 ms per zone, desktop). Rebuilding a 1140-point snapshot takes about 0.9 ms and happens only after state changes.

## Driving it from the game

```gdscript
const STEP_SECONDS := 1.0
const SCENARIOS := ["Normal weekday", "Hot afternoon", "Fan failure", "Damper stuck at 25%", "Dirty filter",
	"Sensor bias", "Data interruption", "Cold morning", "Unoccupied", "Economizer day", "Heat wave"]
var running: bool          # pause
var speed: float           # 0..60 simulated seconds per real second
var sim_seconds: float     # starts 23400 (06:30); time of day = fmod(sim_seconds, 86400)
var scenario: String

func reset() -> void                                   # 06:30 Normal weekday; keeps topology and open doors
func advance(real_delta: float) -> int                 # steps taken; ≤ 3600 per call, backlog beyond that is dropped
func step_for_test(seconds: float) -> void
func set_scenario(name: String) -> void
func configure(topology: Dictionary) -> void
func set_zone_setpoints(zone_id: String, cool_c: float, heat_c: float = NAN) -> void
func set_terminal_setpoint(vav_id: String, cool_c: float) -> void   # VAV-linked thermostat
func set_room_setpoint(id: String, value_c: float) -> void          # legacy: zone or VAV id
func set_open_connections(connections: Array) -> void
func set_lights(zone_id: String, on: bool) -> void
func snapshot_points() -> Array[Dictionary]
func checkpoint() -> Dictionary
func restore_checkpoint(state: Dictionary) -> void
# Read accessors return copies:
func zone_state(zone_id: String) -> Dictionary
func unit_state(ahu_id: String) -> Dictionary
func terminal_state(vav_id: String) -> Dictionary
func weather() -> Dictionary    # outdoor_temp_c, solar_w_m2, occupied, time_of_day_s, clock "07:42", scenario, occupied_elapsed_s, irradiance_w_m2{N,E,S,W,horizontal}
func zone_ids() -> Array        # sorted
func unit_ids() -> Array
func terminal_ids() -> Array
func fault_targets() -> Dictionary   # {fan_failure, dirty_filter, stuck_damper, sensor_bias}: affected id or ""
```

Public dictionaries `zones`, `units` and `terminals` (with `rooms` as an alias of `terminals`) and `route_flows` exist for tests and debugging; UI should use the accessors. Legacy shims remain: `apply_network_status()`, `ensure_room()` (a no-op), and the first-AHU aliases `fan_feedback`, `supply_temp_c`, `available_flow_m3_s`, `outdoor_temp_c`, `occupied`, `solar_w_m2`.

Typical frame: `advance(delta)`, then `snapshot_points()` into PointStore; if steps > 0, `AlarmManager.evaluate(sim, steps × STEP_SECONDS)`. Call `configure()` after any building edit, even while paused. Flows are then reduced immediately to respect a removed or disconnected branch or a smaller capacity; nothing new flows until the next step. Call `set_open_connections()` whenever a door or window opens or closes.

`snapshot_points()` rebuilds only after state changed (a step, an input, a configure). The returned array is fresh, but the point dictionaries and their shared `quality_flags` array are cached and must be treated as read-only. PointStore duplicates what it keeps.

### Setpoint rules (for thermostat UI)

| | Value |
| --- | --- |
| Allowed range | Heating 16–29 °C, cooling 17–30 °C (`SETPOINT_MIN_C` 16, `SETPOINT_MAX_C` 30) |
| Minimum deadband | 1 K (`MIN_DEADBAND_K`). The cooling value wins: heating is pushed down to cool − 1 |
| Occupied defaults | Cooling 23 °C, heating 21 °C (`DEFAULT_COOL_C`, `DEFAULT_HEAT_C`) |
| Unoccupied setbacks | Cooling 29 °C, heating 16 °C (`UNOCC_COOL_C`, `UNOCC_HEAT_C`) |
| Night-cycle targets | Heat to 18 °C and stop when all zones ≥ 17; cool to 27 °C and stop when all ≤ 28 |

`zone_state().cool_setpoint_c` and `heat_setpoint_c` are the player's occupied setpoints. `active_cool_setpoint_c` and `active_heat_setpoint_c` are what control uses right now.

### Topology (`configure`)

```
{
  "zones": { id: { "label", "type", "area_m2", "exterior_wall_m2" (gross, incl. windows), "roof_m2" (default = area),
                   "window_m2": {"N","E","S","W"}, "neighbours": { other_id: shared_wall_m2 }, "exterior_doors": int } },
  "units": { ahu_id: { "label", "capacity_m3_s", "layout": roles in airflow order from damper/filter/cooling_coil/heating_coil/fan } },
  "terminals": { vav_id: { "label", "zone_id" ("" = not in a room), "source_id", "connected", "capacity_m3_s",
                           "layout": subset of damper/heating_coil/cooling_coil } },
  "limits": { resource_id: { "capacity_m3_s", "weights": { vav_id: share } } },
  "routes": { duct_id: { "capacity_m3_s", "weights": { vav_id: share } } }
}
```

N = −Z, S = +Z, E = +X, W = −X. Types: classroom, office, lobby, corridor, restroom, mechanical, conference, break_room, storage, gym, library, room (unknown values become room).

Parsing is defensive. Missing or empty sections give an empty building (the site points still publish). Non-finite or wrong-typed values fall back or are clamped. Unknown neighbour or VAV references are ignored. Shared walls are symmetrised, with the larger declared area winning.

- A terminal counts as connected only if `connected` is true and its `source_id` is a configured AHU.
- A `zone_id` that is not a configured zone becomes "".
- Missing layouts default to the full AHU layout and to `["damper", "heating_coil"]` for VAVs.
- The first instance of a role acts; duplicate coils share its valve and do not add capacity.

A VAV with `zone_id` "" gets its own small space (20 m², no people), so its loops, damper and airflow still work. Several VAVs may serve one zone; their airflow adds, each runs its own loops on the shared zone sensor, and the loop gain is tuned for their combined size. A zone with no connected VAV is **unconditioned**. It still drifts with weather, gains and neighbours, publishes `<zone>.space_temp` and `<zone>.co2`, and reports mode "Unconditioned".

New ids start at the building's average temperature (or the scenario start temperature on an empty canvas). Removed ids and their points disappear.

### Doors, windows, lights

`set_open_connections([{ "a": zone_id | "outside", "b": zone_id | "outside", "kind": "door" | "window" }])`, called with the complete current list:

| Opening | Air exchange |
| --- | --- |
| Exterior door | 0.10 + 0.07·√\|ΔT\| m³/s of outdoor air (wind + buoyancy); ≈ 0.36 m³/s at 14 K |
| Exterior window | 0.04 + 0.025·√\|ΔT\| m³/s |
| Interior door | 0.08 + 0.06·√\|ΔT\| m³/s each way between the zones (heat and CO₂) |
| Interior window | 0.02 m³/s each way |

Propping the front door open at 14:00 on a Hot afternoon warms the lobby 0.8 K in 2.5 min and 2.8 K in 20 min. Its VAV goes to maximum and lobby CO₂ falls; closing the door recovers it.

`set_lights(zone, on)` is an override. It is cleared by the next occupied/unoccupied schedule change, like a BAS sweep. By default lights follow occupancy, except in mechanical rooms and storage (off). `zone_state().lights_on` reports the current state.

## Sequences

### Schedule and AHU modes

Occupied is 07:00–18:00 (never in the Unoccupied scenario). Each AHU with a fan picks a mode every step:

| Mode | When | Fan | OA damper | SAT setpoint | VAV setpoints / minimum |
| --- | --- | --- | --- | --- | --- |
| Occupied | 07:00–18:00 | on | minimum + DCV, economizer | T&R 12.8–18 °C, reset by OAT | occupied / 30 % (CO₂ reset to 60 %) |
| Cool-down | optimal start, zones warm | on | closed or economizer | 12.8 °C | occupied / 0 |
| Warm-up | optimal start, zones cold | on | closed | 35 °C (AHU heating coil) | occupied / 0 |
| Setup | unoccupied, a served zone > 29 °C | on | closed or economizer | 12.8 °C | cool to 27 / 0 |
| Setback | unoccupied, a served zone < 16 °C | on | closed | 35 °C | heat to 18 / 0 |
| Off | otherwise | off | closed | held | 16 / 29, VAVs closed |

**Optimal start** runs from 05:00. Lead time is 15 min + 20 min per K of the worst served zone's error against its occupied setpoints, capped at 2 h. Once started it holds Warm-up or Cool-down until 07:00. At the 06:30 start a Normal-weekday building sits at 24 °C, so cool-down starts on the first step. A zone within 0.2 K of its setpoints does not trigger optimal start.

### VAV terminal (pressure independent, GL36-style dual maximum)

- **Loops.** Cooling and heating PI loops (0–100 %) run on the measured zone temperature against the active setpoints, with anti-windup. Gain is auto-tuned per zone so every zone has about a 15 min crossover; the proportional band is typically about 2 K for a classroom, and integral time is 1200 s.
- **Airflow setpoint.**
  - Cooling loop 0→100 % moves airflow from minimum to maximum (`capacity_m3_s`). This only happens while the supply air is cooler than the room, as in GL36; warm supply holds the minimum.
  - Heating loop 0–50 % holds minimum airflow and raises the discharge setpoint from supply temperature toward min(space + 11 K, 35 °C) with the reheat valve.
  - Heating loop 50–100 % raises airflow to the heating maximum (45 %). With warm AHU supply air (warm-up) the heating loop raises airflow directly.
- **Minimum airflow.** Occupied minimum is 30 % of maximum. It rises toward 60 % as zone CO₂ goes from 1000 to 1400 ppm (ventilation reset). The minimum is 0 in every other mode.
- **Damper.** Command = feedforward from duct static (box flow ∝ opening·√P, 1.25× oversized) plus a slow integral trim on the airflow error. A starved box, whether pressure-limited or duct-limited, drives open. The actuator strokes in 90 s with a 0.4 % deadband.
- **Reheat valve** needs proven airflow. It is positioned for the discharge setpoint from a coil model: hot water at 60 °C, design rise 24 K at heating maximum, 60 s stroke. A terminal cooling coil (rare) cools after airflow, or on its own when the AHU air is warm.

### AHU

- **Supply fan.** A VFD PI loop on duct static; the setpoint starts at 250 Pa. Minimum speed is 20 %; accel and decel take 30 s for 0→100 %. Run proof is a current switch at 10 % speed, and the fan counts as proven after 5 s.
- **Static pressure trim & respond** (after 10 min in a mode, every 2 min). Range is 150–300 Pa: trim −6 Pa, respond +12 Pa per request up to +30 Pa. A VAV with its damper command above 95 % sends one pressure request, or two if it is below 70 % of its airflow setpoint. The number of ignored requests is 0, 1 or 2 by system size.
- **SAT setpoint, occupied.** T&R over 12.8–18 °C: trim +0.1 K, respond −0.2 K per request up to −0.6 K. Cooling requests per zone:
  - 3 requests if the zone is more than 3 K over its cooling setpoint;
  - 2 if more than 1.5 K over;
  - 1 if the cooling loop is above 95 %.
  The T&R value is then blended to 12.8 °C as OAT rises from 16 to 21 °C.
- **Outdoor air.** Occupied minimum position is 20 %, rising to 50 % as the worst served zone's CO₂ goes from 700 to 1000 ppm (DCV). The damper is closed in every other mode unless economizing.
- **Economizer.** Enabled when the fan is proven, a damper is installed, the mode is Occupied, Cool-down or Setup, and OAT is below min(21 °C high limit, return air) − 0.5 K (0.5 K hysteresis).
- **SAT loop.** One PI loop (6 %/K, Ti 150 s) split into:
  - heating coil (−100…0);
  - economizer damper, minimum→100 % (0…50);
  - chilled-water valve (50…100): economizer first, then mechanical cooling.
  Without the economizer the valve takes 0…100. Switching the economizer is bumpless.
- **Interlocks.** Without fan proof all valves close and the OA damper closes. Valves stroke in 60 s, the OA damper in 75 s.
- **Air path.** Return air = flow-weighted zone air + 0.4 K plenum gain (60 s sensor lag). Mixed air = OAF·OAT + (1 − OAF)·RAT, with OAF equal to the OA damper position. Then each installed role applies in layout order:
  - cooling coil: leaving air approaches 6.7 °C chilled water with effectiveness 0.85 (low flow) falling to 0.72 (design flow);
  - heating coil: 60 °C hot water, effectiveness 0.55;
  - fan heat: fan pressure / (η·ρcp), about 1 K at design.
  SAT has a 25 s coil and sensor lag. Leakage keeps air over the coils even when every VAV is shut.

### Duct airflow and mass balance

Per AHU, the fan curve (1000 Pa shutoff × N², 300 Pa droop at design) equals internal plus duct losses plus static. Losses at design flow, all ∝ Q²:

| Item | Pa at design flow |
| --- | --- |
| Casing | 60 |
| OA damper | 20 |
| Cooling coil | 110 |
| Heating coil | 40 |
| Filter | 70 clean, rising 0.1 Pa per run-hour; 500 in Dirty filter |
| Duct to sensor | 120 |

VAV boxes are orifices in parallel, which gives a closed-form flow and static each step.

Delivered flow is then capped, in order, by:
1. each terminal's capacity;
2. the AHU's available airflow, N × min(capacity, √(shutoff/resistance));
3. every shared `limits` entry, as proportional reductions in id order.

Reductions only ever lower flows, so every limit holds after the pass. AHU supply always equals the sum of delivered VAV airflow. `<duct>.airflow` = Σ weight × VAV airflow. A restriction raises the measured static, and the static loop responds.

### Zones (two-node sensible model and CO₂)

- **Air node.** Air plus 20 kJ/(m²·K) of furnishings. It receives:
  - windows (U 2.8);
  - infiltration (0.3 ACH at 3.6 m ceiling, plus 0.01 m³/s per closed exterior door) and open doors and windows;
  - supply air from each VAV;
  - partitions (U 1.8 × shared wall) and interior-door mixing;
  - the convective share of gains.
- **Mass node.** 110 kJ/(m²·K) of structure, coupled to the air at 9 W/(m²·K) of floor. It receives sol-air conduction through opaque walls (U 0.45, absorptance 0.5) and roof (U 0.25, absorptance 0.6, film 20 W/m²K), plus the radiant share of gains: 70 % of solar, 40 % of people, 50 % of lights, 30 % of plug loads.
- **Integration.** Both nodes are integrated exponentially, so they are stable for any step. Coupling uses the previous step, so zone order does not matter.
- **What that gives a 64 m² classroom.** Air node 1.6 MJ/K, mass 7.0 MJ/K. With no airflow at 10:00 it warms 2 K in about 20 min. After the 18:00 shutdown the air rebounds toward the warm structure within an hour, then cools overnight to about 24.5 °C by 06:00. A 2 K setpoint drop pulls the room down 0.7 K in 15 min.
- **Gains by type.** "Profile" is the occupancy profile; its hourly values follow the table.

  | Type | People/m² | W/person | Plug W/m² | Lights W/m² | Profile |
  | --- | --- | --- | --- | --- | --- |
  | classroom | 0.40 | 70 | 5 | 8 | school |
  | office | 0.08 | 75 | 10 | 8 | office |
  | conference | 0.35 | 75 | 4 | 8 | meeting |
  | lobby | 0.08 | 75 | 3 | 8 | office |
  | corridor | 0.02 | 75 | 1 | 5 | office |
  | restroom | 0.05 | 75 | 1 | 6 | office |
  | mechanical | 0 | – | 30 (24/7 equipment) | 4 (off by default) | – |
  | break_room | 0.15 | 75 | 20 | 8 | lunch peak |
  | storage | 0 | – | 1 | 4 (off by default) | – |
  | gym | 0.12 | 150 | 2 | 10 | school |
  | library | 0.10 | 70 | 6 | 9 | school |
  | room | 0.10 | 75 | 5 | 8 | office |

  The school profile ramps in from 07:30, holds about 95 % in class, drops to 30 % at lunch, and falls away after 15:00. The office profile has a lunch dip; meeting rooms are busy 09:00–10:30 and 14:00–16:00. After hours, plug loads fall to 20–50 %, except mechanical and storage, which stay constant.
- **CO₂.** Well mixed. Each person generates 0.0052 L/s (12 in a gym). Outdoor air is 420 ppm. Supply air CO₂ = OAF·420 + (1 − OAF)·return CO₂.

### Weather and sun

Dry bulb follows an asymmetric diurnal curve, minimum at 05:30 and maximum at 15:00. The sun rises at 06:30 in the east, is due south at 13:00, and sets at 19:30 in the west. Irradiance on each façade comes from beam (angle to façade) plus sky diffuse plus ground reflection (albedo 0.2); N gets diffuse only. Window solar = SHGC 0.4 × area × façade irradiance. `site.solar` is global horizontal.

| Scenario weather | Min / max °C | Sky | Peak sun | Building at start |
| --- | --- | --- | --- | --- |
| Normal weekday (and the fault scenarios, Unoccupied) | 17 / 29 | 0.85 | 65° | 24 °C |
| Hot afternoon | 24 / 37 | clear | 70° | 26 °C |
| Cold morning | −2 / 9 | 0.7 | 30° | 15 °C |
| Economizer day | 8 / 19 | 0.9 | 55° | 24 °C |
| Heat wave | 29 / 42 | clear | 72° | 27.5 °C |

The start temperature applies when a scenario is chosen right after `reset()`. Entering Cold morning at any time sets the building to 15 °C (air and mass), an explicit initial condition. Other scenario switches change only weather and faults.

## Scenarios

| Scenario | What happens |
| --- | --- |
| Normal weekday | 06:30 cool-down with economizer, then occupancy at 07:00. Economizer until OAT passes 21 °C (about 09:15), then chilled water. DCV raises OA with classroom CO₂. Lunch dip in airflow and CO₂; evening shutdown and rebound. |
| Hot afternoon | Heavy cooling. A small or undersized AHU runs out of fan or coil capacity and zones drift 1–3 K over setpoint in the afternoon. |
| Heat wave | Mixed air is so hot the chilled-water coil maxes out: SAT floats 1–2.5 K above setpoint, VAVs go to maximum, and zones drift about 2 K over setpoint through the afternoon. On a tight system this raises high-temperature alarms. |
| Economizer day | Free cooling: the OA damper modulates above minimum with the cooling valve closed. Mechanical cooling joins only once the damper is fully open. |
| Cold morning | The building starts at 15 °C. Warm-up with OA closed and 35 °C supply, then occupied reheat: VAV valves open, discharge air is warmer than the room, and zones reach 21 °C by about 08:45 while the structure is still cold. The AHU heating coil tempers cold mixed air. |
| Unoccupied | No occupancy all day (holiday). AHUs stay off within 16–29 °C. Night cycle runs Setup if a sun-lit room passes 29 °C, and Setback if a zone falls below 16 °C. |
| Fan failure | The first AHU with a fan: command stays on, feedback coasts to 0 (τ 12 s), and the VFD command winds up to 100 %. Airflow collapses. After proof is lost, valves and the OA damper close. VAVs drive open. Zones drift. AlarmManager raises fan failure after 20 s and high space temperature later. |
| Damper stuck at 25% | The first VAV id (sorted): feedback frozen at 25 % while the command drives open. Airflow falls short and the zone runs warm. As a rogue zone its requests push static and SAT resets. Stuck-damper alarm after 3 min. |
| Dirty filter | The first AHU with a filter: 500 Pa at design flow. Much higher ΔP, the fan works harder, and delivery falls short at peak demand. Filter alarm. |
| Sensor bias | The first served zone reads +2 K. Control acts on the bad reading and overcools the real room: `true_space_temp` differs from `space_temp`. |
| Data interruption | Every point is published stale (`["stale", "communication_failure"]`) while the model keeps running underneath. Animation holds; AlarmManager raises a comms alarm and freezes other alarms. |

## Points

Every point has `point_id`, `value`, `value_type` ("number", "bool" or "enum"), `unit`, `source_id` "demo", `quality_flags`, `source_timestamp` (= `sim_seconds`), `received_at` and `original_status`.

| Point | Type / unit |
| --- | --- |
| `site.outdoor_temp` / `site.solar` / `site.time_of_day` | degC / W/m2 / h |
| `site.occupied` | bool |
| `<zone>.space_temp`, `<zone>.co2` (every zone, conditioned or not) | degC, ppm |
| `<ahu>.fan_enable_cmd`, `.fan_run_feedback`, `.economizer` | bool |
| `<ahu>.fan_state` ("Running"/"Off"), `.mode` (Off/Occupied/Warm-up/Cool-down/Setback/Setup) | enum |
| `<ahu>.fan_speed_command`, `.fan_speed_feedback` | fraction 0..1 |
| `<ahu>.damper_command`, `.damper_feedback` (outdoor-air damper), `.cooling_command`, `.cooling_output`, `.heating_command`, `.heating_output`, `.outdoor_air_fraction` | % |
| `<ahu>.return_air_temp`, `.mixed_air_temp`, `.supply_air_temp`, `.supply_setpoint` | degC |
| `<ahu>.supply_airflow`, `.available_airflow` | m3/s |
| `<ahu>.duct_pressure`, `.duct_pressure_setpoint`, `.filter_pressure_drop` | Pa |
| `<ahu>.cooling_power`, `.heating_power`, `.fan_power` | W |
| `<vav>.space_temp`, `.true_space_temp`, `.cool_setpoint`, `.heat_setpoint` (active), `.occ_cool_setpoint`, `.occ_heat_setpoint` (thermostat), `.discharge_temp` | degC |
| `<vav>.airflow_target`, `.airflow` | m3/s |
| `<vav>.damper_command`, `.damper_feedback`, `.reheat_command`, `.reheat_output`, `.cooling_command`, `.cooling_output`, `.cooling_loop`, `.heating_loop` | % |
| `<vav>.heating_power` | W |
| `<vav>.mode` (Cooling/Heating/Satisfied/Unoccupied/Disconnected) | enum |
| `<vav>.occupied` | bool |
| `<duct>.airflow` for every route | m3/s |

Sensor realism: smooth deterministic noise (value noise with 20 s knots, hashed from time and id). It is ±0.04 K on zone sensors, ±0.05 K on OAT/SAT/MAT/RAT and discharge air, ±2 Pa on duct static and ±1 % on measured airflow. Controllers see the noisy values. `true_space_temp`, setpoints, commands, feedbacks, powers and route airflow are exact. A zero flow stays exactly zero.

Animation bindings read:

| Equipment | Point |
| --- | --- |
| Fan | `<ahu>.fan_speed_feedback` |
| AHU damper | `<ahu>.damper_feedback` |
| AHU coils | `<ahu>.cooling_output` / `.heating_output` |
| VAV damper | `<vav>.damper_feedback` |
| VAV coils | `<vav>.reheat_output` / `.cooling_output` |
| Airflow | `<ahu>.supply_airflow` / `<vav>.airflow` / `<duct>.airflow` |

## Alarms (`scripts/sim/alarm_manager.gd`)

`evaluate(simulation, dt)` uses only the read accessors. A condition must hold for its delay in simulated seconds before the alarm is raised, and the alarm clears when the condition clears. Acknowledgement persists while the alarm stays active. Equipment removed from the building drops its alarms.

| Alarm id | Condition | Delay | Severity |
| --- | --- | --- | --- |
| `fan_failure:<ahu>` | Fan enabled, no run proof | 20 s | critical |
| `high_temp:<zone>` / `low_temp:<zone>` | Served zone more than 2 K beyond its active setpoint while occupied, after the first 30 min of occupancy | 300 s | warning |
| `filter:<ahu>` | Filter ΔP above 180 Pa | 120 s | notice |
| `damper:<vav>` | Connected VAV with \|command − feedback\| above 20 % | 180 s | warning |
| `comm_failure` | Data interruption (other alarms are held while stale) | 30 s | critical |

API: `active`, `timers`, `list()` (active alarms as `{id, message, severity, acknowledged}`, most severe first), `summary()` ("ALARMS  0 • system normal" or "ALARMS  N active • M unacknowledged"), `acknowledge_all()`, `acknowledge(id)`.

## Checkpoints

`checkpoint()` saves version 3: time, scenario, speed, pause, accumulator, step counters and open doors. For every zone, dummy zone, AHU and VAV it saves all dynamic state: temperatures and mass, CO₂, setpoints, lighting override, loop integrators, actuator positions, trim & respond values, timers, filter loading and mode. It is plain JSON (string keys, finite numbers, bools, strings).

`restore_checkpoint()` is defensive: unknown ids and fields and invalid types are ignored, numbers are clamped to per-field ranges, and the setpoint deadband is enforced. Entries for ids that aren't configured yet are stashed and applied when `configure()` creates them, so restore-then-configure and configure-then-restore both work. Topology stays authoritative. Version-2 saves restore zone temperatures and setpoints from `rooms` (mass starts equal to air). An in-memory restore continues bit-identically; a JSON round trip continues to within rounding.

## Limits (deliberate simplifications)

- Sensible heat only: no humidity, latent loads, condensation or dehumidification. There is no plant: chilled and hot water are assumed available at 6.7 °C and 60 °C for any installed coil.
- Duct flow is a closed-form fan/orifice model with proportional bottleneck reductions, not a pressure-network solver. It can under-use spare capacity in complex networks. Fittings and diffusers limit capacity but add no pressure loss of their own.
- No return or relief fans, building pressurisation, stack effect through shafts, or per-wall orientation for opaque walls (sol-air uses the mean façade irradiance).
- One weekday schedule every day. No weekends, holidays, calendar or seasons beyond the scenario weather.
- VAV control follows GL36 structure (dual maximum, trim & respond, economizer high limit) with simplified request logic. It is not a verified GL36 implementation, and ventilation is not a 62.1 calculation.
- Internal gains, capacitances and occupancy per zone type are illustrative defaults, not measured data.

## Basis

- Sequences follow the structure of ASHRAE Guideline 36 (High-Performance Sequences of Operation for HVAC Systems): VAV reheat dual maximum, SAT and static trim & respond, economizer high limit, optimal start and setback modes.
- The zone model is a lumped air-plus-mass (RC) network in the spirit of the EnergyPlus Engineering Reference, with sol-air conduction, SHGC solar and a sensible air balance.
- Constants are chosen for believable gameplay dynamics and stated above; none is vendor or sizing data.

## Tests

`tests/simulation_fidelity.gd` builds topologies by hand: a two-classroom school wing with an unconditioned corridor and a shared trunk, a lobby with front doors, component-subset AHUs, a 40-zone building, and blank and junk canvases. It asserts:

- start-up (command before feedback, a smooth VFD ramp, minimum OA at occupancy);
- cooling day, economizer and cold morning reheat;
- thermostat response in both directions and setpoint clamping;
- exterior and interior doors and windows;
- each fault with its alarm;
- mass conservation and every capacity limit at every sample of a day;
- reconfiguration mid-run;
- unconditioned drift, setback and night cycle;
- installed-component gating;
- lighting sweep;
- the full point contract, including binding resolution;
- accessor copies and snapshot caching;
- bounded, finite full days;
- 1× vs 60× equivalence;
- checkpoint/restore in both orders, through JSON, and from garbage and version-2 data;
- determinism and performance.

Run:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/simulation_fidelity.gd [-- --timings]
```

It ends with `SIMULATION_FIDELITY PASS checks=N` (exit 0) or `FAIL` with the failed checks (exit 1).

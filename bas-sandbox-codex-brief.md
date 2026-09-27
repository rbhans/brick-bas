# BAS Sandbox — Codex build outline

## Build directive

Build a playable, single-player BAS/BMS construction sandbox in Godot. Users construct a small building, assemble simplified HVAC equipment, connect ductwork and piping, and walk through their creation while the equipment operates.

**Deliver a working offline demo first. Design for live Niagara data through my existing baskStream WebSocket API, but do not require a station to run, develop, or test the game.**

Implement the milestones in order. Finish the first playable milestone before expanding scope. Do not stop at an architecture document, empty scenes, or buttons backed by placeholder behavior. Keep a short `PROGRESS.md` stating what works, what was tested, and what remains.

This document's sizes, setpoints, and simulation behavior are proposed game-design defaults—not measured building data or engineering design guidance.

## 1. Technical direction

- **Engine:** Godot 4.7.2 stable, standard edition, typed GDScript. Pin the version in the README and verify the installed executable. Do not mix Godot 3 examples into the implementation. [1]
- **Delivery:** desktop-first; macOS is the first test target, with Windows-compatible project structure. Browser export, multiplayer, cloud accounts, and a hosted backend are outside the initial scope.
- **UI:** native Godot controls. Build a small, readable interface rather than embedding a web app.
- **Assets:** original, modular, brick-inspired geometry. Start with recognizable procedural models; refine using reproducible Blender Python generators and exported GLB assets. Godot supports the glTF/GLB pipeline. Blender must not be required to play the exported game. [4]
- **Dependencies:** keep them minimal. No runtime AI service, paid assets, or external database is necessary for the demo.

Use `GridMap` where it helps with repeated static floor tiles; it supports script-driven placement. Do not force doors, animated equipment, arbitrary duct routes, or all project state into GridMap. Use ordinary scenes for interactive objects. [2]

## 2. What the player can do

### Build mode

An overhead/orbit camera with a top-down option. A catalog contains Building, Equipment, Components, Duct, and Pipe categories. Placement has a ghost preview, grid snapping, rotation, and clear valid/invalid feedback. Support selection, move, duplicate, delete, and undo/redo.

Build floors and walls, insert door/window segments, and eventually connect floors with stairs. Include hide-roof, wall-cutaway, and show-services controls so overhead mechanical systems are accessible. Picking should respect hidden layers.

Start with one floor. Design floor IDs/elevations now; add actual multi-floor editing in the expansion milestone.

### Mechanical mode

Place an AHU/VAV template or assemble one from constrained modules. Connect equipment ports with duct or pipe routes. Select equipment to inspect its components, connections, point values, and served rooms.

**Both templates and assembled equipment use the same underlying definitions.** A template is not a separate, uneditable special case.

### Walk mode

First-person movement with collision, usable doors, and an easy return to build mode. A simple ramp collider can support visible stair geometry. Clicking equipment opens the same inspector used in build mode. Provide a reset-to-safe-location action.

### Simulation controls

A persistent DEMO/LIVE source badge; pause, 1×, 10×, and 60× demo speed; scenario selection; reset; and a compact alarm/event panel. Demo setpoints and overrides are editable. Live data is read-only in the initial integration.

## 3. Modular construction and asset kit

Use consistent dimensions: one world unit represents one meter; default architectural snap is 0.5 m, with a finer mechanical snap where needed. Document the coordinate/pivot convention. Prefer chunky, readable shapes over photorealism or exact LEGO reproduction.

| Category | Initial kit |
|---|---|
| Building | Floor, wall, corner treatment, door, window, ceiling/roof; stairs and landing in the multi-floor milestone |
| Equipment | AHU housing sections, VAV housing, small boiler and pump in the piping milestone |
| Components | Fan, filter, cooling/heating coil, damper, temperature sensor, valve, grille/diffuser |
| Distribution | Rectangular duct straights/elbows/tees/transitions; pipe straights/elbows/tees; risers |

Fans need separate rotating geometry and correct pivots. Dampers need movable blades. AHU housings need removable or translucent panels so the internals remain visible. Coil fins, filter pleats, and a recognizable fan are enough detail initially; do not leave every item as an indistinguishable cube.

Each asset definition specifies its dimensions, placement footprint, collision shape, moving subparts, attachment points, and ports. Equipment/component definitions also declare semantic point roles. Store generated assets and their generator scripts separately. Regeneration must not overwrite gameplay scripts.

Do not depend on importing an entire LDraw library. Existing models can be references or optional assets after their individual licenses are checked; record any shipped third-party asset in `ASSET_CREDITS.md`.

## 4. Routing and equipment assembly

Begin with orthogonal, waypoint-based routing: select an outlet, click bends/change elevation, then select an inlet. Generate straights and fittings from the route. Full automatic obstacle routing is not required.

A port has a stable ID, local position, direction, medium/service, profile/size, and connection limits. Validate compatibility. Route crossings do not create junctions automatically; branching requires a tee and an explicit graph connection. Moving/deleting equipment must update or invalidate its attached routes rather than leave invisible connections.

Default air-side topology:

`AHU → supply trunk → VAV branches → diffusers → assigned rooms`

Include an explicit simplified return-plenum relationship to the AHU; do not require detailed return-duct routing in the first milestone. Initially support a single-source, branching supply network. Reject unsupported loops with a useful message instead of pretending to solve them.

Build AHUs from a constrained sequence such as mixing/damper section, filter, coil, and fan. VAVs contain a damper, sensor roles, and optional reheat. Warn about incomplete assemblies without preventing the player from finishing them.

In the piping milestone, support a simple hot-water supply/return loop with boiler, pump, valve, and reheat coils. Require a connected loop for sustained heating, but do not attempt a general hydraulic solver.

## 5. Project and data architecture

Keep persistent building data, simulation, live-data transport, and visual scenes separate. Scene node names or transforms must not be the only source of truth.

```text
ProjectModel: floors, rooms, equipment, components, ports, routes, bindings
                         │
             connectivity / served-by relationships
                         │
DemoSimulation → DemoProvider ─┐
                              ├→ PointStore → visuals, inspector, trends, alarms
Niagara → BaskStreamProvider ──┘
```

Use stable IDs for every placed object and logical point. Model containment, physical connections, and served-by relationships separately. A nearby VAV does not automatically serve a room. Initially, the user defines simple room volumes and assigns each conditioned room to a VAV; automatic room detection can wait.

Define a small provider contract covering connection state, point discovery/descriptions, snapshots, subscription management, updates, and optional history. The demo uses that contract in-process; it does not need a local WebSocket server.

A normalized point update should include:

`point_id, value, value_type, unit, source_id, quality_flags, source_timestamp, received_at`

Preserve original Niagara status information alongside normalized quality flags. Keep command, actual feedback, and calculated/derived values distinct. For example, fan command ON is not proof of fan operation. When a visual uses command because feedback is unavailable, label it as command-based.

A binding maps an entity's semantic role, such as `supply_air_temp` or `damper_feedback`, to a provider reference. Live references include a connection ID and Niagara ORD, plus validated unit/type conversion. Do not hardcode station paths into fan or VAV scenes.

**Use project-wide DEMO or LIVE authority initially.** No automatic mixing or fallback. Missing/stale live values remain visibly unknown/stale; never quietly substitute simulated values. A copied live layout can be opened as an explicitly separate demo project later.

Save versioned JSON under the application's writable project location. Store geometry, graph connections, room assignments, bindings, and demo settings. Preserve a demo checkpoint—including clock, controller state, active faults, and random-generator state—when saving a running demo. Use temporary-file-and-replace saving and validate loads. Do not store credentials or session cookies in project files.

## 6. Demo content

Ship an empty lot and a ready-to-play small office. Add a two-story example after stairs and piping work.

The completed office demo should contain one AHU, six VAVs, six conditioned spaces, connected supply ductwork, return-plenum relationships, and approximately 100–150 useful points. Give the spaces different behavior: east office, west office, meeting room, open office, lobby, and equipment room. Labels and small furnishing cues should make them recognizable without building a furniture catalog.

Start the first milestone with a smaller two-room version. Expand it rather than replacing it with a disconnected showcase.

Suggested synthetic defaults: occupied heating/cooling setpoints of 20/22 °C, AHU supply-air target of 13 °C, and a weekday occupancy schedule. Use SI units internally with selectable °F/CFM display. Maintain an explicit unit registry, especially for percent-versus-fraction and absolute-temperature-versus-temperature-difference conversions.

| Group | Useful demo points |
|---|---|
| AHU | Enable command, fan run feedback, speed command/feedback, outdoor/return/mixed/supply temperatures, supply setpoint, airflow, duct pressure, filter pressure drop, damper/coil output |
| VAV/room | Space temperature, heating/cooling setpoints, occupancy, airflow target/actual, damper command/feedback, discharge temperature, reheat output |
| Hot-water expansion | Pump command/status, supply/return temperature, flow, boiler enable/output, valve command/feedback |

## 7. Simulation: cause and effect, not random animation

Implement a lightweight, deterministic game simulation. It is not a calibrated building model, CFD tool, load calculation, or commissioning instrument.

Use a fixed simulation timestep independent of render rate. Time acceleration runs more fixed steps; it must not increase the integration timestep until the system becomes unstable. Use deterministic iteration order and a seed. Optional measurement noise should be small, seeded, and disabled in tests.

Give each room an effective thermal capacitance, envelope heat transfer, occupancy/internal load, and optional simple solar exposure. A suitable deliberately simplified room model is:

```text
C_zone × dT_zone/dt =
    UA × (T_outdoor − T_zone)
  + Q_internal
  + rho_air × cp_air × volume_flow × (T_supply − T_zone)
```

Document units and tune the lumped parameters for understandable gameplay. Include thermal mass beyond the air alone. Make solar/internal gains and equipment capacities explicit rather than hiding everything in arbitrary temperature interpolation.

Implement simple bounded control behavior: room demand changes airflow target; VAV control changes damper command; actuator feedback follows with a lag; AHU control changes fan/coil output. Include deadbands and saturation. A disconnected branch receives no delivered airflow even if its room assignment still exists.

Allocate supply through the supported branch network without creating air at junctions. Total branch delivery cannot exceed available AHU flow, and intermediate branch limits must be respected. Fan shutdown/failure reduces delivered air after a short decay; filter restriction reduces capacity/increases indicated pressure drop. Reheat affects discharge air only when airflow and an applicable heat source are available. Guard against division by zero and invalid values.

Store physical state separately from measured point values. A biased temperature sensor should mislead the controller, not magically change the room's true temperature.

Provide immediately useful history. Generate a consistent previous-day history fixture using the same simulator and ship its matching final state, rather than drawing unrelated random curves. Retain a bounded rolling history, for example 24 simulated hours sampled every 30 seconds. Mark reset/source-change boundaries instead of connecting unrelated history into a continuous line.

### Playable scenarios

| Scenario/control | Expected visible result |
|---|---|
| Normal weekday | Startup, occupancy changes, VAV modulation, and evening setback |
| Hot afternoon | Outdoor/solar loads increase; affected zones ask for more cooling |
| Meeting fills up | Meeting-room load rises and its VAV responds |
| Fan failure | Command can remain ON while feedback/airflow fall; rooms drift; alarms follow |
| Damper stuck at 25% | Command moves, feedback stays stuck, airflow is constrained |
| Dirty filter | Pressure-drop indication rises and available airflow falls |
| Sensor bias | Measured and true room temperatures diverge; control responds to the measurement |
| Data interruption | Source/quality indicators change without silently inventing replacement values |
| Pump failure, later | Hot-water reheat loses sustained capacity while air-side operation can continue |

Make faults reversible. Reset must restore the initial seed/state. Demo alarms need configurable thresholds, delays, and hysteresis; acknowledging an alarm must not clear an ongoing fault.

## 8. Niagara integration: plan now, connect later

The existing source is `rbhans/bask-stream`; read its current `README.md` and `docs/THIRD_PARTY_API.md` before implementing the adapter. The reviewed documentation specifies an authenticated Niagara web session, `/stream/health`, and **binary MessagePack maps over `/stream` WebSocket**, not JSON text frames. It also directs clients to inspect `capabilities` instead of assuming all deployments match the repository version. [6]

Godot's `WebSocketPeer` supports binary frames and desktop handshake headers, but a WebSocket transport alone is not a Niagara login implementation or a MessagePack codec. Reuse or port the repository's documented client flow, select and test a compatible codec, and keep both outside gameplay code. Godot web exports have different handshake restrictions; browser support is not part of this milestone. [3][6]

Integration sequence:

1. Implement and test the documented authentication/session flow and health check. Keep secrets out of logs and saved projects. Require verified TLS or an explicitly configured trusted station certificate.
2. Connect; verify with `ping`; inspect `capabilities` and advertised limits.
3. Discover with bounded browse/search calls and allow manual point-to-role mapping. Do not assume every station has reliable equipment tags.
4. Load initial values with `read`; maintain only required subscriptions using supported subscription operations and leases. A point needed for visible animation is active even when its inspector is closed.
5. Decode updates into the same PointStore used by demo mode. Handle request IDs, push messages, errors, enum metadata, units, timestamps, and status.
6. Support reconnect/backoff, session expiry/revocation, subscription renewal/release, and snapshot resynchronization. Do not assume queued or replayed COV updates will restore a complete state.

A constant point is not necessarily stale merely because no change-of-value event arrived. Separate transport/session health from last-value-change time; use bounded resynchronization where appropriate. Never refresh a source timestamp just because the renderer displayed a cached value.

**The live provider must reject writes in code, not just hide buttons.** Demo scenario actions, thermostat edits, alarm acknowledgment, and equipment failures must never issue station writes or alarm actions. Future writeback is a separate feature requiring explicit scope and safeguards.

Until station access is provided, test against protocol fixtures/mock transport and label the adapter as unverified against a real station. Do not modify the Niagara module to accommodate the game unless separately requested.

## 9. Implementation milestones and acceptance gates

| Milestone | Deliverable | Done when |
|---|---|---|
| 1 — First playable slice | Two rooms, one AHU, two VAVs, connected demo system, build/orbit and walk cameras, inspector, basic floor/wall placement, temperature/setpoint controls, fan-failure scenario | Fresh checkout launches without station credentials; rooms respond to setpoints; fan failure affects airflow and temperatures; the player can place a wall and walk around it |
| 2 — Building editor | Floors/walls/doors/windows, selection/transform tools, room assignment, placement validation, undo/redo, versioned saves | A user can create a small floor plan, save/reopen it, and retain stable identities and room assignments |
| 3 — Mechanical construction | Editable AHU/VAV assemblies, port snapping, duct routing/branching, graph validation, animated components | A newly assembled system conditions an assigned room; deleting/reconnecting its duct changes actual simulated delivery |
| 4 — Demo expansion | Six-zone office, scenarios, trends/alarms, stairs/floor navigation, simple hot-water piping demo | Scenarios are reversible; multi-floor navigation works; disconnecting the hot-water loop removes sustained reheat; saved demos resume coherently |
| 5 — Polish and packaging | Refined modular models, cutaways, readable labels, input help, performance pass, desktop export instructions | The demo is understandable without opening the editor, and verified exports run on the platforms actually tested |
| 6 — Future live connection | Read-only baskStream provider, mapping UI, source/quality states, reconnect tests | Mock transport tests pass; live-read verification is reported separately; switching mode cannot cause demo actions to reach Niagara |

Do not postpone the playable simulation until after the entire asset library is complete. Do not implement multiplayer, a controls-programming language, BIM import, full energy modeling, or an asset marketplace during these milestones.

## 10. Suggested repository layout

```text
project.godot
scenes/          # app shell, world, cameras, equipment, UI
scripts/model/   # persistent project definitions and stable IDs
scripts/build/   # tools, snapping, commands, undo/redo
scripts/network/ # physical connectivity and delivery allocation, not sockets
scripts/sim/     # clock, room/equipment models, controllers, faults
scripts/data/    # point store, bindings, providers, Niagara transport
scripts/ui/      # inspector, catalog, trends, alarms, source indicators
assets/          # generated/imported models and materials
content/         # kit definitions, templates, scenarios, demo fixtures
blender/         # reproducible asset generators
tests/           # headless tests and transport fixtures
README.md
PROGRESS.md
ASSET_CREDITS.md
```

Keep this structure only as deep as implementation needs. Avoid creating dozens of empty abstractions before the first scene runs.

## 11. Verification and handoff

Provide an executable headless test entry point. Godot supports command-line/headless workflows; verify the commands against the pinned version. Example invocations once the test runner exists: [5]

```sh
# GODOT is the path to the installed Godot executable.
"$GODOT" --headless --path . --editor --import
"$GODOT" --headless --path . --script res://tests/run_tests.gd
```

Test deterministic simulation, stable IDs/save round-trips, undo/redo, compatible port connections, disconnected branches, flow limits, unit conversions, actuator command-versus-feedback behavior, fixed-step time acceleration, fault reset, and LIVE-mode write rejection. Include malformed-message and reconnect cases for the future adapter.

Also perform actual visual/input checks when the runtime is available: placement preview alignment, door/stair collision, camera transitions, equipment animations, readable inspector labels, cutaways, and save/reload. Headless parsing is not proof that these work. Report any checks that could not be performed.

At each milestone provide the working changes, exact launch/test commands, a short demonstration checklist, and known limitations. Measure performance on the available machine rather than claiming an untested frame rate or platform.

**Start by implementing Milestone 1. Make it playable and verify it, then proceed through the remaining offline milestones. Plan the provider boundary now, but do not let Milestone 6 or missing station access block the offline release.**

## References checked for this brief

Technical references support engine/API facts, not the proposed simulation defaults. Recheck the current project documentation when implementing the live adapter.

[1] Godot 4.7.2 stable maintenance release, August 18, 2026:
`https://godotengine.org/article/maintenance-release-godot-4-7-2/`

[2] Godot GridMap class documentation:
`https://docs.godotengine.org/en/stable/classes/class_gridmap.html`

[3] Godot WebSocketPeer class documentation:
`https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html`

[4] Godot available 3D formats and asset import documentation:
`https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html`

[5] Godot command-line tutorial:
`https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html`

[6] Owner's baskStream README and third-party protocol guide, reviewed September 13, 2026. The protocol file returned blob SHA `9057755a8653a7ba9098e5da0dc9030b1b9458d0`; this identifies the inspected file, not a pinned repository commit:
`https://github.com/rbhans/bask-stream/blob/main/README.md`
`https://github.com/rbhans/bask-stream/blob/main/docs/THIRD_PARTY_API.md`

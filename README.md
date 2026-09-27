# BRICK / BAS

A brick-built building sandbox where the building's HVAC actually runs. Lay out rooms like a house-building game, zone them with air handlers, VAV boxes, ductwork and thermostats built from LDraw parts, then watch a realistic simulated BAS drive the fans, dampers, coils and airflow, or walk around inside as a minifigure.

Built with typed GDScript on **Godot 4.7.2 stable** (standard edition). One world unit is one metre; one enlarged LDraw stud is 0.5 m.

## Run

Desktop:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Browser (demo simulation only):

```sh
npm run web:build
npm run web:serve
```

Then open `http://127.0.0.1:8060`. Upload the contents of `dist/web/` to any static host to publish. Saves stay in the player's browser; use **Download backup / Import backup** to move them. See [web hosting and save behavior](docs/WEB_HOSTING.md).

Choose **New game → a starter**: the *Corner workshop*, *Neighborhood office*, *Elementary school* or an *Empty lot*. Every starter comes furnished, zoned and already running. Change anything.

## Modes

**Build** works like a house-building game on a 2.5 m tile grid:

- **Room**: drag a rectangle to get walls and a floor in one stroke. **Wall** drags runs along grid lines; Ctrl-drag (or *Remove walls*) erases, taking any door or window in them.
- **Floor** paints finishes; Shift-click floods a whole room. **Door / Window** snap into a hovered wall section, and **R** flips the swing.
- **Furniture** (42 pieces) and **Outdoor** items snap to studs and refuse to overlap. Rooms are detected automatically; name them and set their type on the room card.
- **Sledgehammer** and **Paint** work on single pieces or dragged areas. Every drag is one undo step (Ctrl+Z / Ctrl+Y).
- **V** cycles walls: up, cutaway around the cursor, or down.

**Equipment** is the HVAC layer. The tray's note says what to do next.

- **Air handler**: click it and place it (in a mechanical room or just outside). The ghost labels **Outside air in** and **Supply air out**; **R** turns it.
- **Zone a room**: click a room and it gets a VAV sized to its floor area, one or two ceiling diffusers, a thermostat by the door and all the ducts, in one undo step. If no free outlet is close, it **taps the main**: a trunk cross is spliced into the nearest supply duct and the room branches off it, so every room you add finds air.
- **VAV box, Diffuser, Trunk cross, Branch tee**: place one and it ducts itself. A VAV or fitting hooks onto a nearby free outlet or taps the main. A diffuser hooks onto its room's VAV, adding a branch tee (and nudging the automatically placed diffusers) when the VAV's outlet is taken.
- **Change a unit** from its card: *Edit components* opens the workbench (damper, filter, coils, fan, in any order). *Connect supply* re-hooks a loose piece, and *Open casing* shows the internals.
- **Move** a unit and its ducts re-route with it. If it would land on another duct, the move is refused. **Delete** takes a unit's ducts with it; pulling a trunk cross out of a main re-joins the main.
- **Duct run** is for hand-routing: click one socket, then another. **PageUp/PageDown** change elevation, and clicks add bends. A red **Reroute duct** marker flags a run that no longer clears.
- **B** toggles the BAS overlay, which tints rooms by temperature against their setpoints. Select anything for a live readout and trend chart. The alarm button lists active alarms with **Show** and **Acknowledge**.

**Explore**: **WASD** walks, **Shift** runs, **Space** jumps, drag to look, wheel to zoom. Doors open as you walk into them and close behind you. **E** only offers things that really do something: sit down, adjust a thermostat (**+ / −** in 1 °F steps), open an AHU access door, lift a VAV's casing to watch its damper and reheat coil, or show the airflow at a diffuser (its prompt reads live CFM and supply temperature). Overhead ducts fade as you pass under them. **Tab** returns to Build.

Camera in Build/Equipment: right-drag orbits, middle-drag pans, wheel zooms toward the cursor, **WASD** pans, **Q/E** rotate 45°, **Home** frames the lot, **F** frames the selection.

## The simulation

Demo data comes from a deterministic, fixed-step model built to behave like a real VAV reheat system:

- dual-maximum VAV reheat control, supply-air temperature and duct static pressure trim & respond, and an airside economizer;
- demand-controlled ventilation from CO₂, optimal start, occupied and unoccupied setpoints;
- two-node zone thermal mass, solar gain through each room's actual windows by orientation, and internal loads by room type;
- actuator travel times, fan spin-up, filter loading, and fault scenarios such as a failed fan, a dirty filter, a stuck damper or a biased sensor.

Everything is displayed in US units (°F, CFM, in. w.c., ft, sq ft); the model itself runs in SI and converts only for display (`scripts/core/units.gd`). The **Point links** editor shows each point's raw engineering units, since its mapping ranges must match the incoming data.

Air only reaches a room through the ducts you actually connected: AHU outlet → trunk crosses/tees → VAV → diffusers. Each VAV serves the room its diffusers sit in. Model details, point names and limits are in [docs/SIMULATION.md](docs/SIMULATION.md). This is a game model, not an engineering or commissioning tool.

The desktop build keeps the read-only Niagara/baskStream connection path (**Menu → Data source**; the password stays in memory only). It is tabled until the baskStream SDK is final. The browser build is demo-only.

## Test

Logic tests run headless:

```sh
godot=/Applications/Godot.app/Contents/MacOS/Godot
$godot --headless --path . --editor --import --quit
$godot --headless --path . --script res://tests/run_tests.gd            # unit suite
$godot --headless --path . --script res://tests/build_tools.gd          # build + HVAC tools via real input events
$godot --headless --path . --script res://tests/explore_mode.gd         # starters seed connected HVAC; doors, seats, thermostats
$godot --headless --path . --script res://tests/browser_saves.gd        # save/import/migration
$godot --headless --path . --script res://tests/simulation_fidelity.gd  # control sequences and physics
$godot --headless --path . --script res://tests/geometry_overlaps.gd    # no coplanar bricks (z-fighting) in any starter
```

`tests/connection_smoke.gd` needs `node tests/mock_baskstream_station.mjs` running first.

Rendered captures: `Godot --path . -- --template=office --equipment --capture=/tmp/office.png`. Other flags (`--view=`, `--explore`, `--select=`, `--speed=`, `--walls=`) are parsed in `_ready()` of `scripts/game.gd`. `tools/bake_starter_cards.gd`, `tools/bake_arch_thumbnails.gd` and `tools/bake_catalog_thumbnails.gd` regenerate the UI thumbnails from the real assemblies.

## Layout

- `scripts/core`: the plan grid and brick helpers.
- `scripts/render`: batched brick rendering, cutaway shaders and the stage.
- `scripts/model`: the project model and saves, room detection, starter templates, the furnisher and the HVAC seeder.
- `scripts/build`: architecture rendering, the camera, build tools, equipment models, the duct router and the zone planner.
- `scripts/network`: the supply-air graph and room-to-zone topology.
- `scripts/sim`: the demo simulation.
- `scripts/data`: point store, trend history and data source.
- `scripts/explore`: the minifigure and interactions.
- `scripts/ui`: the HUD, workbench and trend charts.

## Assets

150 official LDraw parts (CC BY 4.0) baked to meshes by `tools/ldraw_to_obj.py`, plus Kenney CC0 interface sounds. Provenance is in [ASSET_CREDITS.md](ASSET_CREDITS.md) and `assets/third_party/ldraw/selection.json`. LEGO is a trademark of the LEGO Group, which does not sponsor or endorse this project.

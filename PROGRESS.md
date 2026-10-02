# BRICK / BAS progress

Updated: 2026-10-01

## Current: flicker and Explore hiding (2026-10-01)

- **Flicker (z-fighting)**: a new check, `tests/zfight.gd`, looks at everything the renderer draws, at triangle level and any orientation, procedural meshes included. The old `geometry_overlaps.gd` only saw upright LDraw boxes, and missed most of it. On first run it found 172, 395 and 809 overlapping pairs in the three starters. The causes:
  - Every duct's lid tiles were exactly as wide as the shell, so their sides doubled its side walls along the whole top edge (the band you could see shimmering).
  - At bends the shell's lid cut-outs were placed by fraction along mitred edges instead of distance along the run. On risers that left a 0.3 m overlap on one side and a hole on the other.
  - Glass draws both sides, so its underside fought whatever it rested on: windows, the lamp, VAV and AHU glass.
  - Pieces of one model sat flush: cupboard drawers, bookshelf books (they overlapped), AHU and VAV details, fitting lids and collars.
  - Some furniture sat inside walls or the ceiling: the park bench backrest (0.2 m behind its own footprint), the whiteboard (0.3 m above the wall top) and the chalkboard (into the ceiling diffusers).
- **Fixes**:
  - Duct walls are now cut by distance along the run, and the outer side walls stop at the lid band.
  - Glass is inset 3 mm (shader and material).
  - Bench, bookshelf, whiteboard, chalkboard and lamp bulb recipes are corrected.
  - `scripts/render/coplanar.gd` settles what's left. Where two pieces share a face plane, the smaller moves back 2.5 mm, too little to see. It runs per model when bricks are batched (with the walls, floors and furniture already there held still), and per equipment unit with its neighbours. Results are cached by content, so a rebuild only pays for what changed: cold, about +0.5 s for the school's equipment; an edit, a few ms.
- **Result**: the three starters are down to 24, 34 and 85 pairs, nearly all slivers under 0.03 m². Measured as flicker you'd see (`tools/flicker_probe.gd`, a millimetre camera creep), the web renderer went from 1–2.5 % of pixels flipping per frame on ducts, fittings and VAVs to about 0 % on the VAV, fittings and lamp. Ducts are left with edge shimmer only, 0.1–0.3 %, no patches. On desktop it's 6–30× lower.
- **Explore hiding**: overhead ducts, VAVs and fittings used to fade (web: vanish) whenever the minifigure was within 6.5 m horizontally, with one threshold both ways. A whole duct run blinked as you crossed it. Now a unit gives way only near the camera's line to the minifigure, hides within 1.1 m of it, and comes back after 0.6 s more than 2 m clear. Whatever you're about to use stays solid. `explore_mode.gd` checks it deterministically; without the hysteresis the duct blinks 12 times in 12 steps and the check fails.
- Verification: unit 180, build tools 32, explore 31, browser saves 36, geometry 3, live station 30, career 295, simulation 291, z-fight (3 starters), bridge 8, all PASS. Not checked: the web build in a browser (the Compatibility renderer was measured natively).

## Current: UI execution pass (2026-10-01)

Same toy-builder identity (charcoal cards, cream parts tray, yellow selection, red brand brick), built properly on one design system: `scripts/ui/toy_theme.gd` holds the palette, type scale, radii and every button, field, tab, list, scrollbar and dialog style, and all panels take their values from it.

- **Type**: Geist (OFL, bundled) on desktop and web, at fixed weights through the font's `wght` axis. The axis has to be keyed by its numeric tag: a `"wght"` string key is silently ignored.
- **Layout** (1440 × 900, 24 px margins): brand, mode tabs and actions on top. A single tool rail on the left: tools, a divider, then view toggles with a ring rather than a fill, so only the active tool is solid yellow. Clock card, a centred tray that no longer overlaps it or shows a scrollbar, and data and alarm pills bottom right. A status toast fades out under the mode tabs.
- **Context card**: the room's name as its title (it showed the floor finish), a subtitle, a Details button, and labelled two-column action chips (Delete in red) instead of bare icons.
- **Explore**: the use prompt is a 2D card with an E keycap beside what you face, replacing the large floating 3D label. Key hints are keycaps.
- **Panels**: the menu, alarms (sizes to its rows; a friendly empty state; separate show and acknowledge buttons), thermostat, details (labelled fields, a swatch grid that marks the current colour), BAS programming (aligned form rows), the service panel (tests and repairs with their time and cost aligned right), the job panel, the workbench and the tour all share the same header, section and footer patterns. Each has one yellow primary action.
- **Pages**: the title screen, Creative starters, job board (standing, rank progress, job cards), briefing and results were rebuilt as one card per page, with an eyebrow, a heading, the content, and a footer of actions.
- **Trends**: fit the window to the history they have (no sliver at game start), with the scale in a gutter and wrapping legends.
- `tools/ui_screens.gd` (was `career_screens.gd`) captures 13 Creative states as well as the career and live sets. The font license ships with the web build as `Font-LICENSE.txt`.

Verification (2026-10-01): all suites pass on the final code (unit 180, build tools 32, explore 26, browser saves 36, geometry 3, live station 30, career 295, simulation fidelity 291, bridge 8). Every Creative, career and live state was re-rendered with `tools/ui_screens.gd` and compared with the pre-pass captures. The web export packs Geist. In the in-app browser the title screen, starters, HUD, tour and Explore prompt render with the bundled font and no console errors. Not checked: Safari and Firefox, and a touch screen.

## Current: Career mode, live station data, simulation upgrades (2026-10-01)

The sandbox is now a game with two modes. **Creative** is the existing sandbox, on simulated or (desktop) live station data. **Career** is a contracting business with three kinds of work. Design: [docs/CAREER.md](docs/CAREER.md). Live data: [docs/LIVE_DATA.md](docs/LIVE_DATA.md).

- **Career**: a job board of ten contracts in three tiers, plus endless on-call service calls.
  - *Install*: an empty-of-HVAC building to design on a budget and commission over a time-lapsed day.
  - *Service call*: hidden faults that start during the morning, comfort calls, tests and repairs in person, and a deadline; closing out plays out the rest of the day.
  - *Tune-up*: re-program a wasteful building and verify a full day against its as-found bill.
  - Stars, money, ranks and tier unlocks persist in `user://career.json`.
  - In a job the building is the client's: architecture is locked, HVAC is editable only while designing an install, and jobs aren't saved part-way.
- **Simulation**:
  - BAS programming (`set_controls`): schedule, optimal start, SAT and static resets or fixed values, economizer, DCV, VAV minimums. People now keep their own hours whatever the schedule says.
  - Faults aimed at one piece of equipment (`set_faults`): stuck dampers and valves, broken belt, loaded filters, sensor bias.
  - Energy and comfort meters, time-lapse to 1800×, a SAT-high alarm, and a filter alarm normalized to airflow.
  - Classroom ventilation: DCV outdoor air up to 70 %, VAV CO₂ reset up to 80 %; "fresh air" is judged at 1,400 ppm.
- **Sizing bug fixed**: every duct was capped at 1.2 m³/s, so each starter's AHU discharge duct starved the building (the school held setpoint ~10 % of a normal day). Ducts, fittings and diffusers are now sized for the VAVs they carry. VAVs are sized from room load (people, plug, lights, envelope, sun on glass), and seeded AHUs at 0.95 × their VAVs. All three starters now hold setpoint on a normal day.
- **Live data**:
  - The baskStream SDK is vendored (`vendor/baskstream-sdk`, upstream `5e11884`, API 1.7). The bridge is rewritten on it: read-only allowlist, token, origin refusal, random port, exits with the game.
  - Game side: `LiveStation` provider, a station browser and search, `PointMatcher` auto-mapping, live readouts and room temperatures, trends backfilled from station history, and station alarms. `tools/demo_station.mjs` is a stand-in station.
  - The hand-rolled SCRAM/MessagePack path, its fixture and the old mock are removed.
- **UI**: title screen (Career / Creative), job board, briefings with objectives, results, the job panel, service panel, BAS programming panel, and an AHU size and price on the workbench. Stars and check marks are drawn, because the web font has no ★ ✓ ✗ glyphs. Several pre-existing → ▶ ● glyphs that rendered as boxes on the web are replaced too.

Verification (2026-10-01, Godot 4.7.2, Apple M4 Max):

- PASS: unit 180, build tools 32, explore 26, browser saves 36, geometry 3, simulation fidelity 291 (54 new: controls, targeted faults, meters, schedule vs people, time-lapse), career mode 295, live station 30, bridge (Node) 8. `tools/compile_check.gd` loads all scripts.
- An independent review of the diff found 12 issues. All are fixed and have regression checks:
  - edits from a tool or workbench left open when a job phase changes;
  - repairs running past the deadline;
  - float32 precision of live trend times;
  - the bridge not starting from a path containing a space;
  - a recursion when the bridge dies mid-login;
  - a station session leaked by an abandoned login;
  - a slow connect landing during a career job;
  - importing a backup during a job;
  - older saves inheriting the last building's BAS programming;
  - hand-typed `station:|` ORDs never receiving values;
  - async links landing on the wrong piece;
  - faults testable before their onset.

  The bridge token now goes by environment variable rather than on the command line.
- Career calibration (competent play, from `tests/career_mode.gd`): service calls end with 3 stars. Tune-ups cut the office from $13.09 to $2.77 a day (79 %) and the school from $63.68 to $26.79 (58 %). Reference installs land at 86–100 % comfort and under their energy targets.
- Web export builds. In the in-app Chromium the title screen, job board and briefing render with drawn stars, and a service job starts and time-lapses with no script errors. That pane ran at 1.3 fps (its own GL path), so the time-lapse budget now grows with frame time.
- Not verified: frame rate in an ordinary browser, a real Niagara station (the bridge is tested against the SDK's protocol through the demo station), Safari/Firefox.

## Current: ready for the site (2026-09-26)

- **Browser performance:** the browser renderer now batches all equipment bricks together (hidden per unit through instance transforms) and batches fitting and diffuser lids. In the school, draw calls fall from 1,944 to 1,317 in Explore and from 1,877 to 1,281 in Equipment (measured natively with the Compatibility renderer). Game-script cost is under 1 ms per frame. Graphics Auto, High and Low were added, with an automatic switch to Low when the frame rate stays low.
- First-run tour, persisted settings (graphics, motion, sound, tour), a mobile/touch note, the tab title fixed to "BRICK / BAS", and whitelisted deep links.
- Packaged into `../personal-site/public/demos/brick-bas` with `tools/package_personal_site.mjs`. The engine is unchanged (same hash); `index.pck`, `index.html`, `bundle.json` and the credits changed. The site's `npm run validate` passed (19 tests). **Not deployed.**
- Not verified: frame rate in a browser on ordinary hardware (only this machine's native numbers), Safari (access declined), and Firefox (not installed).

## Current: equipment building flow (2026-09-26)

A scripted walkthrough (empty lot → two rooms → air handler → zoning → extra pieces) found the flow dead-ended: the first zoned room took the air handler's only outlet, so the next room, and any hand-placed VAV, had nothing to connect to. Changes:

- **Tapping the main** (`ZonePlanner.tap`): when no free outlet is near, a trunk cross is spliced into the nearest straight run of supply duct and the new branch comes off it. Zone a room, placing a VAV, tee or cross, and *Connect supply* all use it. Diffusers tap their VAV's discharge, or have it re-planned through a branch tee (turning diffusers, or nudging automatically placed ones, when needed).
- **Tidier runs:** VAV spots are tried in all four orientations, nearby sockets are compared, and the shortest, least-bent supply run wins.
- **Moves and deletes keep the system whole:** moving a unit re-lays its ducts (a VAV takes its whole discharge along), and a move that would sit on another duct is refused. Deleting equipment removes its ducts, and pulling a trunk cross bridges the main. Ducts now also clear diffusers and fittings (they could pass through them before).
- **UI:** Air handler and VAV box place directly with a standard design, and *Edit components* on the card opens the workbench, which now fits the screen and frames the unit. The tray is simpler (one VAV, plain names, clear tooltips) with a "what's next" note. Placement ghosts label their air in and out. Card actions wrap instead of running off the screen.
- Verification: `BUILD_TOOLS` now 28 checks, covering the second-room tap, diffuser auto-connect, ducts following a moved VAV, the cross-delete bridge and undo. The rest of the suite passes unchanged, with no script errors, and starters still seed 2/2, 6/6 and 10/10.

## Current: flicker, real interactions, US units (2026-09-26)

- **Flicker (z-fighting)**: parking stripes were embedded in the asphalt and doubled between neighbouring stalls; furniture and outdoor decor overlapped each other, walls and windows; a few furniture and AHU models had parts sunk into each other. All fixed. Outdoor decor now keeps clear of tree canopies and other pieces, and wall boards reserve the floor below them and span only plain wall. Camera near planes moved out (build 0.5 m, Explore 0.2 m) for about 5× better depth precision in the web renderer. `tests/geometry_overlaps.gd` fails on any visible coplanar overlap; it caught the stripe bug when that was reintroduced on purpose.
- **Explore interactions**: decorative "E to…" prompts on furniture (chalkboards, computers, printers…) are gone. What's left: doors, seats, thermostats, AHU access doors, VAV casings (lift to watch the damper and coil) and diffusers (live CFM and supply temperature; E shows the airflow). `explore_mode.gd` asserts only those kinds are offered.
- **Units**: all player-facing text is in °F, CFM, in. w.c., ft and sq ft through `scripts/core/units.gd`; thermostat steps are 1 °F. The simulation, saves and points stay SI.
- Verification: unit 171, build tools 21, explore 26, browser saves 36, simulation 237, geometry overlaps 3/3 (all PASS, no script errors); web export rebuilt.

## Current: building and HVAC rework

The pre-rework source is backed up at `../brick-bas-backup-20260925-pre-rework.tar.gz`. Everything below this section describes the previous build and is kept as history.

Completed:

- **Building**: new 2.5 m tile plan grid with walls on grid edges, running-bond brick courses with interlocking corners, and batched rendering (MultiMesh per part with per-instance colour and a GPU cutaway: walls up, cutaway around the cursor, or down). The Room, Wall, Floor, Door/Window, Place, Sledgehammer, Paint and Select/Move tools all use ghost previews, stud snapping and occupancy, and one undo step per drag. Rooms are detected automatically and can be named and typed.
- **Starters**: the Corner workshop, Neighborhood office and Elementary school were redesigned and come furnished (42 furniture pieces, laid out per room type), landscaped, and seeded with a complete, connected VAV system. The office and school have plant rooms sized for their air handlers; each AHU discharges toward the end wall and its main loops back along the corridor, so every branch is downstream of the unit. The studio and the school gym use packaged units on outdoor pads. Starter cards are rendered from the real starters (`tools/bake_starter_cards.gd`).
- **HVAC building**: *Zone a room* plans a VAV sized from floor area, one diffuser (or a branch tee and two spread diffusers in rooms of 80 m² or more), a thermostat by the door and all ducts, in one undo step. It first tries a straight branch off the supply socket, then lets a small room's VAV hang over a neighbour's ceiling, as real VAVs do over corridors. The duct router tries straight runs, then L/Z shapes, then A* on three ceiling planes, and every candidate is re-checked against walls, casings and other ducts. Ducts butt onto equipment collars. Unused fitting outlets get blank-off caps.
- **Equipment models**: more realistic AHU, VAV, diffuser, tee, cross and thermostat assemblies built from LDraw parts. AHU and VAV controller screens show live values: supply temperature and fan speed on AHUs, damper position and discharge temperature on VAVs. Static pieces are batched per unit and static duct and fitting meshes merged per material.
- **Simulation**: rooms become thermal zones (window area by orientation, neighbours, exterior doors); each VAV serves the room its diffusers sit in. The model covers dual-maximum reheat, SAT and static-pressure trim & respond, an economizer, DCV, optimal start, two-node zones and CO₂ (details in `docs/SIMULATION.md`). Trend history uses packed arrays.
- **Explore**: doors open as you walk into them and close behind you; the minifigure can sit on seats, open AHU access doors, read equipment and adjust thermostats; overhead HVAC fades near the player.
- **Saves**: format v2 with an id index; v1 saves migrate on load.

Fixed during integration: equipment batches were built with world transforms under moved unit roots, so rotated units drew their static pieces a second time elsewhere on the site. RouteNetwork never passed air through 4-way crosses. Straight duct stubs between facing sockets folded back over their auto-inserted leads. Standing up cleared the shared seat dictionary, leaving an empty interactable.

Actual verification (2026-09-26, Godot 4.7.2, Apple M4 Max):

- PASS: `UNIT_TESTS checks=171`, `BUILD_TOOLS checks=21` (now includes placing an AHU, one-click zoning, a live connection in the sim, and undo/redo of the whole zone), `EXPLORE_MODE checks=20` (every starter's VAVs connected; doors, seats, thermostat), `BROWSER_SAVE_TESTS checks=36`, `SIMULATION_FIDELITY checks=237`, and `CONNECTION_SMOKE` against `tests/mock_baskstream_station.mjs`. No script errors in any log.
- Seeding: studio 2/2 VAVs connected (8 ducts), office 6/6 (19 ducts), school 10/10 (38 ducts); each starter seeds in under 0.2 s headless.
- Frame rate, 4-second steady-state samples, windowed: Forward+ holds the 120 Hz display cap in every mode for the office and school. With the Compatibility renderer (what the browser uses) the school measures 244 fps in Build (788 draws), 178 fps in Equipment (1,877 draws) and 84 fps in Explore (1,942 draws). Those are native OpenGL numbers, not browser measurements.
- The web export builds. In the in-app Chromium browser it loaded the home screen and new starter cards, ran the office in Equipment mode with a live room card and trend, and entered Explore. The console showed no errors.

Remaining limits:

- Browser frame rate on typical laptops has not been measured. Explore in the school is the heaviest case (about 800k triangles from the low third-person view).
- Walls are single-storey (3.6 m); no stairs or second floors. Doors and windows fill a whole 2.5 m wall section.
- The live Niagara/baskStream path is tabled until the SDK is final; the desktop connection code and its mock test remain.
- The browser page title still reads "BAS Sandbox" (`config/name` in `project.godot`). Renaming it would move desktop `user://` saves, so it was left alone.

## Current: published browser game on personal site

Completed:

- Published the current demo-only Web export at `https://robboborben.xyz/demos/brick-bas/`. The existing project page at `/projects/brick-bas` now has a **Play in browser** link and desktop/browser-save guidance. The game opens full-page, outside the site's app router.
- Added `tools/package_personal_site.mjs` to copy only game assets and required licenses into the site's isolated demo directory. It validates decoded hashes and the host's per-file limit. The engine is unchanged: 39,514,754 bytes raw, 10,153,810 bytes stored as gzip. A small route in the existing site Worker delivers it with proper WASM MIME/encoding and an uncompressed fallback. Cloudflare guidance informed this compressed-delivery approach; no additional account, save backend, database, or station gateway was added.
- Preserved existing personal-site work. Deployment uploaded 15 new game files; 233 existing assets were reused. Published Worker version: `c93fe4e1-9fd8-497a-bef1-0fc50ce234e1`, serving both existing custom domains.

Actual verification:

- PASS: personal-site `npm run validate`: TypeScript, ESLint, production build, and all 17 tests. New coverage checks the rendered project link, bundle inventory/decoded SHA-256 hashes, file-size limits, gzip/identity responses, HEAD, conditional responses, and error/method handling. Cloudflare deployment dry-run and actual deployment passed.
- PASS: actual local Workers preview and public HTTPS engine responses, for both gzip and identity encoding, return HTTP 200 with `application/wasm`; all four decoded SHA-256 hashes match the original exported engine.
- PASS: in-app Chromium followed **Play in browser** from both local and deployed project pages, loaded the welcome screen, and started Little workshop with rendered LDraw geometry and live demo readouts/airflow. Saved the test workshop, reloaded the entire page, and restored it with **Load saved build**, on both origins. Both origins initially had no manual save; no existing user save was overwritten. Reviewed browser logs returned no warnings/errors.
- The deployed menu exposes demo scenarios and browser Save/Load/backup controls, with no Niagara connection form. No station was contacted.

Remaining / delivery boundaries:

- Saves remain local to the browser profile and exact origin. Localhost, `www`, and the bare domain do not share saves; use Download backup / Import backup to transfer builds. Use the published bare-domain link consistently.
- Hosting acceptance was sampled in Chromium, not Safari/Firefox/mobile. No gameplay changes or full gameplay regression rerun were needed for this packaging/publication pass. Existing simulation and builder limitations below remain.

This publication supersedes earlier statements below that the Web export had not been publicly deployed. See `docs/WEB_HOSTING.md` for repeatable publishing instructions.

## Current: demand-driven demo simulation and equipment animation

Completed:

- Replaced the shared fixed-temperature demo behavior with independent AHU state, occupied/setback demand, mixed/return/supply temperatures, sensible zone heat balances, modulating fan pressure/flow, timed damper/valve feedback, and installed-component-aware conditioning. Added Cold morning and Unoccupied scenarios; kept the original fault scenarios.
- Connected VAV reheat to real heating demand and delivered airflow. Fan failures, removed coils, and disconnected branches cannot continue producing phantom conditioning. AHU supply flow now equals actual branch delivery. Shared duct/fitting limits constrain branches together; each duct/diffuser reads its own route's flow. Backward-authored ducts animate in the actual outlet-to-inlet direction.
- Automatic bindings use each equipment owner's actual feedback: numeric fan speed, independent AHU intake damper, separate AHU heating/cooling valves and zone-specific VAV valves. Known old defaults migrate; explicit custom mappings are preserved. Browser remains demo-only, with the desktop Niagara provider boundary intact. No station was contacted.
- Coils now fill their actual LDraw fin surfaces from neutral to their active color using an opaque shader. Removed the translucent overlay boxes. Fixed the VAV's two-row fill scale and damper vane orientation. Pause freezes operational animation; stale data holds equipment state and hides airflow. Authoring-preview motion remains explicitly separate.
- Added compact selected-equipment feedback readouts. Checkpoints preserve room/AHU thermal and actuator state, timing, scenario and pause/speed; invalid negative flows and out-of-range actuator fractions are rejected. Network edits reconcile delivery immediately, and history sampling resumes after a reset clock boundary.
- Godot scripting, 3D and UI guidance informed the fixed-step model, frame-time animation, native readouts and renderer-compatible material handling. Model equations, synthetic defaults, mappings, references and limitations are recorded in `docs/SIMULATION.md`.

Actual verification:

- PASS: `SIMULATION_FIDELITY PASS checks=59 failures=[]`. Tests include a full simulated day, 1×/60× deterministic equivalence, exact checkpoint continuation, independent AHUs, thermostat demand response, shared-trunk conservation during transients, coil/flow interlocks, all fault modes, reversed routes, pause/stale behavior, binding migration and actual mesh transforms/material uniforms.
- Numerical fixture examples, not station measurements: after 900 simulated seconds, normal SAT is 14.67°C with 0.5273 m³/s actual delivery and 58.0% cooling valve. Cold morning after 120 seconds produces 72.4% terminal reheat and 31.95°C discharge at 0.084 m³/s. Fan failure reaches zero actual flow, conditioning power and filter pressure drop.
- PASS: existing 21 BAS test groups, 55-check full playthrough, 30-check save suite, 35-check Explore camera suite, native/headless UI smoke, all five duct routes, three-sensor smoke and 18-door Explore smoke. Retained final logs: `artifacts/sim-review-20260922/`. No script/runtime errors in those final logs. These are engine/headless checks, not browser automation claims.
- The first duct smoke run failed after its deliberate AHU deletion/undo because it assumed instant full-speed restart. It now waits through the physical fan startup before checking restored airflow; the final run passes. The zero-flow behavior after deleting the source is retained.
- PASS: final release web export with the new coil shader. Actual in-app Chromium review loaded an existing saved workshop, opened AHU/VAV cases, exercised normal cooling, cold-morning reheat, fan-failure coast-down, data interruption and reset. Visible readouts and coil fill changed consistently: cold VAV ~71% reheat/~31°C discharge; failed fan subsequently showed 0.000 m³/s, 0% reheat and neutral fins; stale mode showed `Unknown · Stale` and no diffuser airflow. No warning/error entries were returned by the reviewed browser tab's console log. Existing manual browser save was not overwritten.

Remaining limits:

- This is a bounded sensible-only game model, not calibrated HVAC analysis or Guideline 36. No humidity, water plant, economizer, fan-curve/network pressure solver or automatic room-volume calculation. Heating/cooling sources are assumed available when the corresponding coil exists. Multiple same-role coil parts share one role output.
- One VAV per simulation-zone ID; ambiguous multiple-AHU paths/duplicate served-zone assignments receive no flow. Diffuser splits are equal along shortest paths. Monotonic capacity allocation can underutilize spare capacity in complex networks. Bigger architecture does not automatically add HVAC zones.
- Visual acceptance sampled Chromium. No Safari/Firefox/mobile or long-duration GPU benchmark was performed. The existing compact-height duct tray can still crop lower labels at 720 px; no broad builder-UI redesign was included.
- The updated runnable bundle is in `dist/web`. No public deployment, real station test, or overwrite of the user's saved build was performed.

This section supersedes earlier fixed demo values and coil-overlay animation descriptions below.

## Current: Explore camera/cutaways and a demo-only browser edition

Completed:

- Explore now supports full-circle drag orbit with either mouse button, eye-level through overhead tilt, smoothed wheel zoom (3–24 units), and Home to restore the 10-unit isometric view. Short left clicks still select. Removed pointer-lock requests from mode entry and dragging. Release over UI, Escape, focus loss and mode changes cancel the drag.
- Replaced per-physics-frame restore/re-hide of individual meshes with whole-obstruction cutaways and a 0.28-second clear delay. This preserves deliberately hidden animation children and static batch source meshes. Five silhouette rays and a camera-neighbourhood query replace the single central ray; support floors/terrain never cut away. Explore also uses a bounded 0.15–500 camera depth range.
- Render review caught an additional defect: a raised equipment cover could hide the figure from the reverse angle because only its fixed housing had collision geometry. Camera-only areas now follow the actual panel meshes, so a cover can cut away independently of the visible machine internals. This layer does not collide with the player or change door/wall collision.
- Browser UI now has no Connections tab, station form, protocol fixture, or Niagara animation source. Runtime guards enforce demo-only use. Loading/importing desktop projects converts non-demo animation mappings to role-appropriate demo defaults and removes station profiles in the browser's working copy; existing demo mappings and the original imported file are preserved. Desktop Niagara functionality/provider boundary remains intact; no station was contacted.
- Godot camera/physics/UI/GDScript skills guided the physics-tick queries, separate collision layers, input handling and renderer-safe visibility ownership. See the new regression suite at `tests/explore_camera.gd`.

Actual verification:

- PASS: `EXPLORE_CAMERA PASS checks=35`, including real viewport input, both drag buttons, pitch/zoom limits, reset, release/focus handling, demo-only guards/UI, imported binding conversion, camera-only cover geometry, hidden-child preservation, static-batch preservation, and 60 stationary physics frames with actual doorway occluders and no cutaway membership flicker.
- PASS: existing 21 BAS test groups, 55-assertion full playthrough, 30 save-validation assertions, native UI smoke, and Explore smoke. The final playthrough still blocks traversal through a closed door and permits passage after opening. These are native/headless checks, not claimed as browser automation.
- PASS: rebuilt release web export. Logs retained in `artifacts/explore-web-20260922/`; no script/runtime errors in the retained final runs.
- Actual in-app Chromium review: loaded the existing browser save; dragged around front/side/reverse views; tilted overhead; zoomed; reset with Home; walked; opened the AHU with E; inspected the demo-only menu and Animate tab. After the moving-cover fix, the same reverse view shows the minifigure unobstructed while the AHU internals stay visible. No per-piece flashing was observed during these sampled views. Screenshots are in the task's browser review output.
- The browser log retains one generic Chromium `UnknownError` at 16:20:32 UTC from the pre-fix run. It predates the new exports; no new warning/error entries appeared during the rebuilt-version review. The old entry is not counted as a clean whole-session console pass.

Remaining limits:

- Cutaways intentionally remove whole wall modules, duct routes or obstruction groups. They are not transparent clipping-plane slices, and a visibility change when entering/leaving an obstruction is expected.
- This is a targeted Chromium review, not a long-duration or Safari/Firefox/mobile rendering certification. No claim that every possible imported layout is free of intersecting geometry. The existing exploded equipment-opening animation is retained.
- No public deployment or live station work was performed. The runnable updated bundle is in `dist/web`; existing browser saves remain available at the same localhost origin.

This section supersedes the earlier browser Connections/fixture availability and the old Explore controls below.

## Current: static browser version

- [x] Added a runnable Godot Web export without replacing the desktop application. Web uses single-threaded WebAssembly / WebGL 2 Compatibility; desktop retains Forward+. The real LDraw parts, starter sets, editor, simulation, equipment workbench and minifigure remain in the same game.
- [x] Browser Save/Load persists the existing versioned JSON in IndexedDB through Godot `user://`, including explicit filesystem sync. No save server, login, telemetry, cloud storage, or live station is required.
- [x] Added local JSON Download backup / Import backup to the project menu and Import on the welcome screen. Import does not upload anything or overwrite the manual slot. Invalid schemas are rejected before replacing the current model; the previous layout is backed up. Password/cookie keys are stripped from imported connection profiles.
- [x] Added bounded validation for object records, IDs, transforms, wall/duct paths, components, paint, point bindings, camera and simulation data. Partial failures leave the current model unchanged. Added browser-storage warnings and clear site-data/deletion guidance.
- [x] Replaced web system-font lookup with Godot's bundled font, adjusted Compatibility lighting, made placement ghosts use material alpha, and gave exploration occluders a WebGL-compatible cutaway. Fixed project-menu overflow with a scroll container.
- [x] Added `npm run web:build`, `npm run web:serve`, the `Web` export preset, a custom loading/error shell, credits, and engine/asset license output. The preview server exposes only `dist/web` on localhost. Distribution excludes documentation/video, tests, build tools, Node modules, native data and the bridge.
- [x] Preserved the Niagara provider boundary, saved bindings, and station-free fixture. The browser Connections page explicitly explains that live Niagara remains desktop-only; browser calls cannot spawn the bridge or contact a saved station.

Actual verification:

- PASS: release Web export with official Godot 4.7.2 single-threaded templates. Archive SHA-256 matches the official release digest: `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.
- PASS: `21 BAS Sandbox test groups`, `PLAYTHROUGH PASS checks=55`, and `BROWSER_SAVE_TESTS PASS checks=30`. Logs are in `artifacts/web-review/`. These automated checks are native/headless; they are not presented as browser automation results.
- PASS: final `TOY_UI_SMOKE PASS failures=[]` and a fresh successful release export after the browser-only UI wording changes. The persistent desktop-only Niagara notice was checked in the actual browser after loading a save.
- PASS in the actual Codex in-app Chromium browser: New Game → starter selection → Little workshop; inspected real LDraw geometry and the equipment workbench. Entered Explore, used E to open the AHU, and moved the minifigure with keyboard input.
- PASS in browser: saved the 125-object workshop, reloaded the entire page, then loaded the persisted workshop. Loaded it again after an updated web export, confirming save compatibility across that update.
- PASS in browser: Download backup created a real 45,692-byte JSON file. Parsed it: correct format/version, 125 objects, simulation checkpoint, and no password/cookie/token fields. A copy is retained at `artifacts/web-review/downloaded-backup.json`.
- PASS in browser: invalid-version JSON import showed rejection and kept the workshop intact. A valid larger office backup replaced the visible scene. Reloading afterward still loaded the original manually saved workshop, confirming import did not silently overwrite the Save slot.
- Browser review caught and fixed an overflowed project menu and a stale import-error notice. The browser also emitted one generic Chromium `UnknownError` during the keyboard/interaction review; no Godot script error accompanied it, and subsequent interaction/save loading still worked. This is recorded, not counted as a clean-console pass.

Remaining / delivery boundaries:

- No public deployment was requested or performed. Hosting-ready files are in `dist/web`; launch locally with `npm run web:serve`. See `docs/WEB_HOSTING.md` for MIME types, compression, stable-origin saves, asset size and deployment instructions.
- Live Niagara in a hosted browser needs a separately secured browser-compatible gateway. The existing local bridge was not exposed or modified, and no real station was contacted in this pass.
- Tested in the in-app Chromium browser, not Safari/Firefox or mobile. No touch-control pass, cross-browser benchmark, or PWA/offline-reload guarantee. The prior native performance measurements do not establish browser FPS.
- Browser saves are per origin/profile/device, not cloud-synced. Clearing site data or browser eviction can remove them; downloads are the portable backup. Private-mode persistence cannot be guaranteed.
- Measured delivery size: engine WASM 39,514,754 bytes raw / 10,185,394 bytes gzip; game pack 1,946,852 bytes raw / 1,252,002 bytes gzip. Compression is a host configuration requirement, not enabled by the simple local preview server.

## Current: starter sets, expandable site, thermostats, and a tested playthrough

Completed:

- New Game → visual starter selection → Build; Building/Equipment/Explore remain directly switchable. Four editable buildings: 16×12 workshop, 32×20 office, existing 60×34 school, and 84×46 learning center with twelve rooms. Blank starts with no physical floor or terrain. Every populated starter has a connected demo AHU/VAV/diffuser path.
- Removed the fixed lot collider and old placement/pan bounds. The editor grid is not physical ground. Floor, terrain, paving and parking use drag-area previews with atomic stroke undo/redo; trees and shrubs snap onto placed surfaces. A stroke is bounded to 512 tiles to avoid accidentally allocating a huge scene, not to restrict the total site.
- Sourced real LDraw 3470 trees and 2435 small pyramidal foliage; native brick-built paving/parking and wall thermostats use documented parts. Retained the original DAT authorship/licenses/dependencies. No Blender or new third-party runtime package was needed. New catalogue and starter-card images are actual Godot renders.
- Real wall-module placement previews, cached stud-support checks, single-module R rotation, hosted opening previews that temporarily replace their wall face, visible select/rotate/move/copy tools, rotated-equipment overlap checks, and auto-routed duct previews that match the committed route. Fixed the footprint renderer clearing its own placement-valid flag.
- Workbench retains mandatory intake/fan bays and auto-inserts filters before treatment coils. Failed reorder attempts preserve the selected component identity; unavailable thumbnails visibly dim. Static scene objects are reused during edits rather than rebuilding every assembly.
- Thermostats snap to solid wall faces, open VAV-link controls after placement, and retain stable VAV/wall references. Linked demo setpoints drive the VAV's simulation zone. Newly placed VAVs get their own demo zone. Explore offers thermostat readout and adjustment with E. Live Niagara mode blocks these demo edits; the read-only provider/bridge boundary is unchanged.
- Explore has running, jumping, plate-height curb stepping, line-of-sight interaction, and a farther isometric camera with local wall cutaway/obstacle fading. Player collision remains active. Door animation now transforms the physics body itself: the review found and fixed the old visual-open/physically-closed defect. Door state, player position, site identity and build camera persist in saves.
- Static LDraw pieces use spatial/material draw batches while individual colliders and selection IDs remain editable. Network evaluation now runs after construction changes instead of every render frame. Per-frame animation samples are shared by particles with the same owner/role.
- Save replacement uses rename without first deleting the existing file. New Game stores a recovery copy of the previous in-memory project without replacing the manually saved project.

Actual verification, Godot 4.7.2:

- PASS: `tests/playthrough.gd`, **55 assertions**, both headless and native Metal Forward+. Includes actual viewport clicks on New Game and a starter card; all four starters' sizes, support and connected air paths; a 12-tile floor stroke at x=149..155/z=120..124; one-step undo/redo; wall rotation; preview validity; physical standing on the new site; ray-snapped thermostat placement and linking; Explore thermostat interaction; demo/live authority separation; workbench constraints; actual collision-blocked movement at a closed door and traversal after opening; save/load of thermostat links and door state.
- PASS: existing 21 simulation/model/provider/asset test groups; UI, duct (five routes), sensor (three sensors), and Explore (eighteen school doors) smoke tests.
- PASS: localhost-only mock connection smoke: SCRAM, health, capabilities, WebSocket subscriptions, bound 62.5% fan sample, disconnect, and explicit demo fallback. Initial attempts lacked sandbox socket permission/the mock server; after starting the synthetic local server with permission the complete test passed. **No real Niagara station was contacted in this pass.**
- Native render review: inspected starter selection, building views, thermostat panel, equipment workbench and Explore captures at `artifacts/review-20260922/`. The first camera review was too close because its boom hit overhead ductwork; local obstruction handling corrected that in the final capture.
- Measured at 1280×800 on this Apple M4 Max: largest starter decreased from ~8,690 draw calls / 37.5 ms median frame time to **774 draw calls / 16.7 ms median / 16.9 ms p95**. Office and school median/p95 were 16.7 ms in the final 60-frame samples. These are short stationary native samples, not a hardware-independent FPS guarantee. Initial loading of the largest starter was ~594 ms in the final run; edits reuse unchanged objects.
- Restricted headless runs print the existing macOS certificate-store warning. The final native review and project tests reported no parser/runtime errors. Native GUI automation could read screenshots but its click transport returned `noWindowsAvailable`; end-to-end input was therefore exercised through Godot's real viewport input dispatch, not claimed as a manual OS-driven playthrough.

Remaining limits (not claims of finished Sims parity):

- Terrain is flat and the editor is expandable, not a streamed infinite world. Very large constructed sites still consume memory; no floating-origin system is implemented.
- Wall runs are created/removed as runs, not dragged by resize handles. Duct bend handles, automatic room-volume recognition, ceiling tiles, multi-floor navigation and the previously deferred six-zone/trend/alarm expansion remain future work.
- Door swings use a fixed hinge direction. Equipment assembly is constrained by functional bays, not loose-brick rigid-body simulation. Landscaping uses a small curated selection and parking bays have no vehicles/traffic.
- Thermostat controls are demo-only. Live point ORD mapping remains station-specific and this pass did not revalidate a real station.

The dated sections below record earlier passes; the current section above supersedes their obsolete limitations and weaker verification claims.

## Latest: Sims-style placement, structured equipment and physical Explore interactions

- [x] Added a consistent placement language across the floor-plan tools. Floors show a red/green 4x4-stud footprint, wall runs preview every module while dragging, doors/windows ghost directly into their host wall module, equipment shows the assembled unit plus its full stud footprint, tees show a rotated fitting and footprint, and ducts preview their actual shell. Invalid support, overlap and clearance states block placement instead of relying on visual approximation.
- [x] Equipment placement now uses native odd/even stud-center snapping, honors 90-degree `R` rotation in both the model and footprint, retains floor/ceiling/above-ceiling elevation, and excludes the moved unit from its own collision test. Middle-drag pans the large plan while right-drag orbits and the wheel zooms.
- [x] Reworked the workbench into a constrained airflow assembly. AHUs retain a required intake damper and discharge fan with optional treatment bays between them; VAVs retain one inlet damper and one optional heating or cooling bay. Invalid reorders/removals are refused, add buttons disable when a bay is unavailable, Clear restores the required skeleton, and labeled DMP/FLT/CLG/HTG/FAN bay chips expose the actual order.
- [x] Rebuilt terminal diffusers as a brick plenum, framed four-way grille and compatible hollow socket using the existing LDraw kit. Each connected diffuser now has four animated discharge streams. Duct cutaway uses larger unshaded cyan flow markers inside the hollow route, while room discharge remains visible with the duct lids closed.
- [x] Normal demo data now starts at the physically consistent minimum occupied airflow instead of showing zero until the first five-second simulation step. Niagara-bound airflow still follows only its configured live point and never borrows this demo value.
- [x] Explore movement now accelerates/decelerates through a collision-layered `CharacterBody3D`, floor snapping, gravity and `move_and_slide`; the isometric third-person `SpringArm3D` retracts against architecture. All eighteen school doors have hinged `AnimatableBody3D` leaves and jamb/header collision, and nearby `E` interaction opens/closes the real leaf and collider. Nearby AHU/VAV interaction smoothly lifts or replaces the access casing rather than hiding it instantly.
- [x] Kept the existing LDraw and project-authored fitting boundary. This pass reused documented runtime parts and generated no Blender asset or new third-party dependency.

Actual verification on Godot 4.7.2:

- PASS: `tests/run_tests.gd` — `PASS: 21 BAS Sandbox test groups`.
- PASS: `tests/ui_smoke.gd` — `TOY_UI_SMOKE PASS failures=[]`; includes automatic treatment-bay insertion, invalid fan reorder rejection, protected mandatory bays, structural Clear and VAV part availability.
- PASS: `tests/duct_smoke.gd` — `DUCT_SMOKE PASS routes=5 failures=[]`; includes diffuser discharge with closed lids, hidden internal flow when closed and visible internal flow in cutaway.
- PASS: new `tests/explore_smoke.gd` — `EXPLORE_SMOKE PASS doors=18 failures=[]`; verifies player/camera collision configuration, hinged animated door physics and moving equipment access panels.
- PASS: `SENSOR_SMOKE PASS sensors=3 failures=[]`, `RUNTIME_SMOKE PASS objects=754 ... ahu=true`, and `VISION_SMOKE PASS objects=752 failures=[]`.
- PASS: localhost-only mock Niagara path — `CONNECTION_SMOKE PASS failures=[]`; authenticated health/capabilities/read subscription remained read-only and returned explicitly to Demo Simulation.
- PASS: native Metal Forward+ render. The full-school view shows the brighter terminal discharge at both connected diffusers without opening the duct lids. A closer final diffuser/cutaway capture was also inspected after the automated checks.
- Environment note: restricted headless runs still emit the known macOS certificate/log-path warnings. They exited with the pass results above and no project parser/runtime errors.

Remaining builder work:

- Direct manipulation of already-placed wall/floor modules and editable duct bend handles is still a later refinement; existing equipment uses the explicit Move action and walls are rebuilt as new drag runs.
- Doors do not yet choose swing direction from the approach side or persist their temporary open state. Equipment uses structured functional bays rather than loose-brick rigid-body assembly.
- Ceiling tiles, automatic room-volume detection/assignment, multi-floor navigation and the deferred six-zone/trend/alarm expansion remain incomplete.

## Latest: one-minute playable demo video

- [x] Chose Godot's deterministic movie writer for the actual application footage and FFmpeg for the final timing pass. This keeps the capture app-only and reproducible without desktop chrome, generated gameplay, narration, title cards, captions or added text.
- [x] Added a scripted tour of the real playable build: full school overview, supported wall-run/window snapping, separate AHU component assembly, visibly moving damper/fan and blue/red coil fills, equipment cutaway, hollow duct airflow, paint/properties, third-person hallway movement and equipment interaction, Niagara connection setup, and a final demo-driven system overview.
- [x] Replaced the rejected choppy export. The full-school render has a dependable 15 Hz visual cadence, then receives motion-compensated intermediate frames for the 60 fps delivery instead of repeated-frame padding. The Explore shot uses a farther, elevated isometric-like third-person camera; its presentation-only collision override prevents the arm collapsing into a minifigure close-up.
- [x] The Niagara beat uses a real read-only HTTPS connection captured from the requested station through production SCRAM, `/stream/health`, API 1.5 capability discovery and WebSocket setup. The application visibly reports `Connected · School BAS · Live`; the password was supplied only through the render process environment and was not saved. After that successful capture, a later refresh was refused at port 443, so the final edit deliberately retains the earlier verified frame rather than fabricating a new success.
- [x] Corrected an intermittent production bridge defect found while capturing: Niagara's literal SCRAM comma/equal delimiters remain intact while Base64 `+` is escaped as `%2B`, preventing form decoding from corrupting a nonce or proof.

Actual verification:

- PASS: `docs/demo-video/brick-bas-demo-60s.mp4` decodes completely with FFmpeg and contains exactly 3,600 H.264 frames at 60 fps, 1440×900, square pixels, AAC stereo and exactly `60.000000` seconds.
- PASS: inspected the final ordered contact sheet at `docs/demo-video/review/final/contact-sheet.png`. The full floor, wall/window placement, component lineup, both coil colors, fan, duct/VAV cutaway, paint, distant third-person walk, real connected panel and finale are readable.
- PASS: five consecutive full `CONNECTION_SMOKE PASS failures=[]` runs after the SCRAM encoding fix.
- PASS: `RUNTIME_SMOKE PASS ... animation=true`, including live fan rotation and increasing coil fill, after repairing stale fixture coordinates from the school-floor expansion. `PASS: 21 BAS Sandbox test groups` and `TOY_UI_SMOKE PASS failures=[]` also reran.
- SHA-256: `7c247ebd32b233a8b9b848c5b55f1bfdb5763b33296195863d821667e2b368b9`.

## Latest: real baskStream connection setup

- [x] Added a **Connections** tab to the Piece Details properties drawer. It includes a saved friendly name, binding connection ID, station URL, username, strict/self-signed TLS choice, masked password, Test, Connect, Disconnect and Use Demo Simulation controls. The drawer expands for this form so every action remains visible at 1280×800.
- [x] Added the same data-source entry point to the compact project menu while retaining the explicitly labeled station-free protocol fixture.
- [x] Reused the current BAS Whiteboard architecture as an integration pattern: a localhost-only Node bridge performs bounded Niagara SCRAM authentication, owns the session cookies, verifies `/stream/health`, opens `/stream` with Cookie and Origin, and relays only an allowlist of read operations. The current API 1.5 documentation remains protocol authority.
- [x] Added the required `ws` 8.21.3 and `@msgpack/msgpack` 3.1.3 dependencies with a lockfile. Godot starts the bridge only when Test or Connect is requested and stops the child it owns on exit.
- [x] Added an asynchronous Godot bridge transport. The provider no longer assumes a WebSocket is open synchronously: it waits for bridge authentication and station WebSocket readiness before sending `ping` and `capabilities`.
- [x] Test leaves the current source unchanged. Connect activates Niagara only after health and capabilities succeed. Failure also leaves the current source intact. Disconnect and Use Demo switch explicitly to the existing deterministic simulation; a Niagara binding never borrows a demo point.
- [x] Safe connection profiles persist with project saves, but passwords and authenticated cookies do not. The local bridge and provider remain read-only at separate enforcement boundaries.
- [x] Adding a Niagara animation binding while connected refreshes the active view-scoped subscription list immediately. Snapshots/COV continue through the normalized point store and drive the same fan, coil, damper and airflow animation mappings.

Actual verification:

- PASS: `CONNECTION_SMOKE PASS failures=[]` against a localhost-only mock BASkStreamService. This completed SCRAM authentication, cookie handling, `/stream/health`, WebSocket upgrade, API 1.5 capability discovery, a subscription snapshot, a 62.5% live value driving the bound AHU fan, disconnect and explicit Demo Simulation fallback.
- PASS: local bridge `/health` returned `{"service":"brick-bas-baskstream-bridge","ok":true}` with no station configured.
- PASS: `node --check` for both the production bridge and mock station; `npm install` audited three packages with zero vulnerabilities.
- PASS: `tests/run_tests.gd` — `PASS: 21 BAS Sandbox test groups`, including safe connection-profile round-trip and missing-password rejection.
- PASS: `TOY_UI_SMOKE PASS failures=[]`, including the on-demand Connections tab, masked password and incomplete-form Demo fallback.
- PASS: duct, sensor, 752-object playable regression and clean boot after the connection integration.
- PASS: native Metal Forward+ visual inspection at `docs/evidence/current/connections.png` (1280×800). All connection fields and actions are visible in the toy-style properties panel.
- PASS: the requested real station completed read-only HTTPS SCRAM authentication, `/stream/health`, baskStream API 1.5 capability discovery and WebSocket setup with the explicit self-signed-certificate option. No write path was enabled and no secret was persisted. A later reconnect attempt was refused at port 443; live point ORD mapping remains station-specific work.

## Latest: actual small-school first floor

This correction supersedes the 24 m × 14 m office layout described in the next historical section. That was not meaningfully school-sized.

- [x] Rebuilt the seed as a 60 m × 34 m, approximately 2,040 m² first level using 510 connected official-LDraw 4×4 floor plates. The playable model now contains 752 persisted objects before user edits.
- [x] Added a full-length central hall and thirteen enclosed program spaces: seven general/art classrooms, library, administration, health office, entry lobby, multipurpose room and a dedicated mechanical room.
- [x] Added double front entry doors, east/west side exits, a mechanical service exit, exterior windows for occupied rooms and real door modules from the hall into every room bay. The lobby is open directly to the main hall.
- [x] Repositioned AHU-1 into the mechanical room and extended the authored supply system down the school hallway. The west/east VAVs and terminal diffusers now span the two classroom wings; the AHU trunk uses a real service opening through the mechanical partition and still passes full wall/duct clearance validation.
- [x] Expanded the site pad to 68 m × 42 m, the directional-shadow range to 80 m and the default orbit to 78 m so the whole first level can be read and navigated at startup.
- [x] Renamed the two current simulation zones to East Classroom Wing and West Classroom Wing without pretending the deferred six-zone model was completed.

Actual correction verification on Godot 4.7.2:

- PASS: `tests/run_tests.gd` — `PASS: 20 BAS Sandbox test groups`.
- PASS: `tests/duct_smoke.gd` — `DUCT_SMOKE PASS routes=5 failures=[]`; the longer mechanical-room trunk and both hall branches clear the new school walls.
- PASS: `tests/ui_smoke.gd` — `TOY_UI_SMOKE PASS failures=[]`.
- PASS: `tests/sensor_smoke.gd` — `SENSOR_SMOKE PASS sensors=3 failures=[]` at the relocated equipment positions.
- PASS: playable regression — `VISION_SMOKE PASS objects=752 failures=[]`, including an exact assertion for all 510 floor plates and both route-driven wing connections.
- PASS: main scene booted without parser/runtime errors. Restricted headless runs retain the documented log-path and macOS certificate warnings.
- PASS: native Metal Forward+ capture at 1280×800: `docs/evidence/current/school-floor.png`. The rendered evidence shows the full hall, room wings, mechanical room, gray equipment and long duct distribution. No Blender asset or Niagara station was used.

## Latest: larger connected playable floor and offline Niagara transport

This pass supersedes the smaller two-room layout and the teal/generic-equipment limitations recorded in older milestone notes. The requested six-zone/trends/alarms/multifloor/hot-water expansion was intentionally not included.

- [x] Rebuilt the preloaded plan as a 24 m × 14 m, 84-plate office floor with east/west office wings, an open lobby, a rear mechanical room, four exterior windows, three hosted doors and editable model-backed walls/floors. The build camera now frames the larger shell.
- [x] Removed teal/green from the equipment palette. AHU/VAV housings now use light bluish gray and duct uses a darker galvanized gray; functional blue/red/amber/charcoal colors remain on coils, dampers, filters and fans. Sensor status caps are light blue rather than teal. Repaint/reset behavior remains available.
- [x] Replaced the uniformly scaled generic VAV with a dedicated native-scale LDraw assembly: separate damper/actuator, reheat grille, sensor stack, removable casing and open inlet/outlet sockets. No Blender-generated asset was added.
- [x] Added stable per-component records to placed AHUs/VAVs. Each damper/filter/coil/fan retains its ID while being reordered; the toy workbench now supports direct drag reordering in addition to arrow controls. Component records persist beside the compatibility layout summary.
- [x] Added model-backed supply tees and terminal diffusers with explicit inlet/outlet ports. The Ductwork tray now contains a tee placement tool and a regenerated 256×224 transparent thumbnail from the actual runtime geometry.
- [x] Added outlet/inlet, medium and profile compatibility checks plus obstacle-aware orthogonal routing. Aligned sockets use a clean straight run; other routes rise above equipment/walls and try both X-first and Z-first paths. New manual routes reject equipment, solid walls and existing duct runs instead of drawing through them.
- [x] Replaced the old unconnected west stub with one joined distribution system: AHU outlet → supply tee → two VAVs → two diffusers. `RouteNetwork` derives both room connection states from enabled, valid authored ducts. The VAV disconnect control now disables the physical inlet branch, and the demo simulation immediately follows that topology.
- [x] Extended brick attachment validation to equipment placement. AHUs/VAVs snap by native odd/even stud footprint, require complete floor support under their projected footprint, reject another assembly's footprint and reject floor-level wall overlap. Saved objects record stud/ceiling-mount connection metadata.
- [x] Replaced the empty baskStream shell with a read-only provider, bounded MessagePack codec, mock binary transport and desktop WSS transport for an already-authenticated Niagara web session. The provider performs `ping`, reads `capabilities`, uses leased view-scoped subscriptions, normalizes snapshots/COV and quality timestamps, handles revocation/malformed frames, and restores subscriptions after reconnect. Non-TLS URLs and missing sessions are rejected; writes remain impossible at the provider boundary.
- [x] Added an explicitly labeled **NIAGARA FIXTURE** source toggle to the project menu. It exercises the binary protocol path without starting or contacting a station. Demo and Niagara points never substitute for one another, and source switches create history boundaries.
- [x] Read the bundled current baskStream API 1.5 reference before implementing the adapter. The implementation follows its `/stream` binary MessagePack, capability-discovery, COV, leased group and session-revocation shapes. Live login/health/read proof remains a separate station-owned verification step.

Actual verification on Godot 4.7.2:

- PASS: `tests/run_tests.gd` — `PASS: 20 BAS Sandbox test groups`. New coverage checks authored route reachability, branch disabling, known MessagePack bytes, nested map/array/Boolean/float/64-bit round-trip, malformed-frame rejection, ping/capabilities, subscriptions, COV zero/stale handling, reconnect/resubscribe, read-only enforcement and WSS security preconditions.
- PASS: `tests/duct_smoke.gd` — `DUCT_SMOKE PASS routes=5 failures=[]`. All five seeded routes land exactly on clear sockets and include the authored tee branch; manual placement/undo/casing clearance/cutaway tests remain green.
- PASS: `tests/ui_smoke.gd` headless and native Metal — `TOY_UI_SMOKE PASS failures=[]`. The new tee tool and 14 runtime thumbnails are present; mode, workbench, paint, binding and drawer regressions remain green.
- PASS: expanded playable smoke — `VISION_SMOKE PASS objects=152 failures=[]`. This now asserts all 84 floor plates, both route-driven zone connections and stable component identity across drag-style reorder, in addition to casing, animation, mounting, paint, binding, save/load, wall opening, duct authoring and third-person interaction.
- PASS: native Metal/TAA sensor regression — three sensors, 60 frames, peak RGB delta `0.027451`, mean `0.000856`; thresholds remain `0.08` / `0.0025`.
- PASS: the regenerated damper/AHU/VAV/duct/tee thumbnails are all 256×224 RGBA with transparency, checked by the game-asset report script.
- PASS: inspected native 1280×800 Metal renders under `docs/evidence/current/`: `large-floor.png`, `duct-network-open.png`, and `vav-workbench.png`. These are actual engine captures. They show the larger plan, gray equipment/duct system and dedicated VAV; no concept image is used as runtime proof.
- Environment note: restricted headless runs still report the known macOS certificate/log-path warnings. Final native runs used Metal Forward+ and contained no parser/runtime errors. No Niagara station was contacted.

## Latest: sensor flicker correction

- [x] Confirmed this was not an intended status animation: sensor nodes are not in the animation update list. The old centered cap overlapped the white round-plate body by 0.14 m in AHU-local dimensions (proportionally smaller on VAVs); their coincident outer surfaces flickered under TAA. The mounting plate also overlapped roof trim and its round piece sat between studs.
- [x] Kept the existing official 3022 / 6141 / 98138 parts at native scale. The stack now uses 0.2 m plate-body increments and an actual corner stud. Exposed the roof studs beneath the sensor mount by omitting the two conflicting trim tiles on that bay. No flashing material, global antialiasing disable or new asset dependency was added.
- [x] Added `tests/sensor_smoke.gd`: checks all three AHU/VAV sensors, non-penetrating cap/body positions, real-stud alignment, unchanged transforms over 120 animation updates, and a 60-frame native temporal comparison after warm-up.

Actual native Metal comparison, same 1440×900 gameplay camera/TAA and fixed 13×13 neighborhoods around each sensor cap:

- Before: peak frame-to-frame RGB-channel change 0.215686; mean 0.003790. All three assemblies failed cap-overlap and mounting alignment checks.
- After: peak 0.031373; mean 0.001077. `SENSOR_SMOKE PASS sensors=3 failures=[]`. This is not a claim of pixel-identical frames; ordinary edge antialiasing remains. The regression thresholds are 0.08 peak / 0.0025 mean.
- PASS: the existing 18 test groups and four-route duct/aperture regression after the sensor correction. Refreshed sensor/AHU/VAV thumbnails from the corrected assemblies. Headless tests retain the known macOS certificate warning; native sensor verification has no script errors.

Existing open game instances do not hot-reload this correction. They are left untouched to preserve any unsaved building edits.

## Latest: brick ductwork and equipment sockets

- [x] Replaced the thin metal-looking trough profile with a chunky matte plastic body, native-size LDraw 3022 plate lids, studded vertical access plates and restrained module seams. Lids start closed; hollow interiors and point-driven airflow remain available through cutaway. Arbitrary 3D paths retain shared miter rings.
- [x] AHU/VAV end frames now contain real openings and tapered hollow adapters. Removed duplicate mating faces and smoothed-corner shading that caused flickering/pinched-looking joints. The duct material keeps directional lighting and cast shadows but disables received shadows to eliminate checker-pattern self-shadow acne on open rims. Custom bodies/adapters are documented as project-authored fittings, not official parts.
- [x] Added screen-space snapping to vacant inlet/outlet sockets, automatic straight entry leads, destination-click completion and saved equipment/port references. Endpoints follow equipment position, rotation, elevation and bay-count changes; undo restores them.
- [x] Reject new routes that sweep the duct body through an equipment casing, not only routes whose centerline intersects it. The conservative oriented envelope includes square-profile rotation, miter overhang and plate studs. Occupied sockets cannot accept duplicate connections. Existing routes invalidated by a later edit/deletion keep their saved data but show a selectable red “Reroute duct” marker instead of unsafe geometry. Undo or delete/rebuild the route restores the intended workflow; no automatic obstacle solver is claimed.
- [x] Rebuilt the four starter routes against actual socket locations. Demo VAVs now use the 3.4 m ceiling preset, avoiding the AHU roof. The east inlet has a visible AHU-to-VAV riser; the west inlet remains an unconnected upstream stub, not a simulated tee.
- [x] Mesh-level aperture testing found the original four-stud damper tile entering the inlet opening. Sourced official LDraw 63864 tile 1×3 from the already-downloaded library and replaced those blades at native scale. All 27 selected parts and dependencies retain attribution/license records. No Blender or station dependency was added.
- [x] Refreshed affected duct, damper, AHU and VAV catalog thumbnails from the actual assemblies.

Actual verification on Godot 4.7.2:

- PASS: all 18 existing automated test groups, now checking all 27 documented LDraw meshes.
- PASS: `tests/duct_smoke.gd` headless and native Metal: `DUCT_SMOKE PASS routes=4 failures=[]`. Checks all four starter routes, exact socket endpoints and approach directions, 30 mesh-triangle aperture samples across all six equipment ports, body/roof grazing rejection, actual screen-coordinate snapping, saved attachment/JSON retention, mounting/rotation/bay edits, undo, occupied ports, missing-owner warning, rejected-placement non-mutation, cutaway and visible bound airflow.
- PASS: native `TOY_UI_SMOKE PASS failures=[]`; the build/workbench/paint/binding UI regression remains green.
- PASS: full playable smoke headless and native: `VISION_SMOKE PASS objects=76 failures=[]`. Its free 3D routing fixture was moved away from equipment because the old location is correctly rejected by the new body-clearance rule.
- PASS: inspected native 1440×900 floor, connection-detail and open-duct captures, retained under `docs/evidence/duct-*.png`. These are actual engine images, not generated concepts. The updated floor-plan scene was left running without saving test edits over the user's project.
- Import completed for the new LDraw mesh, scripts and thumbnails. Restricted editor cache/profile writes and the headless macOS certificate warning remain environment limitations; final native tests have no script errors.
- Failures resolved during this pass: typed-loop parse error, a stale asset-count expectation, an old routing fixture inside equipment, and the real overlong damper obstruction found by the new mesh test. The aperture test was not weakened to accept that obstruction.

Historical note: the automatic routing, supply tee, compatibility, joined distribution network and simulation-graph items listed here were completed in the latest pass above. Direct editing of existing bend handles and more connector/profile transition families remain. The clearance envelope is not a general loose-brick destruction simulator, and legacy ducts without endpoint data still require rerouting.

## Latest: toy-like minimal UI redesign

The user rejected the generic light application styling. The current runtime now uses the native toy UI in `scripts/ui/toy_builder_ui.gd`; the earlier Maaack-based presentation below is historical.

- [x] Used built-in image generation to create a visual target from the real workbench screenshot. Saved the concept and full prompt in `docs/ui-concepts/`. The generated image is clearly labeled as a concept, not runtime proof.
- [x] Rebuilt the interface as compact studded mode tiles, a cream parts tray, restrained yellow active states, a red brick identity mark, a green place control and consistent custom pictograms.
- [x] Removed the full-width top navigation, permanent tall properties sidebar, always-visible simulation form and solid status bar. Selected equipment gets a compact Open/Paint/Link card. Detailed Object/Paint/Animate controls and project/simulation options open on demand.
- [x] Replaced text-only catalog items with 13 transparent thumbnails rendered from the project's actual LDraw assemblies. No generated concept pixels or rasterized text are used as functional controls. The thumbnail generator is retained at `tools/bake_ui_thumbnails.gd`.
- [x] Kept component selection/reordering/removal, sensor toggle, presets, mounting, cutaways, point bindings, painting, save/load, simulation controls and exploration accessible. Workbench framing is closer and its sample-motion label remains explicit.
- [x] Added `--workbench` for opening directly into equipment authoring.

Actual results on Godot 4.7.2:

- PASS: all 18 existing automated test groups.
- PASS: new `tests/ui_smoke.gd` both headless and native Metal: `TOY_UI_SMOKE PASS failures=[]`. Checks mutually exclusive trays, initial hidden forms, compact context width, all 13 thumbnail textures, mode changes, component thumbnail actions, lineup selection/reordering/removal, sensor toggle, wall/duct tools, paint category, drawer open/close and session-menu behavior.
- PASS: native full playable smoke after replacement: `VISION_SMOKE PASS objects=76 failures=[]`.
- PASS: hands-on native clicks added a filter, selected/reordered a lineup component, started placement with the green control, placed equipment, and opened its point-binding and paint drawers. Project/settings menu visibly exposes save/load and simulation controls. Test edits were not saved over the user's project.
- PASS: all 13 PNGs are 256×224 RGBA with transparency, checked with the game-assets skill's QA script. Report: `docs/ui-concepts/thumbnail-qa.json`. Floor/sensor framing was widened after a first bake touched the image edge.
- PASS: inspected actual 1440×900 Metal captures of workbench, floor and on-demand binding form: `docs/evidence/toy-workbench.png`, `toy-floor.png`, `toy-binding.png`.
- Fixed during verification: both trays initially appeared together; selecting a lineup tile attempted to free a signal-emitting control. Final UI tests and native runs contain neither error. Restricted headless/editor cache and certificate warnings remain environmental.

Limits: this is a native interpretation, not a pixel-perfect rendering of the image-generated concept. Existing mechanical/connection limitations below are unchanged. No station was contacted. UI motion remains immediate except for the small pressed-button depth change; no new network or DCC dependency was added.

## Current playable build: expanded builder vision

This section supersedes older descriptions below of the first-person camera, fixed straight ducts, and AHU-only workbench. Earlier milestone entries and test results remain as history, not proof of the latest build.

### Implemented in this pass

- [x] Native light builder UI adapting Maaack's MIT Lab theme: top modes, bottom catalog/workbench, and Object/Paint/Animate inspector tabs. No web UI or template networking dependency.
- [x] Starting office architecture now lives in the editable project model. Sims-style wall dragging and native LDraw door/window hosting work on both new and starting wall modules. Floor support and overlap checks remain; off-grid receptors can no longer pass by rounding into a stud cell.
- [x] AHU and VAV workbench with separate damper, filter, cooling/heating coil and fan bays; independent housing sensor; reorder/remove/clear; editable presets; re-edit placed units. Workbench sample motion is labeled separately from bound equipment feedback.
- [x] Equipment appears closed on the floor plan. Select it to expose the components, or walk up and press E to toggle the casing.
- [x] Floor, ceiling and above-ceiling placement controls; equipment move/copy follows the cursor and retains component configuration, paint and bindings. Mounting changes and moves are undoable.
- [x] Hollow duct polylines with vertical and diagonal segments, XYZ or any-angle authoring, shared miter rings through bends, removable top surfaces and bound airflow indicators. Elevation changes in 0.25 m steps. A bend is undoable without removing the preceding run.
- [x] Functional defaults plus selected-object, component-role and same-kind painting; reset defaults and eyedropper. A group paint is one undo operation.
- [x] Actual LDraw minifigure with separate articulated limbs, third-person follow camera, wall collision and nearby-equipment interaction. No Blender dependency was added.
- [x] Kenney CC0 placement click sourced and bundled. 0.100023-second sample, small pitch variation, muted option and rapid-event coalescing. Headless tests do not play audio.
- [x] Per-object animation bindings for fan, coil, damper and duct flow: Boolean, finite numeric ranges, supported unit conversions, explicit enum-name/ordinal mapping, inversion, command/feedback labeling. Unknown, stale, faulted and incompatible samples do not imply operation. Offline Niagara references retain connection ID and point reference without borrowing demo values or contacting a station.
- [x] Reduce motion stops continuous fan/air motion, reduces the figure's gait, and applies damper states directly; coil state remains readable.
- [x] Save/load retains the complete scene, components, paint and bindings. Legacy addition-only saves restore their original base office during import. New saves mark themselves as complete scenes.

### Actual verification for this pass

- PASS: 18 automated test groups on Godot 4.7.2. Includes all 26 runtime LDraw meshes; original simulation/provider, save/undo, port-graph and brick-grid tests; numeric/Boolean/enum bindings; stale/source/type/unit rejection; finite 3D miter rings; hollow/removable duct faces; grouped paint undo/redo.
- PASS: expanded headless smoke: `VISION_SMOKE PASS objects=76 failures=[]`. Covers closed/open casing, fan rotation and reduced-motion suppression, VAV placement, painting, Boolean and offline Niagara bindings, move identity/binding preservation and undo, vertical/diagonal connected duct bends and undo, seeded-wall opening hosting, JSON save/load, minifigure camera and nearby interaction.
- PASS: same expanded smoke under native Metal Forward+ on Apple M4 Max: `VISION_SMOKE PASS objects=76 failures=[]`, exit 0, no script/resource-leak errors.
- PASS: original runtime smoke under native Metal Forward+: `RUNTIME_SMOKE PASS objects=79 animation=true rejected_invalid=true opening_host=true wall_clutch=true floor_edge=true ahu=true`.
- PASS: hands-on native UI: Equipment mode; add filter; select/reorder fan; enter placement; select above-ceiling level; place unit; open Animate tab; reject missing Niagara connection ID; save an offline reference and visibly report `Unknown · Source inactive`.
- PASS: hands-on native UI: top-down wall press-drag-release built three supported modules; Window tool snapped an opening into the new run's second module. This closes the earlier pending pointer acceptance for those two actions.
- PASS: native 1440×900 visual captures inspected for workbench layout and assembled third-person minifigure. Evidence: `docs/evidence/workbench.png` and `docs/evidence/walk.png`.
- PASS: placement sample decoded and duration verified with ffprobe; native playback path ran without errors. A subjective listening assessment was not performed.
- PASS: final editor import registered all new/modified script classes and completed. Restricted editor import could not write its help cache/profiler directory outside the workspace; these are environment permissions, not import/parser failures.
- Environment note: restricted headless runs emit a macOS system-certificate lookup warning. Native runs do not; no project parser/runtime errors remain in the final checks. A fresh native starting scene was left running after the tests, without saving the UI-test edits.

### Explicit limits, not completed features

- Authored duct geometry is not yet wired into the simulation's connection graph. The existing DEMO connect/disconnect control still owns branch delivery. Port picking/snapping and equipment-casing clearance checks are now implemented in the duct pass above; tees and automatic whole-scene routing remain.
- Equipment currently uses simple collision boxes and a constrained bay lineup, not loose-brick rigid-body assembly. VAVs use a uniformly reduced generic bay assembly. Full connector compatibility and equipment-to-floor attachment are not validated.
- Floor/wall placement is deterministic stud-grid validation, not a general LEGO physics engine. Running-bond corner joins, moving bonded wall runs and automatic enclosed-room detection remain.
- Ceiling mounting is an elevation choice; there is no ceiling-tile system yet. The current starter VAVs use the 3.4 m Ceiling preset; older saved placements retain their saved elevation.
- Newly built equipment can animate from selected demo points but does not create a new thermal plant/zone automatically. Reheat output defaults to zero in the current cooling demo. Repeated components share a role binding within the equipment rather than having independent per-bay point mappings.
- Niagara transport, live discovery/writes, a six-zone office, hot-water loop, trends UI, stairs and packaged export remain outside this completed pass. No station was started or contacted.

Motion review: `docs/animation-review.md`. Asset provenance: `ASSET_CREDITS.md`.

## Milestone 1 — first playable slice

- [x] Two-room office with one AHU, two VAVs, visible ductwork, diffusers, and room labels.
- [x] Fixed-step deterministic thermal/airflow simulation with setpoint response, damper command/feedback lag, capacity-limited branch allocation, and physical/measured state separation.
- [x] Fan-failure scenario where fan command remains on while feedback and airflow decay.
- [x] Orbit/build camera and first-person walk camera with collision and safe-location reset.
- [x] Sims-like orthogonal wall-run tool: press, drag, and release to create a full 2 m modular run with one undoable project-model object.
- [x] Shared inspector for AHU/VAV selection with editable DEMO cooling setpoint and explicit duct disconnect control.
- [x] DEMO source badge, pause/1x/10x/60x controls, hot-afternoon scenario, and reset.
- [x] Provider/PointStore boundary and a code-level read-only LIVE provider shell; no station required.
- [x] Playable geometry now uses a selected official LDraw kit: 18 named parts, including the 40598a ventilation/fan element, plus their retained dependency closure. The current library is a build-time source only; runtime meshes are baked OBJ assets and retain part IDs.
- [x] Reproducible `tools/ldraw_to_obj.py` converter resolves type-1 references and type-3/type-4 faces without Blender. All selected DAT files and dependencies carry CC BY 4.0 headers.
- [x] Coherent functional palette: three restrained architecture presets plus fixed system colors for galvanized duct, neutral gray AHU/VAV casing, blue cooling, red heating, dark fan, amber damper/filter, and neutral sensors.

## Milestone 2 — building editor

- [x] Versioned project model with stable IDs, floor elevations, explicit room-to-VAV assignments, bindings/routes collections, and demo checkpoint data.
- [x] Atomic temporary-file-and-replace save path with validated format/version on load.
- [x] Undo/redo command stack preserving object identity; wired to placed walls.
- [x] Architectural kit now uses official LDraw 60596/60616b door pieces and 3853/3855b window pieces, sized to replace one valid 4-stud wall module.
- [x] Door/window tools find the nearest wall-run module, reject occupied/invalid slots, replace that module, and persist an explicit `wall_module_host` connection through save/load and undo/redo.
- [x] Door collision uses jamb/header proxies so the opening remains walkable; windows retain a full collision boundary.
- [x] Architectural placement now uses the LDraw clutch lattice rather than generic grid rounding: 4×4 floor plates snap edge-to-edge on a shared module phase, reject overlapping footprints or disconnected placement, and save their edge-connection count.
- [x] 1×4 wall modules center odd/even axes correctly over real stud centers, require all four underside receptors to match floor studs, reject occupied brick cells, and expose valid/invalid green/red drag previews before placement.
- [x] Corrected the built-in office walls, door, windows, and divider from half-meter visual alignment to their actual quarter-stud receptor centers. Wall runs retain a stud/receptor connection specification and hosted openings retain their wall-module relationship through save/load.
- [x] Placed single-wall/floor selection uses connection-safe module moves and duplicates with overlap/support validation; delete remains undoable and rendering remains model-driven. Bonded whole-run relocation waits for a connection-safe drag transform.
- [x] In-game save/load controls use the validated versioned model and restore placed brick walls.
- [ ] Freeform drag transforms and an editable room-volume/assignment UI remain.

## Milestone 3 — mechanical construction

- [x] Stable port records include owner, direction, medium, profile, and connection limits.
- [x] Route graph accepts compatible outlet-to-inlet connections, rejects mismatched services/profiles and unsupported loops, and invalidates routes when equipment is removed.
- [x] The playable VAV inspector can disconnect/reconnect a branch and the simulation immediately stops/restores actual delivered airflow.
- [x] AHU fans visibly spin from fan feedback and blue/red coil banks fill across three rows from bottom to top as a readable output cue; VAV damper feedback animates separately from command values.
- [x] VAV visual detail follows the supplied brick-built reference at a reduced density: open-front enclosure, two round duct collars, visible damper, single actuator, and simplified reheat edge without tiny fittings.
- [x] Rebuilt the AHU hero on native LDraw dimensions: exact 20-LDU stud and 8-LDU plate spacing, unscaled housing bricks, native grille elements, an official 40598a ventilation/fan element, and a stud-mounted sensor pod. The earlier stretched-parts AHU was removed.
- [x] Added a tested construction lattice and documented the open-source boundary: MIT BrickBuilderMCP concepts for System stud/receptor validation now; MIT Sim Studio and CC BY-SA LDCad Shadow metadata as later sources for Technic connectors and joints. See `docs/open-source-brick-tech.md`.
- [x] Changed baked OBJ output from one global smoothing group to hard polygon normals. This removes the melted/cut-off shading caused by averaging across unrelated LDraw faces until an edge-aware conditional-line normal pass exists.
- [x] Reduced plastic specular response and increased roughness/ambient fill for a cleaner matte toy render without per-piece glare.
- [x] Recorded the HVAC shape/detail/motion target and component family in `assets/hvac-art-direction.md` and `assets/hvac-asset-manifest.json`.
- [x] Replaced the GL Compatibility presentation with Metal Forward+, 4× MSAA, TAA, sky ambient/reflections, ACES tonemapping, 4096 px directional shadows, warm key/cool fill lighting, and rougher plastic materials. SSAO/SSIL were tested and then disabled because they produced dark halos between dense LDraw subparts.
- [x] Reworked shadowing at assembly scale: visible LDraw subparts no longer cast separate competing shadows, while AHU, wall, window, VAV, and duct assemblies use simplified shadows-only proxy volumes.
- [x] Corrected negative-determinant LDraw reference transforms in the DAT-to-OBJ converter so mirrored subparts retain valid outward face winding with back-face culling enabled.
- [x] Closed the visible hollow undersides of stacked wall courses with shallow brick-height faces, preserving studs and subtle course joints without the former black horizontal cavities.
- [x] Added a dedicated lower/closer AHU Builder camera treatment and hide the floor-plan scene while building equipment, preventing background geometry from contaminating the hero view.
- [x] AHU Workbench now builds an ordered airflow lineup by appending separate damper, filter, cooling-coil, heating-coil, and fan bays; repeated component types are supported, the last bay can be removed, and the lineup can be cleared.
- [x] One simple native-fit open housing grows around the completed lineup instead of wrapping every component in a separate colored box. The housing sensor remains an independent option.
- [x] Cooling AHU, heat-and-cool, and ventilation presets provide editable prebuilt starting points rather than locking the player to fixed equipment.
- [x] Ordered AHU layouts, duplicates, housing-sensor state, and a legacy boolean component summary persist through the existing versioned project save/load path; older AHU objects are translated into their original airflow order when rendered.
- [x] Simple 2 m LDraw supply-duct segments are grid-placeable, rotatable, selectable, undoable, and persisted with service/profile metadata.
- [x] Interactive socket picking, waypoint duct authoring, supply-tee placement, placed-AHU re-editing and route-driven duct generation are available. Direct dragging of existing bend handles remains a later refinement.

## Milestone 4 — demo expansion

- [x] Reversible normal, hot-afternoon, fan-failure, stuck-damper, dirty-filter, sensor-bias, and data-interruption scenarios are selectable.
- [x] Dirty filter constrains available flow and raises indicated pressure drop; sensor bias changes measured rather than physical temperature; data interruption marks values stale without fallback.
- [x] Bounded 30-second history store with explicit reset boundaries and alarm state with threshold delays.
- [ ] Six-zone physical office, trend rendering, alarm acknowledgment UI, stairs/multi-floor navigation, and the hot-water loop remain.

## Actual test results

- PASS — Godot 4.7.2 import completed and registered all global classes (`--headless --editor --import`, 2026-09-13).
- PASS — Main scene ran for five headless frames with no parser or runtime errors (`--headless --quit-after 5`, 2026-09-13).
- PASS — 7/7 deterministic simulation/provider tests: reset, setpoint response, fan-failure airflow decay, disconnected branch, flow conservation, point normalization, and LIVE write rejection.
- PASS — 9/9 after adding stable-ID save round-trip and undo/redo coverage.
- PASS — 11/11 after adding typed port compatibility/loop/invalidation checks and history sample/boundary checks.
- PASS — 15/15 after adding all 17 selected LDraw runtime-mesh checks, editable AHU save/load, wall-run/opening save/load, and property undo/redo coverage (`--headless --script res://tests/run_tests.gd`, 2026-09-13).
- PASS — All 18 selected OBJ files load with one non-empty Godot mesh surface; selected source and dependency attribution is retained in the LDraw manifest.
- Environment note — the restricted test sandbox denied Godot writes beneath `~/Library/Application Support` and `~/Library/Caches`; commands still exited successfully and project tests passed.
- PASS — Windowed 1280×800 render on Apple M4 Max using OpenGL/Metal compatibility; LDraw studs, plates, walls, VAVs, AHU, ductwork, diffusers, functional colors, and native UI were visibly present. Verification capture: `/tmp/bas-sandbox-ldraw-final.png`.
- PASS — Windowed AHU Builder render isolated the configurable LDraw assembly on its own work surface with component toggles and placement action. Verification capture: `/tmp/bas-sandbox-ahu-builder-final.png`.
- PASS — Windowed runtime smoke verified fan rotation and coil-fill motion, created a three-module wall run, hosted a window in its center module, saved/reloaded six stable-ID objects, retained AHU component data, and switched build/walk cameras (`RUNTIME_SMOKE PASS objects=6`).
- PASS — Rendered 1280×800 floor-plan check shows the official LDraw door/window assemblies and reduced-detail brick VAV (`/tmp/brick-bas-floor-final.png`).
- PASS — Rendered 1280×800 AHU Builder check shows open-front modules, visible animated fan blades, and a partially filled cooling-coil face (`/tmp/brick-bas-ahu-final.png`).
- PASS — Rich HVAC hero render visibly separates multi-piece damper, filter, coil, fan, and sensor assemblies at gameplay scale (`/tmp/brick-bas-ahu-rich-pass1.png`).
- PASS — Updated floor-plan render shows the expanded open-face VAVs with collars, actuator, internal damper, and simplified reheat bank in context (`/tmp/brick-bas-hvac-rich-floor-pass1.png`).
- PASS — Final Forward+ AHU render visibly resolves studs, grille depth, damper vanes, coil rows, fan shroud, contact shadows, and material separation (`/tmp/brick-bas-render-final.png`).
- PASS — Final Forward+ floor-plan render retains readable architecture and HVAC silhouettes under the upgraded lighting (`/tmp/brick-bas-floor-render-final.png`).
- PASS — Normal-renderer smoke reran under Metal Forward+ and retained animation, six-object save/load, hosted opening, and camera switching (`RUNTIME_SMOKE PASS objects=6`).
- PASS — Shadow-corrected floor-plan render visibly replaces the former per-brick dark bands with subtle wall-course joints and one coherent shadow per equipment assembly (`/tmp/brick-bas-shadowfix-floor-final2.png`).
- PASS — Shadow-corrected AHU Builder render shows clean fan, coil, filter, sensor, and damper subparts without a separate cast shadow around every LDraw piece (`/tmp/brick-bas-shadowfix-ahu-final2.png`).
- PASS — 15/15 tests reran after mirrored-winding conversion, material-culling, assembly-shadow, and wall-face changes (`--headless --script res://tests/run_tests.gd`, 2026-09-13).
- PASS — 16/16 tests after adding the exact stud/plate lattice, native-scale enforcement checks, and official 40598a runtime mesh (`--headless --script res://tests/run_tests.gd`, 2026-09-13).
- PASS — Native-fit AHU Builder render verifies unscaled LDraw housing, grille, plate, tile, fan, and sensor elements with hard face normals and matte materials (`/tmp/brick-bas-native-fit-ahu-final.png`).
- PASS — Native-fit floor render verifies the full-size AHU inside a clear rear mechanical bay rather than intersecting the room divider (`/tmp/brick-bas-native-fit-floor-final2.png`).
- PASS — Windowed native-fit runtime smoke retained fan/coil animation, hosted-opening placement, six-object save/load, and build/walk camera switching (`RUNTIME_SMOKE PASS objects=6`).
- PASS — Component-workbench render shows the ordered airflow readout, add/remove/clear controls, preset picker, independent housing sensor, separate component bays, and continuous simple housing (`/tmp/brick-bas-component-workbench-final.png`).
- PASS — 16/16 tests after ordered-layout persistence was extended to cover duplicate filters and independent housing-sensor state (`--headless --script res://tests/run_tests.gd`, 2026-09-13).
- PASS — Windowed workbench smoke built `filter > cooling coil > filter > fan`, disabled the housing sensor, placed the custom AHU, saved/reloaded it, retained animation, and verified the exact ordered layout (`RUNTIME_SMOKE PASS objects=6`).
- PASS — 16/16 automated tests after extending the brick-lattice test with odd/even footprint centering, four-receptor floor support, unsupported-wall rejection, floor-footprint overlap rejection, and explicit edge-connection checks (`--headless --script res://tests/run_tests.gd`, 2026-09-13).
- PASS — Architectural runtime smoke rejected an overlapping floor plate and unsupported wall, then placed/saved/reloaded a four-stud-supported wall run, explicit hosted window, and edge-connected floor plate (`RUNTIME_SMOKE PASS objects=5 ... rejected_invalid=true opening_host=true wall_clutch=true floor_edge=true`, 2026-09-13).
- PASS — Windowed 1280×800 compatibility render after correcting all built-in architectural anchors visibly shows walls, windows, and the door seated on the exposed floor-stud rows (`/tmp/brick-bas-architectural-clutch-final.png`, 2026-09-13).
- Pending — hands-on pointer acceptance for drag/release wall creation, red/green invalid-placement feedback, door/window hosting, and first-person traversal through a newly placed door remains separate from automated model/runtime proof.

## Godot agent skills

- Verified `gamedev-skills/awesome-gamedev-agent-skills` on 2026-09-13: active repository, latest push 2026-09-10, Apache-2.0, and the selected engine skills explicitly target Godot 4.7.
- Installed project-local copies for Codex: `godot-gdscript`, `godot-nodes-scenes`, `godot-3d-essentials`, `godot-physics`, `godot-ui-control`, `save-systems`, and `create-game-assets`. The Godot-specific skills received the installer's low-risk assessment; no paid service or runtime dependency is introduced.

## Remaining work

- Building editor: moving an entire bonded wall run, running-bond/corner cosmetics, automatic enclosed-room detection/assignment, and an in-game save browser remain. Individual floor/wall/equipment placement already uses deterministic stud/receptor support; this is intentionally not a loose-brick rigid-body destruction simulator.
- Mechanical editor: direct dragging of existing duct bend handles and additional connector/profile transition families remain. Tees, explicit sockets, compatibility, automatic obstacle avoidance, native VAV internals and route-driven simulation are complete for the current supply-air kit.
- Per-component mappings now retain stable component records, but repeated components still share their role-level animation binding in the current UI. A per-instance point picker is a later refinement.
- Niagara live verification: the read-only connection UI, SCRAM bridge, health check, WebSocket provider and reconnect fixtures are complete and pass against a local mock BASkStreamService. A real station acceptance run was not performed; its reachability, certificate, deployed capabilities and point ORDs remain environment-specific evidence.
- Explicitly deferred by the user's current request: six-zone simulation, trends, alarm acknowledgement, multiple floors/stairs and hot-water-loop gameplay.

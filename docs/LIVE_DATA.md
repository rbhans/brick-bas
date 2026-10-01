# Live station data

On desktop, Creative mode can run on a real Niagara station instead of the simulation. The equipment you build animates from the station's points: fan speed, damper and valve positions, airflow. The cards show the station's readings with history trends, the BAS view tints rooms by their live temperature, and the alarm list shows the station's open alarms. It is read-only end to end. The browser edition runs on the simulation only.

## How it connects

```
Godot (game) ──JSON over ws://127.0.0.1:<random port>/baskstream──▶ bridge (Node) ──baskStream SDK──▶ station /stream
```

- **Bridge**: `scripts/baskstream-bridge.mjs`, built on the baskStream SDK (`@basidekick/baskstream`, vendored in `vendor/baskstream-sdk`; refresh it with `npm run vendor:baskstream`). The SDK handles Niagara's SCRAM web login (verifying the station's signature), the WebSocket, keepalive, reconnect with backoff, and leased subscription groups that renew themselves and come back after a reconnect.
- The game starts the bridge on demand with `OS.execute_with_pipe`. It uses port 0 (the bridge reports the port it got on its first stdout line), `--owned` (it exits when the game's end of its stdin closes, including after a crash) and a one-time `--token`.
- **Read-only**: the bridge exposes only `hello`, `connect`, `disconnect`, `browse`, `search`, `describe`, `read`, `watch`, `history`, `alarms` and `ping`. Writes, alarm acknowledgements, schedule writes and model edits don't exist on it. `LiveStation.write_point` returns false, and thermostats can't be adjusted while live.
- **Local only**: the bridge listens on 127.0.0.1, needs the token, and refuses any WebSocket that carries an `Origin` header (every web page sends one; the game doesn't), so a page in your browser can't drive it.
- **Secrets**: the station address, username and certificate choice save with the build. The password goes to the bridge, which keeps it in memory for reconnects, and is never written anywhere.

### Bridge protocol

Game → bridge frames are `{op, id, ...}`. Replies are `{op: "<op>_result", id, ...}` or `{op: "error", id, code, message}`. The bridge also pushes `{op: "values", points}` (batched COV for watched points, every 120 ms at most) and `{op: "status", status: "reconnecting" | "connected", message}`.

| op | fields | result |
| --- | --- | --- |
| `hello` | `token` | `readOnly: true` |
| `connect` | `station`, `username`, `password`, `allowSelfSigned`, `name` | `info: {name, station, username, apiVersion, writesEnabled}` |
| `browse` | `ord` | `node`, `children` |
| `search` | `query`, `limit` | `nodes`, `truncated` |
| `read` | `points` | `points` |
| `watch` | `points` (replaces the set; at most 500) | `points`, `truncated` |
| `history` | `ord`, `hours` | `buckets: [{t, avg, min, max}]` |
| `alarms` | | `alarms: [{uuid, priority, ackState, source, message, …}]` |

ORDs come back as `slot:/…`. Values are `{point, ok, value, display, status, timestamp, valueType, units}`. In the game (`LiveStation.normalize`) they become ordinary points: the point id is the ORD, the source is `niagara`, and the quality comes from the status (`{stale}`, `{fault}`, `{down}`, `{disabled}`, and a failed read are not "good"; overrides and alarms stay good with an extra flag).

## Using it

1. **New game → Creative**, pick **Live Niagara station**, then a starter. Or use Menu → **Live station** at any time.
2. Enter the station's address, user and password (tick self-signed if it uses one), then **Connect**. **Try the demo station** starts `tools/demo_station.mjs` on this computer (a stand-in station with an AHU and three VAVs whose values move) and connects to it.
3. Select a piece of equipment and open its details (⋯). On a live station they open on **Live station**: search or browse the station, open a controller's folder, and press **Auto-map from this folder**. `PointMatcher` reads the points list the way an integrator would. It matches `DamperPos`, `DMPR-FB`, `ZN-T`, `SA-FLOW`, `HwVlvPos`, `SupplyFanSpd` and similar names, prefers feedback to command, and never takes a setpoint. You can also select one point and **Link** it to a role.
4. Linked points stream live: the unit animates, its card lists each reading and trends it (starting with four hours of the station's own history), and its room's temperature tints the BAS view against the 68–76.5 °F comfort range.

Roles: fan, damper, cooling coil, heating coil, airflow, and room temperature (VAVs and thermostats; it drives the overlay and readouts, not motion). Units come from the station's facets, so a CFM airflow is scaled to the box's design CFM.

**Back to the simulation** (or Menu → Simulation) switches back. Linked points stay saved and resume when you reconnect. Career jobs always run on the simulation.

## Testing

- `npm run test:bridge` runs `tests/bridge.test.mjs`: the bridge through the real SDK against the demo station (login, browse, search, read with units, watch and COV pushes, history, alarms, the read-only refusals, token and origin checks, a bad password, and live values resuming after the station drops).
- `tests/live_station.gd` runs through the real game: it starts both Node processes, refuses a wrong password, connects, browses and searches, auto-maps a VAV from the details panel, and checks that the VAV animates, the readouts, trends, room temperature and station alarms come from the station, nothing writes, and switching back works.
- `npm run demo-station` starts the stand-in station by hand on port 8790 (user `operator`, password `brick-bas-demo`).

Requirements: Node.js 20+ and `npm install` in the project folder.

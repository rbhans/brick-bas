# Browser build

The same Godot game now exports as a static website. Players need a desktop browser with WebAssembly and WebGL 2, plus a keyboard and mouse. There is no account, database server, save API, or per-player backend.

## Build and preview

```sh
npm run web:build
npm run web:serve
```

Open `http://127.0.0.1:8060`. The preview server binds only to localhost and serves only `dist/web`, not the repository. `GODOT_BIN` can override the Godot executable; `BRICK_BAS_WEB_PORT` can override the preview port. Node dependencies are not required for these two scripts. `npm install` is only needed for the desktop Niagara bridge.

The editor and templates must both be **Godot 4.7.2**. The official web templates are already cached for this checkout. To reproduce on another machine, download [the official export templates](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz), then extract `templates/web_nothreads_release.zip` and `templates/web_nothreads_debug.zip` into `.cache/godot-web/` without their `templates/` directory. Do not unzip the two inner ZIP files. The full source archive SHA-256 verified against the official release metadata is `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.

The build command imports resources, exports the Web preset, and includes engine/asset licenses. It fails on Godot script/import errors, including errors that Godot reports with a zero exit status. Desktop rendering remains Forward+; web uses Compatibility, single-threaded WebAssembly, bundled fonts, and WebGL-compatible placement ghosts/camera cutaways.

## Publish

Live at [robboborben.xyz/demos/brick-bas/](https://robboborben.xyz/demos/brick-bas/), linked by **Play in browser** on the [project page](https://robboborben.xyz/projects/brick-bas).

The game ships from this repo as its own Cloudflare Worker, `brick-bas` (`wrangler.jsonc`, `deploy/worker.ts`). It has no public URL of its own: the personal site's Worker forwards `/demos/brick-bas/*` to it through the `BRICK_BAS` service binding, so the address (and players' browser saves) stays the same while the game deploys independently:

```sh
npm run deploy
```

That runs the web export, lays out `dist/site/demos/brick-bas` (`tools/package_site.mjs`), checks it with `deploy/worker.test.mjs` and runs `wrangler deploy`. The 38 MiB engine is stored as a ~10 MiB `index.wasm.gz` (the static host's per-file limit is 25 MiB). `deploy/engine.ts` serves the normal `index.wasm` URL with `application/wasm`, gzip or a decoded fallback, and conditional requests. `bundle.json` records every shipped file's decoded SHA-256. The site never needs redeploying for a game update.

For other hosts, upload **the contents of `dist/web/` only**, preserving filenames. Do not upload the repository, `.cache`, `node_modules`, native user data, connection bridge, or test artifacts.

- Serve `.wasm` as `application/wasm`, `.js` as JavaScript, and `.pck` as `application/octet-stream`.
- Enable HTTP gzip/Brotli for `.wasm`, `.pck`, and `.js`; the raw engine is approximately 38 MiB, so check the host's per-file limit before choosing it.
- Revalidate `index.html`, `index.js`, and `index.pck` on updates rather than permanently caching unchanged filenames. Deploy the bundle together.
- No COOP/COEP cross-origin isolation headers are required because this preset does not use threads.
- Serve it as a top-level page. Cross-site iframes can restrict persistent storage.
- Keep the same origin (scheme, hostname, port) to preserve access to existing browser saves. Use a dedicated game origin if other apps need separate storage. Moving domains does not migrate saves automatically.
- Keep the credits and license files with the game. The project menu links to the credits.

The export is not a PWA and does not promise offline reloads. Once loaded, the demo simulation needs no network connection. Touch/mobile controls and a Safari/Firefox acceptance pass are not included in this conversion.

## Saves and backups

The existing versioned JSON save uses Godot `user://`, backed by the browser's **IndexedDB**, not `localStorage`. Save/Load remains in the project menu. Save triggers a filesystem sync; persistence is also requested where the browser supports it. Browser/private-mode policies and disk pressure can still prevent persistence or evict data. The app warns when Godot reports that storage is unavailable.

Saves belong to the current browser profile and website origin. They do not sync between devices. Clearing site data removes them. **Download backup** writes a JSON file to the user's downloads; **Import backup** uses the local file picker and never uploads it. Invalid schemas are rejected before replacing the current model. Import preserves the previous in-memory model as `user://before_import.json`, does not replace the manual Save slot, and starts in demo mode. Click Save after importing to make it the saved browser build. Current limits are 8 MiB per imported save, 20,000 object records, and 512 segments per wall/duct record.

Passwords and session cookies are not saved. Files are data only, never executable Godot resources. Native JSON save files use the same schema and can be imported into the web version. The browser's working copy removes station profiles and converts live animation bindings to the corresponding demo defaults. Existing demo mappings are preserved. The original imported desktop file is not modified.

## Niagara boundary

The browser edition is **demo-only**. There is no Connections tab, protocol fixture, station credential form, or live source in its animation controls. Scenarios and demo point mappings still drive fans, coils, dampers and airflow. Runtime guards block both live and fixture activation. The desktop provider boundary and connection functionality remain in place.

A later live web version needs a separately secured, browser-compatible gateway, trusted HTTPS/WSS, origin controls, and network access to the station. This build does not expose the current localhost bridge publicly, proxy credentials through the static host, bypass TLS, or automatically connect to a saved station.

## Explore controls

WASD walks, Shift runs, Space jumps, drag with either mouse button to look around, and the wheel zooms. Doors open as the minifigure walks into them and close behind it; E uses whatever is in front: sit, adjust a thermostat (+ / − in 1 °F steps), open an AHU access door, lift a VAV casing, or show the airflow at a diffuser. Overhead ducts and equipment near the player are hidden in the browser build (the Compatibility renderer has no per-object fade). No pointer lock is required.

## Links, graphics and first run

- **Deep links:** `?starter=studio|office|school|blank`, `&mode=equipment|explore` and `&graphics=auto|high|low` open straight into a starter (skipping the home screen), e.g. `/demos/brick-bas/?starter=school&mode=explore`. Only these values are accepted.
- **Graphics:** Menu → Graphics offers Auto, High and Low. Low drops shadows and MSAA and renders 3D at 75 % resolution. Auto starts High and switches to Low once if the frame rate stays under about 38 fps. The choice is remembered.
- **First run:** after the first starter is picked, a four-step tour runs (Build → Equipment → Watch it run → Explore). Menu → "Show the quick tour" brings it back.
- **Touch devices** get a note that the game is made for a mouse and keyboard; it still loads.

## Older saves

Saves from the pre-rework build (format v1) load automatically: floors and walls are converted onto the 2.5 m tile grid, doors and windows move with their walls, and equipment keeps its ids. Loose terrain pieces are dropped and the simulation checkpoint restarts. The original file is not modified until you save again.

Authoritative platform details: [Godot web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) and [JavaScriptBridge](https://docs.godotengine.org/en/stable/classes/class_javascriptbridge.html).

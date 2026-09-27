# Asset credits

## Web distribution

The browser build uses Godot 4.7.2, including its bundled fallback font. The engine is MIT licensed: [Godot license](https://godotengine.org/license/). The exported folder includes `GODOT-LICENSES.txt` with copyright notices and license texts read from the installed engine, `LDraw-AUTHORS.json` with per-part provenance, `LDraw-LICENSE.txt`, and `Audio-LICENSE.txt`. These files must travel with the web build. No CDN font or analytics service is used.

## LDraw Official Parts Library 2026-08

- Source: <https://library.ldraw.org/library/updates/complete.zip>
- Project: <https://www.ldraw.org/>
- Downloaded: 2026-09-13
- Source archive SHA-256: `d2a695868ed2b3957c45b022a6451908edab22cc043179dd61d18dd382b35e11`
- License for every selected part and dependency: CC BY 4.0, as recorded by each bundled DAT file's `!LICENSE` header and the retained `CAreadme.txt` / `CAlicense4.txt`. Twelve older parts are dual-licensed "CC BY 2.0 and CC BY 4.0" in their headers; this project uses them under CC BY 4.0.
- Selected official parts: 2431 tile 1×4, 2877 brick 1×2 with grille, 3001 brick 2×4, 3003 brick 2×2, 3004 brick 1×2, 3010 brick 1×4, 3020 plate 2×4, 3022 plate 2×2, 3031 plate 4×4, 3039 45-degree slope 2×2, 3853 window 1×4×3, 3855b window glass, 3941 round brick 2×2, 40598a venting-disc/fan element, 60596 door frame 1×4×6, 60616b smooth door, 6141 round plate 1×1, and 98138 round tile 1×1.
- Added minifigure parts: 973 torso, 3815b hips, 3816b/3817b legs, 3818/3819 arms, 3820 hands, and 3626c head. The figure uses source assembly coordinates and separate limb pivots; the eyes are simple project-authored geometry.
- Added for inlet clearance: 63864 tile 1×3, by Tim Gould, official update 2019-01. Replaces the overlong four-stud damper blades without deforming the part. Sourced from the same retained Official 2026-08 archive; CC BY 4.0 header and all eight required DAT files are bundled. The baked mesh has 312 vertices and 140 triangles.
- Added 2026-09-22 from a fresh official archive download (identical SHA-256): 3470 oval tree by Christian M. Angele, 2435 pyramidal tree by Ildefonso Zanette (used as a small shrub), 2417 foliage, 3024 plate 1×1 (thermostat body), and 3069b tile 1×2 (parking markings). The foliage is actual LDraw geometry at native scale; thermostat display/buttons are project-authored. All retain the source authors, licenses, and dependency DATs. The 2417 foliage is included for future landscaping assemblies but is not currently placed by the starter sets.
- Added 2026-09-25 for the building/HVAC rework, from the same official library source (`complete.zip` above): wall bricks (1×1 through 1×8, 1×2 and 1×4 plates and tiles for running-bond courses), the 60594/60596/60603/60623/57894/57895 door and window family, furniture parts (chairs, tables, cabinets, shelves, computers, plants, bikes, fences, lamp posts and more), and the extra slopes, tiles, round bricks, grilles and hinge parts used by the redesigned AHU, VAV, diffuser, fitting and thermostat models. The selection now holds **150 parts**; each keeps its author, license and dependency closure.
- Attribution, authorship, update provenance, and the selected dependency closure for all 150 parts are retained in `assets/third_party/ldraw/selection.json` and `assets/third_party/ldraw/source/`.
- `tools/ldraw_to_obj.py` produces the runtime OBJ meshes at 0.025 meters per LDraw unit. The complete 138 MB library is not included and is not a runtime dependency.

LDraw is an unofficial, community-run CAD system representing parts produced by the LEGO Group. LEGO is a registered trademark of the LEGO Group, which does not sponsor or endorse this project.

## Kenney Brick Kit 1.0

- Creator: Kenney, <https://kenney.nl>
- Source: <https://kenney.nl/assets/brick-kit>
- Release date in bundled metadata: 2024-05-29
- Source archive SHA-256: `b303d293c278fab713eed28395829b18513b171d2562f7f518c3355c2896861a`
- License: CC0 1.0 Universal. Personal, educational, and commercial use are permitted; attribution is optional.
- Local evidence: `assets/third_party/kenney_brick_kit/License.txt`

The earlier prototype's selected 14-model GLB subset remains in the repository for provenance but is no longer loaded by the playable scene. Current architecture, equipment housings, components, and minifigure use the selected LDraw kit above. Duct lids and opposing vertical access plates now reuse actual 3022 plate 2×2 meshes at native size. Hollow duct bodies, custom tapered equipment sockets/end frames, module joint details, airflow indicators, collision proxies, and UI layout are project-authored. The custom duct fittings are not official LEGO/LDraw parts. They use a 1.0 m outer profile and 0.6 m air passage; adapters match the existing uniformly reduced VAV assembly.

## Maaack Godot Game Template: Lab theme

Retained as provenance for the previous UI. The current toy UI uses a project-authored native theme instead; it does not load this `.tres` theme at runtime.

- Source: https://github.com/Maaack/Godot-Game-Template
- Retrieved and reviewed: 2026-09-13; the Godot listing showed an update on 2026-09-10.
- License: MIT; retained at `assets/third_party/maaack/LICENSE.txt`.
- Source archive SHA-256: `45f4b6115fd0bf2f45f3ed18dbf6fafb4f6839d10d25cdd32d0b1fcadf7d1a51`.
- Reused asset: `resources/themes/lab.tres`, stored as `assets/third_party/maaack/lab.tres`.
- No longer used at runtime; kept for provenance only. No template autoloads, save services, telemetry, or networking were imported.

## Kenney Interface Sounds

- Creator: Kenney. Source: https://kenney.nl/assets/interface-sounds
- Downloaded: 2026-09-13. License: CC0; retained at `assets/third_party/kenney_interface/License.txt`.
- Source archive SHA-256: `f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`.
- Selected: `click_001.ogg`, `click_002.ogg`, `drop_001.ogg`. The active placement cue is `click_001.ogg`, a 0.100023-second sample, with restrained pitch variation.
- These are generic interface/placement sounds, not recordings or licensed audio from a LEGO game. No subscription, account, attribution fee, or runtime download is required.

## Toy UI concept and component thumbnails

- Concept: generated with the built-in image-generation tool on 2026-09-13 using the previous actual game screenshot as context. Saved to `docs/ui-concepts/toy-builder-concept.png`; full prompt and implementation decisions are recorded in `docs/ui-concepts/design-notes.md`. The concept is documentation, excluded from runtime import.
- Runtime UI: project-authored native Godot Controls, StyleBoxes, vector symbols and dynamic text. No extracted generated labels, copied commercial game UI, or new external UI package.
- Thumbnails: `assets/ui/thumbnails/`, rendered in Godot from the actual assemblies by `tools/bake_arch_thumbnails.gd` (rooms, walls, floors, doors, windows, plants) and `tools/bake_catalog_thumbnails.gd` (furniture and equipment). LDraw-derived imagery retains the CC BY 4.0 attribution above; duct geometry is project-authored.
- Font: runtime system-font selection with Avenir Next / Nunito Sans / generic sans-serif fallbacks. No font file was downloaded or redistributed.

Starter cards are renders of the actual editable starters (walls down, HVAC visible), baked by `tools/bake_starter_cards.gd`; they are not concept art. LDraw attribution above applies to these renders too.

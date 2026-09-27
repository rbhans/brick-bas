# Open-source brick construction technology review

Verified 2026-09-13 for the offline Godot prototype.

## Adopt now

- [BrickBuilderMCP](https://github.com/jonx/BrickBuilderMCP), MIT. Its useful boundary is the deterministic System-brick model: 20 LDU per stud, 8 LDU per plate, stud-to-bottom-receptor mating, overlap rejection, floating-part rejection, and connection-to-ground validation. The prototype ports that small construction-space concept into `scripts/build/brick_grid.gd`; it does not embed the Python server or require MCP at runtime.
- [LDraw Official Parts Library](https://library.ldraw.org/), per-file CC BY terms retained with each source. It remains the geometry source of truth.

## Evaluate for later connector work

- [Sim Studio](https://github.com/WorketeWorks/SimStudio-LEGO-Technic-Physics-Simulator), MIT. It has connection maps, compound colliders, configurable joints, runtime engagement, and diagnostic editors. Its connector/collider boundary is relevant when axles, gears, motors, or physical fan shafts become interactive; its Three.js/Rapier runtime is not a drop-in Godot dependency.
- [LDCad Shadow Library](https://github.com/RolandMelkert/LDCadShadowLibrary), CC BY-SA 4.0. Its `!LDCAD SNAP_*` metadata is the strongest catalog-scale source for pins, axles, clips, hinges, and inherited connection features. It should be ingested as attributed build-time data rather than hand-entered per-part guesses.
- [LeoCAD](https://github.com/leozide/leocad) is a mature open-source LDraw CAD implementation and a useful BFC/rendering reference. Replacing the game runtime with a CAD application would not solve gameplay construction or Godot integration.

## Reference only

- [multi-box-3d](https://github.com/pdaddyo/multi-box-3d) demonstrates an effective Godot 4.7 face-anchor editor and implicit rigid construction. GitHub currently reports no repository license, so no source or assets will be copied unless clear reuse terms are added.
- [Legolization](https://github.com/hbmartin/legolization), GPL-3.0-or-later, solves whole-model structural stability and repair. It is substantially heavier than the current System-brick placement need and would impose a stronger software-license boundary.

## Project decision

Use exact stud/plate coordinates and native, uniformly scaled LDraw parts for the playable builder. Validate simple System connections locally. Add LDCad/Sim Studio-style feature data only when the milestone introduces non-stud mechanical connectors. Keep Godot collision proxies separate from connection semantics: a collider answers whether volumes intersect, while a connector answers whether two parts are legally mated.

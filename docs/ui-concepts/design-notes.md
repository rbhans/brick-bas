# Toy builder UI

Generated concept and native implementation, 2026-09-13.

## Direction selected

The user rejected the generic light application UI and asked for a minimal LEGO-like game interface developed with image generation. The built-in image-generation tool produced `toy-builder-concept.png`, using the previous workbench screenshot as scene context. The generated image is a design reference, not a screenshot of the implemented game.

The implementation uses native Godot Controls: small studded mode tiles, charcoal contextual tools, a warm cream parts tray, yellow active states, and a green place control. Full-width navigation/status panels and the permanent properties sidebar are removed. Detailed forms and simulation settings open on demand. The workbench omits the selected floor equipment card because that data does not describe the assembly preview.

Technical frame: Godot 4.7.2 / Forward+, base viewport 1440 by 900, native responsive anchors and Containers. Labels, focus, hover, press states and vector symbols are code-native, not baked into a raster interface. Thirteen 256 by 224 RGBA thumbnails are rendered from the existing LDraw assemblies using `tools/bake_ui_thumbnails.gd`. They are imported once; the game does not create 13 extra live viewports. No Blender or new downloaded asset library was needed.

The generated target informed composition, physical button depth, sparse stud details and color roles. It is not claimed as pixel-perfect reproduction: the playable scene keeps its real meshes and renderer, and the native controls adapt to content.

## Generation record

- Tool: built-in image generation, not the API/CLI fallback.
- Reference: `docs/evidence/workbench.png`, the previous actual game capture.
- Output: `docs/ui-concepts/toy-builder-concept.png`; original retained under the Codex generated-images directory.
- Runtime: `scripts/ui/toy_builder_ui.gd`, `toy_button.gd`, `toy_theme.gd`, `toy_tray.gd`, `toy_symbols.gd`.
- Native evidence: `docs/evidence/toy-workbench.png`, `toy-floor.png`, `toy-binding.png`.

## Full generation prompt

Use case: ui-mockup. Create one polished, buildable 16:9 in-game UI concept for a LEGO-inspired offline building sandbox named BRICK / BAS. The attached image is the EXISTING GAME for context, not a UI to preserve. Keep the same recognizable teal brick-built AHU with fan/coil/damper, but redesign the interface radically. User asks: MINIMAL, clearly a toy construction GAME, not an app dashboard and not generic AI SaaS rounded panels. Aim the craftsmanship of a premium contemporary cozy construction game with restrained tactile molded plastic.
Composition: the 3D brick equipment occupies a generous clear central 75% against the existing dark studio backdrop. No permanent right sidebar, no full width top navbar, no white cards around everything. Small top-left brand lockup on a red 2-stud plastic tile, elegant white BRICK / BAS lettering nearby. Three compact toy-tab mode buttons Build / Equipment / Explore at top center, selected Equipment in warm yellow with an inset dark pictogram; other modes dark desaturated charcoal. Tiny undo/redo/settings icons top right.
Bottom-center is a SINGLE low, beautifully sculpted warm ivory parts tray occupying roughly 65% width and 14% height: rounded-square physical slots containing miniature 3D render thumbnails of actual parts (damper, filter, blue coil, red coil, fan, sensor), very short embossed dark labels underneath, selected slot mustard yellow. Refined thin bevel highlights, tiny shadows, excellent contrast, tactile but not chunky cartoon over-decoration. A small green triangular place/play tile on tray right. Above tray a compact lineup strip showing 4 tiny numbered colored tiles joined by small arrows. Small AHU / VAV selector near that strip, no form fields everywhere.
On selection only, show a SMALL floating charcoal equipment card upper right, about 210px by 140px, with 'AHU-1', three icon actions for open casing / paint / link point and a compact 'Demo · fan 72%' readout. This is a context tool, not a tall property inspector. Include a tiny bottom-left shortcut hint 'R rotate · Esc cancel'. No full status bar.
Visual style: cream/offwhite plastic, charcoal bluegray, one warm yellow selection accent, tiny red brand brick, green commit control. Stud motifs used sparingly, maximum 2 or 4 on any broad panel. No gradients over every surface, no neon, no purple, no glassmorphism, no webpage layout, no big title blocks, no grids of text-only buttons, no LEGO corporate logo. Crisp understated typography and custom pictograms. This must look like a shippable game screen, not a moodboard.

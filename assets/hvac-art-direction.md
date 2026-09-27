# HVAC visual target

- Engine/view: Godot 4.7 Forward+, three-quarter orbit camera, 1280×800 verification frame.
- Shape language: chunky brick-built housings with open service faces and clearly separated internal assemblies.
- Detail density: 6–12 visible pieces per major component; omit wiring, fasteners, and small pipe fittings unless they affect function.
- Silhouette priorities: round VAV collars, repeated damper vanes, pleated filter bank, layered coil face, radial fan, compact sensor pod.
- Materials: moderately rough molded-plastic/LDraw surfaces with controlled specular response. Color is semantic support, not the source of component identity.
- Lighting: sky ambient/reflections, one warm shadowed key, restrained cool fill, ACES tone mapping, SSAO/SSIL contact depth, 4× MSAA, and TAA.
- Motion: steady mechanical fan rotation; dampers move with feedback; coil output fills across rows from bottom to top.
- Collision: simple equipment boxes remain separate from visual LDraw geometry.
- Acceptance: each component must remain recognizable in the floor-plan camera and in the isolated AHU Builder view.

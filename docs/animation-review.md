# Animation review: expanded builder

Reviewed 2026-09-13 with the review-animations skill. Applied its motion principles to native Godot Node3D/Control behavior; browser-only CSS prescriptions are not applicable.

| Before | After | Why |
| --- | --- | --- |
| Placed fan and coil visuals read the demo simulation directly. | Renderers consume an explicit normalized binding sample from PointStore. Invalid/stale/inactive-source samples hold equipment state; airflow disappears and the inspector reports unknown. | A convincing animation must not misrepresent the source or quality of its data. |
| Continuous equipment motion had no reduction control. | Reduce motion stops fan rotation and moving air indicators, reduces limb swing and applies damper state directly. Coil color/level remains readable. | Keep operational state without requiring continuous motion. |
| Workbench motion could be confused with selected equipment feedback. | The workbench explicitly labels its 65% sample motion. Placed units use their saved bindings. | Authoring preview and feedback are different states. |
| Rapid placement could restart the short audio cue repeatedly. | A currently playing cue is allowed to finish; concurrent placement events are coalesced. | Short, restrained placement feedback avoids an abrasive repeated transient. |

## Verdict

No blocking UI-motion regression found in this pass. Frequent tools, tabs, undo, and cutaway toggles respond immediately without ornamental transitions. Damper/fill updates retarget their current transform rather than restarting an entrance animation. Fan rotation and airflow direction communicate operation rather than decorating the panel.

### Origin, physicality and cohesion

The minifigure's gait uses independent limb pivots on actual LDraw parts. Duct indicators follow each segment's centerline; this is an explanatory flow cue, not simulated fluid. Continuous mitered duct geometry is present, but tees and connected-equipment route semantics remain unfinished.

### Performance

Motion uses Node3D transforms and visibility, not Control layout animation. The final native smoke passed, but this is not a frame-time benchmark. Large-layout profiling remains required before making performance claims.

### Accessibility

The in-app Reduce motion toggle is implemented and fan suppression is exercised in runtime tests. Automatic synchronization with the operating system's accessibility preference is not implemented. The setting is not yet persisted between launches.

Verification: 18 automated test groups; native Metal smoke; inspected workbench/minifigure captures; hands-on builder and binding-form interactions. No subjective audio listening sign-off.

---
status: stub
depends_on:
  - ./07b2-input-and-turn-advance.md
---

# Perspective switch + fog of war

Third of four sub-PRs. Toggle between Player A's and Player B's views with each rendered using its own fog of war (per-entity vision per ADR-0016).

## Likely scope

- Perspective toggle in HUD (button or hotkey).
- Per-player vision computation: gather all entities owned by the active player, union their `VisionDef.sight_radius`-tiles into a visibility mask.
- Fog overlay shader on a `ColorRect` overlay fed from a `SubViewport` we draw white circles into for each unit's vision radius (pattern from `godot-open-rts`).
- Two-state visibility (currently visible / previously seen) — red/green channels in the mask texture.
- Hidden-entity rendering: enemies in fog don't show; previously-seen buildings in fog show as silhouettes.

ADR-0016 (fog of war from M0) lands here.

To be detailed once 07b2 lands.

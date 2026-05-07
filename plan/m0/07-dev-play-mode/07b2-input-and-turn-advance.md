---
status: stub
depends_on:
  - ./07b1-renderer-and-camera.md
---

# Input + manual turn advance

Second of four sub-PRs splitting the visual half of plan node 07. After this lands, a developer can issue orders for either player and advance the turn manually — the simultaneous-turn loop becomes operable for the first time.

## Likely scope

- Mouse selection (click to select; selection state lives in MatchState, not the views).
- Right-click → MOVE / ATTACK / GATHER / BUILD targeting based on the selected unit and what's under the cursor.
- "Resolve turn" button that calls `Resolver.resolve(state, submit_a, submit_b, registry, tunables)` and feeds the result into `MatchRenderer.render_step`.
- HighlightLayer TileMapLayer for hover/selection/range tiles (allocated in 07b1's scene tree but unused there).

To be detailed once 07b1 lands.

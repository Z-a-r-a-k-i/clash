---
status: stub
depends_on:
  - ./00-play-mode-consolidation.md
---

# Graphics pass — stay 2D, make it readable

**Decision to confirm: stay 2D at M1.** Moving to 3D is *not* easier — it
swaps cheap sprite work for modeling/rigging/animation/lighting/camera work
and gains nothing for a tile-grid WeGo game. The sim/view split means 3D
remains a pure presentation-layer swap later if the game earns it (an ADR
should record this). What actually hurts today is readability, not dimension.

Scope (ordered by readability value):

- **Terrain**: real tilemap art for ground/impassable/chokes instead of flat
  color; the 1v1 map (node 03) is the showcase.
- **Units**: directional facing (flip/rotate by last move/attack vector),
  idle/move/attack frame sets where sprites allow; per-player tinting that
  survives on all terrain.
- **Statuses**: consume the reserved presentation hints — `sprite_key`
  swaps the sieged tank sprite (asset already exists:
  `data/art/sprites/siege_tank.png`), `overlay_keys` render rings/badges.
- **Combat feedback**: muzzle/impact flashes, floating damage numbers (events
  already carry damage + hp_after), death fade, focus-fire reticle polish.
- **Fog**: soften the explored/visible boundary; keep silhouette logic.

Constraints: renderer-only (no sim reads); sprite assets land in dedicated
asset PRs per repo convention; placeholder art is acceptable wherever it
doesn't block readability.

## Done when (to be refined when promoted to sketch)

- [ ] A spectator can read a recorded AI-vs-AI match without the debug grid:
      who owns what, who is shooting whom, what is sieged, where fog is.

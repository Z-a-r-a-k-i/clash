---
status: done
depends_on:
  - ./08-mvp-map.md
  - ./10-dev-play-human-playable.md
---

# M0 simple facing playtest map

The first human playtest map should be visually obvious before it is strategic:
two bases face each other, each player starts with four workers, and each base has
its resources behind it on the outside edge away from the opponent.

## Scope

- Replace the previous macro-map layout with one mirrored main base per player.
- Keep the existing 50×50 map dimensions and left-half authoring / mirror bake
  pipeline.
- Start each player with 4 workers.
- Place 8 standard mineral patches and 1 gas geyser behind each base.
- Keep resources within opening vision so the start view reads as a base and
  resource line, not an empty field.
- Update map tests to lock the simplified counts and behind-base placement.

## Non-goals

- No obstacles, ramps, cliffs, terrain blockers, naturals, thirds, or gold base.
- No pathfinding changes.
- No balance tuning beyond removing extra expansion resources from the opening
  playtest map.

## Done when

- [x] `mvp_map.tscn` authors 14 left-half placements.
- [x] `mvp_map.tres` bakes to 28 mirrored placements.
- [x] Resolver map tests assert two bases, eight workers, sixteen minerals, two
  geysers, and zero gold minerals in the MVP scenario.
- [x] Resolver map tests assert resources are behind each base.

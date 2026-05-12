---
status: done
depends_on:
  - ./00-config-and-tunables.md
---

# Tile grid + multi-tile occupancy

The foundation everything else depends on. Get this wrong and pathfinding, vision, range, and collision all need rewriting.

## What it is

- A square-tile grid map. Tile size is small enough that a unit or building occupies multiple tiles.
- Each placed entity has `{ origin: (x, y), footprint: (w, h) }`. No `entity.tile`.
- The grid stores occupancy as a 2D array of optional entity IDs (or a sparse map keyed by tile). Either is fine; the consumer interface is "what's at tile (x, y)" and "is the rect (x, y, w, h) clear."
- Configurable: tile pixel size, per-entity-type footprint. Both must be data-driven, not hardcoded — playtesting will dial them in.

## Open questions

- Entity rotation / facing? Probably no facing at MVP — buildings have a fixed orientation, units are direction-agnostic. Revisit if combat needs flanking.
- Diagonal adjacency for range checks? Probably yes — Chebyshev distance — but flag for playtest.
- Single map or multiple? **Single fixed map at MVP** (per ADR-style decision in `docs/DECISIONS.md`). Hardcode it for now; data-driven map loader is a later concern.

## Done when

- [x] Grid type can represent a placed entity at `(origin, footprint)`.
- [x] Query API: "what entity is at tile (x, y)?", "is rect clear?", "rect-to-rect distance / adjacency".
- [x] Tile size and entity footprint are data driven (config files or scriptable resources, not constants in code).
- [x] Unit tests cover: place, move, remove, overlap rejection, distance/adjacency between two multi-tile rects.
- [x] A Godot test scene exercises multi-tile placement; visual rendering lands in node 07b1.

## Artifacts

- PR [#1](https://github.com/Z-a-r-a-k-i/clash/pull/1) — initial M0 data layer, runtime classes, tile grid (covers nodes 00 + 01).

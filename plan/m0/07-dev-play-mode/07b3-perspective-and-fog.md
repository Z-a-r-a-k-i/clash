---
status: doing
depends_on:
  - ./07b2-input-and-turn-advance.md
---

# Perspective switch + fog of war

Third of four sub-PRs. Toggle between Player A's and Player B's views
with each rendered using its own fog of war (per-entity vision per
ADR-0016).

## Scope

- Perspective switch follows the dev HUD's active player buttons.
- Per-player vision computation gathers live owned entities and unions
  their `VisionDef.sight_radius` tile coverage.
- Fog overlay is a simple tile overlay for M0, not a shader mask.
- Visibility has two states: currently visible and previously seen.
- Enemies outside current vision are hidden from rendering and
  hit-testing.
- Previously seen enemy buildings render as silhouettes.
- Hidden enemies require allied detector coverage through
  `VisionDef.detection_radius`; normal sight alone is not enough.

ADR-0016 (fog of war from M0) lands here.

## Done when

- [x] A pure visibility helper computes current per-player tile vision.
- [x] Multi-tile footprints reveal from the full occupied rect.
- [x] Detector radius reveals hidden enemies; normal sight alone does not.
- [x] Match renderer supports an active perspective player id.
- [x] Fog overlay draws unseen and previously seen tiles distinctly.
- [x] Enemy entities outside current vision are not rendered or
  hit-testable.
- [x] Previously seen enemy buildings render as silhouettes.
- [x] Dev play mode P0/P1 controls update both input ownership and
  rendered perspective.
- [x] Headless tests cover visibility, renderer fog behavior, and dev
  perspective switching.

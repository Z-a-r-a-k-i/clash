# clash M0 visual spec

The objective standard for evaluating placeholder visuals during M0. Used by the `visual-reviewer` subagent to grade screenshots produced by `MatchRenderer` work.

## Reference frame

A screenshot from a recent commercial top-down RTS at low zoom — pinned at `docs/visual-references/`. Updated when the project's visual direction shifts.

The reference is the calibration anchor, not the target. M0 placeholders should land at 3-4 across the criteria below; the reference would land at 5. We are not trying to ship a finished game in M0.

## Acceptance criteria (1-5 ratings)

For each, the reviewer assigns a rating with concrete pass/fail anchors:

1. **Silhouette readability** — at 1× zoom on the actual tile grid, can a playtester identify the entity type without reading the label?
   - 1: no idea what most things are
   - 3: could identify with a moment's attention
   - 5: obvious in <1 second

2. **Owner clarity** — is "this is player 0's stuff" vs "player 1's stuff" distinguishable at a glance?
   - 1: need to read text or zoom in
   - 3: clear with a moment's look
   - 5: instantly obvious from color tint and silhouette

3. **Action visibility** — when a unit attacks, can you see attacker AND target without checking the combat log?
   - 1: invisible — no attack rendering
   - 3: visible if you're watching the right area
   - 5: obvious flash + line + label even from across the map

4. **Style coherence** — do the entities look like they belong in the same game?
   - 1: stitched together from random sources, mixed styles
   - 3: roughly consistent palette, varied silhouettes acceptable
   - 5: visual identity, cohesive across the roster

5. **Scale plausibility** — does a tank look bigger than a marine, a base bigger than a barracks?
   - 1: scale violations (marine bigger than tank)
   - 3: roughly consistent, minor exceptions
   - 5: rigorously consistent, scale supports gameplay reading

## Anti-criteria (immediate `BLOCKER` flags)

- **Untextured 3D primitives** (`BoxMesh` / `CylinderMesh` / `SphereMesh`) on a flat plane — looks like an unfinished tutorial, not a game. Auto-flagged as unshippable.
- **Sprites with default backgrounds visible** — forgot to use transparency. Catches "I dropped a checkered-bg PNG into the scene" mistakes.
- **Sub-pixel grid drift** — entities visibly off-tile due to position rounding errors. Breaks the tile-grid illusion the gameplay relies on.
- **Owner color invisible at 1× zoom** — if you can only tell who owns what by zooming in, the rendering is too subtle for a playtest tool.
- **Z-fighting / overlap glitches** — stacked sprites flickering or rendering in unexpected order.

## What this spec does NOT define

- Final art direction (deferred to post-M0 once playtest reveals what visual identity matters).
- Animation polish (M0 ships modulate-fade attack lines and float-up damage labels; everything else is static).
- Sound design.
- UI / HUD beyond the dev combat log.
- Effects beyond the attack line + hit flash + damage label.

## How to use this spec

The `visual-reviewer` subagent receives:
- The screenshot under review (path)
- This spec file (path)
- The reference image (path from `docs/visual-references/`)
- Optionally a previous-version screenshot for before/after

The reviewer outputs a structured per-criterion rating + anti-criteria check + verdict (`ACCEPTABLE` / `NEEDS WORK` / `BLOCKER`) + ranked findings. See `.claude/agents/visual-reviewer.md` for the full prompt.

A verdict of `ACCEPTABLE` means "ship this for M0" — not "this looks great." `NEEDS WORK` means iterate. `BLOCKER` means an anti-criterion fired and you must not proceed.

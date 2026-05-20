---
status: done
depends_on:
  - ./09-manual-playtest-readiness.md
---

# M0 dev play human playability

The first manual pass could not evaluate gameplay because the dev scene was not
human-playable: the HUD covered the opening units, the camera framed the whole
map so sprites were tiny, and there was no practical camera control.

## Scope

- Use a larger desktop dev window with Godot stretch settings suitable for
  anchored UI.
- Move the dev HUD away from the starting play area while keeping the existing
  command surface.
- Focus the camera on the active player's starting base, workers, and visible
  neutral resources at a readable zoom.
- Render zero-HP neutral resource sources as present map entities, not as dead
  combat units.
- Add basic mouse camera control for zoom and pan, including left-drag panning
  from empty map space.
- Update playtest docs with the failed first attempt and new controls.

## Non-goals

- No polished RTS HUD, minimap, or keyboard shortcut layer.
- No authored terrain obstacles, gameplay, resolver, entity data, or balance
  changes.
- No final mobile/web layout decision.

## Done when

- [x] P0 and P1 starts are focused at a readable zoom with nearby minerals and
  geysers visible.
- [x] Zero-HP neutral resource sources render and remain visible when inside
  player vision.
- [x] The dev HUD no longer covers the opening units.
- [x] Mouse zoom and pan are available during dev play.
- [x] Empty-space left-drag pans the camera without interfering with normal
  click selection or right-click context commands.
- [x] Renderer/dev play tests cover the camera/HUD behavior.
- [x] Runtime screenshots at 1920x1080 and 1280x720 confirm the scene is
  readable enough for a human pass.

# M0 Manual Playtest Pass 01

Date: 2026-05-18
Branch / PR: `m0-manual-playtest-readiness` / PR #22
Tester:
Scenario: `res://data/scenarios/mvp_map.tres`
Dev scene: `res://scenes/_dev/dev_play_mode.tscn`

Goal: drive one complete M0 match far enough to identify the first gameplay
or pacing problem worth fixing. This is not a balance pass.

## Smoke Result

Command:

```powershell
make test "GODOT=C:\Program Files\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe"
```

Result:

## Setup Confirmation

- [ ] Opened `client/project.godot`.
- [ ] Ran `res://scenes/_dev/dev_play_mode.tscn`.
- [ ] Confirmed the scene is using `res://data/scenarios/mvp_map.tres`.
- [ ] Started as P0 and switched to P1 at least once.

## Pass Summary

- Turns played:
- Winner / end condition:
- First moment of confusion: initial attempt was blocked before gameplay; the
  HUD covered the opening area, the map was framed as a tiny whole-map view,
  zero-HP resource sources were not rendered as map entities, and the scene felt
  non-interactive.
- Most promising fun moment:
- Biggest pacing issue: not evaluated yet; visual/click playability blocked
  the pass.

## Turn Log

Use short notes only when something matters.

| Turn | P0 intent | P1 intent | Result / note |
|---|---|---|---|
| 0 |  |  |  |
| 1 |  |  |  |
| 2 |  |  |  |
| 3 |  |  |  |
| 4 |  |  |  |

## Observations

### Economy

- Worker selection:
- Gather targeting:
- Deposit/resource feedback:

### Production

- Build placement:
- Construction progress:
- Train/research clarity:

### Fog

- Own vision:
- Enemy visibility:
- Switching player perspective:

### Combat

- Targeting:
- Damage feedback:
- Move / Move Only / halt-on-sight:
- Abilities:

### End State

- Surrender:
- Base destruction:
- Winner display:

## Next Iteration Triage

- Must fix before next pass: make the dev scene human-playable by moving the
  HUD away from the starting units, focusing the camera on the active player
  and nearby resources, rendering zero-HP resources, and adding basic mouse
  camera control. Follow-up command UX pass should make queued intent,
  resources, gather, costs, auto-starting workers, and unit-training progress
  visible enough for a human playtest.
- Gameplay or pacing change:
- Tooling or debuggability issue:
- Later polish:

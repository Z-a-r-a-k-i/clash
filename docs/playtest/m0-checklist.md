# M0 Playtest Checklist

Purpose: get a complete, repeatable pass through the current playable loop so the next work can focus on what feels unclear, slow, or unfun. This is not a balance test.

## Setup

- Open `client/project.godot`.
- Run `res://scenes/_dev/dev_play_mode.tscn`.
- Verify the scene uses `res://data/scenarios/mvp_map.tres`. This is the
  default `scenario_path` on the scene root.
- Start as player 0, then switch to player 1 when checking mirrored behavior.
- Keep the resolver authoritative: queue actions, resolve the turn, and record what changed.

## Dev Play Controls

- Left click selects a visible entity.
- Right click issues a context action: move to empty tile, gather from a
  resource, or attack an enemy.
- `P0` / `P1` switches the active player and fog perspective.
- `Resolve` submits both players' queued actions and advances the turn.
- `Clear` clears currently queued submissions.
- `Surrender` queues surrender for the active player.
- The command card exposes available attack-move, hold-fire, build, train,
  research, ability, and cancel actions for the selected entity.

## Automated Smoke

Run:

```powershell
make test "GODOT=C:\Program Files\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe"
```

The M0 smoke runner covers the mechanical path that should exist before a human pass:

- MVP map loads with two bases, two workers per player, starting resources, and opening fog.
- Workers can gather from the MVP mineral patches and deposit at the canonical base.
- A worker can build a barracks from gathered minerals.
- A barracks can train a marine.
- A nearby marine attack emits combat damage.
- Surrender ends the match with the expected winner.

## Agent Smoke Notes

- MVP mineral patches are zero-HP neutral resource sources. Gather validation must treat placed resource-source capacity as the usable-state check, not combat health.
- The canonical base must carry the `deposit_sink` tag. Without it, workers fill cargo and then idle because there is nowhere valid to deposit.

## Human Pass

### Economy Opening

- Select each worker and queue gather orders on nearby mineral patches.
- Resolve until minerals are deposited.
- Note whether the selected worker, target, and queued order are obvious.
- Note whether the resource flow is legible enough to support decisions.

### First Production

- Build a barracks near the starting base.
- Resolve until construction completes.
- Train at least one marine.
- Note whether placement feedback, construction progress, production state, and blocked actions are clear.

### Fog And Scouting

- Check player 0 vision at match start.
- Move a unit toward contested space.
- Switch to player 1 and compare what each side can see.
- Note whether hidden information is understandable from the current renderer.

### First Fight

- Queue a marine attack against a visible enemy.
- Queue attack-move and hold-fire in nearby turns.
- Use stim after research is available if the pass reaches that point.
- Note whether damage, target choice, and unit state are readable.

### End Condition

- Use surrender for a deterministic end-state check.
- If time allows, also destroy the last enemy building and confirm match end.
- Record whether the end state is visible and unambiguous.

## Notes

Use `docs/playtest/m0-pass-01.md` for the first pass. For later passes, copy
`docs/playtest/m0-notes-template.md`. Prefer concrete observations over
suggested fixes unless the fix is obvious and local.

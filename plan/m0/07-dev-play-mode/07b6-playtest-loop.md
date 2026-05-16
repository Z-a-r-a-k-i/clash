---
status: ready
depends_on:
  - ./07b5-use-abilities.md
---

# M0 playtest loop

Gameplay validation starts here. This node creates a repeatable way to play
through `mvp_map.tres`, record first impressions, and distinguish gameplay
problems from missing debug tooling.

## Scope

- Add a short M0 playtest checklist covering:
  - opening economy
  - first tech building
  - first army production
  - scouting through fog
  - first engagement
  - base raze or surrender
- Add a lightweight notes template for mechanics feedback:
  - too much clicking
  - too slow to reach combat
  - confusing commands
  - unreadable fog/scouting
  - unclear unit counters
  - stalled endgame
- Add a headless smoke test that loads `mvp_map.tres`, queues representative
  economy/production/combat commands, and resolves enough turns to prove the
  core systems can run together without errors.

## Non-goals

- No tuning pass yet; this node captures what to tune.
- No AI opponent.
- No player-facing UI polish.
- No tick-step debugger unless smoke/playtest results prove it is blocking.

## Done when

- [ ] `docs/playtest/m0-checklist.md` exists with a repeatable manual flow.
- [ ] `docs/playtest/m0-notes-template.md` exists for qualitative feedback.
- [ ] A headless smoke test exercises economy, production, combat, fog, and
  match end on `mvp_map.tres`.
- [ ] First mechanics notes are captured in the checklist or in follow-up plan
  nodes for tuning/M1.
- [ ] `make test`, `gdlint`, and `gdformat --check` pass.

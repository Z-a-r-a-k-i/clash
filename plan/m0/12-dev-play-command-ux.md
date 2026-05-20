---
status: done
depends_on:
  - ./10-dev-play-human-playable.md
  - ./11-simple-facing-playtest-map.md
---

# M0 dev play command UX

The first readable playtest pass still had command-surface blockers: actions
were queued but hard to see, workers had no explicit gather button, resources
were not visible in the HUD, and empty command sections made the menu feel
debug-first instead of playable.

## Scope

- Show the selected unit's queued/current intent on the map.
- Add a HUD toggle that also shows all friendly queued/current intents for the
  active player.
- Add an explicit worker Gather command that enters a resource target-pick mode.
- Show current-player minerals, gas, and population in the dev HUD.
- Replace raw queue/debug labels with player-readable text.
- Hide the command card and command sections when they have no valid action.
- Show mineral, gas, population, and turn-time costs on build, train, and
  research command buttons.
- Disable eager-paid build commands while the active player cannot afford them,
  instead of letting the resolver reject the order after resolve.
- Reject occupied build placements immediately with a readable status message,
  so workers do not appear to ignore the command and resume their previous job.
- Show active unit-training progress as a small in-world bar on producer
  buildings.

## Non-goals

- No keyboard shortcut layer, minimap, drag select, or control groups.
- No resolver changes; gather auto-mode and production timing stay
  authoritative in existing systems.
- No final HUD art direction or mobile/web layout.

## Done when

- [x] Empty/non-actionable selection does not show a command card.
- [x] Worker selection exposes Gather; clicking a resource queues GATHER and
  lets the existing gather FSM continue after resolve.
- [x] The active player HUD shows resources and a readable queued-action count.
- [x] Selected unit intent always draws; all-friendly intent is toggleable.
- [x] Build, train, and research buttons include compact cost/time labels.
- [x] Unaffordable build buttons stay visible with costs but cannot queue an
  order.
- [x] Occupied build footprints are rejected before resolve.
- [x] Active unit training draws an in-world progress bar on the producer.
- [x] Dev play and renderer tests cover the command UX behavior.

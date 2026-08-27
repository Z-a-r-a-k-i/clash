---
status: sketch
---

# clash — root plan

Turn-based PvP strategy game with simultaneous-turn resolution. SC2-shaped economy, tech, counters, and macro on top of an action-slot lockstep resolver. See [../AGENTS.md](../AGENTS.md) for the architecture overview, [../docs/DECISIONS.md](../docs/DECISIONS.md) for the decisions log, and [../docs/ROADMAP.md](../docs/ROADMAP.md) for the long-horizon plan.

## Milestone state

- **[M0](m0/) — completed.** The dev-only prototype established the resolver,
  game systems, scenario/save tooling, and playable command surface.
- **[M1](m1/) — active.** Solo AI, the simulation harness, shared match
  controller, main-and-natural arena, HUD work, and resolved-movement animation
  are implemented. External playtesting and remaining presentation work drive
  the next focused nodes.
- **M2 — development slice implemented.** Trusted same-version invite-code
  matches run on a headless Godot WebSocket server. Production hosting,
  security, reconnection, persistence, and the final stack decision remain M2.

## Future milestones

These remain one-line entries in `../docs/ROADMAP.md` until they become active:

- **M3** — Lobby and matchmaking. Accounts, MMR.
- **M4** — Web and mobile exports.
- **M5** — Card / deck / race progression layer.

## Reading order for new agents

1. `../AGENTS.md` — repo-level architecture and rules.
2. `../docs/ARCHITECTURE.md` — turn resolution, spatial model, components.
3. `../docs/DECISIONS.md` — why things are the way they are.
4. `./AGENTS.md` — plan-tree mechanics for agents.
5. `./m1/README.md` — current milestone and remaining validation gates.
6. `./m0/README.md` — completed prototype history when older decisions matter.

---
status: sketch
---

# clash — root plan

Turn-based PvP strategy game with simultaneous-turn resolution. SC2-shaped economy, tech, counters, and macro on top of an action-slot lockstep resolver. See [../AGENTS.md](../AGENTS.md) for the architecture overview, [../docs/DECISIONS.md](../docs/DECISIONS.md) for the decisions log, and [../docs/ROADMAP.md](../docs/ROADMAP.md) for the long-horizon plan.

## Active milestone

- **[m0/](m0/)** — Dev-only playable prototype. One developer drives both players through a rough debug tool to validate the systems and start finding obvious gameplay/fun problems. Hot-seat is incompatible with simultaneous-turn blind input; AI is M1; first real PvP arrives with network play in M2.

## Future milestones

These exist as `sketch` directories (or as one-line entries in `../docs/ROADMAP.md`) and become real plan trees when each becomes the next thing to work on:

- **M1** — AI opponent. First time a single human can play solo. Control groups. Full counter matrix. Initial tuning pass.
- **M2** — Network play by invitation. Resolver lifted to a server (technology TBD per ADR 0006). First time two humans can actually play.
- **M3** — Lobby and matchmaking. Accounts, MMR.
- **M4** — Web and mobile exports.
- **M5** — Card / deck / race progression layer.

## Reading order for new agents

1. `../AGENTS.md` — repo-level architecture and rules.
2. `../docs/ARCHITECTURE.md` — turn resolution, spatial model, components.
3. `../docs/DECISIONS.md` — why things are the way they are.
4. `./AGENTS.md` — plan-tree mechanics for agents.
5. `./m0/README.md` — current milestone.

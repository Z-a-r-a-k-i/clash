# Roadmap

Long-horizon view of clash. Concrete near-term work lives in the plan tree (`plan/`); this document is for the bigger picture.

## Milestones

- **M0 — Dev-only playable prototype.** One machine, one developer driving both sides through a debug tool. Square-tile grid, multi-tile entities, tick-based resolver, identical roster (marine, tank, helicopter; barracks, factory, starport; base + workers), fog of war, raze-to-win. Exposes enough rough commands to gather, build, train, scout, fight, and finish a match so we can start finding obvious gameplay/fun problems before AI or network work. True solo validation starts in M1; true PvP validation starts in M2.
- **M1 — AI opponent.** First time a single human can play solo. Bot opponent, control groups, full counter matrix (light / heavy / flying), first tuning pass on tile size, pop slots, action timer.
- **M2 — Network play by invitation.** Lift the resolver to a server. Server technology and wire protocol picked at this point — candidate paths (Go + protobuf, headless Godot/GDScript, Nakama, etc.) tracked in ADR 0006. Direct invitation links; no matchmaker yet. First time two humans can actually play.
- **M3 — Lobby and matchmaking.** Accounts, matchmaking on the Clash-Royale model (arena tiers, MMR). Public invite-only test.
- **M4 — Web and mobile exports.** HTML5, Android, iOS. Public.
- **M5 — Card / deck / progression layer.** Card-based unit selection, race or leader perks, card evolution, arena unlocks for deck slots, monetization for cosmetics and progression speed-ups.

## Near-term handoff

- **Next M0 PR:** `plan/m0/13-combat-command-simplification.md`. Simplify the
  playtest combat command model before deeper balance iteration: automatic
  closest-target shooting stays on, Target is priority focus only, Retreat gives
  full move without shooting, Halt on Sight replaces Hold Fire, attack damage is
  simultaneous, and units that shoot get reduced same-turn movement by a tunable
  percentage.

## Speculative

Ideas not yet ready to become plan nodes:

- Replays (deterministic resolver makes this almost free).
- Spectator mode.
- AI opponent calibration ladder for solo training.
- Asynchronous mode (24h per turn) as a contrast to fast-paced live.
- Tournament brackets.
- Cosmetics and battle pass (revenue, post-M5).

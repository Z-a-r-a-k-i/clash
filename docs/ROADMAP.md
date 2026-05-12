# Roadmap

Long-horizon view of clash. Concrete near-term work lives in the plan tree (`plan/`); this document is for the bigger picture.

## Milestones

- **M0 — Dev-only prototype.** One machine, one developer driving both sides through a debug tool. Square-tile grid, multi-tile entities, tick-based resolver, identical roster (marine, tank, helicopter; barracks, factory, starport; base + workers), fog of war, raze-to-win. Validates that the **systems are correct**. Fun validation requires a real opponent and waits for M1 (AI) or M2 (network).
- **M1 — AI opponent.** First time a single human can play solo. Bot opponent, control groups, full counter matrix (light / heavy / flying), first tuning pass on tile size, pop slots, action timer.
- **M2 — Network play by invitation.** Lift the resolver to a server. Server technology and wire protocol picked at this point — candidate paths (Go + protobuf, headless Godot/GDScript, Nakama, etc.) tracked in ADR 0006. Direct invitation links; no matchmaker yet. First time two humans can actually play.
- **M3 — Lobby and matchmaking.** Accounts, matchmaking on the Clash-Royale model (arena tiers, MMR). Public invite-only test.
- **M4 — Web and mobile exports.** HTML5, Android, iOS. Public.
- **M5 — Card / deck / progression layer.** Card-based unit selection, race or leader perks, card evolution, arena unlocks for deck slots, monetization for cosmetics and progression speed-ups.

## Speculative

Ideas not yet ready to become plan nodes:

- Replays (deterministic resolver makes this almost free).
- Spectator mode.
- AI opponent calibration ladder for solo training.
- Asynchronous mode (24h per turn) as a contrast to fast-paced live.
- Tournament brackets.
- Cosmetics and battle pass (revenue, post-M5).

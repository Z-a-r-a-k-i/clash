# Roadmap

Long-horizon view of clash. Concrete near-term work lives in the plan tree (`plan/`); this document is for the bigger picture.

## Milestones

- **M0 — Dev-only playable prototype (completed).** One machine, one developer driving both sides through a debug tool. Square-tile grid, multi-tile entities, tick-based resolver, identical roster (marine, tank, helicopter; barracks, factory, starport; base + workers), fog of war, raze-to-win, save/load, and replay foundations.
- **M1 — Solo play and iteration engine (active).** Solo play against three scripted AI strategies, box/multi-selection with group orders, the light/heavy/flying counter matrix, a main-and-natural 1v1 arena, AI-vs-AI simulation, the shared HUD, and resolved-movement animation are implemented. The remaining work is external playtesting and the combat/status presentation needed to judge pacing, readability, and fun reliably. Persistent numbered RTS control groups are not implemented.
- **M2 — Network play by invitation (development slice implemented).** A trusted same-version headless Godot WebSocket server already hosts invite-code matches and completed the first human-vs-human playtest. M2 still owns the production decision: harden that stack or choose another server and wire format, then add the missing timer, reconnect, hosting, persistence, and security boundaries. Candidate paths are tracked in ADR 0006.
- **M3 — Lobby and matchmaking.** Accounts, matchmaking on the Clash-Royale model (arena tiers, MMR). Public invite-only test.
- **M4 — Web and mobile exports.** HTML5, Android, iOS. Public.
- **M5 — Card / deck / progression layer.** Card-based unit selection, race or leader perks, card evolution, arena unlocks for deck slots, monetization for cosmetics and progression speed-ups.

## Near-term handoff

- Validate the resolved-unit movement animation landed in PR #61 and turn any
  repeated readability problem into a focused presentation node.
- Prepare a simple same-version build and run an external solo/network
  playtest cycle focused on clarity, pacing, controls, and the blind-submit
  loop.
- Turn the first repeated playtest blocker into the next focused plan node
  before adding progression or production infrastructure.

## Balance notes (M0 counter triangle)

First pass at the M1 "full counter matrix", encoded as integer-percent
`AttackModifier`s in entity data (the resolver uses integer math only):

- **Marine > Helicopter** — marine deals +50% vs the `flying` tag
  (anti-air rifles). Cost-efficient swarms keep helicopters honest.
- **Tank > Marine** — raw stats (30 dmg vs 45 hp marines, 175 hp chassis);
  sieged tanks (status `sieged`: 40 dmg, range 6, immobile) zone infantry.
- **Helicopter > Tank** — helicopter deals +50% vs the `heavy` tag and
  tanks cannot shoot `flying` at all.

Workers (10 dmg, range 2) lose cost-for-cost to any combat unit. Bases
currently have 333 hp; rush viability should be judged in playtests rather
than inferred from the obsolete 1000-hp prototype value.

## Speculative

Ideas not yet ready to become plan nodes:

- Spectator mode.
- AI opponent calibration ladder for solo training.
- Asynchronous mode (24h per turn) as a contrast to fast-paced live.
- Tournament brackets.
- Cosmetics and battle pass (revenue, post-M5).

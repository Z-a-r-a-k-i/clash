---
status: stub
depends_on:
  - ./00-play-mode-consolidation.md
---

# HUD pass

One HUD for both play modes (after node 00 there is one place to build it).
Builds on the M0 cockpit shell (plan-51) rather than restarting.

Scope candidates (to be prioritized from playtest pain):

- Top bar: minerals / gas / supply (used/cap) with income-per-turn deltas.
- Selection panel: multi-select grid with HP bars; single-select detail
  (stats, active statuses with remaining duration, cooldowns).
- Production: queue progress on selected producers; global production strip;
  idle-worker button (indicator logic exists, plan-50/52).
- Minimap: viewport rect, fog, army blips, attack pings. Likely the single
  biggest situational-awareness win; needs renderer support.
- Turn flow: submit state for both sides, turn counter, (later) timer.
- Command card: keep, polish iconography + hotkey hints; statuses/abilities
  already auto-hide by applicability.

## Done when (to be refined when promoted to sketch)

- [ ] A full match is playable without ever opening the debug panels:
      economy, production, army, and turn state all visible at a glance.

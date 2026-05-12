---
status: done
depends_on:
  - ./00-config-and-tunables.md
  - ./01-tile-grid-and-occupancy.md
---

# Economy: workers, resources, expansion

SC-shaped economy at MVP scope. Just enough to make tech and unit production feel meaningful.

## Resources at MVP

Two resources, SC2-shaped:

- **Minerals.** Mineral patches are placed in clusters at each base location. Each patch has a finite stockpile (or infinite for prototyping; flag for playtest). Gathered directly by a worker.
- **Gas.** Each base location has one **gas geyser**. To extract, a player builds a **refinery** on top of the geyser, then assigns workers to gather from it. No refinery → no gas income from that geyser.

Units, buildings, and research items each have a cost of `{ minerals, gas }` (either may be zero).

## Workers

- Each player starts with a base + N workers (N tunable, default 4).
- A worker assigned to a mineral patch or a refinery is **autonomous**: it gathers each turn, returns to the nearest base to deposit, and resumes — without per-turn re-issuing. This is the anti-overwhelm rule.
- Workers can be reassigned manually (build, scout, fight). Reassignment cancels autonomy until the player puts them back on a patch or refinery.
- Workers count toward the pop cap.

## Expansion

- A new base can be built at another mineral cluster (worker → build base).
- Defended/proxy expansion is a strategic option, not a special-cased mechanic — just a base built somewhere risky.

## Open questions

- Worker carry capacity / round-trip time: just a stat. Flag for playtest tuning.
- What happens when a mineral patch is depleted? Worker idles and surfaces a UI hint. Optional auto-reassign to nearest patch — defer.
- Gas geyser depletion: same model as minerals (finite stockpile) or infinite for MVP simplicity? Default infinite at MVP, revisit on playtest.
- Refinery destruction: when an enemy razes the refinery, the geyser stays but workers idle. Confirmed.

## Done when

- [x] Mineral patches and gas geysers placed on the MVP map (per base location, per node 08).
- [x] Workers can be assigned to a patch or to a refinery; gathering happens automatically each turn until reassigned.
- [x] Refinery building can be placed on a geyser; only then can workers extract gas.
- [x] Build/economy simulation supports new bases and worker reassignment; prototype UI issuance lands in 07b2.
- [x] Pop accounting reflects worker count plus military units in simulation state.
- [x] Resource counters (minerals, gas) exist per player in simulation state; HUD visibility lands in dev-play UI work.

## Artifacts

- PR [#4](https://github.com/Z-a-r-a-k-i/clash/pull/4) — gather pipeline (workers, mineral patches, refinery on geyser, deposit sinks).

---
status: done
depends_on:
  - ./01-tile-grid-and-occupancy.md
---

# Action queue + order types

The order-issuance UI and the in-flight queue that submits to the resolver.

## Order types at MVP

| Order | Target | Notes |
|---|---|---|
| Move | tile or rect | Ignores enemies along path. Persists across turns until arrived / dead / overridden. |
| Attack-move | tile or rect | Stops to engage if an enemy enters attack range; resumes pathing when threat is cleared. |
| Attack | entity (with priority chain) | Up to N priority targets in chain; fall-back to closest enemy unless on hold-fire. |
| Hold-fire toggle | self | Unit mode. Independent of move/target focus. |
| Build | building type + tile rect | Issued from a worker (or HQ for the initial set). N-turn build time. |
| Train | unit type | Issued from a production building. N-turn train time. |
| Research | research id | Issued from a building. N-turn research time. |
| Cancel | targets a queued order | Cancels persistent move or production. |
| Surrender | none | Match-end. Goes in `SubmitTurn` flag, not the per-unit queue. |

## Group orders

Players will mostly issue orders to *groups* of selected units, not individuals. At MVP:

- Selection is multi-select (drag, click, shift-click).
- A group order fans out into per-unit orders at submit time.
- Group composition can be heterogeneous (mixed marine / tank / helicopter).
- Control groups (assign-to-hotkey persistent groups) are deferred to **M1**.

## Persistence

- Move persists across turns. The unit's "last issued move" is part of state and continues to be acted on each turn until it completes, the unit dies, the player overrides it, or the unit fires while following an old move without a fresh move command.
- Target focus persists separately from movement until replaced, cleared, or the target becomes invalid.
- The submitted `queue[]` for a turn contains only **new** orders issued during that turn. Persistent state is held by the resolver, not re-sent each turn.

## UX considerations (M0 prototype level)

- Player must be able to see, for each selected unit, what its current persistent order is.
- Player must be able to cancel a persistent order without issuing a new one.
- Action queueing is wall-clock-pressured only — no hard cap on orders per turn.

## Done when

- [x] Runtime order resources exist for all resolver-level order types listed above.
- [x] Persistent move state survives across turn submissions.
- [x] Cancel works on persistent moves and on queued production.
- [x] Group orders fan out correctly at submit time.
- [x] Surrender flag is deliverable and resolves to a win event.

## Deferred UI criteria

- Prototype UI issuance for all order types lands in 07b2.
- Visible persistent-order/path indicators land with the dev-play rendering/input work in 07b2/07b3.

## Artifacts

- PR [#3](https://github.com/Z-a-r-a-k-i/clash/pull/3) — SubmitTurn shape + OrderBuilder fan-out.

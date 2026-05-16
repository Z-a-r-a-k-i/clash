---
status: done
depends_on:
  - ./07b3-perspective-and-fog.md
---

# Gameplay command surface

Fourth gameplay-first sub-PR for dev play mode. The goal is not a polished RTS
command UI; it is a complete enough control surface to drive the existing M0
systems on `mvp_map.tres` and start finding obvious gameplay problems.

## Scope

- Extend `DevTurnInput` with order builders for:
  - `ATTACK_MOVE`
  - `HOLD_FIRE_TOGGLE`
  - `BUILD`
  - `TRAIN`
  - `RESEARCH`
  - `CANCEL`
- Extend `DevPlayMode` with rough dev-only controls:
  - selected-entity command buttons
  - build/train/research option lists derived from the selected entity and registry
  - build-placement mode that uses the next clicked tile
  - attack-move mode that uses the next clicked tile
  - cancel action defaulting to `cancel_index = -1`
- Keep the current right-click context path for move/attack/gather.
- Keep validation in the input model where possible; the resolver remains the
  final authority and may still reject illegal orders.

## Non-goals

- No polished player command card.
- No control groups.
- No AI opponent.
- No network, timers, or simultaneous hidden input.
- No `USE_ABILITY`; self-target abilities land in 07b5.
- No tick-step debugger; that is deferred to 07b7 unless playtests make it urgent.

## Done when

- [x] Dev input can queue `ATTACK_MOVE`, `HOLD_FIRE_TOGGLE`, `BUILD`, `TRAIN`,
  `RESEARCH`, and `CANCEL` orders with strict GDScript typing.
- [x] Dev play mode exposes rough controls for every non-ability M0 order.
- [x] Build placement and attack-move use an explicit pending-click mode.
- [x] Train and research controls only list valid items for the selected producer.
- [x] Command status messages explain why invalid selections or commands fail.
- [x] Headless tests cover each new order constructor and a representative
  dev-play-mode command flow.
- [x] `make test`, `gdlint`, and `gdformat --check` pass.

## Artifacts

- PR [#19](https://github.com/Z-a-r-a-k-i/clash/pull/19)

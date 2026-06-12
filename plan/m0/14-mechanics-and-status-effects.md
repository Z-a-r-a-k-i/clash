---
status: done
depends_on:
  - ./13-combat-command-simplification.md
---

# Mechanics profile and status effects

The next gameplay-system work should split mechanics from statuses.

Mechanics are resolver-supported concepts: when a unit may attack, whether it
attacks before movement, after movement, or both, initiative participation,
movement permission and speed, end-of-turn healing or damage, and any future
phase-level rules.

Statuses are runtime modifiers over those mechanics. Any status may have a
finite duration or an indefinite duration; that is just how long it stays, not
a separate kind of status. Statuses can be positive or negative, visible or
hidden. They can block shooting, block movement, add end-of-turn damage or
healing, grant initiative, change effective combat data, or change which visual
treatment the renderer should use. They should not be implemented as scattered
one-off checks in the resolver.

This should land as two PRs.

## PR 1: mechanics profile

Introduce a central resolver query layer for effective mechanics, without
adding status runtime state yet.

The query layer should derive an entity's current mechanics from its existing
definition and runtime state. The initial implementation keeps today's behavior
as the default:

- combat-capable units attack in the pre-movement attack window;
- a unit may attack at most once in each attack window it participates in;
- initiative is a separate simultaneous attack batch that resolves before the
  normal pre-movement attack batch;
- attack batches stay deterministic and simultaneous, so entity ID order never
  decides whether a unit gets to fire;
- movement continues to use current movement definitions and post-shot movement
  reduction;
- no status, ability, or rendering behavior changes in this PR.

The purpose of this PR is to give the resolver stable connection points before
statuses arrive. Combat should ask the mechanics layer which attack windows an
entity participates in and whether it belongs to the initiative batch. Movement
should ask the same layer whether the entity may move and what movement budget
applies.

The mechanics layer should support, with tests but not necessarily new playable
content:

- pre-movement attackers, matching today's behavior;
- post-movement attackers, for future melee or charge-style units;
- units that attack both before and after movement, with one attack per window;
- initiative as an early simultaneous attack batch: initiative units that kill
  each other both deal damage, while units destroyed by initiative do not
  participate in later normal attack batches.

Do not add statuses in this PR. Do not add a targeted ability UI. Do not add new
production roster units unless needed as isolated test fixtures.

Remove the unused `CombatDef.attacks_per_turn` field as part of PR 1. The
planned model is not "N generic attacks per turn"; it is explicit attack
windows, with at most one attack per participating window.

## PR 2: status effects

Add the status runtime on top of the mechanics profile.

Remove stim from the game instead of migrating it. Delete the stim ability data,
remove it from marine data, remove stim research if it only exists to unlock
stim, and remove or rewrite tests and UI assumptions that exist only for stim.

Replace the current buff-only runtime shape with a general status shape. The
new runtime state should be able to represent:

- duration as a property of any status, where a finite duration expires and an
  indefinite duration is permanent until explicitly cleared;
- blocking statuses such as "cannot shoot" or "cannot move";
- turn-hook statuses such as end-of-turn damage or regeneration;
- mechanics modifiers such as movement speed, attack window participation, or
  initiative participation;
- optional presentation hints for renderer-visible status visuals.

Siege mode should become the first concrete status-driven mode instead of a
second concrete unit definition. The tank remains one entity definition and a
siege status modifies its effective mechanics while active. The status should
be able to change combat behavior and expose enough presentation metadata for a
future renderer pass to display a different sprite or overlay. The first status
PR should define that presentation hook but does not need to implement final
art, animation, or visual effects.

Ability effects, future attack procs, terrain triggers, movement triggers, and
turn-start or turn-end hooks should all apply statuses through the same
resolver-owned application path. For this PR, keep the exposed player path
minimal: self-target ability application is enough if it supports the siege
mode use case.

The resolver should stay explicit. It should call the status system at known
phase boundaries and query points, not run arbitrary status callbacks from deep
inside combat or movement. Status effects must remain deterministic and must be
serializable through save/load and the current same-version network codec.

## Visual planning

Statuses may affect visuals later, but renderer polish is out of scope for
these two PRs.

The status data should reserve a small presentation surface that the renderer
can consume later, such as:

- an optional visual key for a replacement sprite or mode-specific sprite;
- optional overlay/effect keys for future rings, particles, tinting, or badges;
- a clear distinction between simulation fields and presentation hints.

Simulation must not depend on presentation data. Missing visual data should
never change resolver behavior.

## Suggested tests

PR 1:

- A default combat unit still attacks before movement exactly as today.
- A post-movement attacker does not attack before movement, then can attack
  after movement if a target is in range.
- A unit configured for both attack windows can attack once before movement and
  once after movement.
- Initiative attacks resolve as an early simultaneous batch; two initiative
  units attacking each other both deal damage, and units killed by initiative do
  not attack in later batches.
- Existing post-shot movement budget behavior is preserved.
- `CombatDef.attacks_per_turn` is removed from code and data.

PR 2:

- Stim data, stim research, and stim-only tests are removed.
- A no-shoot status prevents attack participation for its active duration.
- A no-move status prevents movement while leaving other valid actions intact.
- End-of-turn damage applies deterministically and can destroy an entity.
- End-of-turn regeneration heals without exceeding max HP.
- A status with finite duration expires; a status with indefinite duration
  persists across turns and save/load round trips.
- Siege mode is represented as a status on a tank, changes effective mechanics,
  and can be cleared or replaced by the unsiege path.
- Status state round-trips through `MatchSaver` and `NetworkV0Codec`.
- Status presentation hints serialize but do not affect simulation.

## Done when

- [x] PR 1 adds the mechanics profile/query layer and preserves existing
  gameplay behavior by default.
- [x] PR 1 removes `CombatDef.attacks_per_turn`.
- [x] PR 1 tests cover attack windows, initiative, and existing
  combat/movement behavior.
- [x] PR 2 removes stim and its research/data/test dependencies.
- [x] PR 2 adds the general status runtime, status application path, duration
  handling, and serialization.
- [x] PR 2 represents siege mode as status-driven mechanics on the tank rather
  than as a separate playable unit definition.
- [x] PR 2 reserves renderer-facing presentation hints without making
  simulation depend on visuals.
- [x] Resolver, save/load, network, and dev-play tests pass after each PR.

## Artifacts

- Implemented as a single change (not the two-PR split): `StatusEffect`
  runtime (`client/scripts/runtime/status_effect.gd`), resolver-owned
  `StatusSystem` (`client/scripts/resolver/status_system.gd`),
  `MechanicsSystem` as the status-aware query layer, stim removed, siege
  as the indefinite `sieged` status on the single tank def, statuses
  serialized through clone/save/replay and `NetworkV0Codec`, presentation
  hints (`sprite_key`, `overlay_keys`) reserved but unread by simulation.
  Multipliers are integer percents — no float math in the resolver.

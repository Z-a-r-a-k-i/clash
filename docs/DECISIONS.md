# Architecture Decision Records

Light ADRs. One entry per decision that's load bearing for future agents. Add new entries at the bottom; keep old entries even when superseded (mark them so).

## 0001 — Codename `clash`

**Date:** 2026-04-28

Project codename. Folder: `C:\Users\alk\Documents\Developpement\games\clash`. Cheap to rename later if a better name emerges.

## 0002 — Monorepo layout

**Date:** 2026-04-28

Single repo with three top level stacks: `client/` (Godot), `server/` (deferred), `proto/` (conditional on protobuf being chosen at M2). Generated code is committed alongside its consumer if proto is adopted.

**Updated 2026-04-29:** ADR 0020 supersedes the original C# client assumption. Game code is GDScript, server technology remains deferred to M2, and proto remains conditional on the M2 wire-format decision.

**Why:** The shape matches the [godot-go-protobuf-ws](https://github.com/ignoxx/godot-go-protobuf-ws) reference template and the termwatch project. Keeping Godot in `client/` rather than at the repo root prevents non Godot folders from polluting Godot's FileSystem dock.

## 0003 — C# default, GDScript when ergonomic (SUPERSEDED by 0020)

**Date:** 2026-04-28

Game code defaults to C#. GDScript is allowed where it's meaningfully simpler (single file `@tool` editor scripts, simple signal wiring, scenes that don't justify a `.csproj` entry).

**Why:** C# scales better for complex multiplayer logic and matches Go on the server side stylistically. GDScript stays available for trivial cases.

**Superseded by ADR 0020 (2026-04-29).** Reason: the C# choice was made on aesthetic / scaling grounds before researching Godot's actual platform support matrix. C# does not support web export in Godot 4.6/4.7-beta (a clash core target), and C# mobile is officially experimental with documented crashes. GDScript ships production-ready on every clash target.

## 0004 — Simultaneous turn model with action-slot lockstep

**Date:** 2026-04-28

Both players queue orders during a shared turn timer. A turn ends when both players submit or when the timer expires. The resolver then runs deterministically.

A turn is divided into N ticks, where N equals the maximum action-queue length across all units that turn. On tick k, every unit's k-th queued action resolves; within a tick, all attacks fire before any moves execute. Target-chain fallbacks (priority targets, closest-enemy unless on hold-fire) apply per attack action. End-of-turn effects fire after the last tick.

**Why:** Simultaneous resolution is server authoritative without rollback, feels faster than alternating turns, and supports the "fast paced StarCraft turn based" vision. Lockstep ticks make multi-action turns (`attack A → move → attack B`) predictable for the player without ranking units by stats. Asymmetric information — both players commit blind, then see the result — is a feature, not a bug.

## 0005 — Server authoritative

**Date:** 2026-04-28

Clients submit action queues; the server is the only authority for game state. Clients render the resolved outcome; they do not predict or speculate.

**Why:** Anti cheat (PvP), determinism (the resolver has nontrivial rules), and the simultaneous turn model demand a single source of truth.

## 0006 — Deferred server, deferred network technology

**Date:** 2026-04-28 (revised 2026-04-29)

`server/` is empty in v0. The resolver lives inside the Godot client for the prototype, driven by dev tooling on a single machine, so we can validate the rules without a network. M1 adds an AI opponent (still all client-side). M2 adds network play.

**M0 scope is dev-only.** One developer drives both players through a debug tool with no timer plus a scenario loader. No AI opponent (M1), no hot-seat (incompatible with simultaneous-turn blind input by construction — a single shared screen can't deliver independent concurrent input from two players), no PvP (arrives with M2 network play).

**Server technology and wire protocol are deferred to M2.** Candidate paths and tradeoffs:

- Go server + WebSocket + protobuf — most control; standard production pattern; biggest setup; two languages.
- Headless Godot/GDScript server + WebSocket (any encoding) — same engine and language on both sides; resolver code reused 1:1; less standard.
- Nakama or similar BaaS — fast to ship; covers M3+ matchmaking for free; vendor lock-in.
- Godot built-in MultiplayerAPI — zero setup but P2P, can't be server-authoritative without a host peer.

Full evaluation in `plan/m0/00-config-and-tunables.md`. ADR 0007 (generated proto code committed) only applies if proto is chosen at M2.

**Why:** Build the rules first; build the network when there's something worth networking. The resolver is a pure function on plain-data structures, so it's portable to any wire protocol — the M2 choice can be made on operational grounds (cost, scaling needs, team familiarity) without touching game logic.

## 0007 — Generated proto code is committed (conditional on proto being chosen)

**Date:** 2026-04-28

If protobuf is chosen as the wire format at M2 (see ADR 0006), generated GDScript (via godobuf) and language-appropriate server-side proto files are checked into git. The pre-commit gate verifies no drift between `proto/` and the generated outputs.

**Why:** Lets fresh clones build without a separate generation step, and surfaces protobuf changes in PR diffs.

**Note:** Conditional on proto being the chosen wire format. If a non-proto path is picked at M2 (e.g. JSON or Godot-native serialization), this ADR becomes moot. Per ADR 0020, the GDScript-side codegen would be [godobuf](https://github.com/oniksan/godobuf), which does not support proto `package` directives — workaround is a name-prefix convention (e.g. `ClashV1TurnStart`).

## 0008 — godot-ai-plugin used externally

**Date:** 2026-04-28

The agent drives the Godot editor through the [godot-ai-plugin](https://github.com/Z-a-r-a-k-i/godot-ai-plugin) MCP server when needed. The plugin itself is not vendored into the clash repo.

**Why:** Avoids per project addon install overhead. The plugin updates independently.

## 0009 — AGENTS.md instead of CLAUDE.md

**Date:** 2026-04-28

The repo level agent instruction file is `AGENTS.md`, not `CLAUDE.md`. Per project hooks live in `.claude/settings.json` (Claude Code specific); other agent tools (Codex, Cursor, etc.) can add their own config without renaming the main file.

**Why:** Tool agnostic by default. Claude Code reads `AGENTS.md` natively; the convention is becoming the standard across agent CLIs.

## 0010 — Multi-tile entity occupancy

**Date:** 2026-04-29

Tiles are small. Units and buildings occupy a footprint of one or more tiles, defined per entity type. Tile size and per-entity footprint are tuning knobs the prototype must keep configurable.

**Why:** The intended feel sits between SC2 (continuous space) and a classic hex/grid wargame. Small tiles plus multi-tile footprints let buildings feel like real structures and let unit positioning carry meaning, without giving up the determinism of grid-based resolution.

**Implication:** State is `entity{ origin: (x,y), footprint: (w,h) }`, not `entity{ tile: (x,y) }`. Pathfinding, range checks, vision, and collision must all assume multi-tile occupancy from day one — retrofitting later is painful.

## 0011 — Pop cap 50, variable slot cost per unit

**Date:** 2026-04-29

Total population cap per player is 50 (tunable). Each unit type costs a fixed integer number of pop slots based on tier (e.g. marine 1, tank 3, helicopter 4). Workers count toward the cap.

**Why:** Caps the action surface a player has to manage and forces composition tradeoffs (mass-T1 vs few-T3). Aligns with the anti-overwhelm design goal: at any given moment a player has on the order of 4–5 *groups* to think about, not 50 individual units.

## 0012 — Persistent move orders

**Date:** 2026-04-29

A move order issued to a unit persists across turns until: (a) the unit reaches its destination, (b) the unit dies, or (c) the player explicitly cancels or replaces it. The unit advances along its path each turn at its movement speed; players do not need to re-issue the order.

Movement and combat are independent in the current playable model:

- **Move:** advances toward the destination and does not stop just because combat is available.
- **Target focus:** stores a preferred enemy target. If that enemy is in range, the unit shoots it first; otherwise it falls back to the closest in-range enemy unless hold-fire is enabled.
- If a unit fires while following an old persistent move, that old move is cleared after the resolve unless the player submitted a fresh move this turn.

Hold-fire mode is independent and orthogonal: a hold-fire unit still moves, but will not fallback-auto-acquire enemies.

**Why:** SC2 demands continuous re-issuing of orders to a moving army; clash demands one issue, then the unit handles its trajectory. Aligns with the anti-overwhelm goal.

## 0013 — Deterministic resolution, no RNG by default

**Date:** 2026-04-29

The resolver is fully deterministic with no random number source. Same `(state, queue_a, queue_b)` triple always produces the same `events[]`. RNG may be introduced later for specific mechanics (crit chance, ability proc) but only behind a seeded PRNG whose seed lives in the turn frame.

The speed stat is used **only** for movement distance per turn. It does not affect attack order. Attack order within a tick is set by ADR 0004 (action-slot lockstep) with a stable, ID-based tiebreak.

**Why:** Replays, network reconciliation, and tournament integrity are free if the resolver is deterministic. The user-facing reason matters more, though: players can mentally model a turn's outcome without comparing stat sheets, which is the predictability the design depends on.

## 0014 — Wall-clock action budget, no hard cap

**Date:** 2026-04-29

Number of orders a player may queue per turn is bounded by the shared turn timer alone. No hard "actions per turn" cap.

**Why:** More skill-expressive than a hard cap. The action budget naturally scales with the player's UX speed (mobile vs desktop, expert vs novice) and the timer is the lever we tune for pacing. Revisit if playtesting shows runaway micro.

## 0015 — Identical fixed roster at MVP; deck and race systems deferred

**Date:** 2026-04-29

Both players start a match with the same units and buildings: marine + tank + helicopter, barracks + factory + starport, plus base and workers. No deck construction, no race choice, no leader perks at MVP.

The card-based unit selection, race / leader perks, card evolution, arena progression, and ladder unlocks (Clash-Royale-style) are all post-MVP layers. Implementing them before the underlying simultaneous-turn RTS is fun is premature.

**Why:** Validates the core mechanic in isolation. Add asymmetry only after symmetry plays well.

## 0016 — Fog of war from day one

**Date:** 2026-04-29

Each player sees only what their units and buildings have vision on. Vision is per-entity (per-type radius) and recomputed each turn. Memory ("last seen") for terrain and previously sighted enemy buildings is desirable but not strictly required for MVP.

**Why:** Scouting is a strategic action the design relies on (worker scouts, harass routing, drops). Without fog of war, scouting has no meaning and the strategy space collapses. Ship it from M0; the dev play tool renders both players' fog correctly even though one developer is driving both sides.

## 0017 — Win condition: raze all enemy buildings, or surrender

**Date:** 2026-04-29

A player wins when (a) the opponent has no buildings remaining, or (b) the opponent surrenders. No timer-based decision, no objective points at MVP.

**Why:** Matches SC2's win condition and gives a clean, undisputed end state for the resolver to detect. Revisit after playtesting if matches stall.

## 0019 — Entity component composition model

**Date:** 2026-04-29

All entities — units, buildings, neutrals (mineral patches, gas geysers), future entity kinds — share a single data shape: `EntityDef` with optional capability sub-resources. An entity has a capability (`HealthDef`, `CombatDef`, `MovementDef`, `VisionDef`, `PopulationDef`, `ConstructionDef`, `ProductionDef`, `GatherDef`, `ResourceSourceDef`, `AbilitiesDef`) only if the corresponding sub-resource on its def is non-null. The resolver dispatches per-capability via null checks: `if (entity.Def.Combat != null) ResolveCombatTick(...)`.

There is no separate `UnitDef` / `BuildingDef` / `NeutralDef` hierarchy. A "unit" is just an `EntityDef` with `Movement`; a "building" is one without; a sieged tank, a mineral patch, and a future lift-off-capable building are all just different capability compositions of the same `EntityDef` shape.

Polymorphic concepts (e.g. ability effects: `StatBuffEffect`, `TransformEffect`) use GDScript Resource inheritance (`class_name X extends Effect`) for editor ergonomics. If a future wire format requires a discriminated-union encoding (e.g. proto `oneof`), a thin mapping layer is added at that point.

Full design: `plan/m0/00-config-and-tunables.md`.

**Why:** Future entities (transforming units, lift-off buildings, neutral creatures, asymmetric race units, deck-based card units) compose by combining different capabilities — no schema rewrites needed. Matches how SC2 internally models entities (a sieged tank is a different unit type sharing the same data shape) and keeps the resolver pure-function over plain-data structures.

**Implication:** The runtime `Entity` is a plain GDScript class (not a Godot `Node`), with optional state fields paralleling the def's optional capabilities (e.g. `production_state` is non-null only if `def.production != null`). Plan node 00 and the design spec carry the field-level details.

## 0018 — Tunables are data-driven Godot Resources, never hardcoded

**Date:** 2026-04-29

All gameplay numbers live in Godot Resource files (`.tres`) or a single global `Tunables.tres`. This includes: unit stats (HP, damage, range, speed, vision, pop, footprint, tags), building stats (HP, footprint, build time), entity costs (minerals + gas), research effects, counter modifiers, tile pixel size, default turn timer, default starting workers / minerals / gas, mineral patch yields, gas geyser yields.

Entity definitions use a single `EntityDef` GDScript Resource subclass with capability sub-resources (per ADR 0019); one `.tres` file per concrete entity (`marine.tres`, `tank.tres`, `barracks.tres`, etc.). Strict GDScript typing throughout — most stat-name typos surface as parse errors or runtime errors loud enough to catch quickly.

Scenarios may override individual tunables for testing without mutating the canonical files.

**Why:** During M0 and M1 we will retune dozens of numbers per playtest session. Hardcoding any of them costs a code change per tweak — fatal for iteration speed. Godot Resources are editor-friendly, hot-reloadable, version-controllable, and the typed-subclass approach catches mistakes earlier than a generic config bag would.

**Implication:** The resolver loads tunables at match start and treats them as immutable for the duration of the match (no live edits mid-turn). A "reload tunables, restart scenario" path is in scope for the dev play mode.

## 0020 — GDScript primary, C# dropped

**Date:** 2026-04-29

Supersedes ADR 0003. Game code is GDScript. C# is not used.

**Why:** As of Godot 4.6 stable and 4.7 beta 1, C# does not support web export — and clash's roadmap targets web at M4. C# mobile (iOS/Android) is also officially "experimental" with documented issues (SSL crashes on Android, NativeAOT reflection trimming on iOS). GDScript ships production-ready on every clash target (web, iOS, Android, desktop).

The "C# scales better" framing in ADR 0003 was made on aesthetic / scaling grounds before the platform support matrix was researched; it does not survive contact with the actual platform constraints in 2026. GDScript 4.x typed instructions close most of the runtime perf gap for typical game logic, and clash is turn-based with ~50 entities — perf is not the bottleneck.

The "C# enables proto-shared types with the Go server" framing from ADR 0007 also dissolves: [godobuf](https://github.com/oniksan/godobuf) (BSD-3, actively maintained, Godot 4.6 compatible) provides `.proto` → GDScript codegen, so proto-as-source-of-truth is still viable if proto is chosen at M2.

**Implication:**

- Capability composition pattern from ADR 0019 unchanged — same shape, GDScript syntax (`class_name X extends Resource`) instead of C# (`[GlobalClass] public partial class X : Resource`).
- The pre-commit hook drops `dotnet format / build / test` checks; `gdlint` / `gdformat` remain.
- The CI workflow drops the `cs` job.
- Bootstrap skips "Project → Tools → C# → Create C# Solution".
- ADR 0007's "if proto is chosen" framing still applies; if used, the GDScript-side codegen is godobuf instead of protoc.
- C# may be reconsidered if Godot ships official C# web export AND mobile graduates from experimental. As of 2026-04-29, no timeline for either.

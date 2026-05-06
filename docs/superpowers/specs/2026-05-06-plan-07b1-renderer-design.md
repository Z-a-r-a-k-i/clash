# Plan-07b1 — Renderer + Camera (the visual foundation) — Design

**Date:** 2026-05-06
**Status:** Draft, pending user review
**Scope:** clash M0 plan node 07 (`plan/m0/07-dev-play-mode.md`), sub-PR 1 of 4

## Context

Plan-08 shipped the MVP map — `mvp_map.tscn` authored, `mvp_map.tres` baked, `ScenarioLoader` consumes it without ceremony. The simulation layer is fully done (resolver, scenario load/save, deterministic golden, ~92 passing tests). What's missing for the M0 "Done when" checklist is the **visual half** of plan node 07: a renderer that draws what the resolver computed.

Plan node 07's "Done when" splits naturally into four user-visible verbs:
- **see the map** (07b1, this PR)
- **play a turn** (07b2)
- **swap perspectives** (07b3)
- **step ticks** (07b4)

This PR ships the first one. After it lands, opening `Match.tscn` shows the mvp_map with all entities rendered as sprites at their correct tile positions. No input, no fog, no manual turn advance, no debugger. Pure "render the current MatchState given any incoming events."

## Goals

1. **Render `MatchState` to screen.** Tile-grid terrain, sprite-per-entity, owner color tints, attack visualization overlays.
2. **Decouple rendering from simulation cleanly.** Resolver stays a pure function (ADR-0013); renderer reads `ResolveResult.events`, never injects callbacks.
3. **Web-sourced placeholder sprites for now.** One sprite per entity type, picked at impl time from CC0 sources (Kenney, OpenGameArt, itch.io). Defer the 2D-vs-3D-final-look question to post-M0 playtest.
4. **Make attack actions visible.** Red line attacker→target, hit flash on target, floating `-N` damage label, dev-mode combat log. Missing combat info breaks the playtest loop.
5. **Architecture survives a future art swap.** EntityView is a dumb sprite holder; later replacing it with a mesh-based view (or a different sprite pack) doesn't touch the sync code.
6. **Lock in methodology guardrails so the BoxMesh failure doesn't recur.** Visual spec written before generation, fresh-context reviewer subagent, screenshot hook.

## Non-goals

- **Manual turn advance UI** — plan-07b2.
- **Mouse input / unit selection / order issuing** — plan-07b2.
- **Per-player perspective + fog of war** — plan-07b3.
- **Tick-step debugger** — plan-07b4.
- **Final art direction.** M0 is for validating mechanics, not visuals (per `plan/m0/README.md`).
- **Animation polish.** Modulate-fade attack lines and float-up damage labels are the only animations.
- **Sound.**
- **Object pooling** — community consensus: not needed at our scale (~100 entities). Revisit if profiler flags it.

## Decision history (relevant context)

- We tried 3D low-poly `BoxMesh` + `CylinderMesh` primitives in a spike (`client/scripts/_spike/`, `client/scenes/_spike/`). I rated my own output as "looks pretty good for a placeholder"; the user correctly identified it as unshippable junk.
- Three rounds of research (5 subagent reports total) compared 2D sprite generation (PixelLab, SpriteLab.dev, Retro Diffusion, Nano Banana, GPT-Image-2), 3D mesh generation (Tripo, Meshy, Hunyuan3D, TRELLIS.2, Rodin, Sloyd), and Claude Code methodology for visual work.
- Mar–Apr 2026 community evidence: style drift across a 15-entity 2D AI sprite roster is THE pain point; Tripo fails on character meshes; GPT-Image-2 has no transparent PNG; Sloyd is a dark-horse parametric option but coverage of our roster types is unverified.
- **Final user decision:** use generic web-sourced 2D sprites picked per entity, ship the renderer + attack-vis quickly, defer 2D-vs-3D and AI-generation decisions to post-playtest. Generative tools "probably at some point" but not yet.

The methodology lessons — never self-rate visual output, write a spec before generating, use a fresh-context reviewer — apply regardless of which art pipeline we eventually pick. They land in this PR alongside the renderer code.

## Architecture

### Scene tree (`client/scenes/match.tscn`)

```text
Match (Node2D, script: match_renderer.gd)
├── Camera2D                  # initial view, pan/zoom in 07b2
├── Terrain (TileMapLayer)    # ground tiles only at 07b1
├── Entities (Node2D)         # parent for all EntityView instances
├── Overlays (Node2D)
│   ├── AttackLines           # Line2D children, one per active attack
│   └── DamageLabels          # floating "-N" Label children
└── HUD (CanvasLayer)
    └── CombatLog (RichTextLabel)
```

Mineral patches, geysers, bases, units — all rendered as `EntityView` children of `Entities`, not as TileMapLayer scene tiles. Treating "everything that isn't ground" as an entity keeps the data flow uniform.

### `EntityView` scene (`client/scenes/entity_view.tscn`)

```text
EntityView (Node2D, script: entity_view.gd)
├── Sprite2D
└── Label                     # HP / def_id; toggled via dev flag
```

Single `func update_from_state(entity: Entity, def: EntityDef) -> void`. Zero game logic. Swappable to mesh-based view post-M0 without touching renderer.

### Data flow

```text
ScenarioLoader.load(scenario, registry, tunables)
       │
       ▼
   MatchState  ──────────────►  MatchRenderer
       │                              │
       │                              ├──► spawn EntityView per entity
       │                              ├──► paint Terrain TileMapLayer
       │                              └──► center Camera2D on map midpoint,
       │                                   zoom to fit 50×50 in viewport
       │
       │ (07b2 wires this) Resolver.resolve(state, ...)
       ▼
   ResolveResult { new_state, events }
       │
       │ MatchRenderer.render_step(new_state, events)
       │
       ├──► reconcile entity views (spawn / update / despawn)
       ├──► for each ATTACK event:    spawn AttackLine + DamageLabel
       ├──► for each DESTROYED event: trigger fade-out, despawn after 1s
       └──► append to CombatLog
```

### MatchRenderer API

```gdscript
class_name MatchRenderer
extends Node2D

func bind_state(state: MatchState, registry: EntityRegistry) -> void
func render_step(new_state: MatchState, events: Array[ResolverEvent]) -> void
```

Why direct calls instead of Godot signals from the resolver: the resolver is a pure function (ADR-0013). Adding signals would couple simulation to rendering and break determinism. Renderer reads `ResolveResult.events` — same data, no coupling.

### Sprite-mapping registry

New `EntityVisuals` Resource (`client/data/entity_visuals.tres`):

```gdscript
class_name EntityVisuals
extends Resource

@export var sprite_paths: Dictionary = {}
# { "marine": "res://data/art/sprites/marine.png", ... }
```

Decoupled from `EntityRegistry` so we can swap art without touching gameplay defs.

### Attack visualization

For each `ATTACK` event in `events`:
- Spawn `Line2D` from attacker.center → target.center (red, 2px, ~1s lifetime)
- Spawn `Label` at target.center, text `"-%d" % damage`, animated up + fade
- Append to `CombatLog`: `"%s #%d → %s #%d (%d dmg)"`

Pure rendering; no game logic. The resolver already computed who hit whom.

## Methodology guardrails

### `docs/visual-spec.md`

Written before any visual work. Sections:
1. Reference frame — pinned screenshot from a recent commercial top-down RTS at low zoom.
2. Acceptance criteria (1-5 ratings): silhouette readability, owner clarity, action visibility, style coherence, scale plausibility.
3. Anti-criteria (immediate rejection): untextured 3D primitives on flat planes, sprites with default backgrounds visible, sub-pixel grid drift, owner color invisible at 1× zoom.

### `.claude/agents/visual-reviewer.md` subagent

Read-only (`tools: Read, Glob`), `model: opus`. Receives screenshot path + visual-spec path + reference image path. Outputs structured 1-5 ratings per criterion + specific findings + verdict (`ACCEPTABLE` / `NEEDS WORK` / `BLOCKER`). Cannot say "looks good" without a numeric rating.

### `PostToolUse` hook

In `.claude/settings.json`, matching `Write|Edit` on `client/scenes/**/*.tscn` writes. Emits a reminder to capture viewport via `godot_capture_game_viewport` before declaring visual work done. Reminder, not a forced action — Godot may not be running, change may be a refactor.

### `CLAUDE.md` updates

Append a *Visual work* section. Prune any "double-check before returning" / "verify before completing" scaffolding per Opus 4.7 guidance — that scaffolding now degrades output.

## Tests (7 new)

Live in `client/scripts/_dev/test_renderer.gd` + `test_renderer_scene.tscn` — separate from `test_resolver.gd` because they have different setup helpers and don't share resolver-test fixtures.

| Name | Asserts |
|---|---|
| `match_renderer_classes_load` | `MatchRenderer.new()` returns non-null; `entity_view.tscn` instantiates; `match.tscn` instantiates. |
| `match_renderer_initial_state_spawns_views` | Synthetic 10×10 state with 3 entities → after `bind_state`, 3 `EntityView` children at correct world positions. |
| `match_renderer_owner_modulate` | One entity per owner (0/1/-1) → modulate matches spec (blue/red/untinted). |
| `match_renderer_uses_visuals_registry` | Two `mineral_patch` entities → both EntityViews use the same Texture2D loaded from `entity_visuals.tres`. |
| `match_renderer_renders_attack_event` | Synthetic state + ATTACK event → 1 Line2D in AttackLines with correct endpoints, 1 Label with correct text, 1 new line in CombatLog. |
| `match_renderer_renders_destruction` | Synthetic state + DESTROYED event → EntityView begins fade tween, despawns after lifetime. |
| `match_renderer_reconciles_state_diff` | `bind_state(A)` then `render_step(B with added/removed entities)` → scene tree matches B. |

Helpers (`_make_renderer_state`, `_renderer_registry`, `_make_attack_event`) keep tests self-contained and free of disk fixtures.

What renderer tests do NOT cover:
- Pixel-level visual correctness (visual-reviewer subagent's job)
- Animation timing (assert *start*, not exact ms)
- Performance (no benchmarks at M0 scale)

### Cold-start brittleness — known issue, not blocking

Plan-08 surfaced that the existing `test_resolver_scene.tscn` has 21 pre-existing tests that fail on a fresh Godot editor cold-start (gather/build/train/research cycles), even though they pass in a warm editor. CI doesn't run @tool tests, so this never blocks PRs. New renderer tests inherit the same risk; we accept it for 07b1 and don't invest in a "fix the cold-start" workstream as part of this PR.

## Files

### Create

**Methodology / process (chunk 1):**
- `docs/visual-spec.md`
- `docs/visual-references/match-initial.png` (placeholder until chunk 3 captures the real one)
- `.claude/agents/visual-reviewer.md`

**Renderer code (chunks 2-4):**
- `client/scripts/game/match_renderer.gd`
- `client/scripts/game/entity_view.gd`
- `client/scripts/game/attack_line.gd`
- `client/scripts/game/damage_label.gd`
- `client/scripts/data/entity_visuals.gd`
- `client/data/entity_visuals.tres`

**Scenes:**
- `client/scenes/match.tscn`
- `client/scenes/entity_view.tscn`

**Tests:**
- `client/scripts/_dev/test_renderer.gd`
- `client/scripts/_dev/test_renderer_scene.tscn`

**Placeholder art (chunk 3):**
- ~13 sprite PNGs under `client/data/art/sprites/` (one per entity type)
- `client/data/art/sprites/CREDITS.md`

### Modify

- `CLAUDE.md` — add *Visual work* section, prune Opus 4.7-degrading scaffolding
- `.claude/settings.json` — add `PostToolUse` hook on `client/scenes/**/*.tscn`

### Delete (chunk 1)

- `client/scripts/_spike/render_3d_spike.gd` + `.uid`
- `client/scenes/_spike/render_3d_spike.tscn`
- empty `client/scripts/_spike/` and `client/scenes/_spike/` directories

## Build order (committable chunks)

1. **Methodology + spike cleanup.** No code; pure docs/process. `gdformat`/`gdlint` trivially clean.
2. **Renderer scaffolding.** API stubs; scene tree; smoke test (`match_renderer_classes_load`). Opening `match.tscn` shows an empty scene with no errors.
3. **Sprites + initial-state rendering.** Web-sourced placeholder PNGs, `entity_visuals.tres` populated, `bind_state` actually spawns EntityViews + paints terrain + fits camera. Tests `match_renderer_initial_state_spawns_views`, `match_renderer_owner_modulate`, `match_renderer_uses_visuals_registry`. **Visual reviewer invocation: yes** — first time we look at clash on screen.
4. **Attack overlays + reconciliation.** AttackLine, DamageLabel, CombatLog implementations; `render_step` consumes events; entity-view reconciliation across state diffs. Tests `match_renderer_renders_attack_event`, `match_renderer_renders_destruction`, `match_renderer_reconciles_state_diff`. **Visual reviewer invocation: yes** — attack mid-frame screenshot.

Each chunk independently committable, all tests green at the end of each.

## Verification

1. `gdformat --check client/scripts` clean.
2. `gdlint client/scripts` clean.
3. `res://scripts/_dev/test_renderer_scene.tscn` opens → log: `[test_renderer] 7 passed, 0 failed`.
4. `res://scripts/_dev/test_resolver_scene.tscn` still green (no new failures vs. main).
5. `res://scenes/match.tscn` opens → mvp_map renders with sprites at correct tile coordinates, camera fitted to the 50×50 map, no shader/script errors in console.
6. Visual-reviewer verdict on chunk 3's match-initial screenshot: `ACCEPTABLE` or `NEEDS WORK` (not `BLOCKER`).
7. Visual-reviewer verdict on chunk 4's attack-mid-frame screenshot: same standard.
8. CI proto + gdscript jobs green.

## ADRs invoked

- **ADR-0010** (multi-tile occupancy): renderer uses `state.tile_grid.entity_rect(id)` to position EntityViews; supports any footprint.
- **ADR-0013** (deterministic resolution): resolver stays a pure function; renderer reads `ResolveResult` data, never injects callbacks into the simulation.
- **ADR-0016** (fog of war from M0): the M0 mandate is honored by plan-07b3; 07b1 excludes fog from its sub-scope.
- **ADR-0019** (capability composition): `EntityVisuals` is a separate Resource alongside `EntityDef`; doesn't extend the capability shape.
- **ADR-0020** (GDScript-only): all new code is GDScript.

## Plan invocations

- `plan/m0/07-dev-play-mode.md` — 07b1 is the first of four sub-PRs splitting the visual half of plan node 07.
- `plan/m0/08-mvp-map.md` — 07b1 consumes `mvp_map.tres` produced by plan-08's MapBaker, closing the loop.

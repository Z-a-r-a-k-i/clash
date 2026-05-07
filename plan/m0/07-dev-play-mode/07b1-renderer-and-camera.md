---
status: done
---

# Renderer + camera (the visual foundation)

First of four sub-PRs splitting the visual half of plan node 07. After this lands, opening `Match.tscn` shows the mvp_map with all entities rendered as sprites at their correct tile positions. No input, no fog, no manual turn advance, no debugger — pure "render the current MatchState given any incoming events."

## Context

Plan-08 shipped the MVP map — `mvp_map.tscn` authored, `mvp_map.tres` baked, `ScenarioLoader` consumes it without ceremony. The simulation layer is fully done (resolver, scenario load/save, deterministic golden, ~92 passing tests). What's missing for the M0 "Done when" checklist is the **visual half** of plan node 07: a renderer that draws what the resolver computed.

Plan node 07's "Done when" splits naturally into four user-visible verbs:
- **see the map** (07b1, this node)
- **play a turn** ([07b2-input-and-turn-advance.md](./07b2-input-and-turn-advance.md))
- **swap perspectives** ([07b3-perspective-and-fog.md](./07b3-perspective-and-fog.md))
- **step ticks** ([07b4-tick-step-debugger.md](./07b4-tick-step-debugger.md))

## Goals

1. **Render `MatchState` to screen.** Tile-grid terrain, sprite-per-entity, owner color tints, attack visualization overlays.
2. **Decouple rendering from simulation cleanly.** Resolver stays a pure function (ADR-0013); renderer reads `ResolveResult.events`, never injects callbacks.
3. **Web-sourced placeholder sprites for now.** One sprite per entity type, picked at impl time from CC0 sources (Kenney, OpenGameArt, itch.io). Defer the 2D-vs-3D-final-look question to post-M0 playtest.
4. **Make attack actions visible.** Red line attacker→target, hit flash on target, floating `-N` damage label, dev-mode combat log. Missing combat info breaks the playtest loop.
5. **Architecture survives a future art swap.** EntityView is a dumb sprite holder; later replacing it with a mesh-based view (or a different sprite pack) doesn't touch the sync code.

## Non-goals

- **Manual turn advance UI** — 07b2.
- **Mouse input / unit selection / order issuing** — 07b2.
- **Per-player perspective + fog of war** — 07b3.
- **Tick-step debugger** — 07b4.
- **Final art direction.** M0 is for validating mechanics, not visuals (per [`../README.md`](../README.md)).
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

New `EntityVisuals` Resource at `client/data/entity_visuals.tres`. The class definition lives in `client/scripts/data/entity_visuals.gd` (a single typed `sprite_paths` map from `def_id` to `res://` texture path). Decoupled from `EntityRegistry` so we can swap art without touching gameplay defs. Per the project rule, type schemas live in code, not in markdown — see the source file for the authoritative shape.

### Attack visualization

For each `ATTACK` event in `events`:
- Spawn `Line2D` from attacker.center → target.center (red, 2px, ~1s lifetime)
- Spawn `Label` at target.center, text `"-%d" % damage`, animated up + fade
- Append to `CombatLog`: `"%s #%d → %s #%d (%d dmg)"`

Pure rendering; no game logic. The resolver already computed who hit whom.

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
- Pixel-level visual correctness (visual eyeballing, not automated)
- Animation timing (assert *start*, not exact ms)
- Performance (no benchmarks at M0 scale)

### Cold-start brittleness — known issue, not blocking

Plan-08 surfaced that the existing `test_resolver_scene.tscn` has 21 pre-existing tests that fail on a fresh Godot editor cold-start (gather/build/train/research cycles), even though they pass in a warm editor. CI doesn't run @tool tests, so this never blocks PRs. New renderer tests inherit the same risk; we accept it for 07b1 and don't invest in a "fix the cold-start" workstream as part of this PR.

## Files

### Create

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

### Delete (chunk 1)

- `client/scripts/_spike/render_3d_spike.gd` + `.uid`
- `client/scenes/_spike/render_3d_spike.tscn`
- empty `client/scripts/_spike/` and `client/scenes/_spike/` directories

## Build order (committable chunks)

1. **Spike cleanup.** Remove the 3D primitive spike. No code; pure cleanup.
2. **Renderer scaffolding.** API stubs; scene tree; smoke test (`match_renderer_classes_load`). Opening `match.tscn` shows an empty scene with no errors.
3. **Sprites + initial-state rendering.** Placeholder PNGs (deferred quality-pass to a dedicated sprite PR), `entity_visuals.tres` populated, `bind_state` actually spawns EntityViews + paints terrain + fits camera. Tests `match_renderer_initial_state_spawns_views`, `match_renderer_owner_modulate`, `match_renderer_uses_visuals_registry`.
4. **Attack overlays + reconciliation.** AttackLine, DamageLabel, CombatLog implementations; `render_step` consumes events; entity-view reconciliation across state diffs. Tests `match_renderer_renders_attack_event`, `match_renderer_renders_destruction`, `match_renderer_reconciles_state_diff`.

Each chunk independently committable, all tests green at the end of each.

## Done when

- [ ] `gdformat --check client/scripts` clean.
- [ ] `gdlint client/scripts` clean.
- [ ] `res://scripts/_dev/test_renderer_scene.tscn` opens → log: `[test_renderer] 16 passed, 0 failed`.
- [ ] `res://scripts/_dev/test_resolver_scene.tscn` still green (no new failures vs. main).
- [ ] `res://scenes/match.tscn` opens → mvp_map renders with sprites at correct tile coordinates, camera fitted to the map, no shader/script errors in console.
- [ ] Manual eyeball check on a chunk-3 initial-state capture and a chunk-4 attack-mid-frame capture: bases distinct in owner color, attack line clearly traces attacker→target, damage label readable above the target, combat log panel doesn't overlap the play area.
- [ ] CI proto + gdscript jobs green.

## ADRs invoked

- **ADR-0010** (multi-tile occupancy): renderer uses `state.tile_grid.entity_rect(id)` to position EntityViews; supports any footprint.
- **ADR-0013** (deterministic resolution): resolver stays a pure function; renderer reads `ResolveResult` data, never injects callbacks into the simulation.
- **ADR-0016** (fog of war from M0): the M0 mandate is honored by 07b3; 07b1 excludes fog from its sub-scope.
- **ADR-0019** (capability composition): `EntityVisuals` is a separate Resource alongside `EntityDef`; doesn't extend the capability shape.
- **ADR-0020** (GDScript-only): all new code is GDScript.

## Artifacts

- PR [#9](https://github.com/Z-a-r-a-k-i/clash/pull/9)

# clash

Turn-based PvP RTS in Godot 4.6 (GDScript-only). See `docs/ROADMAP.md` for milestones.

## Plan tree convention

The canonical roadmap lives under `plan/`. Format spec at `docs/PLAN-FORMAT.md` (v0.1 draft, mirrored from termwatch).

- **Plan node bodies are the spec.** Design rationale, build chunks, tests, ADR invocations all live in the relevant plan node (`plan/m0/<NN>-<topic>.md` or `plan/m0/<area>/<sub-topic>.md`). **Do NOT write spec files under `docs/superpowers/specs/`** — that directory is intentionally absent. The brainstorming skill's default save path is overridden for this project.
- Compound nodes are directories with `README.md` (the node's own file). Leaves are plain `.md` files.
- YAML frontmatter `status: stub | sketch | ready | doing | done`. Optional `depends_on` for cross-branch dependencies, `questions` for unresolved blockers.
- Done nodes stay in place as historical record with an `## Artifacts` section linking the merged PR.
- `docs/` is for cross-cutting reference docs (`DECISIONS.md`, `ARCHITECTURE.md`, `PLAN-FORMAT.md`, `ROADMAP.md`) — not plans.

## Visual work (clash M0 onward)

- Never self-rate visual output. After producing any rendered scene, invoke the `visual-reviewer` subagent with: screenshot path, `docs/visual-spec.md`, `docs/visual-references/<latest>.png`. (Subagent + spec land in plan-07b1 chunk 1.)
- Untextured 3D primitives (`BoxMesh` / `CylinderMesh` / `SphereMesh` on a flat plane) are auto-flagged as unshippable. Don't proceed with them as a "good placeholder" without explicit user sign-off.
- `godot_capture_game_viewport` (via godot-mcp) is the required evidence before declaring visual work done.
- Reference: plan node `plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md` for the renderer + methodology guardrails design.

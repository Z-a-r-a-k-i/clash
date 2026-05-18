---
status: done
depends_on:
  - ./07-dev-play-mode/07b6-playtest-loop.md
  - ./08-mvp-map.md
---

# M0 manual playtest readiness

This node prepares the first human M0 playtest handoff. It does not complete
the playtest; it makes the pass repeatable and gives feedback a clear place to
land before the next gameplay PR.

## Scope

- Add a playtest docs entrypoint that points to the current pass, canonical
  checklist, and notes template.
- Add the first pass notes file for `mvp_map.tres`, including smoke command,
  setup confirmation, turn log, observations, and next-iteration triage.
- Tighten the M0 checklist with the exact dev scene path and current controls.

## Non-goals

- No runtime, scene, or HUD changes.
- No balance or tuning changes.
- No claim that the full human pass has already succeeded.

## Done when

- [x] The manual playtest entrypoint explains which file to use for pass 01.
- [x] Pass 01 has a pre-filled notes file for the canonical M0 scenario.
- [x] The checklist names the exact dev scene and current controls.
- [x] The M0 index tracks this readiness node separately from the final M0
  complete-match checkbox.

## Artifacts

- PR #22: Prepare M0 manual playtest handoff.

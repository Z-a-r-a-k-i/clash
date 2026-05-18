# Playtest Docs

This folder is the handoff point for repeatable manual gameplay passes.

## Current Pass

Use [m0-pass-01.md](m0-pass-01.md) for the first M0 manual playtest. It is
pre-filled for the canonical scenario and has space for the smoke result,
turn log, observations, and next-iteration triage.

Before the manual pass, run the automated smoke command from the pass file.
Then open `client/project.godot`, run
`res://scenes/_dev/dev_play_mode.tscn`, and verify the scene is using
`res://data/scenarios/mvp_map.tres`.

## Supporting Files

- [m0-checklist.md](m0-checklist.md): canonical manual pass flow.
- [m0-notes-template.md](m0-notes-template.md): blank template for later passes.

## Feedback Loop

After a pass, keep the notes concrete: what action was attempted, what was
expected, what happened, and why it slowed down or improved the game. Triage
the feedback into the pass file as:

- Must fix before next pass.
- Gameplay or pacing change.
- Tooling or debuggability issue.
- Later polish.

The next PR should take the smallest gameplay-facing slice that makes another
manual pass more useful.

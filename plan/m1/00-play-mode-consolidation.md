---
status: sketch
---

# Play-mode consolidation (solo/multi DRY)

`client/scripts/_dev/dev_play_mode.gd` (~2300 lines) and
`client/scripts/network/network_play_mode.gd` (~1750 lines) are parallel
implementations of the same match session: selection, drag-boxing, context
right-click, pending commands, command card wiring, action/target previews,
camera, hover, escape menu, outcome overlay, idle-worker indicators. They have
already drifted (the M0 "HUD fixes" round had to be applied twice and still
broke one side). Every M1 presentation node (graphics, HUD) would double its
cost against this duplication — so this lands first.

## Shape

Extract a shared `MatchSessionController` (name TBD) owning everything between
raw input and "a turn was submitted":

- selection model + drag box + click selection (`selection_drag_controller.gd`
  already exists and is shared — fold its glue in too);
- context-action resolution and pending-command state machine;
- command card + preview refresh wiring (`action_preview_builder.gd`,
  `tactical_preview_builder.gd` are already shared builders);
- camera pan/zoom, hover tile, HUD update hooks;
- `MatchPlaySurface` ownership.

The two modes shrink to adapters over a small strategy interface:

- **LocalAdapter** (dev play): owns both players' submissions, runs
  `Resolver.resolve` locally, drives perspective switching and the scenario
  loader / save-load / replay tooling.
- **NetworkAdapter**: owns one player slot, submits over the wire, binds
  authoritative snapshots, handles submit-in-flight blocking and
  connection status.

The AI opponent (node 01) becomes a third submission source behind the same
interface — that is the real payoff: "who produces the other SubmitTurn" stops
being baked into the mode.

## Constraints

- Pure refactor: behavior changes only where the two modes already disagree
  by accident; each such disagreement gets called out and resolved explicitly.
- The combined test suites (test_dev_play_mode, test_dev_turn_input,
  test_network_multiplayer ≈ 120 tests) must pass before/after; they are the
  spec for what the controller does.
- Keep `DevTurnInput` as the order-queue model; this node is about the layer
  above it.

## Done when

- [ ] Shared controller exists; both modes are adapters under ~400 lines each.
- [ ] No copy-pasted logic blocks remain between the two modes (spot-audit).
- [ ] All existing play-mode and network tests pass unchanged (or with
      documented intentional fixes).
- [ ] A third submission source (AI stub returning empty submits) can be
      plugged in without touching the controller.

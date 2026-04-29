---
status: sketch
depends_on:
  - ./00-config-and-tunables.md
  - ./01-tile-grid-and-occupancy.md
---

# MVP map layout

A single fixed map at MVP, modeled on SC2 macro-map shapes but adapted for clash's smaller-tile, multi-tile-footprint grid.

## Topology

Symmetric mirror layout, two players. Per side:

- **Main.** Starting base location. Mineral cluster + 1 gas geyser + a few starting workers + the player's starting base building.
- **Natural.** Forward expansion adjacent to the main, behind a chokepoint that can be **walled off by ground**. Mineral cluster + 1 gas geyser. The wall covers ground access to both main and natural — sealing it gates the only ground entry until the wall is broken.
- **Left expansion.** Mineral cluster + 1 gas geyser off the main–natural axis, on one flank.
- **Right expansion.** Mineral cluster + 1 gas geyser on the opposite flank.

Each of the 8 base positions on the map has both a mineral cluster and a gas geyser. Gas requires a refinery (built on the geyser) before workers can extract it.

Maximum 4 bases per player in the late game. The two off-axis expansions are equidistant between the two players' mains, so taking one is always contestable — that's the lever for cheese, harass, denial, and late-game flank plays.

```text
                            P2 MAIN
                               │
                            P2 NAT
                           [walled choke]
                               │
                               │  (only ground path between sides)
                               │
       P2 LEFT  ─────── contested middle ─────── P2 RIGHT
                          (open ground)
       P1 LEFT  ─────── contested middle ─────── P1 RIGHT
                               │
                               │
                           [walled choke]
                            P1 NAT
                               │
                            P1 MAIN
```

Per side: **main** is the safest position (deepest behind the choke); **natural** is one step forward, still behind the wall; the two **expansions** sit out in the contested middle, *forward* of the choke and exposed to attack from across the map. Each player's left/right is from their own perspective — under vertical mirror, P1's LEFT and P2's RIGHT occupy the same map flank.

Cheese, harass, and tower-rush plays exist precisely because the opponent's expansions are reachable without first breaking through their natural choke. The wall-or-don't decision at the natural is the same shape as SC2 maps — wall up to deny ground harass and protect both the main and natural with one structure, or skip the wall to keep mobility and rely on units instead.

This layout follows SC2 ladder convention: main + close natural separated by one choke, with the third / fourth bases scattered toward map flanks. Pro ladder maps often use point-symmetry (diagonal mains) rather than vertical mirror because it equalizes path length to the middle from either spawn. MVP keeps vertical mirror for simplicity; point-symmetric variants become an option once the map-authoring story exists post-MVP.

## Why this shape

- Encourages SC2-style macro decisions: one-base all-in, two-base timing, four-base late game.
- The natural's chokepoint creates the wall-off / contain decision — same shape as SC2 maps that play out over decades.
- Off-axis expansions equidistant between players means taking one is a real strategic statement: it's not "free territory," it's a contested asset within the opponent's reach.
- Path distances should encourage at least some combat positioning — too cramped and there's no maneuver, too spread and the simultaneous-turn budget can't cover the map.

## Configurable bits

All in `Tunables.tres` (per node 00):

- Tile dimensions (overall map size in tiles).
- Mineral patch yield and capacity per cluster.
- Gas geyser yield (per turn, per worker, with refinery built).
- Choke width (in tiles) at the natural — drives whether walls of the MVP buildings actually fit.
- Path distance main-to-main, main-to-expand, expand-to-expand. These are derived from the tile layout but should be checked / tuned during playtest.

## What's NOT here at M0

- Vision-blocking terrain (cliffs, doodads). M0 ships with open visibility plus fog of war on enemy positions; high-ground and line-of-sight come later.
- Destructible rocks / map gimmicks. Defer.
- Multiple maps. Single map at MVP per ADR / scope. Map authoring tooling is post-MVP.

## Open questions

- Does the natural chokepoint use a built-in wall (terrain) or rely on the player walling with their own buildings? **Player walls with their own buildings.** Reason: it makes wall-or-don't a real strategic choice, and it stresses the multi-tile-footprint system in exactly the way we want to validate at M0.
- How many mineral patches per cluster? Default 6, tunable.
- Are expansions visible to both players from turn 0, or behind fog? Behind fog. The map silhouette is known (terrain in the open), enemy presence is not.

## Done when

- [ ] Map is implemented as a hand-authored Godot scene with tile data.
- [ ] Mineral cluster + gas geyser positions match the per-side topology (1 main + 1 natural + 2 expansions per player, mirrored).
- [ ] Natural choke is buildable into a wall using marines/buildings of MVP size.
- [ ] Default tile size and footprint values produce a path distance from main to enemy main that fits a 5-min match (~10–20 turns to traverse with a marine — tune in playtest).
- [ ] Map loads via the scenario / tunables system; switching maps later is just swapping the scene reference.

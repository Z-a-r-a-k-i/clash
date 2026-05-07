# Sprite credits

All sprites in this directory are placeholder art for clash M0. They are sourced from Kenney's "Sci-Fi RTS" asset pack and are licensed under **Creative Commons CC0 1.0 Universal** (public domain).

- **Source:** https://kenney.nl/assets/sci-fi-rts (Kenney Vleugels)
- **License:** [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) — free for unrestricted commercial and non-commercial use, attribution not required.

## Mapping

clash entity → Kenney source file:

| clash entity | source file |
|---|---|
| base | scifiStructure_01.png |
| barracks | scifiStructure_05.png |
| factory | scifiStructure_06.png |
| starport | scifiStructure_13.png |
| refinery | scifiStructure_09.png |
| worker | scifiUnit_01.png |
| marine | scifiUnit_15.png |
| tank | scifiUnit_45.png |
| siege_tank | scifiUnit_47.png |
| helicopter | scifiUnit_30.png |
| mineral_patch | scifiEnvironment_08.png |
| mineral_patch_gold | scifiEnvironment_08.png (same as standard until distinct sprite is sourced or recolored) |
| gas_geyser | scifiEnvironment_12.png |

## Status: M0 placeholders

These are dev-tool placeholders, not final art. Per [`docs/visual-spec.md`](../../../../docs/visual-spec.md), M0 visuals should land at 3-4/5 across the spec criteria — not 5/5. Final art direction is deferred to post-M0 once playtest reveals which entities matter visually.

The Kenney pack is alien/Mars-themed, while clash's entity vocabulary is StarCraft-Terran-ish (marine/tank/helicopter/barracks/factory/starport). The aesthetic mismatch is acceptable for placeholder use; readability per entity type is what M0 needs.

Known weak picks:
- `helicopter.png` is a green van-shaped vehicle — the pack contains no clear aircraft. Replace if a better source emerges.
- `mineral_patch_gold.png` is currently identical to `mineral_patch.png` — needs recoloring to gold so players can tell standard vs golden patches apart at a glance.
- The whole sprite set is footprint-agnostic and not yet sized per-entity (1x1 vs 2x2 vs 4x4 vs 1x3 vs 3x3). A dedicated sprite-asset PR will replace these with footprint-aware art.

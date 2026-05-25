# Sprite credits

Sprites in this directory are placeholder art for clash M0. The current
gameplay sprite set is made from AI-generated art direction tests and is tracked
below. Earlier placeholders came from Kenney's "Sci-Fi RTS" asset pack and were
licensed under **Creative Commons CC0 1.0 Universal** (public domain), but no
current mapped sprite still uses those files.

- **Source:** https://kenney.nl/assets/sci-fi-rts (Kenney Vleugels)
- **License:** [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) — free for unrestricted commercial and non-commercial use, attribution not required.

## Mapping

clash entity → source file:

| clash entity | source file |
|---|---|
| base | Gemini-generated command base, cleaned to transparent PNG |
| barracks | Gemini-generated infantry barracks, cleaned to transparent PNG |
| factory | Gemini-generated vehicle factory, cleaned to transparent PNG |
| starport | Gemini-generated aircraft starport, cleaned to transparent PNG |
| refinery | Gemini-generated gas refinery, cleaned to transparent PNG |
| worker | Gemini-generated worker mech, cleaned to transparent PNG |
| marine | Gemini-generated armored infantry, cleaned to transparent PNG |
| tank | Gemini-generated battle tank, cleaned to transparent PNG |
| siege_tank | Gemini-generated siege-mode battle tank, cleaned to transparent PNG |
| helicopter | Gemini-generated VTOL gunship, cleaned to transparent PNG |
| mineral_patch | Gemini-generated blue mineral patch, cleaned to transparent PNG |
| mineral_patch_gold | Gemini-generated gold mineral patch variant, cleaned to transparent PNG |
| gas_geyser | Gemini-generated gas geyser, cleaned to transparent PNG |

## AI-generated sprites

`base.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the custom units and resources as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the base only.

`barracks.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the base and infantry images as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the barracks only.

`factory.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the base, barracks, and tank images as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the factory only.

`starport.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the base, factory, and helicopter images as style references.
It was processed locally into a transparent 1024x1024 PNG and replaces the
earlier Kenney placeholder for the starport only.

`refinery.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the gas geyser, base, and factory images as style references.
It was processed locally into a transparent 1024x1024 PNG and replaces the
earlier Kenney placeholder for the refinery only.

`worker.png` was generated in the Gemini web app with Nano Banana Pro image
generation as a style test for the final clash art direction. It was processed
locally into a transparent 1024x1024 PNG and replaces the earlier Kenney
placeholder for the worker only.

`marine.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the worker image as a style reference. It was processed locally
into a transparent 1024x1024 PNG and replaces the earlier Kenney placeholder for
the marine only.

`tank.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the worker and marine images as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the tank only.

`siege_tank.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the tank image as the vehicle identity reference. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the siege tank only.

`helicopter.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the worker, marine, and tank images as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the helicopter only.

`mineral_patch.png` was generated in the Gemini web app with Nano Banana Pro
image generation using the custom unit images as style references. It was
processed locally into a transparent 1024x1024 PNG and replaces the earlier
Kenney placeholder for the standard mineral patch only.

`mineral_patch_gold.png` was generated in the Gemini web app with Nano Banana
Pro image generation using the standard mineral patch image as the structure
reference. It was processed locally into a transparent 1024x1024 PNG and
replaces the earlier duplicate Kenney placeholder for the gold mineral patch
only.

`gas_geyser.png` was generated in the Gemini web app with Nano Banana Pro image
generation using the mineral patch and custom unit images as style references.
It was processed locally into a transparent 1024x1024 PNG and replaces the
earlier Kenney placeholder for the gas geyser only.

## Status: M0 placeholders

These are dev-tool placeholders, not final art. The current renderer-facing
entity sprite set is fully covered by the first candidates for the custom art
direction.

Known weak picks:
- The whole sprite set is footprint-agnostic and not yet sized per-entity (1x1 vs 2x2 vs 3x3 vs 4x4). A dedicated sprite-asset PR will replace these with footprint-aware art.

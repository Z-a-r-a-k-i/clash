---
status: sketch
depends_on:
  - ./00-config-and-tunables.md
  - ./04-economy.md
---

# Production: buildings, units, research

All production happens on per-item turn-count timers. Same shape across buildings, units, and research — one queue mechanism, three consumers.

## Common shape

```text
ProductionItem {
  type: building | unit | research
  cost: { minerals, gas, pop }   # gas may be zero; pop only for units
  build_turns: int               # stat per item
  produces_at: building or worker  # depending on type
}
```

A building (or worker, for buildings) has a queue of `ProductionItem`s. Each turn the head item's `turns_remaining` decrements; at zero it completes and the next item starts.

## Per-type detail

- **Buildings.** Built by a worker on a target tile rect. Worker is locked to the build site for the duration. Building "appears" mid-construction (placeholder visual) and becomes functional at completion.
- **Units.** Trained at a production building (barracks, factory, starport). On completion the unit appears at a rally tile adjacent to the building.
- **Research.** Run from a research-capable building. Unlocks abilities, raises stats, or enables units. No mid-research cancellation refund at MVP.

## At MVP, keep these data-driven

| Building | Produces |
|---|---|
| Base | Workers |
| Refinery | (none — workers extract gas from it) |
| Barracks | Marines |
| Factory | Tanks |
| Starport | Helicopters |

Tank and helicopter likely cost gas in addition to minerals; marine is mineral-only. Exact costs are tuned via `Tunables` per node 00.

## Open questions

- Cancel-mid-production refund? **Full refund at MVP.** Revisit if it enables exploits.
- Multiple-queue per building (Q+5 unit batching) or single-slot? **Single slot at MVP** for UI simplicity.
- Rally points: per-building or global per-player? **Per-building.** Default rally = adjacent to building.

## Done when

- [ ] Worker can issue a build order on a tile rect; building progresses N turns; building becomes functional at 0.
- [ ] Production buildings can queue one unit at a time; units spawn at rally on completion.
- [ ] Research item completes and applies its effect (test with a placeholder research that bumps marine HP).
- [ ] All build/train/research times are data-driven.
- [ ] Cancel returns the full mineral and gas cost to the player.

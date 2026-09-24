# Strategy and Decision Support

## Principle

A candle has no fixed independent meaning. A candidate requires context, location, structure, signal-bar quality, follow-through, room, and opposing-pressure evidence.

## Setup composition

Current candidate types:

- Trend pullback
- Second entry
- Failed breakout reversal
- Three-push wedge reversal
- Breakout with follow-through

A single bull or bear bar without composed context returns `NO TRADE` unless stronger evidence exists.

## Decision status

- `NO TRADE` — no composed setup or a configured gate failed.
- `WEAK` — evidence exists but is below the quality threshold.
- `POSSIBLE` — evidence meets the minimum threshold.
- `PROBABLE` — strong composed evidence.
- `CONFIRMED EVIDENCE` — breakout evidence with follow-through; not a prediction of future success.

## Evidence score

The score is additive and capped at 100:

| Component | Maximum | Evidence |
|---|---:|---|
| Context | 25 | medium state, micro state, pressure, Always-In |
| Signal | 32 | strength, close location, pullback quality |
| Location | 20 | support/resistance proximity and obstacles |
| Follow-through | 15 | same-direction extension or failure |
| Room | 15 | reward/risk to logical target |
| Opposing pressure | 15 | directional pressure against the candidate |

Weights are transparent defaults, not optimized probabilities. Users can change the minimum quality and minimum reward/risk.

## Risk and reward

- Entry reference: latest closed-bar close.
- Invalidation: signal-bar extreme plus a range buffer.
- Target: compatible measured move, nearby obstacle, or two-range fallback.
- Reward/risk: absolute target distance divided by stop distance.

These are analytical levels, not execution recommendations. Spread, slippage, commission, and order-book effects are not modeled.

## No-trade gates

A candidate becomes `NO TRADE` when:

- no setup structure is present;
- fewer than three closed bars are available;
- invalid stop distance is produced;
- quality is below `InpMinimumQuality`; or
- reward/risk is below `InpMinimumRiskReward`.

## Methodology integrity

Brooks concepts are implemented as formal rules or heuristics only where measurable. Human judgment remains necessary for context, nuanced location, and execution.

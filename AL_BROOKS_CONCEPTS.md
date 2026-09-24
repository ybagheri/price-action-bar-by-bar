# Al Brooks Concepts

This project formalizes useful, explainable portions of Price Action. It does not claim to reproduce Al Brooks exactly.

## Implemented

| Concept | Status | Notes |
|---|---|---|
| Bull/bear trend bar | Formal rule | Body ratio and close location |
| Doji, inside, outside | Formal rule | OHLC geometry |
| H1/H2/H3+ and L1/L2/L3+ | Heuristic | Stateful leg and pullback tracking |
| Signal-bar quality | Heuristic | Close location and prior pullback extreme |
| Trend vs trading range | Heuristic | Overlap, displacement, ATR normalization |
| Always-In | Heuristic | Sticky structural swing-break proxy |
| Breakout attempt | Formal/heuristic | Fresh extreme plus strong close |
| Follow-through | Formal rule | Same-direction extension after trend bar |
| Failed breakout | Heuristic | Wick through confirmed level and rejection close |
| Double top/bottom | Heuristic | Similar recent same-type swings |
| HH/HL and LH/LL | Formal approximation | Latest two highs and lows |
| Rising/falling wedge | Heuristic | Three monotonic highs and lows |
| Measured move | Heuristic | Equal-size projection from three alternating swings |
| Climax/exhaustion | Heuristic | Large range with weak body |
| First/second entry | Heuristic composition | Pullback count plus context and signal quality |
| Channels | Partial | Overlap and slope are available, not a full channel model |
| Trapped traders | Manual aid | Requires higher-timeframe and order-flow judgment |
| Gaps and session context | Not implemented | Future context-layer work |
| Cyclical behavior | Not implemented | Avoided to prevent overfitting |

## Status vocabulary

Use these terms in development and documentation:

- **Formal rule** — deterministic implementation of the stated rule.
- **Heuristic approximation** — measurable proxy that may differ from discretionary judgment.
- **Statistical feature** — measurable input without a binary claim.
- **Visual aid** — annotation requiring trader interpretation.
- **Manual only** — intentionally not automated.

## What remains human

Nuanced location, context shifts, bar-to-bar intent, higher-timeframe alignment, and execution quality require human judgment.

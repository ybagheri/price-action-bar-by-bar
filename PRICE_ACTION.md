# Price Action Features

## Completed-bar features

For every committed bar the engine records:

- open, high, low, close, range, and body size;
- body ratio and upper/lower wick;
- close location value;
- previous-bar overlap;
- inside/outside/doji/bull/bear classification;
- large/small range relative to prior average range;
- strength: weak, moderate, or strong;
- consecutive bull/bear run;
- follow-through and failed follow-through;
- reversal-bar approximation;
- H1/H2/H3+ or L1/L2/L3+ pullback attempt;
- breakout and climax/exhaustion flags.

## Structure

- Delayed strict fractal swing highs and lows.
- Pullback numbering resets when a new leg extreme is made.
- Sticky Always-In proxy flips on closes beyond confirmed structural extremes.
- Trading-range state uses overlap and normalized displacement.

## Context

The context analyzer uses the latest 3–10 completed bars and reports:

- micro state;
- normalized displacement;
- overlap;
- bull and bear pressure;
- nearest confirmed support and resistance;
- failed bull/bear breakout heuristics;
- proximity to levels.

## Interpretive limits

- A large bar can be continuation or climax depending on context.
- H2/L2 is a pullback attempt, not a universal entry.
- Wedge and double-top detection is a simple approximation.
- Measured move is a three-swing projection, not a complete measured-move model.
- Volume, order flow, market microstructure, and higher-timeframe context are not yet included.

The chart annotations are aids for reading bars, not autonomous conclusions.

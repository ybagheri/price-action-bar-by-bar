# MT5 Guide

## Attach

Add **PriceActionBarByBar** to a normal price chart. Analysis is computed on the chart timeframe. Decisions use completed bars only, so the newest forming bar is not classified as a confirmed event.

## Main chart elements

- Pullback labels: H1/H2/H3+ and L1/L2/L3+.
- Swing arrows: delayed fractal highs and lows.
- Trading-range box: active coarse range context.
- Breakout and climax markers.
- Pattern and measured-move annotations.
- State panel: medium state, micro state, Always-In, and swing count.
- Setup marker: long, short, or NO TRADE.
- Entry, invalidation, and target lines.
- Explanation panel: status, score, reward/risk, reasons, and risks.

## Visibility

Important controls include:

- Show setups
- Show explanations
- Show debug
- Show measured move
- Show state panel
- Feature-level controls for labels, swings, ranges, patterns, breakouts, and climax

Objects use an instance-specific prefix, so multiple copies do not delete each other's objects.

## Interpretation

A `Confirmed` status means the configured breakout evidence had follow-through at decision time. It is not a guarantee. A `Probable`, `Possible`, or `Weak` candidate is evidence strength, not a deterministic forecast.

When support/resistance is close, inspect whether the apparent reward remains realistic. The displayed R:R uses analytical reference levels and does not model spread, commission, slippage, or order-book execution.

## Event export

Set **Export events** to `true` to write `pab_events.csv` in MT5's sandbox. The file is closed when the indicator is removed or MT5 shuts down.

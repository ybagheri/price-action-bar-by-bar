# Architecture

## Decision

MQL5 is the canonical real-time and historical analysis engine. Python is an offline research and validation layer. No live bridge is used.

## Runtime layers

1. **Closed-bar gate** — index 0 is never committed as a decision bar. Duplicate timestamps are ignored.
2. **BarClassifier** — geometry, range, body/wick, overlap, strength, runs, reversal, pullback, breakout, and climax features.
3. **SwingDetector** — delayed strict fractals with stable timestamps.
4. **TradingRangeDetector / AlwaysInTracker** — coarse regime and sticky structural proxy.
5. **ContextAnalyzer** — 3–10 bar micro state, pressure, nearby levels, and failed-breakout heuristics.
6. **PatternDetector / MeasuredMoveDetector** — lightweight structure and target references.
7. **DecisionEngine** — setup composition, NO TRADE gates, levels, reward/risk, additive score, reasons, and risks.
8. **ChartRenderer** — stable, instance-specific object lifecycle.
9. **Event export** — optional sandboxed CSV written at decision time.

## Data flow

```text
MT5 OHLC closed bars
  -> bar-driven analyzers
  -> confirmed swing list
  -> swing-derived analyzers
  -> context snapshot
  -> setup candidate
  -> chart and optional CSV
```

## Timing contract

A decision uses only completed bars. Fractal events are delayed by the configured right-side bars. Exported events include:

- `bar_open_time`
- `bar_close_time`
- `confirmed_at`
- `decision_time`

The research package rejects events where confirmation occurs after the decision or the decision occurs before bar close.

## Platform split

- MQL5: canonical logic, visualization, and event production.
- Python: schema/timing validation and outcome measurement.
- NinjaTrader: secondary unverified adapter; shared fixtures are required before claiming parity.

## Performance

- Analyzer state updates only for new closed bars.
- ATR copying is skipped on unchanged ticks.
- Unchanged ticks do not rebuild swing-derived state.
- Chart objects use stable keys and are deleted when inactive.
- Historical ring buffers have fixed capacity.

## Future boundaries

Multi-timeframe context, sessions, prior-day levels, and richer measured moves belong in the context layer. They must use only fully closed higher-timeframe data and report unavailable data honestly.

# Architecture

## Decision

MQL5 is the canonical real-time and historical analysis engine. Python is an offline research and validation layer. No live bridge is used.

## Runtime layers

1. **Closed-bar gate** — index 0 is never committed as a decision bar. Duplicate timestamps are ignored.
2. **CPabEngine** — owns the analyzers and the per-bar pipeline. `ProcessBar()`
   feeds raw OHLC to the classifier, swing detector, and range detector;
   `Evaluate()` turns accumulated state into a setup candidate.
3. **BarClassifier** — geometry, range, body/wick, overlap, strength, runs, reversal, pullback, breakout, and climax features.
4. **SwingDetector** — delayed strict fractals with stable timestamps.
5. **TradingRangeDetector / AlwaysInTracker** — coarse regime and sticky structural proxy.
6. **ContextAnalyzer** — 3–10 bar micro state, pressure, nearby levels, and failed-breakout heuristics.
7. **PatternDetector / MeasuredMoveDetector** — lightweight structure and target references.
8. **DecisionEngine** — setup composition, NO TRADE gates, levels, reward/risk, additive score, reasons, and risks.
9. **ChartRenderer** — stable, instance-specific object lifecycle.
10. **Event export** — optional sandboxed CSV written at decision time.

## One engine, two drivers

`CPabEngine` is the only place the pipeline order exists. Two entry points
drive it:

- `PriceActionBarByBar.mq5` on a chart, calling `Evaluate()` once per
  `OnCalculate` over the batch of newly closed bars.
- `PabEventExport.mq5` in the Strategy Tester, calling `Evaluate()` after
  every `ProcessBar()` across a historical range.

`Evaluate()` takes the newest bar's close and time as arguments rather than
reading series index 1, which is what lets both callers share it without
either reimplementing the "newest closed bar" lookup. ATR injection is
likewise a separate call, because the injected series is indexed by series
position and is only valid at the instant it was copied: a live chart copies
once per tick, a replay copies once against its own static arrays.

Consequence worth stating: a setup drawn on a chart and a setup in an
exported event are the same computation, not two implementations that agree
until one is edited.

## Data flow

```text
MT5 OHLC closed bars
  -> CPabEngine.ProcessBar (bar-driven analyzers)
  -> CPabEngine.Evaluate  (swing-derived analyzers, context, setup)
  -> chart rendering  |  event CSV  |  bar CSV
```

## Timing contract

A decision uses only completed bars. Fractal events are delayed by the configured right-side bars. Exported events include:

- `bar_open_time`
- `bar_close_time`
- `confirmed_at`
- `decision_time`
- `symbol`
- `period`

All four timestamps are ISO-8601, written by `IsoTimestamp()`.
`TimeToString(..., TIME_DATE|TIME_SECONDS)` is deliberately avoided: it emits
a dot date separator that `datetime.fromisoformat` rejects, which made every
export unreadable by the research layer before this was found.

`decision_time` equals `bar_close_time`, since the engine decides the instant
the bar completes. The research package rejects events where confirmation
occurs after the decision or the decision occurs before bar close.

## Platform split

- MQL5: canonical logic, visualization, and event production.
- Python: schema/timing validation, outcome measurement, walk-forward
  separation, and cross-instrument grouping. It measures; it never re-derives
  a setup.
- NinjaTrader: secondary unverified adapter; shared fixtures are required before claiming parity.

## Measured quantities

Any value compared across symbols or timeframes is normalized to a fraction or
a ratio. Pattern slopes are a fraction of price per bar, computed from swing
timestamps rather than series indexes, so one threshold holds on EURUSD and on
gold and does not drift when a history reload shifts every index.

The same discipline applies to the export: a price is always written with
enough precision to be unambiguous. A target one point beyond entry is
rejected rather than exported, because at five decimal places it prints as the
same string as entry and is indistinguishable from no target at all.

## Performance

- Analyzer state updates only for new closed bars.
- ATR copying is skipped on unchanged ticks.
- Unchanged ticks do not rebuild swing-derived state.
- Chart objects use stable keys and are deleted when inactive.
- Historical ring buffers have fixed capacity.

## Future boundaries

Multi-timeframe context, sessions, prior-day levels, and richer measured moves belong in the context layer. They must use only fully closed higher-timeframe data and report unavailable data honestly.

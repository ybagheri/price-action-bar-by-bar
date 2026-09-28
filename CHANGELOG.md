# Unreleased - 2026-09-24

### Added

- Closed-bar-only MQL5 processing with timestamp-idempotent analyzers.
- Bar wick, overlap, range, strength, run, reversal, and follow-through features.
- Micro/medium context snapshot with pressure, levels, and failed-breakout heuristics.
- Composed setup engine with NO TRADE, invalidation, target, reward/risk, and evidence scores.
- Setup arrows, trade levels, explanation panel, and optional debug score details.
- Opt-in sandboxed CSV event export with engine and parameter versions.
- Python event timing validation and target/invalidation/ambiguity/MFE/MAE analysis.
- Repository audit, architecture proposal, and English maintainer documentation.
- Archived MQL5 harness runtime output under `research/test_artifacts`.
- `setup_type` carried into `SetupEvent` and validated against the engine's setup list.
- `load_price_bars` for outcome evaluation from exported bar history.
- Aggregate reporting by setup type or engine status: counts, win rate,
  expectancy in R, average MFE/MAE, and average bars to exit.
- `python -m pab_research EVENTS.csv BARS.csv` report entry point.

### Fixed

- MQL5 no-longer replays already processed bars on unchanged ticks.
- Forming bar index 0 is no longer used for confirmed decisions.
- ATR history is not copied on unchanged ticks.
- Transition and trend states clear stale range rectangles.
- Dynamic pattern, range, measured-move, and panel objects are reconciled.
- Indicator instances use unique chart-object namespaces.
- Relative indicator headers are compiled from the repository tree.
- MQL5 test success no longer writes a chart comment.
- Intended inside-bar test fixture now is an inside bar.
- Pullback-sequence fixture no longer expects H1 on a bar that sets a new leg high.
- Context fixture is now built in series order (index 0 = newest closed bar).

### Validation

- MQL5 indicator: 0 compile errors, 0 warnings.
- MQL5 harness: 0 compile errors, 0 warnings.
- MQL5 harness runtime: 41 passed, 0 failed (Alpari MT5_2, EURUSD M5, 2026-09-28).
- Python research suite: 27 tests passed.
- Python `compileall`: passed.

### Known gaps

- Reporting has never been run against a real exported event file, so no
  measured win rate or expectancy figure exists yet.
- Indicator lifecycle (duplicate ticks, history reload) has no runtime test yet.
- No Strategy Tester or broad historical backtest has been run.
- Multi-timeframe and session context are not implemented.
- NinjaTrader has not been recompiled or brought to feature parity.

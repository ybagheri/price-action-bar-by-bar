# Unreleased - 2026-09-29

### Added

- Closed-bar-only MQL5 processing with timestamp-idempotent analyzers.
- Bar wick, overlap, range, strength, run, reversal, and follow-through features.
- Micro/medium context snapshot with pressure, levels, and failed-breakout heuristics.
- Composed setup engine with NO TRADE, invalidation, target, reward/risk, and evidence scores.
- Setup arrows, trade levels, explanation panel, and optional debug score details.
- Opt-in sandboxed CSV event export with engine and parameter versions.
- Python event timing validation and target/invalidation/ambiguity/MFE/MAE analysis.
- Repository audit, architecture proposal, and English maintainer documentation.
- `HANDOFF.md` summarising verified state, conventions, gaps, and next steps.
- Archived MQL5 harness runtime output under `research/test_artifacts`.
- `setup_type` carried into `SetupEvent` and validated against the engine's setup list.
- `load_price_bars` for outcome evaluation from exported bar history.
- Aggregate reporting by setup type or engine status: counts, win rate,
  expectancy in R, average MFE/MAE, and average bars to exit.
- `python -m pab_research EVENTS.csv BARS.csv` report entry point.
- `pab_research.validation`: chronological walk-forward splitting into
  alternating in-sample and out-of-sample blocks, pooled IS/OOS comparison,
  and an expectancy/win-rate degradation gap.
- Cross-instrument grouping and per-instrument walk-forward, surfaced as
  `--group instrument` and `--walk-forward N [--walk-forward-per-instrument]`.
- Inclusive `--from` / `--to` date windowing on `decision_time`, for slicing
  a multi-year export into explicit periods.
- Each fold's decision-time span is now printed, so a multi-year walk-forward
  result can be read without reconstructing the boundaries by hand.
- `symbol` and `period` columns in the event export.
- `CPabUtils::NormalizedSlopePerBar` and the `TestNormalizedPatternSlopes`
  harness group.

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
- Event and bar CSV loaders read `utf-8-sig` so a BOM cannot hide the first column name.
- **`PATTERN_TRIANGLE` could never be produced.** The triangle branch
  compared a raw price-per-bar-index slope against `InpConvergenceMin = 0.15`.
  On a 1.10 instrument that slope is about 0.0025, so the condition was
  unreachable. Slopes are now a fraction of price per bar measured from swing
  timestamps, and `InpConvergenceMin` defaults to 0.00020.
- Pattern slopes no longer use `SSwingPoint.barIndex`, a series position that
  shifts on every new bar and restarts on a history reload.
- The event export recorded engine version `1.30` while the compiled
  indicator reported `1.20`. Both now derive from `PAB_ENGINE_VERSION`, and
  `#property version` is `1.40`.

### Validation

- MQL5 indicator: 0 compile errors, 0 warnings (Alpari MT5_3 build 6230).
- MQL5 harness: 0 compile errors, 0 warnings.
- MQL5 harness runtime: 54 passed, 0 failed (Alpari MT5_3, EURUSD H1, 2026-09-29).
  Archived at `research/test_artifacts/mql5_harness_20260929.txt`.
- Python research suite: 57 tests passed; `pytest` and `unittest` agree.
- Python `compileall`: passed.
- Walk-forward and instrument CLI paths exercised end to end on a clearly
  labelled **synthetic** export. No real event export has been analysed.

### Known gaps

- Reporting and walk-forward have never been run against a real exported
  event file, so no measured win rate or expectancy figure exists yet.
- Indicator lifecycle (duplicate ticks, history reload) has no runtime test yet.
- No Strategy Tester run and no broker-spread modelling.
- Multi-timeframe and session context are not implemented.
- NinjaTrader has not been recompiled or brought to feature parity; its
  slope math is still dimensionally wrong.
- Harness execution still requires a human to run the script on a chart.

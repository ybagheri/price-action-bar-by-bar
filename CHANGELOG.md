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

### Validation

- MQL5 indicator: 0 compile errors, 0 warnings.
- MQL5 harness: 0 compile errors, 0 warnings; runtime execution remains manual.
- Python research suite: 6 tests passed.
- Python `compileall`: passed.

### Known gaps

- MQL5 harness has not been executed automatically in MT5 yet.
- No Strategy Tester or broad historical backtest has been run.
- Multi-timeframe and session context are not implemented.
- NinjaTrader has not been recompiled or brought to feature parity.

# Development

## Source layout

- `MQL5/Indicators` — orchestration and MT5 lifecycle.
- `MQL5/Include/PriceActionBarByBar` — typed analysis modules.
- `MQL5/Scripts` — deterministic MQL5 tests.
- `research/pab_research` — offline event validation and outcomes.
- `research/tests` — Python unit tests.
- `NinjaTrader` — secondary unverified port.

## Change discipline

1. Keep detection separate from decision, risk, explanation, and rendering.
2. Use completed bars for real-time decisions.
3. Add an explicit status for heuristic output.
4. Do not add unrelated oscillators.
5. Keep score components transparent and capped.
6. Add deterministic tests before parameter tuning.
7. Compile every changed MQL5 target with MetaEditor.
8. Run Python tests when research code changes.
9. Inspect `git status`, `git diff`, and recent log before each commit.
10. Commit and push coherent phases separately.

## Analyzer contracts

Bar-driven analyzers implement `IAnalyzer`. Swing-derived services use explicit methods such as `AnalyzeSwings` or `Evaluate`; no-op interface methods are not allowed.

## Timing

An analyzer update is idempotent by bar timestamp. The orchestrator must stop at series index 1. Index 0 is forming and cannot produce a confirmed decision.

## Research boundary

Python must not independently redefine MT5 setups. It validates and measures exported events. Research-only algorithms must be labelled separately and cannot be reported as chart output.

## Current technical debt

- Indicator lifecycle runtime tests (duplicate ticks, history reload).
- Higher-timeframe and session context.
- A real event export to point the reporting and walk-forward tooling at.
- NinjaTrader compilation/parity fixtures; its slope math still hardcodes
  adjacent x coordinates and is dimensionally wrong.
- The harness run still depends on a human opening a chart and reading the
  journal, so evidence is slow to regenerate.

## Measurement conventions

Anything compared across symbols or timeframes must be dimensionless. A raw
price-per-bar quantity is not: on a 1.10 instrument it is roughly three
orders of magnitude smaller than on gold, so a single threshold either never
fires or always fires. Pattern slopes are therefore a fraction of price per
bar, measured off swing **timestamps** rather than series indexes, because a
series index shifts when a new bar arrives and restarts on a history reload.

## MQL5 test fixtures

Analyzers consume series order: index 0 is the newest bar, and `bars[n-1]` is the oldest. Synthetic `SBarInfo` fixtures built directly in a test must follow that convention; building them oldest-first silently inverts displacement, net-move, and overlap direction. Route OHLC fixtures through `BuildSeries` in the harness rather than hand-ordering them.

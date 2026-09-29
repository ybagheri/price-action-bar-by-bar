# Price Action Bar-by-Bar

[فارسی](README_FA.md) | English

An explainable MetaTrader 5 indicator that formalizes selected Price Action and Al Brooks-style concepts. It is decision support for reading charts, not an autonomous trading system.

## What it does

- Classifies completed bars by body, wick, overlap, relative range, strength, sequence, and follow-through.
- Detects delayed fractal swings and classifies H1/H2/H3+ and L1/L2/L3+ pullbacks.
- Reports micro and medium context, Always-In proxy, range state, nearby levels, failed breakout heuristics, and measured moves.
- Composes trend pullback, second entry, failed breakout, wedge, and breakout candidates.
- Produces `NO TRADE`, `WEAK`, `POSSIBLE`, `PROBABLE`, or `CONFIRMED EVIDENCE` status.
- Shows transparent 0–100 evidence components, reasons, risks, invalidation, target, and approximate reward/risk.
- Optionally exports closed-bar event records for offline outcome analysis.

The software does not claim to understand the market or reproduce Al Brooks exactly. It implements explicit, testable approximations and leaves ambiguous visual judgment to the trader.

## Architecture

```text
Closed bars
  -> BarClassifier
  -> SwingDetector
  -> TradingRangeDetector + AlwaysInTracker
  -> ContextAnalyzer
  -> PatternDetector + MeasuredMoveDetector
  -> DecisionEngine
  -> ChartRenderer
  -> optional CSV event export
```

MQL5 is the canonical live and historical engine. Python under `research/` validates event timing and evaluates outcomes; it does not duplicate live decisions.

See `ARCHITECTURE.md` and `ARCHITECTURE_PROPOSAL.md` for design rationale.

## Installation

1. Open MetaTrader 5: **File → Open Data Folder**.
2. Copy this repository's `MQL5` directory into the terminal's data directory.
3. Compile `MQL5/Indicators/PriceActionBarByBar.mq5` in MetaEditor.
4. Attach **PriceActionBarByBar** from Navigator to a chart.

Detailed instructions are in `INSTALLATION.md` and `MT5_GUIDE.md`.

## Reading the chart

- `Medium` is the rolling overlap/displacement state.
- `Micro` uses the last ten closed bars.
- H2/L2 labels are pullback attempts, not automatic entries.
- A setup arrow is accompanied by entry, invalidation, and target lines.
- The explanation panel lists supporting and opposing evidence.
- `Quality` is evidence strength, not win probability.
- `NO TRADE` is a valid and frequent result.

## Testing

Verified in the current environment:

- MQL5 indicator compilation: 0 errors, 0 warnings.
- MQL5 regression harness compilation: 0 errors, 0 warnings.
- MQL5 export EA compilation: 0 errors, 0 warnings.
- MQL5 regression harness runtime: 54 passed, 0 failed at commit 831aeda, but
  **not re-executed** since the pipeline moved into `CPabEngine`.
- Python research tests: 67 passed.
- Python `compileall`: passed.
- Real headless historical export: 72,189 bars replayed, 72,188 events.

No profitability backtest is claimed. See `TESTING.md` and `BACKTESTING.md`.

## Historical analysis

Set `InpExportEvents=true` to create a sandboxed CSV file. Every event records bar open/close, confirmation, decision time, levels, status, score, engine version, parameter fingerprint, symbol, and period.

Python validates `confirmed_at <= decision_time` and evaluates target, invalidation, ambiguous same-bar exits, time to exit, MFE, and MAE. It can group the result by setup type, engine status, or symbol, and print win rate and expectancy in R:

For a historical sample, `MQL5/Experts/PabEventExport.mq5` replays real broker
history through the same engine the chart uses and writes both the event CSV
and the bar CSV this tool needs. It runs unattended from the MT5 Strategy
Tester; see `TESTING.md`.

```powershell
python -m pab_research events.csv bars.csv --group setup
python -m pab_research events.csv bars.csv --from 2025-01-01T00:00:00 --to 2025-12-31T00:00:00
```

For a chronological in-sample / out-of-sample split with a reported degradation gap and each fold's date span:

```powershell
python -m pab_research events.csv bars.csv --walk-forward 4
python -m pab_research events.csv bars.csv --walk-forward 4 --walk-forward-per-instrument
```

### First real measurement, and it shows no edge

EURUSD M5, Alpari-MT5-Demo, one full year of 2023, 72,188 events. Resolved
expectancy by setup type runs from -0.06R to +0.04R; win rate from 38.2 to
55.4 percent; walk-forward degradation +0.01R, meaning the two halves
performed the same rather than either being good.

These figures are **gross of spread, slippage, and commission**, which the
export does not carry, and real costs would consume several times the
measured per-trade edge. This is a measurement of the engine, not evidence
that it works. Full output is archived at
`research/test_artifacts/real_export_eurusd_m5_2023.txt`.

The setups also resolve too fast to be measurable at M5 — average 1.9 to 2.8
bars to exit for most types, with about one in five exits touching both the
target and the stop inside the same bar.

## Current limitations

- Single timeframe only; higher-timeframe and session context are not implemented.
- Pattern and measured-move logic remains lightweight.
- Current forming bars are intentionally excluded from decisions.
- NinjaTrader is an unverified secondary port and is not at parity with the new MQL5 engine.
- Indicator lifecycle, Strategy Tester runs, broker-spread modeling, and broad historical validation remain required.
- Reported figures exclude spread, slippage, and commission.
- No orders are placed.

## Documentation

- `HANDOFF.md` — current verified state, conventions, gaps, and next steps
- `INSTALLATION.md` — MT5 installation
- `MT5_GUIDE.md` — chart usage and visibility controls
- `CONFIGURATION.md` — inputs and score thresholds
- `PRICE_ACTION.md` — bar and context features
- `AL_BROOKS_CONCEPTS.md` — automation boundaries
- `STRATEGY.md` — setup composition and scoring
- `TESTING.md` — validation workflow
- `BACKTESTING.md` — event and outcome methodology
- `DEVELOPMENT.md` — architecture and contribution workflow
- `PROJECT_AUDIT.md` — original repository audit
- `CHANGELOG.md` — release history

## License

MIT. See `LICENSE`.

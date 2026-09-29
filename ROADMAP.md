# Roadmap

Current state, verified evidence, and open gaps are summarised in
[`HANDOFF.md`](HANDOFF.md).

## Completed

- Repository audit and architecture decision.
- Closed-bar, idempotent MQL5 processing.
- Bar geometry, strength, overlap, run, reversal, and follow-through features.
- Context, Always-In, ranges, levels, failed-breakout heuristics, and measured moves.
- Setup composition, NO TRADE, risk/reward, transparent scoring, and explanations.
- Lifecycle-safe MT5 visualization.
- Opt-in event export and Python outcome/MAE/MFE tooling.
- English architecture, usage, strategy, testing, and backtesting documentation.
- MQL5 runtime harness execution with archived evidence (41 passed, 0 failed).
- Aggregate event reports with win rate, expectancy in R, MFE, and MAE by setup type or engine status.
- Walk-forward validation: chronological in-sample/out-of-sample blocks with a reported
  degradation gap, and per-instrument grouping and walk-forward.
- `symbol` and `period` added to the event export so multi-instrument runs are possible.
- Stable, normalized pattern slopes (fraction of price per bar, keyed off swing timestamps).
- MQL5 runtime harness re-executed and archived (54 passed, 0 failed).
- Inclusive `--from` / `--to` date windowing and per-fold date spans in the report.
- `CPabEngine` holds the pipeline; the chart and the historical replay share it.
- `MQL5/Experts/PabEventExport.mq5` replays real broker history headlessly and
  writes both the event CSV and the bar CSV the research layer needs.
- **First real event export measured** (EURUSD M5, Alpari-MT5-Demo, 2023-01-02 to
  2023-12-29, 72,188 events), archived at
  `research/test_artifacts/real_export_eurusd_m5_2023.txt`.
- Five defects that only a real export could expose are fixed: wrong-side
  targets, over-triggered failed-breakout detection, NO TRADE rows carrying a
  direction and levels, a loader that could not read MQL5's tab delimiter, and
  a timestamp format `datetime.fromisoformat` rejects.
- The regression harness runs **headlessly** from the Strategy Tester and
  writes a machine-readable verdict. One copy of the assertions, shared by the
  interactive Script and the headless EA.
- Headless harness evidence archived: 69 passed, 0 failed.

## Next

1. Repeat the real export on more symbols and timeframes, then re-run the
   walk-forward per instrument. One symbol and one year is not a study.
2. Add spread, slippage, and commission to the export so costs can be included
   in the reported expectancy. Every figure so far is gross of costs.
3. Review whether the setups are too tight to measure at M5: average
   bars-to-exit is under 3 for most types, and one in five exits is ambiguous.
4. Add MQL5 indicator lifecycle integration tests. The harness covers the
   analyzers, not `OnCalculate` or the chart renderer, so duplicate ticks and
   history reload are still unproven.
5. Implement configurable higher-timeframe context using closed HTF bars.
6. Add session/prior-day/overnight levels with broker-time assumptions.
7. Apply the timestamp-normalized slope to the NinjaTrader port and compile it.

## Explicitly deferred

- Live Python/MT5 bridge.
- Automated order placement.
- Black-box machine-learning prediction.
- Large unrelated indicator collections.
- Claims of exact Al Brooks replication.

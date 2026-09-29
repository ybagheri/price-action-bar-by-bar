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

## Next

1. Run the report against a real exported event file and archive the result.
2. Point the walk-forward tooling at that real export across more than one instrument.
3. Implement configurable higher-timeframe context using closed HTF bars.
4. Add session/prior-day/overnight levels with broker-time assumptions.
5. Apply the same timestamp-normalized slope to the NinjaTrader port and compile it.
6. Add MQL5 indicator lifecycle integration tests.
7. Automate the harness run so evidence does not depend on a human opening a chart.

## Explicitly deferred

- Live Python/MT5 bridge.
- Automated order placement.
- Black-box machine-learning prediction.
- Large unrelated indicator collections.
- Claims of exact Al Brooks replication.

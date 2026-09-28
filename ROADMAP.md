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

## Next

1. Run the report against a real exported event file and archive the result.
2. Add broader historical and multi-instrument validation with walk-forward separation.
3. Implement configurable higher-timeframe context using closed HTF bars.
4. Add session/prior-day/overnight levels with broker-time assumptions.
5. Replace index-based pattern slopes with stable normalized measurements.
6. Add shared fixtures and compile NinjaTrader 8.
7. Add MQL5 indicator lifecycle integration tests.

## Explicitly deferred

- Live Python/MT5 bridge.
- Automated order placement.
- Black-box machine-learning prediction.
- Large unrelated indicator collections.
- Claims of exact Al Brooks replication.

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
- **Multi-market, multi-timeframe study completed**: 242,473 events across
  EURUSD/GBPUSD/USDCHF/USDJPY at M5 and H1, 2014. Archived at
  `research/test_artifacts/study_multi_market_2014.txt`. The engine shows no
  edge on any of the seven market/timeframe combinations.
- `BarBook` so each event is measured against its own market's bars. Scoring a
  USDJPY event against EURUSD prices is a confident wrong number, not a small
  error, so it now raises instead.
- `--group market` for symbol+timeframe buckets, because pooling M5 and H1
  averages two different holding profiles.
- The bar export carries `symbol` and `period` per row.
- **Execution costs in the export** (Phase 19). `TradingCost.mqh` is the one
  place that decides what a trade costs; every exported row carries
  `spread_points`, the three price components, `cost_r`, and a `cost_model`
  label that says which parts are measured and which are assumed.
- **The report separates gross from net.** `grossR`, `costR`, and `netR` are
  distinct columns, and a missing cost column yields `n/a` rather than a
  repeated gross figure.
- **Break-even cost and assumed-spread re-pricing.** `--break-even` solves for
  the cost at which a group's edge vanishes, which needs no assumed spread at
  all; `--cost-scenario` re-prices the sample at a spread you state.
- **Costed multi-market study**: 319,650 events, 4 markets, 2 timeframes. The
  edge is worth 0.0003% of price on the best M5 market. Archived at
  `research/test_artifacts/study_costed_multi_market_2013.txt`.
- Headless harness evidence archived: 84 passed, 0 failed (up from 69).
- **Phase 20 investigated the measured-spread gap and closed it as BLOCKED,
  with evidence** rather than left open on a guess. `MQL5/Experts/PabSpreadProbe.mq5`
  and `research/test_artifacts/spread_probe_20260930.txt`. `iSpread`/`CopyBuffer`
  still fails with 4807; `CopyTicksRange` is clipped to the tester's current
  time; real tick mode silently degrades (3,145 ticks against 416,989);
  there are no per-day tick files on this machine; and the tester agent is
  offline (`ACCOUNT_TRADE_MODE` 0) so it cannot download them. The tester's
  bid/ask are therefore SYNTHESISED and the spread inside them is a tester
  setting, not a measurement. The blank cost columns are correct and stand.
- **Three exporter defects found and fixed on the way**, each of which had
  produced a silently wrong or misleading result: `CopyRates`
  `(start_time, stop_time)` returns 4401 in the tester for windows it holds,
  so the exporter now always uses the positional form and filters by
  timestamp; the empty-window error message asserted a cause it had not
  established and now prints the span the agent really offered; and the
  tester's own `FromDate`/`ToDate` turn out not to bound the replay at all,
  which is recorded in `TESTING.md` as the easiest way to believe you
  measured a period you did not.
- **First measurement on swing timeframes**: EURUSD 2009 at M5, H1, H4 and
  D1 over the same window, engine 1.50 and an unchanged parameter
  fingerprint. 79,673 events. Archived at
  `research/test_artifacts/study_swing_timeframes_eurusd_2009.txt`.
  Gross expectancy +0.003R M5, +0.035R H1, **-0.068R H4**, +0.115R D1.
  Walk-forward: no timeframe shows an out-of-sample edge. H4 is negative in
  both halves, so it has no gross edge for a cost model to erode, which is a
  stronger negative than Phase 19's. D1's positive figure is entirely
  in-sample (+0.30R to -0.09R, a -0.39R degradation on 122 outcomes) and is
  reported so it cannot be mistaken for a result.
- **Roadmap item 5's premise does not reproduce.** "H1 takes 24-34 bars to
  exit with slightly negative expectancy" does not happen on EURUSD 2009:
  H1 exits in 2.8 bars and is +0.035R. Bars-to-exit is 2.4-3.3 on every
  timeframe including D1, under the same engine and parameters that produced
  Phase 19's 28.9-bar figure. The long H1 holding period is a property of
  the 2013 sample, not of H1 setup construction, and should not be cited as
  a structural fact. The mechanism is recorded (no maximum holding horizon;
  target anchored to one bar's range), and nothing was tuned.
- **Phase 21 — lifecycle integration test groups added to the shared
  harness.** `TestEnginePipeline` drives `CPabEngine` end-to-end: the
  closed-bar gate (index 0 never enters the pipeline), a decision stamped
  on the newest CLOSED bar, duplicate-tick idempotence, and
  history-reload determinism (a second engine fed the same bars
  reproduces the same decision). `TestRendererLifecycle` drives the
  chart-object lifecycle: stable keys, no duplication on redraw, NO TRADE
  leaking no entry/stop/target lines, and `ClearAll` removing everything.
  **Not yet executed**: this phase was authored on a machine with no
  MetaEditor, so the 84-assertion verdict in
  `research/test_artifacts/mql5_harness_20260930.txt` remains the last
  *run* evidence. Executing the harness is the immediate next step.
- **Phase 22 — the NinjaTrader port's pattern slopes are
  normalized.** `PabUtils.NormalizedSlopePerBar` ports
  `CPabUtils::NormalizedSlopePerBar` (fraction of price per
  bar, keyed off swing timestamps), so the port's triangle
  detection uses the same scale-free threshold as the MQL5
  engine. The old index-based slope was dimensionally wrong
  and could never fire the triangle branch on a 1.10
  instrument. The indicator passes the chart's real
  seconds-per-bar; non-time-based periods yield 0 and disable
  slope detection. **Not yet compiled** — this machine has no
  NinjaTrader 8 SDK.

## Next

1. **Execute the Phase 21 lifecycle groups headlessly** and archive the
   verdict, as every other group was. This needs MetaEditor and the
   Strategy Tester, which the machine that authored Phase 21 does not
   have; the group code is committed and the recipe is in `TESTING.md`.
   Expected gain: ~30 assertions over the current 84, covering
   `CPabEngine`, duplicate ticks, history reload, and the renderer.
2. **Widen the swing study past one market.** Blocked on which years the
   tester agent can serve per symbol and timeframe, not on code. The agent
   holds about one year per timeframe and *which* year drifts between runs,
   so two timeframes measured minutes apart can cover different years. Read
   the range each run printed before comparing anything.
3. **Obtain a measured spread.** Still the top cost-related gap, but Phase 20
   established that it is not reachable from the command line: it needs the
   terminal UI (the History dialog, or an indicator left running on a live
   chart). Live forward collection would measure a *different, current*
   period and cannot cover a historical year, so it is not a substitute for a
   measured historical spread.
4. Repeat across a second year and a second broker feed. One broker's demo
   feed, one year, is a narrow base. An **Epic Pips MT5 Terminal** is already
   installed on this machine and unused.
5. Re-examine the H1 claim that item 5 above rested on, and record what a
   24-34 bar H1 sample would have to be. Do not tune toward either figure.
6. Implement configurable higher-timeframe context using closed HTF bars.
7. Add session/prior-day/overnight levels with broker-time assumptions.
8. ~~Apply the timestamp-normalized slope to the NinjaTrader port.~~
   Phase 22 applied the fix in code; compiling it still needs the
   maintainer's NinjaTrader 8 build environment, which this
   machine lacks.

## Explicitly deferred

- Live Python/MT5 bridge.
- Automated order placement.
- Black-box machine-learning prediction.
- Large unrelated indicator collections.
- Claims of exact Al Brooks replication.

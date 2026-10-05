# Unreleased - 2026-09-29

### Added

- **Phase 22: the NinjaTrader port's pattern slopes are now
  normalized.** `PabUtils.NormalizedSlopePerBar` ports
  `CPabUtils::NormalizedSlopePerBar` verbatim: the x-axis is the
  swing timestamp (never a series index, which shifts on every new
  bar and restarts on a history reload) and the y-axis is divided by
  the reference price, so one convergence threshold is meaningful on
  EURUSD at 1.10 and on gold at 3400 alike. The old index-based
  `PabUtils.Slope` produced ~0.0025 per bar on a 1.10 instrument,
  so a 0.15 threshold could never be met and the triangle branch
  could never fire — the same defect the MQL5 engine fixed in
  Phase 14. The indicator now passes the chart's real seconds-per-bar
  (`ChartSecondsPerBar()`); non-time-based periods (tick, volume,
  range, renko) yield 0, which disables slope-based detection rather
  than guessing. The `secondsPerBar` constructor parameter defaults
  to 300, matching the MQL5 default. **Not yet compiled**: this
  machine has no NinjaTrader 8 SDK; compilation is the maintainer's
  next step for this port.
- **Phase 21: lifecycle integration test groups** in the shared
  MQL5 harness. `TestEnginePipeline` drives `CPabEngine`
  end-to-end (closed-bar gate, decision stamped on the newest
  closed bar, duplicate-tick idempotence, history-reload
  determinism); `TestRendererLifecycle` drives the chart-object
  lifecycle (stable keys, no duplication on redraw, NO TRADE
  leaking no levels, `ClearAll`). The harness now includes
  `PabEngine.mqh` and `ChartRenderer.mqh`. Authored on a machine
  with no MetaEditor, so these groups are **not yet executed**;
  the last run evidence remains 84 passed, 0 failed
  (`research/test_artifacts/mql5_harness_20260930.txt`).
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
- `research/pyproject.toml` is now a working package definition: explicit
  package list, a `pab-research` console script, a `dev` extra carrying
  pytest, and pytest `testpaths`.
- `CPabEngine`, which owns the whole analysis pipeline, plus `SEngineConfig`.
  The chart indicator and the historical replay now build the same engine
  with the same parameters instead of two implementations of one pipeline.
- `MQL5/Experts/PabEventExport.mq5`: replays real broker history through that
  engine and writes the event CSV *and* the `open_time`/`high`/`low` bar CSV the
  research layer needs. Runnable headlessly from the MT5 Strategy Tester.
- `BarSeries`, a precomputed time index, so outcome evaluation is a binary
  search rather than a per-event sort.
- `parse_timestamp` and `sniff_delimiter`, so the research layer can actually
  read a real MQL5 export.
- `TestTargetAndNoTradeContract` and `TestFailedBreakoutRequiresAnActualBreakout`
  harness groups covering the Phase 16 fixes.
- `Include/PriceActionBarByBar/PabTests.mqh`: the regression suite as a shared
  header, so `Scripts/PAB_UnitTests.mq5` (interactive) and
  `Experts/PAB_HarnessEA.mq5` (headless) run the same assertions.
- `Experts/PAB_HarnessEA.mq5`: runs the suite unattended in the Strategy
  Tester and writes `pab_harness.txt` with the verdict, the engine version,
  the MT5 build, and the names of any failing assertions. A test run no
  longer depends on a human opening a chart, and the evidence is
  machine-readable rather than scraped from a journal.
- `BarBook`, which holds bar history per market and refuses to measure an
  event against a market it does not have. USDJPY prices are two orders of
  magnitude above EURUSD, so a cross-market mismatch is not a small error but
  a confident, meaningless number.
- `load_price_bars_by_symbol`, so a concatenated multi-market bar file keeps
  its market mapping instead of being flattened.
- `partition_by_bar_history`, which splits events into measurable and
  unattributable and reports the excluded count rather than guessing.
- `group_by_market` and `--group market`, which bucket by symbol *and*
  timeframe. Pooling M5 and H1 averages a two-bar holding profile with a
  thirty-five-bar one, which describes neither.
- The bar export now writes `symbol` and `period` per row, so a merged
  multi-market file is self-describing.
- **Multi-market, multi-timeframe study: 242,473 events, EURUSD/GBPUSD/USDCHF/
  USDJPY at M5 and H1, 2014.** Archived at
  `research/test_artifacts/study_multi_market_2014.txt`.
- **`Include/PriceActionBarByBar/TradingCost.mqh`** (Phase 19): the one place
  that decides what a trade costs. `RoundTripCostPrice`, `CostInR`, the
  commission-to-price-distance conversion, `ReadSymbolCostFacts`, and a
  self-describing cost label that marks every assumed number as assumed. Both
  exporters and the regression harness call it, so there is one implementation
  rather than three that agree until one is edited.
- **Per-row cost columns in the event export**: `spread_points`, the three
  price components, `cost_r`, and `cost_model`. Measured where the platform
  supplies a measurement; blank where it does not, and labelled where a value
  is an input rather than a reading.
- `SetupStats` now separates `expectancy_r` (gross, unchanged in meaning),
  `average_cost_r`, and `net_expectancy_r`, and the report prints all three as
  `grossR`, `costR`, and `netR`. A group whose export lacks costs reads `n/a`
  for both rather than repeating the gross figure.
- `WalkForwardResult.net_expectancy_degradation_r`, reported alongside the
  gross degradation. It is `None` when either pooled half lacks costs, so a
  gross degradation can never be read as a net one.
- `expected_cost_r`, which **recomputes** an event's cost from its exported
  price components rather than trusting the exported `cost_r`. Disagreements
  beyond rounding are counted and reported, and the recomputed value is the
  one used.
- `SetupEvent.has_costs`, which distinguishes "this row carries no cost data"
  from "this trade was free". A blank cost column is `None`, never `0.0`.
- **`--break-even`**: the round-trip cost at which each group's gross edge
  becomes exactly zero. Reported as a percentage of price so it is comparable
  across EURUSD at 1.10 and gold at 3400, and it needs no assumed spread at
  all, so no cost guess can influence it.
- **`--cost-scenario PERCENT`**, repeatable: re-prices the whole sample at an
  assumed spread and reports net expectancy. Every row in that table is
  labelled an assumption in its own header, because that is what it is.
- `compare_cost_scenarios` and `format_cost_scenarios`.
- `TestTradingCost`, a 15-assertion harness group pinning the cost arithmetic,
  the commission conversion, the zero-denominator cases, and the labelling of
  assumed values.
- `research/tests/test_costs.py`: 40 tests over the cost model, the gross/net
  split, the break-even solution, the scenarios, and the loader's handling of
  absent and blank cost columns.
- `MQL5/Experts/PabSpreadProbe.mq5`, a viability probe that establishes
  whether a historical per-bar spread can be measured on this machine. It
  reports what it observed including every failure, and ends in a VERDICT line
  worded so it cannot be read optimistically. Archived at
  `research/test_artifacts/spread_probe_20260930.txt`.

### Fixed

- **`CopyRates` with `(start_time, stop_time)` returns 4401 in the Strategy
  Tester** for windows it demonstrably holds; the positional
  `(start_pos, count)` form loads the same data. The exporter now always uses
  the positional form and filters by timestamp itself, which is what makes a
  pinned replay window work headlessly at all.
- **The exporter's empty-window failure message asserted a cause it had not
  established.** It said "Check that the broker actually has history", which
  was wrong every time it fired and is indistinguishable from a genuinely
  empty cache. It now prints how many bars the agent actually offered and the
  real first and last timestamps of that span, so the two cases are separable
  from the output rather than inferred from prose.

- **The export wrote 0.0 into its cost columns when the spread could not be
  measured.** The MT5 Strategy Tester exposes no historical spread buffer:
  `iSpread`'s `CopyBuffer` fails there with error 4807 and returns no values.
  The first Phase 19 build filled those columns with zeros, which would have
  handed the research layer 73,751 rows asserting that trading was free, and
  published a "net" expectancy that was really the gross one wearing a net
  label. The exporter now writes **blanks**, the loader reads a blank as "no
  cost data", and every report says GROSS in those words. This is the most
  consequential single decision in the phase: a missing cost is not a zero
  cost.

- **A multi-market export could have been scored against the wrong market.**
  `evaluate_setup` took a single bar list, so concatenating seven
  market/timeframe exports would have measured USDJPY events against EURUSD
  prices and reported confident nonsense. `BarBook` makes that a hard error.
  Caught while building the study rather than by a failing test: the old
  signature had no way to express the mistake.
- A near-miss measured move rejected a whole setup. `mmUsable` required only
`targetPrice > entry`, so a projection a fraction of a point beyond entry was
adopted and then thrown out by the final one-point guard, turning a usable
setup into NO TRADE. A too-close resistance clamp already fell back to the
baseline target, so the two were inconsistent. A near-miss projection is now
ignored and the baseline kept. This was found by the first headless harness
run, not by reading the code, and it is the clearest argument for having made
the suite runnable unattended.

Five defects that only became visible once a real export existed. None of them
could have been found from the synthetic fixtures, because the fixtures did not
look like the real file.

- **`PATTERN_TRIANGLE` could never be produced.** The triangle branch compared
  a raw price-per-bar-index slope against `InpConvergenceMin = 0.15`. On a 1.10
  instrument that slope is about 0.0025, so the condition was unreachable.
  Slopes are now a fraction of price per bar measured from swing timestamps,
  and `InpConvergenceMin` defaults to 0.00020.
- **A setup could be given a target on the wrong side of entry.** A
  measured-move projection was adopted on direction alignment alone, with no
  requirement that it lie beyond entry. Reward/risk then took an absolute
  value, so an unreachable target scored a healthy R:R and a full room score.
  Real export: 6,025 of 72,188 rows.
- **The resistance clamp could land a target on top of entry.** A level a hair
  above entry produced a target that exports as the same printed price as
  entry, indistinguishable from no target at all. A target must now clear entry
  by more than one point.
- **A rejected setup leaked a direction and stale levels.** `status=no_trade`
  rows were written with `direction=long` and non-zero entry/stop/target,
  contradicting the export schema. All NO TRADE exits now route through one
  `NoTrade()` helper that clears direction, type, and every price level.
- **`failed_breakout` fired on 74 percent of all bars.** The test only asked
  whether the current bar sat below the swing high, which is true for almost
  every bar that has not broken out. It now requires the recent bars to have
  traded beyond the level. Real export before the fix: 53,329 of 72,188
  events; after: 12,654.
- **The research layer could not read a real MQL5 export at all.**
  `csv.DictReader` defaults to a comma delimiter while MQL5's `FILE_CSV`
  defaults to a tab, so a whole tab-separated line was read as one field and
  the loader raised `KeyError: event_id`. Every test passed because the
  fixtures were written with Python's comma-defaulting writer.
- **`datetime.fromisoformat` cannot parse MQL5's `TimeToString` output.** It
  emits `2026.01.02 07:00:00` with a dot date separator, which is not
  ISO-8601, so every event file exported before this change was unreadable.
  New exports write real ISO-8601 via `IsoTimestamp()`, and `parse_timestamp`
  accepts both spellings so existing files still load.
- **`SETUP_TYPES` did not mirror `SetupTypeLabel()`.** It listed `"none"`, which
  is a *direction*, and omitted `"no_trade"`, so every no-trade row in a real
  export was rejected as an unknown setup type. A test now pins the set.
- **The walk-forward report timed out on real data.** `evaluate_setup` sorted
  the entire bar list once per event; 72,188 events against 72,175 bars is
  roughly five billion operations. `BarSeries` builds the index once. The same
  report now finishes in about 50 seconds.
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
- MQL5 export EA: 0 compile errors, 0 warnings.
- MQL5 harness: 0 compile errors, 0 warnings.
- MQL5 harness runtime, **headless in the Strategy Tester**: **84 passed, 0
  failed** (Alpari MT5_3 build 6230, 2026-09-29, ~0.15 s). Archived at
  `research/test_artifacts/mql5_harness_20260929_cost.txt`. The first headless
  run ever was 67/1 and exposed the near-miss measured-move defect above; the
  previous archived run was 69/0.
- MQL5 unit-test Script: 0 compile errors, 0 warnings.
- Python research suite: **124 tests passed**; `pytest` and `unittest` agree.
- Python `compileall`: passed.
- **Multi-market, multi-timeframe study, headless:** 242,473 events across 4
  markets and 2 timeframes, 2014, all seven combinations measured, 0 events
  excluded for missing bar history. Walk-forward over the pooled set
  reported degradation −0.00R on about 50,000 resolved outcomes per side.
  Archived at `research/test_artifacts/study_multi_market_2014.txt`.
- **Real export, headless, Alpari-MT5-Demo EURUSD M5, 2023-01-02 to
  2023-12-29:** 72,189 bars replayed, 72,188 events written, 0 skipped, in
  11 seconds. Grouped report, status report, and a 4-fold walk-forward all
  produced. Archived at
  `research/test_artifacts/real_export_eurusd_m5_2023.txt`.
- **Costed multi-market study, headless:** 319,650 events, 4 markets,
  2 timeframes, all eight combinations, 0 events excluded for missing bars.
  Break-even, assumed-spread re-pricing, per-setup breakdown, and a 4-fold
  walk-forward were all produced. Archived at
  `research/test_artifacts/study_costed_multi_market_2013.txt`. Note the year
  in that filename: the run **requested** 2014 and **replayed** 2013-01-01 to
  2013-12-31, because that is the range the EA reported. Quoting the requested
  range instead of the reported one is the reproducibility trap already
  documented in `TESTING.md`.

### Measured result, gross only (Phase 18, superseded by the section below)

**The engine shows no measurable edge, and ten times the data did not change
that.** Across 242,473 events spanning EURUSD, GBPUSD, USDCHF and USDJPY at
M5 and H1, every one of the seven market/timeframe combinations lands within a
few hundredths of an R of zero. Pooled walk-forward expectancy is +0.02R in
sample and +0.02R out of sample, degradation −0.00R, on about 50,000 resolved
outcomes per side.

The one clear signal is structural and negative: H1 setups average 31 to 36
bars to exit with slightly *negative* expectancy, while M5 setups average
about 3 bars. An edge that needs 35 bars to resolve is a different claim from
one that resolves in 3, and needs a different risk model.

Every figure there is **gross of spread, slippage, and commission**, because
the export did not carry them. The section below is what that costs.

### Measured result, revised with costs (Phase 19)

**The gross edge is worth a thousandth of a percent of price, and the cost of
trading is several times that.** This is a stronger negative result than the
gross-only study, and it required no new measurement of the engine. It
required admitting that the number the whole project rested on could never
survive contact with a broker's cost sheet.

319,650 events across EURUSD, GBPUSD, USDCHF and USDJPY at M5 and H1, all eight
market/timeframe combinations, about 33,000 resolved outcomes each. Pooled
gross expectancy **+0.017R**, walk-forward degradation **-0.00R**.

- **EURUSD M5: the entire edge is worth 0.0003% of price in round-trip cost.**
  Roughly a third of a pip of spread, slippage and commission combined. No
  retail FX market trades at that cost.
- The largest break-even in the study is 0.0019% of price (GBPUSD H1).
- Re-priced at a thousandth of a percent of price, the whole sample goes from
  **+0.017R to -0.045R**. At 0.005% it is -0.294R; at 0.02%, -1.228R.

The earlier report said this study "cannot say whether the net figure is
small-positive or clearly negative." It can now: **not small-positive.**

This is a statement about this engine's output on one broker's feed. It is
**not** a refutation of the Al Brooks material the indicator is based on, and
no profitability claim is made in either direction.

### Measured result, swing timeframes (Phase 20)

**No timeframe shows an out-of-sample edge, and H4 has no gross edge at all.**
EURUSD 2009, M5/H1/H4/D1 over the same window, 79,673 events, engine 1.50 with
an unchanged parameter fingerprint.

- Gross expectancy: M5 **+0.003R**, H1 **+0.035R**, H4 **-0.068R**, D1
  **+0.115R**. Walk-forward, 4 folds: M5 -0.00R to +0.01R, H1 +0.01R to
  +0.06R, H4 -0.10R to -0.03R, D1 **+0.30R to -0.09R**.
- **H4 is the significant one.** Its gross expectancy is negative before any
  cost is applied, so there is no edge for a cost model to erode and
  break-even is undefined. That is a stronger negative than Phase 19's, which
  at least had a positive gross figure to lose.
- **D1's +0.115R is the largest positive gross figure in the project and it is
  entirely in-sample**, a -0.39R degradation on 122 resolved outcomes. It is
  reported here so it cannot be mistaken for a result. The report's
  `reliable: yes` flag only means the resolved count cleared a threshold; it
  is not a claim that the edge is real.
- At 0.001% of price, H1 is still positive (+0.025R) where M5 is already
  negative (-0.038R), because H1's wider stop makes the same cost a smaller
  fraction of R. Not a reason to prefer H1: its break-even is 0.0060% of
  price and it is negative at 0.005%.
- One market and one year. Not a widening of the Phase 19 study, and not
  poolable with it.

**Roadmap item 5's premise does not reproduce.** "H1 takes 24-34 bars to exit
with slightly negative expectancy" does not happen here: H1 exits in 2.8 bars
at +0.035R, and bars-to-exit is 2.4-3.3 on every timeframe including D1, under
the same engine and parameters that produced the 28.9-bar figure. The long
holding period is a property of the 2013 sample, not of H1 construction.
`evaluate_setup` has no maximum holding horizon, and the baseline target is
`entry +/- 2.0 * bar.range`, which is why holding time in *bars* is roughly
timeframe-invariant while holding time in *hours* is not. Nothing was tuned.

### Known gaps

- The harness covers the analyzer classes, not `CPabEngine`, `OnCalculate`, or
  the chart renderer. Duplicate ticks and history reload remain untested, and
  the chart path is compile-verified and replay-verified but not
  lifecycle-verified. **This is now the most actionable remaining gap,
  because it is the one that does not depend on broker data.**
- **No measured spread on a historical study, and Phase 20 established that it
  is not obtainable headlessly.** `iSpread`/`CopyBuffer` still fails with 4807;
  `CopyTicksRange` is clipped to the tester's current time; real tick mode
  silently degrades to 3,145 ticks against 416,989; there are no per-day tick
  files on the machine; and the tester agent is offline, so it cannot download
  any. The tester's bid/ask are synthesised and the spread inside them is a
  tester **setting**. It needs the terminal UI, not the command line.
  `MQL5/Experts/PabSpreadProbe.mq5` and
  `research/test_artifacts/spread_probe_20260930.txt` are the evidence.
- Slippage and commission remain assumptions everywhere, because neither is
  observable from a bar series by construction.
- The swing timeframes are measured on **one market, one year** (EURUSD 2009).
  The other three symbols were not run at H4 or D1.
- The tester's history window is **not selectable and drifts between runs**, so
  two timeframes measured minutes apart can cover different years. The
  tester's own `FromDate`/`ToDate` do not bound the replay at all. Always read
  the range a run printed.
- One broker's demo feed per study. An **Epic Pips MT5 Terminal** is already
  installed on this machine and unused.
- The setups are tight: average bars-to-exit is under 3.5 for every timeframe
  measured, and a large share of exits are ambiguous (both levels touched in
  one bar).
- Multi-timeframe and session context are not implemented.
- NinjaTrader has not been recompiled or brought to feature parity; its
  slope math is still dimensionally wrong.

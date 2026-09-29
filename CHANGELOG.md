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

### Fixed

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
- MQL5 harness runtime, **headless in the Strategy Tester**: 69 passed, 0 failed
  (Alpari MT5_3 build 6230, 2026-09-29, 0.16 s). Archived at
  `research/test_artifacts/mql5_harness_20260929_headless.txt`. The first
  headless run was 67/1 and exposed the near-miss measured-move defect above.
- Python research suite: 77 tests passed; `pytest` and `unittest` agree.
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

### Measured result, stated plainly

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

Every figure is **gross of spread, slippage, and commission**, because the
export does not carry them. The measured edge is smaller than realistic costs
by several times, so the net result is worse than shown. This is a
measurement of the engine, not evidence that it works, and not evidence that
it cannot work at a different cost or timeframe. No profitability claim is
made.

### Known gaps

- The harness covers the analyzer classes, not `CPabEngine`, `OnCalculate`, or
  the chart renderer. Duplicate ticks and history reload remain untested, and
  the chart path is compile-verified and replay-verified but not
  lifecycle-verified.
- Costs are absent from the export, so every expectancy figure is gross. The
  measured edge is smaller than realistic costs, which makes this the
  blocking gap for any profitability question.
- Timeframe breadth is M5 and H1 only. Nothing here says whether the rules do
  anything on a swing timeframe.
- One broker's demo feed, one year (2014).
- The setups are tight: average bars-to-exit is under 3 for most types, and a
  large share of exits are ambiguous (both levels touched in one M5 bar).
- One symbol, one timeframe, one year. Multi-instrument and multi-regime
  validation remain open.
- Indicator lifecycle (duplicate ticks, history reload) has no runtime test.
- Multi-timeframe and session context are not implemented.
- NinjaTrader has not been recompiled or brought to feature parity; its
  slope math is still dimensionally wrong.

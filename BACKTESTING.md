# Backtesting and Historical Analysis

## Principle

A setup must be classified using only information available at its decision timestamp. Future bars may evaluate an outcome but may not change that setup.

## Event contract

The opt-in MQL5 CSV contains:

```text
event_id, direction, setup_type, status,
bar_open_time, bar_close_time, confirmed_at, decision_time,
entry, invalidation, target, risk_reward, quality,
engine_version, parameter_version
```

`confirmed_at` is conservatively set to the decision time for the current closed-bar decision. Python rejects events where confirmation is later than the decision.

## Outcome rules

For each event, Python examines bars opening at or after `decision_time`:

- target hit;
- invalidation hit;
- expired without either level;
- ambiguous when target and invalidation are both touched in one OHLC bar.

It also records MFE, MAE, exit time, and bars to exit. Same-bar ambiguity is not silently resolved because OHLC data does not reveal path order.

## Usage

Enable `InpExportEvents`, attach the indicator to historical/replay data, and let MT5 produce the CSV. Then use `research.pab_research.load_setup_events` to validate records and `evaluate_setup` to measure outcomes.

The indicator does not export bars. Export the same symbol and timeframe from MT5 history (or a replay source) as a CSV with `open_time`, `high`, and `low` columns, then run the report:

```powershell
python -m pab_research events.csv bars.csv
python -m pab_research events.csv bars.csv --group status
python -m pab_research events.csv bars.csv --group instrument
python -m pab_research events.csv bars.csv --from 2025-01-01T00:00:00 --to 2025-12-31T00:00:00
```

`--from` and `--to` are inclusive ISO timestamps. Filtering is on
`decision_time`, not `bar_open_time`, because that is the instant the engine
committed and the field the walk-forward split cuts on — so a window and a
fold can never disagree about which side of a boundary an event is on. A
window containing no events reports that and exits non-zero rather than
printing an empty table. An inverted window is rejected outright.

## Aggregate reporting

`pab_research.report` groups events by `setup_type`, by engine `status`, or by
`symbol`, and prints counts, win rate, expectancy in R, average MFE/MAE, and
average bars to exit.

Reporting rules, stated so the numbers are not over-read:

- Win rate and expectancy use resolved outcomes only (`target`, `invalidation`, `ambiguous`). `expired` and `no_trade` rows are counted in their own columns and excluded from both, because they never reached an exit.
- Expectancy is in R: a target adds the event's own reward/risk, an invalidation subtracts 1, and an ambiguous same-bar exit contributes 0.
- MFE and MAE are price excursions from entry, not realised P/L, and are not risk-normalised.
- `no_trade` rows are kept in the report so selectivity per setup type is visible.

None of these figures include spread, slippage, or commission, because the export does not carry them.

## Walk-forward separation

A single win rate over one contiguous date range cannot separate a rule that
generalizes from a rule that was fitted to that range. `pab_research.validation`
implements the standard remedy:

```powershell
python -m pab_research events.csv bars.csv --walk-forward 4
python -m pab_research events.csv bars.csv --walk-forward 4 --walk-forward-per-instrument
```

- Events are ordered by `decision_time` and cut into `N` contiguous,
  non-overlapping blocks at even fractions of the event count.
- Even-numbered blocks are in-sample, odd-numbered are out-of-sample, so every
  out-of-sample block is preceded by an in-sample block of the same length.
- The report prints each fold, then the decision-time span of each fold, then
  the pooled in-sample and out-of-sample comparison, then the degradation gap
  (`OOS - IS`) in expectancy (R) and win rate (percentage points). The spans
  are what make a multi-year result interpretable, so read them before
  comparing figures from two different exports.
- A result resolving fewer than `--walk-forward-min-resolved` outcomes (default
  5) is reported with `reliable: no` and the reason, rather than publishing an
  expectancy off a handful of trades.
- `--walk-forward-per-instrument` runs the split per symbol. A symbol with too
  few events for the requested fold count falls back to two folds and says so,
  instead of being dropped.

How to read the result:

- A gap near zero is *consistent with* stability on this sample. It does not
  prove the rule generalizes, and it is not a profitability claim.
- A negative gap means the out-of-sample blocks did worse than the in-sample
  ones. That is a finding about the parameters, not a bug in the tool.
- Outcomes are evaluated against the full bar history, so an event near a fold
  boundary may resolve using bars that fall in the next block. That is
  intentional — truncating outcomes would bias measured holding periods — but
  it means boundaries leak forward in *outcome* space only, never in
  *decision* space.

`symbol` and `period` are in the export, which is what makes per-instrument
runs possible. Files written before those columns existed still load; their
rows group under `unspecified` rather than being silently dropped.

## Bias controls

- Decisions exclude forming bar index 0.
- Fractal swings are delayed by right-side confirmation bars.
- Event timestamps are explicit.
- Parameter and engine versions are stored.
- Future data is isolated in the outcome evaluator.
- Walk-forward blocks never overlap and are cut on `decision_time`.

## Multi-market exports

An export covers one symbol and one timeframe, because that is what a single
Strategy Tester run can replay. A study is assembled by running the export
several times and concatenating the results. Two things make that safe:

- The bar file carries `symbol` and `period` on every row, so a merged file is
  self-describing. Without those columns the merge would destroy the only
  information that says which market a price belongs to.
- The research layer refuses to measure an event against a market it has no
  bars for. `BarBook` raises `MissingBarHistory` rather than falling back,
  because USDJPY at 105 and EURUSD at 1.37 differ by two orders of magnitude
  and a cross-market mismatch produces a confident, meaningless number rather
  than an obvious failure.

Events that name a market with no bar history are excluded and counted, and
the report prints the count. Here it is zero, which is the number to check
before believing a multi-market figure.

Group with `--group market`, not `--group instrument`, whenever the export
covers more than one timeframe. Symbol-only grouping pools M5 and H1, which
averages a two-bar holding profile with a thirty-five-bar one. In the 2014
study that pooling turned −0.01R..−0.04R (H1) and +0.01R..+0.03R (M5) into a
single figure that described neither.

## Current limitations

**The first real measurement exists, and it shows no edge.** A 242,473-event
study across EURUSD, GBPUSD, USDCHF and USDJPY at M5 and H1 for 2014, with
roughly 50,000 resolved outcomes in each walk-forward half. Every one of the
seven market/timeframe combinations lands within a few hundredths of an R of
zero; pooled expectancy is +0.02R in sample and +0.02R out of sample,
degradation −0.00R. Archived at
`research/test_artifacts/study_multi_market_2014.txt`.

The one clear signal is structural and negative: **H1 setups average 31 to 36
bars to exit and are slightly negative, while M5 setups average about 3 bars
and are slightly positive.** An effect that needs 35 bars to resolve is a
different claim from one that resolves in 3, and needs a different cost and
risk model to hold.

All figures are **gross of spread, slippage, and commission**, because the
export does not carry them. The measured edge is smaller than realistic costs
by several times, so the net is worse than shown, not better. This is
therefore not a profitability result in either direction: the study cannot
say whether the net figure is small-positive or clearly negative. No
profitability claim is made and none is supported.

Remaining limits:

- M5 and H1 only. Nothing here says whether the rules work on H4 or D1.
- One broker's demo feed, one year.
- USDJPY exists at H1 only, so its +0.06R rests on 1,403 resolved outcomes
  and is the one figure here worth re-testing before believing.

## Producing an export

Enable `InpExportEvents` on a chart for live forward events, or run
`MQL5/Experts/PabEventExport.mq5` for a historical replay. The replay is the
practical route: the chart's own export produces one event per bar of forward
time, which is not a sample. See `TESTING.md` for the headless recipe and the
list of traps that silently produce a wrong result rather than an error.

The replay writes two files from one command:

- `pab_events.csv` — the event schema the research layer validates.
- `pab_bars.csv` — `open_time`/`high`/`low`, which `pab_research` cannot
  derive and which the outcome evaluator needs.

Avoid optimizing the score or thresholds on one dataset. Prefer broad, walk-forward, multi-regime validation and investigate suspiciously good results for leakage.

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

## Current limitations

**The first real measurement exists, and it shows no edge.** EURUSD M5,
Alpari-MT5-Demo, 2023-01-02 to 2023-12-29, 72,188 events. Resolved expectancy
by setup type runs from -0.06R to +0.04R and win rate from 38.2 to 55.4
percent. Walk-forward degradation is +0.01R and +0.9 percentage points, which
means the in-sample and out-of-sample halves performed the same, not that
either was good. Archived at
`research/test_artifacts/real_export_eurusd_m5_2023.txt`.

That is one symbol, one timeframe, one year, one parameter set, and it is
**gross of spread, slippage, and commission** because the export does not
carry them. Realistic costs on EURUSD M5 would consume several times the
measured per-trade edge, so the net result is worse than shown, not better. No
profitability claim is made and none is supported.

Two structural limits matter more than the headline numbers:

- **The setups are too tight to measure at M5.** The stop is the signal bar's
  own extreme plus 0.25 bar range, and the target is the nearest resistance or
  support, so average bars-to-exit is 1.9 to 2.8 for every type except
  `breakout_follow_through` at 10.8. One event in five resolves ambiguously
  because both levels are touched inside the same M5 bar. A two-bar hold
  cannot distinguish skill from noise.
- **One symbol and one year is not a study.** Multi-instrument and multi-regime
  validation remain open.

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

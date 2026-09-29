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
```

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
- The report prints each fold, then the pooled in-sample and out-of-sample
  comparison, then the degradation gap (`OOS - IS`) in expectancy (R) and win
  rate (percentage points).
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

The walk-forward and multi-instrument tooling exists and is tested on fixtures
and on a clearly labelled synthetic CLI sample, but **it has never been run
against a real event export**. No broad historical backtest, broker-spread
simulation, walk-forward run, or multi-instrument study has been performed on
real data, so no measured win rate or expectancy figure exists for this project
yet. These tools establish the safe measurement contract; they do not
demonstrate profitability.

Avoid optimizing the score or thresholds on one dataset. Prefer broad, walk-forward, multi-regime validation and investigate suspiciously good results for leakage.

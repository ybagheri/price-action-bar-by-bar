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
```

## Aggregate reporting

`pab_research.report` groups events by `setup_type` or by engine `status` and prints counts, win rate, expectancy in R, average MFE/MAE, and average bars to exit.

Reporting rules, stated so the numbers are not over-read:

- Win rate and expectancy use resolved outcomes only (`target`, `invalidation`, `ambiguous`). `expired` and `no_trade` rows are counted in their own columns and excluded from both, because they never reached an exit.
- Expectancy is in R: a target adds the event's own reward/risk, an invalidation subtracts 1, and an ambiguous same-bar exit contributes 0.
- MFE and MAE are price excursions from entry, not realised P/L, and are not risk-normalised.
- `no_trade` rows are kept in the report so selectivity per setup type is visible.

None of these figures include spread, slippage, or commission, because the export does not carry them.

## Bias controls

- Decisions exclude forming bar index 0.
- Fractal swings are delayed by right-side confirmation bars.
- Event timestamps are explicit.
- Parameter and engine versions are stored.
- Future data is isolated in the outcome evaluator.

## Current limitations

No broad historical backtest, broker-spread simulation, walk-forward validation, or multi-instrument study has been run. The reporting tool exists and is tested, but it has never been pointed at a real event export, so no measured win rate or expectancy figure exists for this project yet. These tools establish the safe measurement contract; they do not demonstrate profitability.

Avoid optimizing the score or thresholds on one dataset. Prefer broad, walk-forward, multi-regime validation and investigate suspiciously good results for leakage.

"""
RESEARCH-ONLY SENSITIVITY ANALYSIS -- NOT PART OF THE CANONICAL ENGINE.

What this is
------------
The engine decides levels itself: a baseline target of `entry +/- 2.0 *
bar.range`, then a clamp toward context support/resistance, then a gate that
rejects anything below a 1.50 reward/risk minimum. So the R:R in an export is
VARIABLE per trade, not fixed.

This script answers a different question: what if reward/risk were fixed at
exactly 1:2, with each trade risking a fixed fraction of the account?

Why it is research-only, and why that matters
--------------------------------------------
`pab_research` is not supposed to re-derive a setup. This does not invent
setups, but it DOES override the engine's exit: it replaces the exported
target with `entry +/- 2 * risk` and re-simulates. That is a legitimate
sensitivity question and a research-only algorithm, and it is labelled as one
here and in every figure it prints. It is NOT a measurement of the engine and
NOT a profitability claim. The canonical numbers stay the ones in
`research/test_artifacts/`.

The trap this script exists to avoid
------------------------------------
It is tempting to take the measured 47.7% win rate from the 1.5R-gated
export and plug it into a 1:2 payoff:

    0.477 * 2 - 0.523 * 1 = +0.43R      <- looks wonderful, and is WRONG

That is wrong because widening the target from ~1.7R to 2R means fewer targets
are reached, so the win rate FALLS. This script re-simulates the exits from
the bar data and measures the win rate that a 1:2 target actually produces.

Two concurrency policies, because they are not the same experiment
------------------------------------------------------------------
  every_event : every export row is treated as an independent trade. This is
                what the report's expectancy means, but it is NOT an account:
                at 71,816 M5 events it implies ~35,000 simultaneous positions.
  one_at_time : at most one position open; the next signal is taken only after
                the previous one has closed. This is the only one of the two
                that is a real balance curve.

Neither is a trading system. The indicator places no orders and this places
none either.
"""

from __future__ import annotations

import csv
import sys
from bisect import bisect_left
from dataclasses import dataclass
from datetime import datetime, timedelta

# Account convention for this run. Both are stated on every output line.
RISK_FRACTION = 0.005          # 0.5% of current balance risked per trade
TARGET_R = 2.0                 # reward:risk of exactly 1:2
MAX_HOLD_BARS = 200            # forward-scan cap; binds on almost nothing
TIMEFRAME_MINUTES = {"M5": 5, "H1": 60, "H4": 240, "D1": 1440}

# Assumed round-trip spread, as a PERCENT OF PRICE. NOT a measurement: the
# Strategy Tester exposes no historical spread (error 4807), so every net
# figure below is an assumption supplied here and labelled as one.
ASSUMED_SPREAD_PCT = (0.000, 0.001, 0.005)

# Win rate the ENGINE'S OWN variable R:R produced, from
# research/test_artifacts/study_swing_timeframes_eurusd_2009.txt. These are
# the numbers a reader is most likely to have in hand, and they are what the
# shortcut below wrongly reuses. They are inputs to a warning, not a
# measurement taken from this run.
ENGINE_WIN_RATE = {"M5": 0.477, "H1": 0.476, "H4": 0.426, "D1": 0.484}


@dataclass
class Trade:
    decision_time: datetime
    direction: str
    entry: float
    stop: float
    risk: float
    start: int          # index of the first bar at or after decision_time


@dataclass
class Outcome:
    kind: str           # target | stop | ambiguous | expired | timeout
    bars: int
    r: float            # realised R, 0.0 for ambiguous/expired/timeout


def parse_dt(text: str) -> datetime:
    return datetime.strptime(text.strip(), "%Y-%m-%d %H:%M:%S")


def load_trades(events_path: str) -> list[Trade]:
    trades: list[Trade] = []
    with open(events_path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if row["status"] == "no_trade" or row["direction"] == "none":
                continue
            entry = float(row["entry"])
            stop = float(row["invalidation"])
            risk = abs(entry - stop)
            if entry <= 0.0 or risk <= 0.0:
                continue
            trades.append(Trade(parse_dt(row["decision_time"]),
                                row["direction"], entry, stop, risk, 0))
    trades.sort(key=lambda t: t.decision_time)
    return trades


def load_bars(bars_path: str) -> tuple[list[datetime], list[float], list[float]]:
    """Bars carry open_time, high, low only. There is NO close column in the
    export, which matters only for valuing an expired trade; that is counted
    and reported wherever it happens."""
    times: list[datetime] = []
    highs: list[float] = []
    lows: list[float] = []
    with open(bars_path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            times.append(parse_dt(row["open_time"]))
            highs.append(float(row["high"]))
            lows.append(float(row["low"]))
    order = sorted(range(len(times)), key=lambda i: times[i])
    return ([times[i] for i in order],
            [highs[i] for i in order],
            [lows[i] for i in order])


def simulate(trade: Trade, times, highs, lows) -> Outcome:
    """Walk forward from the first bar at or after the decision.

    The stop is the engine's own invalidation level, unchanged. Only the
    TARGET is replaced, by entry +/- 2 * risk. R is defined by the stop
    distance, which is the same definition TradingCost.mqh uses.
    """
    start = bisect_left(times, trade.decision_time)
    if start >= len(times):
        return Outcome("expired", 0, 0.0)

    if trade.direction == "long":
        target = trade.entry + TARGET_R * trade.risk
        stop = trade.stop
    else:
        target = trade.entry - TARGET_R * trade.risk
        stop = trade.stop

    last = min(len(times), start + MAX_HOLD_BARS)
    for index in range(start, last):
        high, low = highs[index], lows[index]
        if trade.direction == "long":
            hit_target, hit_stop = high >= target, low <= stop
        else:
            hit_target, hit_stop = low <= target, high >= stop
        bars = index - start + 1
        if hit_target and hit_stop:
            return Outcome("ambiguous", bars, 0.0)
        if hit_stop:
            return Outcome("stop", bars, -1.0)
        if hit_target:
            return Outcome("target", bars, TARGET_R)
    if last >= len(times):
        return Outcome("expired", last - start, 0.0)
    return Outcome("timeout", last - start, 0.0)


def cost_r(trade: Trade, spread_pct: float) -> float:
    """Assumed round-trip spread as a fraction of R. Slippage and commission
    are excluded, so a real cost is at least this large."""
    if spread_pct <= 0.0:
        return 0.0
    return (spread_pct / 100.0) * trade.entry / trade.risk


def analyse(period: str, events_path: str, bars_path: str) -> None:
    trades = load_trades(events_path)
    times, highs, lows = load_bars(bars_path)
    for trade in trades:
        trade.start = bisect_left(times, trade.decision_time)

    outcomes = [simulate(t, times, highs, lows) for t in trades]

    counts: dict[str, int] = {}
    for o in outcomes:
        counts[o.kind] = counts.get(o.kind, 0) + 1
    resolved = [o for o in outcomes if o.kind in ("target", "stop")]
    wins = sum(1 for o in resolved if o.kind == "target")
    gross = sum(o.r for o in resolved) / len(resolved) if resolved else 0.0
    mean_bars = (sum(o.bars for o in resolved) / len(resolved)) if resolved else 0.0

    minutes = TIMEFRAME_MINUTES[period]
    print(f"\n{'=' * 74}")
    print(f"EURUSD 2009  {period}   fixed 1:2, risk {RISK_FRACTION * 100:.1f}% of balance")
    print(f"{'=' * 74}")
    print(f"signals (non no_trade)  {len(trades)}")
    print(f"  target {counts.get('target', 0)}  stop {counts.get('stop', 0)}  "
          f"ambiguous {counts.get('ambiguous', 0)}  expired {counts.get('expired', 0)}  "
          f"timeout {counts.get('timeout', 0)}")
    print(f"resolved (target+stop)  {len(resolved)}")
    print(f"win rate                {wins / len(resolved) * 100:.1f}%  "
          f"at a 1:2 payoff the break-even win rate is 33.3%")
    print(f"gross expectancy        {gross:+.3f}R   GROSS, before any cost")
    print(f"mean bars to exit       {mean_bars:.1f} bars "
          f"({mean_bars * minutes / 60.0:.1f} hours)")

    # ---- sequential account, one position at a time --------------------
    print(f"\n-- one position at a time --")
    for pct in ASSUMED_SPREAD_PCT:
        balance = 1.0
        peak = 1.0
        max_dd = 0.0
        taken = 0
        busy_until = -1
        gross_pl = 0.0
        wins_taken = 0
        for trade, outcome in zip(trades, outcomes):
            if outcome.kind not in ("target", "stop"):
                continue
            if trade.start <= busy_until:
                continue
            taken += 1
            busy_until = trade.start + outcome.bars
            r = outcome.r - cost_r(trade, pct)
            if outcome.kind == "target":
                wins_taken += 1
            gross_pl += r
            balance *= (1.0 + RISK_FRACTION * r)
            peak = max(peak, balance)
            max_dd = max(max_dd, (peak - balance) / peak)
        label = "GROSS (no cost assumed)" if pct == 0.0 else \
                f"assumed spread {pct:.3f}% of price"
        growth = (balance - 1.0) * 100.0
        print(f"  {label:<34} trades {taken:>6}  "
              f"win {wins_taken / taken * 100 if taken else 0:>5.1f}%  "
              f"final {balance:>8.4f}x ({growth:+.1f}%)  maxDD {max_dd * 100:>5.1f}%")
        if pct == 0.0:
            print(f"  {'sum of R over taken trades':<34} {gross_pl / taken if taken else 0:>+9.3f}R")

    # ---- what the WRONG shortcut would have claimed --------------------
    engine_win = ENGINE_WIN_RATE.get(period)
    if engine_win is not None:
        shortcut = engine_win * TARGET_R - (1.0 - engine_win)
        print(f"\n-- the shortcut this script exists to prevent --")
        print(f"  the engine's own R:R gave a {engine_win * 100:.1f}% win rate; "
              f"plugging that")
        print(f"  into a 1:2 payoff claims            {shortcut:+.3f}R")
        print(f"  a 1:2 target actually achieves      {gross:+.3f}R "
              f"({wins / len(resolved) * 100:.1f}% win rate)")
        print(f"  overstatement if anyone reports it  {shortcut - gross:+.3f}R")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: pab_fixed_rr.py <events.csv> <bars.csv>")
        return 2
    events_path, bars_path = argv[1], argv[2]
    period = ""
    with open(events_path, newline="", encoding="utf-8") as handle:
        period = next(csv.DictReader(handle, delimiter="\t"))["period"]
    analyse(period, events_path, bars_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

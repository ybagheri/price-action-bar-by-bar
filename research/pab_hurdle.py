"""
RESEARCH-ONLY: how big an edge would this engine need, and could this data
even detect one?

The point of this script is to make the "how do we get to a profitable trade"
question answerable with numbers instead of adjectives. It answers three
questions, all of them about the HURDLE rather than about a strategy:

  1. What is the smallest edge, in R per trade, that beats a realistic cost?
  2. How precisely can this sample measure an edge at all?
  3. Therefore: how many parameter combinations would somebody have to try
     before a search produced a configuration that APPEARS to clear a
     realistic cost, purely by luck?

Question 3 is the one that matters most, and it is the reason this project
refuses to tune. The arithmetic below is not a forecast; it is a statement
about what a search over this data can and cannot distinguish from noise.

Uses the canonical loaders and the canonical outcome rule, so the expectancy
here is the same number the report prints. Research-only; not a measurement of
any configuration; no profitability claim.
"""

from __future__ import annotations

import math
import sys

sys.path.insert(0, ".")

from pab_research.events import load_price_bars, load_setup_events
from pab_research.outcomes import evaluate_setup

# Assumed round-trip spread, PERCENT OF PRICE. NOT measurements: the Strategy
# Tester exposes no historical spread (error 4807), so each of these is an
# assumption supplied here. 0.001% is roughly a third of a pip on EURUSD and
# is therefore already optimistic.
ASSUMED_SPREAD_PCT = (0.000, 0.0005, 0.001, 0.005)

# Expected maximum of N draws from a standard normal, used to ask how far
# above the true mean the BEST of N noisy estimates tends to land.
def expected_max_z(n: int) -> float:
    # Acklam's-style rational approximation to the inverse normal CDF,
    # good to ~1e-9 over the range used here.
    if n <= 1:
        return 0.0
    # two-sided: we take the max, so use the n-th of 2n order statistics
    p = 1.0 - 1.0 / (2.0 * n)
    a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00]
    plow, phigh = 0.02425, 1 - 0.02425
    if p < plow:
        q = math.sqrt(-2 * math.log(p))
        return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / \
               ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    if p > phigh:
        q = math.sqrt(-2 * math.log(1 - p))
        return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / \
               ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    q = p - 0.5
    r = q * q
    return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q / \
           (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)


def analyse(period: str, events_path: str, bars_path: str) -> None:
    events = load_setup_events(events_path)
    bars = load_price_bars(bars_path)

    risks = []
    entries = []
    r_values = []
    for event in events:
        if event.status == "no_trade":
            continue
        result = evaluate_setup(event, bars)
        # The canonical rule, copied from report.py so these numbers ARE the
        # project's numbers rather than a near miss:
        #   resolved = target + invalidation + ambiguous
        #   a target contributes the event's OWN exported risk_reward
        #   an invalidation contributes -1
        #   an ambiguous bar contributes 0 but still sits in the denominator
        if result.outcome == "target":
            r_values.append(event.risk_reward)
            risks.append(abs(event.entry - event.invalidation))
            entries.append(event.entry)
        elif result.outcome == "invalidation":
            r_values.append(-1.0)
            risks.append(abs(event.entry - event.invalidation))
            entries.append(event.entry)
        elif result.outcome == "ambiguous":
            r_values.append(0.0)
            risks.append(abs(event.entry - event.invalidation))
            entries.append(event.entry)

    n = len(r_values)
    if n == 0:
        print(f"{period}: no resolved outcomes")
        return

    mean_r = sum(r_values) / n
    var = sum((r - mean_r) ** 2 for r in r_values) / (n - 1)
    std = math.sqrt(var)
    se = std / math.sqrt(n)
    ci95 = 1.96 * se

    mean_risk = sum(risks) / len(risks)
    mean_entry = sum(entries) / len(entries)
    win_rate = sum(1 for r in r_values if r > 0) / n
    mean_win = (sum(r for r in r_values if r > 0) /
                max(1, sum(1 for r in r_values if r > 0)))

    print(f"\n{'=' * 74}")
    print(f"EURUSD 2009  {period}   the hurdle, not a strategy")
    print(f"{'=' * 74}")
    print(f"resolved outcomes            {n}")
    print(f"win rate                     {win_rate * 100:.1f}%")
    print(f"mean R on a win              {mean_win:+.3f}R   (the engine's own payoff)")
    print(f"gross expectancy             {mean_r:+.4f}R")
    print(f"standard deviation of R      {std:.3f}")
    print(f"standard error of the mean   {se:.4f}R")
    print(f"95% confidence interval      {mean_r - ci95:+.4f}R .. {mean_r + ci95:+.4f}R"
          f"   (half-width {ci95:.4f}R)")
    print(f"mean stop distance           {mean_risk:.5f}   mean price {mean_entry:.5f}")

    print(f"\n-- edge required to beat an ASSUMED round-trip spread (spread only) --")
    hurdles = {}
    for pct in ASSUMED_SPREAD_PCT:
        spread_price = (pct / 100.0) * mean_entry
        need = spread_price / mean_risk
        hurdles[pct] = need
        if need == 0.0:
            continue
        ratio = need / ci95
        verdict = "inside the noise" if ratio < 1.0 else \
                  ("marginal" if ratio < 2.0 else "outside the noise")
        print(f"  {pct:.4f}% of price -> {need:+.4f}R per trade   "
              f"({ratio:5.1f}x the 95% noise half-width, {verdict})")

    hurdle = hurdles[0.001]
    print(f"\n-- how big must the edge be to matter? --")
    print(f"  clearing a 0.0010% spread needs {hurdle:.4f}R per trade.")
    print(f"  the measured edge is {mean_r:+.4f}R")
    if mean_r > 0:
        print(f"  -> about {hurdle / mean_r:.1f}x improvement needed. That is a signal "
              f"quality problem,")
        print(f"     not a threshold problem.")
    else:
        print(f"  -> the edge is NEGATIVE, so there is no multiple: the first requirement")
        print(f"     is to get it above zero at all, before cost is even considered.")

    print(f"\n-- how many parameter tries before a search 'finds' an edge --")
    print(f"  (assuming the truth is zero edge, so any apparent gain is pure selection)")
    for trials in (10, 50, 100, 500, 1000):
        z = expected_max_z(trials)
        best = z * se
        verdict = ("clears a 0.001% cost" if best > hurdle
                   else "still does not clear it")
        print(f"  {trials:>5} tries: best-of-N lands near {best:+.4f}R "
              f"(z={z:.2f}) -- {verdict}")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: pab_hurdle.py <events.csv> <bars.csv>")
        return 2
    events_path, bars_path = argv[1], argv[2]
    with open(events_path, encoding="utf-8") as handle:
        handle.readline()                      # header
        first = handle.readline().rstrip("\n")  # first DATA row carries period
    period = first.split("\t")[16]
    analyse(period, events_path, bars_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

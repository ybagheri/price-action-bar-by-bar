"""Walk-forward and cross-instrument validation over exported setup events.

This module never re-derives a trading decision. It re-uses the same
counting primitives as :mod:`pab_research.report` and only changes *how the
events are partitioned before counting*.

Why this exists
---------------
A single win rate over one contiguous date range cannot distinguish a rule
that generalizes from a rule that happened to be fitted to that range. The
standard remedy is walk-forward separation: split the event stream
chronologically into alternating in-sample and out-of-sample blocks, tune or
inspect only on the in-sample block, and then read the untouched
out-of-sample block. The gap between the two is reported as *degradation*.

Honest limits, stated up front
------------------------------
* Degradation is a measurement, not a verdict. A negative value is a finding
  about the sample, not a bug in this module.
* If a block resolves too few events, expectancy is not reported as
  trustworthy: the result is marked ``reliable = False`` and the reason is
  carried alongside, rather than publishing a number off a handful of trades.
* The bars used to evaluate an event are not restricted to the fold. An event
  near a fold boundary may resolve using bars that fall in the next block.
  That is intentional -- truncating outcomes would bias measured holding
  periods -- but it means fold boundaries leak forward in *outcome space*
  only, never in *decision space*.
* Costs are reported separately from expectancy, never folded silently into
  it. An export written before Phase 19 has no cost column at all, in which
  case the net figures read ``n/a`` and the gross figures are labelled as
  gross. Reporting a gross number under a net heading would be worse than
  reporting nothing.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Sequence

from .events import UNKNOWN_SYMBOL, PriceBar, SetupEvent
from .outcomes import BarBook, BarSeries, evaluate_setup
from .report import SetupStats, summarize

IN_SAMPLE = "in_sample"
OUT_OF_SAMPLE = "out_of_sample"

#: Below this many resolved outcomes a block's expectancy is not trustworthy.
DEFAULT_MIN_RESOLVED = 5


@dataclass(frozen=True)
class Fold:
    """One chronological block of the event stream and its statistics."""

    index: int
    role: str
    first_decision: datetime
    last_decision: datetime
    stats: SetupStats

    @property
    def is_in_sample(self) -> bool:
        return self.role == IN_SAMPLE

    @property
    def span_label(self) -> str:
        return f"{self.first_decision} .. {self.last_decision}"


@dataclass(frozen=True)
class WalkForwardResult:
    """Pooled in-sample vs out-of-sample statistics plus the degradation gap."""

    folds: tuple[Fold, ...]
    in_sample: SetupStats
    out_of_sample: SetupStats
    expectancy_degradation_r: float
    win_rate_degradation: float
    reliable: bool
    reason: str
    #: Net (after-cost) degradation. None when either pooled half lacks
    #: cost data, so a gross degradation can never be read as a net one.
    net_expectancy_degradation_r: float | None = None

    @property
    def folds_promised(self) -> int:
        return len(self.folds)

    @property
    def costs_available(self) -> bool:
        return self.net_expectancy_degradation_r is not None


def _block(events: Sequence[SetupEvent], start: int, stop: int) -> list[SetupEvent]:
    return list(events[start:stop])


def _pooled(
    role: str,
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
) -> SetupStats:
    results = [evaluate_setup(event, bars) for event in events]
    return summarize(role, events, results)


def split_walk_forward(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
    folds: int = 4,
    min_resolved: int = DEFAULT_MIN_RESOLVED,
) -> WalkForwardResult:
    """Split ``events`` chronologically into alternating IS/OOS blocks.

    Blocks are contiguous and non-overlapping, cut at even fractions of the
    event count. Even-numbered blocks are in-sample, odd-numbered blocks are
    out-of-sample, which is the usual walk-forward arrangement: every
    out-of-sample block is preceded by an in-sample block of the same length.

    ``events`` need not be pre-sorted; they are ordered by ``decision_time``
    here so that the split is deterministic. ``bars`` may be a plain list or a
    prebuilt :class:`~pab_research.outcomes.BarSeries`; the index is built once
    and shared by every fold and by the pooled totals.
    """
    if folds < 2:
        raise ValueError("folds must be at least 2 (one in-sample plus one out-of-sample)")
    if min_resolved < 1:
        raise ValueError("min_resolved must be at least 1")

    series = bars if isinstance(bars, (BarSeries, BarBook)) else BarSeries.of(bars)

    ordered = sorted(events, key=lambda event: event.decision_time)
    if not ordered:
        raise ValueError("no events to split")
    if folds > len(ordered):
        raise ValueError(
            f"cannot build {folds} folds from {len(ordered)} events; "
            "reduce folds or export a longer history"
        )

    produced: list[Fold] = []
    in_sample_events: list[SetupEvent] = []
    out_of_sample_events: list[SetupEvent] = []
    for index in range(folds):
        start = (index * len(ordered)) // folds
        stop = ((index + 1) * len(ordered)) // folds
        block = _block(ordered, start, stop)
        role = IN_SAMPLE if index % 2 == 0 else OUT_OF_SAMPLE
        if role == IN_SAMPLE:
            in_sample_events.extend(block)
        else:
            out_of_sample_events.extend(block)
        produced.append(
            Fold(
                index=index,
                role=role,
                first_decision=block[0].decision_time,
                last_decision=block[-1].decision_time,
                stats=summarize(
                    f"fold{index}-{role}",
                    block,
                    [evaluate_setup(e, series) for e in block],
                ),
            )
        )

    pooled_in = _pooled("in_sample (pooled)", in_sample_events, series)
    pooled_out = _pooled("out_of_sample (pooled)", out_of_sample_events, series)

    if pooled_in.resolved < min_resolved:
        reliable, reason = False, f"in-sample resolved {pooled_in.resolved} < {min_resolved}"
    elif pooled_out.resolved < min_resolved:
        reliable, reason = False, f"out-of-sample resolved {pooled_out.resolved} < {min_resolved}"
    else:
        reliable, reason = True, ""

    net_degradation = None
    if pooled_in.net_expectancy_r is not None and pooled_out.net_expectancy_r is not None:
        net_degradation = pooled_out.net_expectancy_r - pooled_in.net_expectancy_r
    else:
        # Cost data is missing on one side, which is a different problem
        # from an unreliable sample. Report both, not one in place of the
        # other.
        reason = (
            (reason + "; " if reason else "")
            + "export carries no cost column, so net expectancy is unavailable"
        )

    return WalkForwardResult(
        folds=tuple(produced),
        in_sample=pooled_in,
        out_of_sample=pooled_out,
        expectancy_degradation_r=pooled_out.expectancy_r - pooled_in.expectancy_r,
        win_rate_degradation=pooled_out.win_rate - pooled_in.win_rate,
        reliable=reliable,
        reason=reason,
        net_expectancy_degradation_r=net_degradation,
    )


def group_by_instrument(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
) -> dict[str, SetupStats]:
    """Group events by the exported symbol.

    Events exported before the symbol column existed group under
    ``"unspecified"`` rather than being dropped, so an old file still reports
    honestly instead of quietly shrinking the sample.
    """
    grouped: dict[str, list[SetupEvent]] = {}
    for event in events:
        grouped.setdefault(event.symbol or UNKNOWN_SYMBOL, []).append(event)
    series = bars if isinstance(bars, (BarSeries, BarBook)) else BarSeries.of(bars)
    return {
        key: _pooled(key, group, series) for key, group in sorted(grouped.items())
    }


def market_of(event: SetupEvent) -> str:
    """Bucket key for an event's market and timeframe together.

    Grouping by symbol alone mixes timeframes, and that is not a meaningful
    average: an M5 setup resolves in about two bars and an H1 setup in about
    six, so a pooled expectancy describes neither. On a 242,473-event
    multi-timeframe export this is the difference between a readable study and
    a single number hiding two different things.
    """
    symbol = event.symbol or UNKNOWN_SYMBOL
    period = event.period or "unknown"
    return f"{symbol} {period}"


def group_by_market(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries | BarBook,
) -> dict[str, SetupStats]:
    """Group events by symbol and timeframe together.

    Prefer this over :func:`group_by_instrument` whenever the export covers
    more than one timeframe, which is the normal case for a real study.
    """
    grouped: dict[str, list[SetupEvent]] = {}
    for event in events:
        grouped.setdefault(market_of(event), []).append(event)
    series = bars if isinstance(bars, (BarSeries, BarBook)) else BarSeries.of(bars)
    return {
        key: _pooled(key, group, series) for key, group in sorted(grouped.items())
    }


def instrument_walk_forward(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
    folds: int = 4,
    min_resolved: int = DEFAULT_MIN_RESOLVED,
) -> dict[str, WalkForwardResult]:
    """Run :func:`split_walk_forward` independently for every symbol.

    A symbol with too few events for the requested fold count is reported with
    a one-block fallback rather than raising, so a multi-instrument run still
    says something about every symbol it was given.
    """
    grouped: dict[str, list[SetupEvent]] = {}
    for event in events:
        grouped.setdefault(event.symbol or UNKNOWN_SYMBOL, []).append(event)

    series = bars if isinstance(bars, (BarSeries, BarBook)) else BarSeries.of(bars)
    results: dict[str, WalkForwardResult] = {}
    for symbol, group in sorted(grouped.items()):
        try:
            results[symbol] = split_walk_forward(group, series, folds, min_resolved)
        except ValueError:
            results[symbol] = split_walk_forward(group, series, 2, min_resolved)
    return results


def filter_window(
    events: Sequence[SetupEvent],
    start: datetime | None = None,
    end: datetime | None = None,
) -> list[SetupEvent]:
    """Keep only events whose ``decision_time`` falls in ``[start, end]``.

    Both bounds are inclusive, and ``None`` means unbounded. Filtering is on
    ``decision_time`` rather than ``bar_open_time`` because that is the instant
    the engine actually committed, and it is the field the walk-forward split
    cuts on, so a filter and a fold can never disagree about which side of a
    boundary an event falls on.
    """
    if start is not None and end is not None and start > end:
        raise ValueError("start must not be later than end")
    kept = [
        event
        for event in events
        if (start is None or event.decision_time >= start)
        and (end is None or event.decision_time <= end)
    ]
    kept.sort(key=lambda event: event.decision_time)
    return kept


def format_fold_report(result: WalkForwardResult) -> str:
    """Render a walk-forward result as a fixed-width text block."""
    from .report import format_report

    spans = "\n".join(
        f"  {fold.stats.key:<28}{fold.span_label}" for fold in result.folds
    )
    blocks = [
        "walk-forward per-fold results",
        format_report({fold.stats.key: fold.stats for fold in result.folds}),
        "",
        "decision-time span per fold",
        spans,
        "",
        "pooled comparison",
        format_report(
            {
                result.in_sample.key: result.in_sample,
                result.out_of_sample.key: result.out_of_sample,
            }
        ),
        "",
        f"gross expectancy degradation (OOS - IS): {result.expectancy_degradation_r:+.2f}R",
        (
            f"net expectancy degradation   (OOS - IS): {result.net_expectancy_degradation_r:+.2f}R"
            if result.net_expectancy_degradation_r is not None
            else "net expectancy degradation   (OOS - IS): n/a -- the export carries no cost column"
        ),
        f"win-rate degradation  (OOS - IS): {result.win_rate_degradation * 100:+.1f} pp",
        f"reliable: {'yes' if result.reliable else 'no -- ' + result.reason}",
    ]
    blocks.append(
        "Degradation is a measurement of this sample, not a profitability claim. "
        "Outcomes may resolve using bars past a fold boundary; decisions never do. "
        "netR includes the measured spread plus any assumed slippage and commission, "
        "each labelled in the export's cost_model column."
    )
    return "\n".join(blocks)

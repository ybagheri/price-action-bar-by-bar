"""Aggregate exported setup events into descriptive outcome statistics.

This module never re-derives a trading decision. It consumes events that the
MQL5 indicator already exported and outcomes that the evaluator already
produced, and only counts them. Every figure below is descriptive of the
measured sample, not a profitability claim, and all of them ignore spread,
slippage, and commission because the export does not carry them.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Sequence

from .events import PriceBar, SetupEvent
from .outcomes import BarSeries, OutcomeResult, evaluate_setup


@dataclass(frozen=True)
class SetupStats:
    """Descriptive counts and averages for one group of setup events."""

    key: str
    total: int
    targets: int
    invalidations: int
    ambiguous: int
    expired: int
    no_trade: int
    win_rate: float
    expectancy_r: float
    average_mfe: float
    average_mae: float
    average_bars_to_exit: float

    @property
    def resolved(self) -> int:
        return self.targets + self.invalidations + self.ambiguous


def summarize(
    key: str,
    events: Sequence[SetupEvent],
    results: Sequence[OutcomeResult],
) -> SetupStats:
    """Summarize one already-evaluated group of events.

    ``events`` and ``results`` must be aligned by index. Win rate and
    expectancy are computed over resolved outcomes only, because NO TRADE
    and expired events never reached an exit and would otherwise inflate or
    deflate the result. Expectancy is expressed in R: a target contributes
    the event's own reward/risk, an invalidation contributes -1, and an
    ambiguous same-bar exit contributes 0.
    """
    if len(events) != len(results):
        raise ValueError("events and results must be the same length")

    counts = {
        "target": 0,
        "invalidation": 0,
        "ambiguous": 0,
        "expired": 0,
        "no_trade": 0,
    }
    r_units: list[float] = []
    mfe: list[float] = []
    mae: list[float] = []
    holds: list[int] = []

    for event, result in zip(events, results):
        outcome = result.outcome
        if outcome not in counts:
            raise ValueError(f"unexpected outcome {outcome!r}")
        counts[outcome] += 1

        if outcome in ("target", "invalidation", "ambiguous"):
            if outcome == "target":
                r_units.append(event.risk_reward)
            elif outcome == "invalidation":
                r_units.append(-1.0)
            else:
                r_units.append(0.0)
            mfe.append(result.mfe)
            mae.append(result.mae)
            if result.bars_to_exit is not None:
                holds.append(result.bars_to_exit)
        elif outcome == "expired":
            mfe.append(result.mfe)
            mae.append(result.mae)

    resolved = counts["target"] + counts["invalidation"] + counts["ambiguous"]
    win_rate = counts["target"] / resolved if resolved else 0.0
    expectancy_r = sum(r_units) / resolved if resolved else 0.0

    return SetupStats(
        key=key,
        total=len(events),
        targets=counts["target"],
        invalidations=counts["invalidation"],
        ambiguous=counts["ambiguous"],
        expired=counts["expired"],
        no_trade=counts["no_trade"],
        win_rate=win_rate,
        expectancy_r=expectancy_r,
        average_mfe=sum(mfe) / len(mfe) if mfe else 0.0,
        average_mae=sum(mae) / len(mae) if mae else 0.0,
        average_bars_to_exit=sum(holds) / len(holds) if holds else 0.0,
    )


def _as_series(bars: Sequence[PriceBar] | BarSeries) -> BarSeries:
    """Reuse an already-built index, or build it once for a plain list."""
    return bars if isinstance(bars, BarSeries) else BarSeries.of(bars)


def evaluate_and_summarize(
    key: str,
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
) -> SetupStats:
    """Evaluate every event against one bar history, then summarize the group.

    The bar index is built once here rather than once per event. On a real
    export that is the difference between seconds and hours.
    """
    series = _as_series(bars)
    results = [evaluate_setup(event, series) for event in events]
    return summarize(key, events, results)


def _grouped(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar] | BarSeries,
    key_of,
) -> dict[str, SetupStats]:
    grouped: dict[str, list[SetupEvent]] = {}
    for event in events:
        grouped.setdefault(key_of(event), []).append(event)
    # Index the bars a single time for the whole report.
    series = _as_series(bars)
    return {
        key: evaluate_and_summarize(key, group, series)
        for key, group in sorted(grouped.items())
    }


def group_by_setup(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar],
) -> dict[str, SetupStats]:
    """Group events by the exported ``setup_type``.

    NO TRADE rows are included so the report can show how selective each
    setup type actually is on the measured sample.
    """
    return _grouped(events, bars, lambda event: event.setup_type)


def group_by_status(
    events: Sequence[SetupEvent],
    bars: Sequence[PriceBar],
) -> dict[str, SetupStats]:
    """Group events by the engine's own status label."""
    return _grouped(events, bars, lambda event: event.status)


def format_report(groups: dict[str, SetupStats], title: str = "Setup outcome report") -> str:
    """Render grouped statistics as a fixed-width text table."""
    columns = (
        f"{'group':<24}{'total':>7}{'tgt':>6}{'inv':>6}{'amb':>6}"
        f"{'exp':>7}{'nt':>7}{'win%':>8}{'expR':>8}{'MFE':>9}{'MAE':>9}{'bars':>7}"
    )
    lines = [title, columns, "-" * len(columns)]
    for key, stats in groups.items():
        lines.append(
            f"{key:<24}{stats.total:>7}{stats.targets:>6}{stats.invalidations:>6}"
            f"{stats.ambiguous:>6}{stats.expired:>7}{stats.no_trade:>7}"
            f"{stats.win_rate * 100:>7.1f}%{stats.expectancy_r:>8.2f}"
            f"{stats.average_mfe * 100:>8.2f}%{stats.average_mae * 100:>8.2f}%"
            f"{stats.average_bars_to_exit:>7.1f}"
        )
    lines.append("")
    lines.append(
        "win% and expR cover resolved outcomes only; expired and NO TRADE rows "
        "are excluded. MFE/MAE are price excursions, not realised P/L. "
        "Spread, slippage, and commission are not included."
    )
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    """Print a setup report for an exported event CSV and a bar history CSV."""
    import argparse

    from .events import load_price_bars, load_setup_events

    parser = argparse.ArgumentParser(
        prog="python -m pab_research",
        description="Summarize exported PriceActionBarByBar events.",
    )
    parser.add_argument("events_csv", help="CSV produced by the InpExportEvents option")
    parser.add_argument("bars_csv", help="CSV with open_time, high, low columns")
    parser.add_argument(
        "--group",
        choices=("setup", "status", "instrument"),
        default="setup",
        help="group the report by setup_type, engine status, or symbol",
    )
    parser.add_argument(
        "--walk-forward",
        type=int,
        metavar="N",
        help=(
            "split the event stream chronologically into N alternating "
            "in-sample/out-of-sample blocks and report the degradation gap"
        ),
    )
    parser.add_argument(
        "--walk-forward-min-resolved",
        type=int,
        default=5,
        help="mark a walk-forward result unreliable below this many resolved outcomes",
    )
    parser.add_argument(
        "--walk-forward-per-instrument",
        action="store_true",
        help="run the walk-forward split separately for each symbol",
    )
    parser.add_argument(
        "--from",
        dest="from_iso",
        metavar="TIMESTAMP",
        help="only count events decided at or after this ISO timestamp",
    )
    parser.add_argument(
        "--to",
        dest="to_iso",
        metavar="TIMESTAMP",
        help="only count events decided at or before this ISO timestamp",
    )
    args = parser.parse_args(argv)

    events = load_setup_events(args.events_csv)
    bars = load_price_bars(args.bars_csv)
    if not events:
        print("no events found")
        return 1

    start = datetime.fromisoformat(args.from_iso) if args.from_iso else None
    end = datetime.fromisoformat(args.to_iso) if args.to_iso else None
    if start is not None or end is not None:
        from .validation import filter_window

        try:
            events = filter_window(events, start, end)
        except ValueError as error:
            print(f"invalid window: {error}")
            return 1
        if not events:
            print("no events in the requested window")
            return 1
        window_label = f", window {start or 'start'} .. {end or 'end'}"
    else:
        window_label = ""

    if args.walk_forward is not None:
        from .validation import format_fold_report, instrument_walk_forward, split_walk_forward

        try:
            if args.walk_forward_per_instrument:
                per_symbol = instrument_walk_forward(
                    events, bars, args.walk_forward, args.walk_forward_min_resolved
                )
            else:
                per_symbol = {
                    "all": split_walk_forward(
                        events, bars, args.walk_forward, args.walk_forward_min_resolved
                    )
                }
        except ValueError as error:
            print(f"walk-forward not possible: {error}")
            return 1

        for label, result in per_symbol.items():
            header = (
                f"walk-forward: {label}, {len(events)} events, "
                f"{len(bars)} bars{window_label}, {result.folds_promised} folds"
            )
            print(header)
            print(format_fold_report(result))
            print("")
        return 0

    if args.group == "setup":
        grouper = group_by_setup
    elif args.group == "instrument":
        from .validation import group_by_instrument

        grouper = group_by_instrument
    else:
        grouper = group_by_status
    title = f"{len(events)} events, {len(bars)} bars{window_label}, grouped by {args.group}"
    print(format_report(grouper(events, bars), title))
    return 0

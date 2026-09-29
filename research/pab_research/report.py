"""Aggregate exported setup events into descriptive outcome statistics.

This module never re-derives a trading decision. It consumes events that the
MQL5 indicator already exported and outcomes that the evaluator already
produced, and only counts them. Every figure below is descriptive of the
measured sample, not a profitability claim.

Costs, Phase 19
---------------
Every expectancy figure before this phase was GROSS, and the measured edge
was a couple of hundredths of an R, so no figure could be compared to a
broker statement. Expectations are now reported twice:

* ``expectancy_r``  — the gross figure, unchanged in meaning.
* ``net_expectancy_r`` — the same resolved outcomes with each event's
  round-trip cost in R subtracted.

A net figure is only published when the export actually carries costs. If
the ``cost_r`` column is missing, ``net_expectancy_r`` is ``None`` and the
report says so in those words, rather than printing the gross number twice
and letting the reader assume it was net. That distinction is the whole
point: a report that cannot say which of its numbers is net has not
resolved the question it was run to answer.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Sequence

from .events import UNKNOWN_SYMBOL, PriceBar, SetupEvent, expected_cost_r
from .outcomes import BarBook, BarSeries, OutcomeResult, evaluate_setup


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
    #: Round-trip cost in R, averaged over the same resolved outcomes as
    #: expectancy. Reported on its own so the size of the drag is visible
    #: rather than only its effect on the bottom line.
    average_cost_r: float = 0.0
    #: None when the export carries no cost column. Never 0.0 in that case:
    #: "no cost data" and "costless trading" are different statements.
    net_expectancy_r: float | None = None
    #: Resolved outcomes that actually carried a cost figure. A group can
    #: be partially costed, which is why this is a count and not a flag.
    costed_resolved: int = 0
    #: Rows whose exported ``cost_r`` disagreed with the value recomputed
    #: from the exported price components by more than half a basis point.
    #: Non-zero means the export and this module do not agree about cost,
    #: which the report prints rather than averaging over.
    cost_mismatches: int = 0

    @property
    def resolved(self) -> int:
        return self.targets + self.invalidations + self.ambiguous

    @property
    def costs_available(self) -> bool:
        """Whether every resolved outcome in this group carried a cost."""
        return self.resolved > 0 and self.costed_resolved == self.resolved


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
    cost_units: list[float] = []
    costed = 0
    #: Events whose exported cost_r disagrees with the re-derivation. Kept
    #: as a count rather than raised, because one bad row should not hide
    #: a 240,000-row study, but it must never be silently averaged in.
    mismatched = 0

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

            # Cost is only counted over RESOLVED outcomes, the same
            # denominator expectancy uses. Charging a cost on an event
            # that never reached an exit would quietly deflate expectancy
            # with a cost that was never actually paid.
            if event.has_costs:
                cost = expected_cost_r(event)
                if event.cost_r is not None and abs(event.cost_r - cost) > 0.005:
                    mismatched += 1
                cost_units.append(cost)
                costed += 1
        elif outcome == "expired":
            mfe.append(result.mfe)
            mae.append(result.mae)

    resolved = counts["target"] + counts["invalidation"] + counts["ambiguous"]
    win_rate = counts["target"] / resolved if resolved else 0.0
    expectancy_r = sum(r_units) / resolved if resolved else 0.0
    average_cost_r = sum(cost_units) / costed if costed else 0.0
    # Net is published only when every resolved outcome was costed. A
    # partially-costed group would produce a net figure whose denominator
    # silently differs from the gross one beside it.
    net_expectancy_r = (
        (sum(r_units) - sum(cost_units)) / resolved
        if resolved and costed == resolved
        else None
    )

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
        average_cost_r=average_cost_r,
        net_expectancy_r=net_expectancy_r,
        costed_resolved=costed,
        cost_mismatches=mismatched,
    )


@dataclass(frozen=True)
class BreakEven:
    """The round-trip cost at which a group's gross edge disappears entirely.

    This exists because the cost of trading is the one input a bar series
    cannot supply. Spread is broker state that changes minute to minute,
    the Strategy Tester has no historical spread to read, and a study that
    picks a spread is reporting that author's assumption. Solving for the
    cost instead removes the guess: the answer is a property of the sample.

    Expressed as a fraction of entry price, because a raw price distance
    on EURUSD is not comparable with one on gold or USDJPY, and a
    fraction-of-price cost is. This project has been bitten by exactly
    that comparison before.
    """

    key: str
    resolved: int
    gross_expectancy_r: float
    average_risk: float          # price distance, in the instrument's own units
    average_entry: float
    break_even_spread_fraction: float
    #: True when the gross edge is already negative, so no cost could
    #: make it worse. Reported rather than hidden, because a "break-even
    #: spread" on a losing group is a negative number with no meaning.
    gross_is_negative: bool

    @property
    def break_even_spread_percent(self) -> float:
        return self.break_even_spread_fraction * 100.0

    @property
    def is_meaningful(self) -> bool:
        return not self.gross_is_negative and self.break_even_spread_fraction > 0.0


def break_even_cost(
    key: str,
    events: Sequence[SetupEvent],
    results: Sequence[OutcomeResult],
) -> BreakEven:
    """Solve for the round-trip cost that exactly cancels a group's edge.

    Cost in R is ``cost_price / risk_distance``, so a group whose mean
    gross expectancy is G is exactly neutral when the mean cost is also
    G. Multiplying G by the mean risk distance gives the price distance
    that does it. Converting to a fraction of the mean entry price is what
    makes the result comparable across EURUSD at 1.10 and gold at 3400.

    A group with no resolved outcomes has no expectancy and therefore no
    break-even; the fields are left at zero and ``is_meaningful`` is
    False, so a caller cannot accidentally quote a break-even for a group
    that never resolved.
    """
    if len(events) != len(results):
        raise ValueError("events and results must be the same length")

    risks: list[float] = []
    entries: list[float] = []
    r_units: list[float] = []

    for event, result in zip(events, results):
        if result.outcome not in ("target", "invalidation", "ambiguous"):
            continue
        r_units.append(
            event.risk_reward if result.outcome == "target"
            else (-1.0 if result.outcome == "invalidation" else 0.0)
        )
        risk = abs(event.entry - event.invalidation)
        if risk <= 0.0:
            continue
        risks.append(risk)
        entries.append(event.entry)

    resolved = len(r_units)
    if not resolved or not risks:
        return BreakEven(key, resolved, 0.0, 0.0, 0.0, 0.0, False)

    gross = sum(r_units) / resolved
    average_risk = sum(risks) / len(risks)
    average_entry = sum(entries) / len(entries)
    if average_entry <= 0.0:
        return BreakEven(key, resolved, gross, average_risk, 0.0, 0.0, gross < 0.0)

    fraction = gross * average_risk / average_entry
    return BreakEven(
        key=key,
        resolved=resolved,
        gross_expectancy_r=gross,
        average_risk=average_risk,
        average_entry=average_entry,
        break_even_spread_fraction=fraction,
        gross_is_negative=gross < 0.0,
    )


def format_break_even(groups: Sequence[BreakEven]) -> str:
    """Render break-even costs as a table.

    A negative gross expectancy gets its own wording rather than a
    negative spread, which would read as a real number.
    """
    columns = (
        f"{'group':<24}{'resolved':>10}{'grossR':>9}{'avgRisk':>11}"
        f"{'breakEvenSpread':>17}"
    )
    lines = [
        "break-even execution cost (the cost at which the gross edge becomes zero)",
        columns,
        "-" * len(columns),
    ]
    for item in groups:
        if item.gross_is_negative:
            verdict = "n/a (gross < 0)"
        elif not item.resolved:
            verdict = "n/a (none resolved)"
        else:
            verdict = f"{item.break_even_spread_percent:.4f}% of price"
        lines.append(
            f"{item.key:<24}{item.resolved:>10}{item.gross_expectancy_r:>9.3f}"
            f"{item.average_risk:>11.5f}  {verdict}"
        )
    lines.append("")
    lines.append(
        "breakEvenSpread is a round-trip cost: the full spread plus slippage on both "
        "sides plus commission. avgRisk is the mean stop distance in the instrument's "
        "own price units, which is why it is not comparable between symbols and the "
        "percentage is. A group's edge is negative once real costs exceed this, and no "
        "cost model was assumed to produce it."
    )
    return "\n".join(lines)


def format_cost_scenarios(
    rows: Sequence[tuple[str, float | None]],
    event_count: int,
) -> str:
    """Render assumed-spread scenarios as a table.

    The word "assumed" is in the header. Every figure in this table depends
    on a number the caller chose, and a table that merely said "spread"
    would let one of these be quoted as a measurement.
    """
    columns = f"{'assumed round-trip spread':<28}{'net expectancy':>16}"
    lines = [
        "net expectancy under ASSUMED round-trip spread (percentage of price)",
        f"{event_count} events",
        columns,
        "-" * len(columns),
    ]
    for label, value in rows:
        shown = "n/a" if value is None else f"{value:+.3f}R"
        lines.append(f"{label:<28}{shown:>16}")
    lines.append("")
    lines.append(
        "These spreads are ASSUMPTIONS supplied on the command line, not measurements. "
        "The MT5 Strategy Tester exposes no historical spread, so no figure in this "
        "table came from the broker feed. Spread only; slippage and commission are "
        "excluded, so a real cost is at least this large."
    )
    return "\n".join(lines)


def compare_cost_scenarios(
    events: Sequence[SetupEvent],
    bars,
    scenarios: Sequence[tuple[str, float]],
) -> list[tuple[str, float | None]]:
    """Re-price a whole event stream at several assumed spread levels.

    Answers a question a single break-even number cannot: not just *where*
    the edge disappears, but how fast. A group whose edge dies at 0.001% of
    price and one whose edge dies at 0.05% are both "negative in practice",
    and only the second is arguably within reach of a different execution
    setup. The scenario list is supplied by the caller, never invented here,
    because which spreads are plausible is a broker question.

    Costs are applied by rewriting each event's spread component, so the
    arithmetic is the same one :func:`expected_cost_r` uses and there is no
    second implementation to drift.
    """
    series = _as_series(bars)
    results = [evaluate_setup(event, series) for event in events]
    out: list[tuple[str, float | None]] = []
    for label, spread_fraction in scenarios:
        repriced = []
        for event in events:
            risk = abs(event.entry - event.invalidation)
            # A row with no levels has no risk and no cost, exactly as in a
            # real export. Guarding the division here is the same guard the
            # MQL5 cost model applies, so the two agree.
            cost_r = (event.entry * spread_fraction / risk) if risk > 0.0 else 0.0
            repriced.append(
                SetupEvent(**{**event.__dict__,
                              "cost_spread_price": event.entry * spread_fraction,
                              "cost_r": cost_r})
            )
        stats = summarize("scenario", repriced, results)
        out.append((label, stats.net_expectancy_r))
    return out


@dataclass(frozen=True)
class MeasuredSet:
    """Events that can be measured, plus those that provably cannot.

    An event whose symbol has no bar history is not measured at all. Silently
    scoring it against some other market's prices would produce a plausible,
    wrong number, which is the failure mode this project exists to avoid. It
    is counted and reported instead.
    """

    measurable: list[SetupEvent]
    unattributed: list[SetupEvent]

    @property
    def excluded_count(self) -> int:
        return len(self.unattributed)


def partition_by_bar_history(
    events: Sequence[SetupEvent],
    bars: BarBook,
) -> MeasuredSet:
    """Split events into those with bar history and those without."""
    measurable: list[SetupEvent] = []
    unattributed: list[SetupEvent] = []
    for event in events:
        (measurable if bars.has(event.symbol) else unattributed).append(event)
    return MeasuredSet(measurable, unattributed)


def _as_series(bars) -> BarSeries | BarBook:
    """Reuse an already-built index, or build it once for a plain list."""
    return bars if isinstance(bars, (BarSeries, BarBook)) else BarSeries.of(bars)


def group_key_of(event: SetupEvent, group: str) -> str:
    """The bucket an event belongs to, matching the --group grouper.

    The break-even table reuses the chosen grouping, so this has to agree
    with the grouper exactly. A mismatch would not raise; it would print a
    second table of different-looking numbers, which is precisely the kind
    of quiet inconsistency this project keeps catching.
    """
    if group == "setup":
        return event.setup_type
    if group == "status":
        return event.status
    if group == "instrument":
        return event.symbol or UNKNOWN_SYMBOL
    if group == "market":
        from .validation import market_of

        return market_of(event)
    return event.setup_type


def evaluate_and_summarize(
    key: str,
    events: Sequence[SetupEvent],
    bars,
) -> SetupStats:
    """Evaluate every event against one bar history, then summarize the group.

    The bar index is built once here rather than once per event. On a real
    export that is the difference between seconds and hours. ``bars`` may be a
    plain list, a :class:`BarSeries`, or a :class:`BarBook` in which case each
    event is measured against its own market's bars.
    """
    series = _as_series(bars)
    results = [evaluate_setup(event, series) for event in events]
    return summarize(key, events, results)


def _grouped(events: Sequence[SetupEvent], bars, key_of) -> dict[str, SetupStats]:
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
    """Render grouped statistics as a fixed-width text table.

    ``grossR`` is expectancy before costs, ``costR`` is the average
    round-trip cost in R, and ``netR`` is expectancy after it. ``netR``
    prints ``n/a`` for a group whose export carried no cost column, which
    is the honest reading: the number is unavailable, not zero.
    """
    columns = (
        f"{'group':<24}{'total':>7}{'tgt':>6}{'inv':>6}{'amb':>6}"
        f"{'exp':>7}{'nt':>7}{'win%':>8}{'grossR':>8}{'costR':>7}{'netR':>8}"
        f"{'MFE':>9}{'MAE':>9}{'bars':>7}"
    )
    lines = [title, columns, "-" * len(columns)]
    for key, stats in groups.items():
        net = "n/a" if stats.net_expectancy_r is None else f"{stats.net_expectancy_r:.2f}"
        cost = "n/a" if not stats.costed_resolved else f"{stats.average_cost_r:.2f}"
        lines.append(
            f"{key:<24}{stats.total:>7}{stats.targets:>6}{stats.invalidations:>6}"
            f"{stats.ambiguous:>6}{stats.expired:>7}{stats.no_trade:>7}"
            f"{stats.win_rate * 100:>7.1f}%{stats.expectancy_r:>8.2f}{cost:>7}{net:>8}"
            f"{stats.average_mfe * 100:>8.2f}%{stats.average_mae * 100:>8.2f}%"
            f"{stats.average_bars_to_exit:>7.1f}"
        )
    lines.append("")

    costed = sum(1 for stats in groups.values() if stats.costed_resolved)
    if costed == 0:
        lines.append(
            "COSTS: this export carries no cost column, so netR and costR are n/a. "
            "Every expectancy here is GROSS and cannot be compared to a broker "
            "statement. The MQL5 exporter has measured spread, slippage, and "
            "commission per row since Phase 19; re-run the export to obtain a net "
            "figure."
        )
    else:
        partial = [key for key, stats in groups.items()
                   if stats.costed_resolved and not stats.costs_available]
        lines.append(
            "COSTS: netR subtracts each event's round-trip cost in R "
            "(full measured spread + slippage on both sides + round-trip commission). "
            "An assumed cost is labelled 'assumed' in the export's cost_model column."
        )
        if partial:
            lines.append(
                "WARNING: some groups were only partially costed, so their netR is "
                f"withheld: {', '.join(partial)}."
            )

    mismatches = sum(stats.cost_mismatches for stats in groups.values())
    if mismatches:
        lines.append(
            f"WARNING: {mismatches} rows have an exported cost_r that disagrees with the "
            "value recomputed from their exported price components. The recomputed "
            "value is the one used above."
        )

    lines.append(
        "win%, grossR, costR and netR cover resolved outcomes only; expired and NO TRADE "
        "rows are excluded. MFE/MAE are price excursions, not realised P/L. Cost is "
        "charged on resolved outcomes only, because an unresolved event never paid it."
    )
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    """Print a setup report for an exported event CSV and a bar history CSV."""
    import argparse

    from .events import (
        load_price_bars,
        load_price_bars_by_symbol,
        load_setup_events,
    )
    from .outcomes import BarBook

    parser = argparse.ArgumentParser(
        prog="python -m pab_research",
        description="Summarize exported PriceActionBarByBar events.",
    )
    parser.add_argument("events_csv", help="CSV produced by the InpExportEvents option")
    parser.add_argument("bars_csv", help="CSV with open_time, high, low columns")
    parser.add_argument(
        "--group",
        choices=("setup", "status", "instrument", "market"),
        default="setup",
        help=(
            "group by setup_type, engine status, symbol, or symbol+timeframe. "
            "Use 'market' whenever the export covers more than one timeframe, "
            "since pooling M5 and H1 averages two different holding profiles."
        ),
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
        "--break-even",
        action="store_true",
        help=(
            "also report the round-trip cost at which each group's gross edge "
            "becomes zero. Use this when the export carries no cost column, "
            "since it needs no assumed spread: the answer is a property of "
            "the sample rather than of anyone's cost guess."
        ),
    )
    parser.add_argument(
        "--cost-scenario",
        dest="cost_scenarios",
        action="append",
        type=float,
        metavar="SPREAD_PERCENT",
        help=(
            "re-price the whole sample at an assumed round-trip spread, given "
            "as a PERCENT OF PRICE, and report net expectancy. Repeatable. "
            "These are assumptions, not measurements: the Strategy Tester has "
            "no historical spread to read, so nothing here is taken from the "
            "broker feed. A 0.01 value is a tenth of a pip on EURUSD."
        ),
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
    if not events:
        print("no events found")
        return 1

    # Bars are loaded per symbol whenever the event file names one. Mixing
    # markets in a single bar series is not a small error: USDJPY prices are
    # two orders of magnitude above EURUSD, so an event measured against the
    # wrong market yields a confident, meaningless number.
    symbols = {event.symbol for event in events}
    if len(symbols) > 1:
        by_symbol = load_price_bars_by_symbol(args.bars_csv)
        bars = BarBook.of(by_symbol)
        split = partition_by_bar_history(events, bars)
        events = split.measurable
        if not events:
            print(
                "no events have bar history for their own symbol; "
                f"bar file covers {sorted(by_symbol)}, events name {sorted(symbols)}"
            )
            return 1
        excluded_label = f", {split.excluded_count} events excluded (no bars for their symbol)"
        bar_label = f"{sum(len(v) for v in by_symbol.values())} bars across {len(by_symbol)} markets"
    else:
        bars = load_price_bars(args.bars_csv)
        excluded_label = ""
        bar_label = f"{len(bars)} bars"

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
                f"{bar_label}{window_label}{excluded_label}, "
                f"{result.folds_promised} folds"
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
    elif args.group == "market":
        from .validation import group_by_market

        grouper = group_by_market
    else:
        grouper = group_by_status
    title = (
        f"{len(events)} events, {bar_label}{window_label}{excluded_label}, "
        f"grouped by {args.group}"
    )
    groups = grouper(events, bars)
    print(format_report(groups, title))

    if args.break_even:
        series = _as_series(bars)
        keyed: dict[str, list[SetupEvent]] = {}
        for event in events:
            keyed.setdefault(group_key_of(event, args.group), []).append(event)
        rows = [
            break_even_cost(key, group, [evaluate_setup(e, series) for e in group])
            for key, group in sorted(keyed.items())
        ]
        print("")
        print(format_break_even(rows))

    if args.cost_scenarios:
        # Each flag is one number, so the label is derived from it rather
        # than passed separately; a label the caller typed could disagree
        # with the value it names.
        scenarios = [
            (f"{value:.3f}% of price", value / 100.0)
            for value in args.cost_scenarios
        ]
        rows = compare_cost_scenarios(events, bars, scenarios)
        print("")
        print(format_cost_scenarios(rows, len(events)))
    return 0

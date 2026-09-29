"""Outcome evaluation for an exported setup event.

The evaluator answers one question: given an event's entry, invalidation and
target, what did price do next, and when did it first touch one of the levels?

Performance note, learned the hard way
--------------------------------------
This module originally began every evaluation with a full ``sorted(...)`` scan
of the bar list. That is fine for a handful of fixture bars and catastrophic
on a real export: 72,188 events against 72,175 bars is roughly five billion
operations, and the walk-forward report times out. :class:`BarSeries` precomputes
the sorted time index once so locating the first bar at or after a decision is
a binary search instead of a sort.

Behaviour is unchanged. ``evaluate_setup`` still accepts a plain list of
:class:`~pab_research.events.PriceBar`, so existing callers and tests are
unaffected; the fast path is simply used automatically when handed a
``BarSeries``.
"""

from bisect import bisect_left
from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Sequence

from .events import PriceBar, SetupEvent

Outcome = Literal["target", "invalidation", "expired", "ambiguous", "no_trade"]


@dataclass(frozen=True)
class OutcomeResult:
    outcome: Outcome
    exit_time: datetime | None
    bars_to_exit: int | None
    mfe: float
    mae: float


@dataclass(frozen=True)
class BarSeries:
    """Bars paired with a precomputed, ascending time index."""

    bars: tuple[PriceBar, ...]
    times: tuple[datetime, ...]

    @classmethod
    def of(cls, bars: Sequence[PriceBar]) -> "BarSeries":
        """Build an index from any bar sequence, sorting it if necessary.

        Sorting here rather than in the loader means a caller may pass bars in
        arrival order and still get correct, fast evaluation. It happens once
        per report run.
        """
        ordered = sorted(bars, key=lambda bar: bar.open_time)
        return cls(tuple(ordered), tuple(bar.open_time for bar in ordered))

    def first_index_at_or_after(self, when: datetime) -> int:
        return bisect_left(self.times, when)

    def __len__(self) -> int:
        return len(self.bars)


class MissingBarHistory(LookupError):
    """Raised when an event names a market for which no bar history was given.

    This is a hard error rather than a silent fallback. Evaluating a USDJPY
    event against EURUSD bars produces plausible-looking numbers that are
    entirely meaningless, which is far worse than refusing to answer.
    """


@dataclass(frozen=True)
class BarBook:
    """Bar history for several markets, keyed by the exported ``symbol``.

    A single :class:`BarSeries` is only valid for one price scale. EURUSD at
    1.37 and USDJPY at 105 differ by two orders of magnitude, so an outcome
    computed from the wrong one is not a small error, it is a fabricated
    number. Any event whose symbol has no entry here raises
    :class:`MissingBarHistory` instead of being measured against something
    else.
    """

    series: dict[str, BarSeries]

    @classmethod
    def of(cls, by_symbol: dict[str, Sequence[PriceBar]]) -> "BarBook":
        return cls({key: BarSeries.of(value) for key, value in by_symbol.items()})

    def get(self, symbol: str) -> BarSeries:
        found = self.series.get(symbol)
        if found is None:
            raise MissingBarHistory(
                f"no bar history for symbol {symbol!r}; "
                f"have: {sorted(self.series)}"
            )
        return found

    def has(self, symbol: str) -> bool:
        return symbol in self.series

    def __len__(self) -> int:
        return len(self.series)

    def symbols(self) -> list[str]:
        return sorted(self.series)


def evaluate_setup(
    event: SetupEvent,
    bars: Sequence[PriceBar] | BarSeries | BarBook,
) -> OutcomeResult:
    if event.status == "no_trade":
        return OutcomeResult("no_trade", None, None, 0.0, 0.0)

    if isinstance(bars, BarBook):
        series = bars.get(event.symbol)
    elif isinstance(bars, BarSeries):
        series = bars
    else:
        series = BarSeries.of(bars)

    start = series.first_index_at_or_after(event.decision_time)
    if start >= len(series.bars):
        return OutcomeResult("expired", None, None, 0.0, 0.0)

    mfe = 0.0
    mae = 0.0
    for index, bar in enumerate(series.bars[start:], start=1):
        if event.direction == "long":
            favorable = (bar.high - event.entry) / event.entry
            adverse = (bar.low - event.entry) / event.entry
            target_hit = bar.high >= event.target
            invalidation_hit = bar.low <= event.invalidation
        else:
            favorable = (event.entry - bar.low) / event.entry
            adverse = (event.entry - bar.high) / event.entry
            target_hit = bar.low <= event.target
            invalidation_hit = bar.high >= event.invalidation

        mfe = max(mfe, favorable)
        mae = min(mae, adverse)

        if target_hit and invalidation_hit:
            return OutcomeResult("ambiguous", bar.open_time, index, mfe, mae)
        if invalidation_hit:
            return OutcomeResult("invalidation", bar.open_time, index, mfe, mae)
        if target_hit:
            return OutcomeResult("target", bar.open_time, index, mfe, mae)

    return OutcomeResult("expired", None, None, mfe, mae)

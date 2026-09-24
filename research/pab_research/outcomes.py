from dataclasses import dataclass
from typing import Literal

from .events import PriceBar, SetupEvent

Outcome = Literal["target", "invalidation", "expired", "ambiguous", "no_trade"]


@dataclass(frozen=True)
class OutcomeResult:
    outcome: Outcome
    exit_time: object | None
    bars_to_exit: int | None
    mfe: float
    mae: float


def evaluate_setup(event: SetupEvent, bars: list[PriceBar]) -> OutcomeResult:
    if event.status == "no_trade":
        return OutcomeResult("no_trade", None, None, 0.0, 0.0)

    future = sorted(
        (bar for bar in bars if bar.open_time >= event.decision_time),
        key=lambda bar: bar.open_time,
    )
    if not future:
        return OutcomeResult("expired", None, None, 0.0, 0.0)

    mfe = 0.0
    mae = 0.0
    for index, bar in enumerate(future, start=1):
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

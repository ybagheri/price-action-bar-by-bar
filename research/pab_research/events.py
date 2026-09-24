from dataclasses import dataclass
from datetime import datetime
from typing import Literal

Direction = Literal["long", "short", "none"]


@dataclass(frozen=True)
class PriceBar:
    open_time: datetime
    high: float
    low: float


@dataclass(frozen=True)
class SetupEvent:
    event_id: str
    direction: Direction
    bar_open_time: datetime
    bar_close_time: datetime
    confirmed_at: datetime
    decision_time: datetime
    entry: float
    invalidation: float
    target: float
    status: str = "possible"
    quality: int = 0
    risk_reward: float = 0.0
    engine_version: str = ""
    parameter_version: str = ""

    def __post_init__(self) -> None:
        validate_event_timing(self)
        if self.direction not in ("long", "short", "none"):
            raise ValueError("direction must be long, short, or none")
        if self.status == "no_trade":
            if self.direction != "none":
                raise ValueError("no_trade events must use direction none")
            return
        if self.direction == "none":
            raise ValueError("directional events require long or short direction")
        if self.entry <= 0 or self.invalidation <= 0 or self.target <= 0:
            raise ValueError("price levels must be positive")
        if self.direction == "long" and not self.invalidation < self.entry < self.target:
            raise ValueError("long levels must satisfy invalidation < entry < target")
        if self.direction == "short" and not self.target < self.entry < self.invalidation:
            raise ValueError("short levels must satisfy target < entry < invalidation")


def validate_event_timing(event: SetupEvent) -> None:
    if event.bar_open_time > event.bar_close_time:
        raise ValueError("bar_open_time must not exceed bar_close_time")
    if event.confirmed_at > event.decision_time:
        raise ValueError("confirmed_at must not exceed decision_time")
    if event.decision_time < event.bar_close_time:
        raise ValueError("decision_time must not precede bar_close_time")


def load_setup_events(path: str) -> list[SetupEvent]:
    import csv

    events: list[SetupEvent] = []
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            events.append(
                SetupEvent(
                    event_id=row["event_id"],
                    direction=row["direction"],
                    bar_open_time=datetime.fromisoformat(row["bar_open_time"]),
                    bar_close_time=datetime.fromisoformat(row["bar_close_time"]),
                    confirmed_at=datetime.fromisoformat(row["confirmed_at"]),
                    decision_time=datetime.fromisoformat(row["decision_time"]),
                    entry=float(row["entry"]),
                    invalidation=float(row["invalidation"]),
                    target=float(row["target"]),
                    status=row["status"],
                    quality=int(row["quality"]),
                    risk_reward=float(row["risk_reward"]),
                    engine_version=row["engine_version"],
                    parameter_version=row["parameter_version"],
                )
            )
    events.sort(key=lambda event: event.decision_time)
    return events

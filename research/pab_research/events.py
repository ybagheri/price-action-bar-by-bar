from dataclasses import dataclass
from datetime import datetime
from typing import Literal

Direction = Literal["long", "short", "none"]

# Mirrors SetupTypeLabel() in MQL5/Indicators/PriceActionBarByBar.mq5.
# Kept in sync deliberately: the research layer validates exported events,
# it does not re-derive them.
SETUP_TYPES = frozenset(
    {
        "none",
        "trend_pullback",
        "second_entry",
        "range_reversal",
        "failed_breakout",
        "breakout_follow_through",
        "wedge_reversal",
    }
)


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
    setup_type: str = "none"
    # ``symbol`` and ``period`` were appended to the export after the first
    # release. They default to "" so files written by an older build still
    # load, and multi-instrument grouping reports them as "unspecified"
    # instead of silently discarding those rows.
    symbol: str = ""
    period: str = ""

    def __post_init__(self) -> None:
        validate_event_timing(self)
        if self.direction not in ("long", "short", "none"):
            raise ValueError("direction must be long, short, or none")
        if self.setup_type not in SETUP_TYPES:
            raise ValueError(f"unknown setup_type {self.setup_type!r}")
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
    """Load and validate exported setup events from the MQL5 CSV.

    ``utf-8-sig`` is used because Windows tooling frequently writes a BOM, and
    a BOM on the first column name would otherwise hide ``event_id``.
    """
    import csv

    events: list[SetupEvent] = []
    with open(path, newline="", encoding="utf-8-sig") as handle:
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
                    setup_type=row.get("setup_type") or "none",
                    symbol=row.get("symbol") or "",
                    period=row.get("period") or "",
                )
            )
    events.sort(key=lambda event: event.decision_time)
    return events


def load_price_bars(path: str) -> list[PriceBar]:
    """Load outcome-evaluation bars from a CSV with open_time, high, low columns.

    The indicator does not export bars, so this reads broker or replay history
    exported separately. Only high and low are required because outcome
    evaluation never looks at open or close. Extra columns are ignored.
    """
    import csv

    bars: list[PriceBar] = []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            bars.append(
                PriceBar(
                    open_time=datetime.fromisoformat(row["open_time"]),
                    high=float(row["high"]),
                    low=float(row["low"]),
                )
            )
    bars.sort(key=lambda item: item.open_time)
    return bars

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

Direction = Literal["long", "short", "none"]

# Must contain exactly the strings SetupTypeLabel() in
# MQL5/Indicators/PriceActionBarByBar.mq5 can emit.
#
# It previously listed "none" and omitted "no_trade", so it did not mirror
# the engine at all: every no-trade event in a real export was rejected with
# "unknown setup_type 'no_trade'". Note that "none" IS what
# SetupDirectionLabel() emits, for direction - it is not a setup type.
# A test pins this set so the two cannot drift apart again unnoticed.
SETUP_TYPES = frozenset(
    {
        "no_trade",
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
    # "no_trade" is what SetupTypeLabel() emits when there is no setup, so
    # it is also the right default when the column is missing entirely.
    setup_type: str = "no_trade"
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


DELIMITERS = ("\t", ";", ",")

#: Bucket for events and bars whose symbol column is missing or empty, which
#: is the case for every export written before Phase 16. Kept here rather
#: than in validation so both the loaders and the grouping can use it without
#: importing each other.
UNKNOWN_SYMBOL = "unspecified"


def sniff_delimiter(handle) -> str:
    """Pick the CSV dialect that matches the header line actually on disk.

    MQL5's ``FileOpen(..., FILE_CSV)`` defaults to a TAB delimiter, but
    ``csv.DictReader`` defaults to a comma. Assuming the comma meant the
    loader treated a whole tab-separated line as one field and then raised
    ``KeyError: event_id`` on every real export, while passing every test,
    because the test fixtures were themselves written with Python's
    comma-defaulting writer.

    The delimiter is therefore read from the file rather than assumed, and
    the first line is pushed back so the caller still sees the header.
    """
    header = handle.readline()
    if not header:
        raise ValueError("file is empty")

    for candidate in DELIMITERS:
        if candidate in header:
            handle.seek(0)
            return candidate

    # A single-column file is legal; tab is what MQL5 would have used.
    handle.seek(0)
    return "\t"


def parse_timestamp(value: str) -> datetime:
    """Parse a timestamp from an MQL5 export or a hand-built bar file.

    Two spellings occur in practice and both are accepted:

    * ``2026-01-02 07:00:00`` — what ``IsoTimestamp`` in the MQL5 engine
      writes, and what ``datetime.fromisoformat`` understands.
    * ``2026.01.02 07:00:00`` — what ``TimeToString(..., TIME_DATE |
      TIME_SECONDS)`` writes, and what every event file exported before
      Phase 16 contains.

    The second form is not ISO-8601, so ``datetime.fromisoformat`` rejects
    it. Rejecting it would mean the research layer cannot read any export
    produced by an earlier build, which is exactly the sort of silent gap
    this project is supposed to avoid. The replacement is unambiguous:
    a dot may only ever appear as a date separator here, so a targeted
    rewrite of the date component is safe.

    A naive ``str.replace(".", "-")`` would also mangle fractional seconds
    and timezone offsets, so only the leading ``YYYY.MM.DD`` is touched.
    """
    text = value.strip()
    if not text:
        raise ValueError("empty timestamp")

    try:
        return datetime.fromisoformat(text)
    except ValueError:
        pass

    # YYYY . MM . DD <sep> time...   where <sep> is a space or "T"
    head, dot, rest = text.partition(".")
    if not dot:
        raise ValueError(f"unrecognised timestamp {value!r}")

    month, dot, rest = rest.partition(".")
    if not dot or len(head) != 4 or len(month) != 2:
        raise ValueError(f"unrecognised timestamp {value!r}")

    # ISO 8601 permits either separator, and MT5 emits the space form.
    if " " in rest:
        day, _, tail = rest.partition(" ")
        rebuilt = f"{head}-{month}-{day} {tail}"
    elif "T" in rest:
        day, _, tail = rest.partition("T")
        rebuilt = f"{head}-{month}-{day}T{tail}"
    else:
        raise ValueError(f"unrecognised timestamp {value!r}")

    if len(day) != 2:
        raise ValueError(f"unrecognised timestamp {value!r}")

    try:
        return datetime.fromisoformat(rebuilt)
    except ValueError as error:
        raise ValueError(f"unrecognised timestamp {value!r}") from error


def load_price_bars_by_symbol(path: str) -> dict[str, list[PriceBar]]:
    """Load bar history grouped by the ``symbol`` column.

    A bar file written for one market cannot be evaluated against another
    market's events, so a multi-instrument study needs the mapping kept
    intact. This returns it directly rather than flattening, because
    flattening is precisely the mistake that would be invisible afterwards.

    Rows without a ``symbol`` column, or with an empty value, are grouped
    under ``"unspecified"`` so an older single-market file still loads.
    """
    import csv

    grouped: dict[str, list[PriceBar]] = {}
    with open(path, newline="", encoding="utf-8-sig") as handle:
        delimiter = sniff_delimiter(handle)
        for row in csv.DictReader(handle, delimiter=delimiter):
            symbol = (row.get("symbol") or "").strip() or UNKNOWN_SYMBOL
            grouped.setdefault(symbol, []).append(
                PriceBar(
                    open_time=parse_timestamp(row["open_time"]),
                    high=float(row["high"]),
                    low=float(row["low"]),
                )
            )
    for bars in grouped.values():
        bars.sort(key=lambda item: item.open_time)
    return grouped


def load_setup_events(path: str) -> list[SetupEvent]:
    """Load and validate exported setup events from the MQL5 CSV.

    ``utf-8-sig`` is used because Windows tooling frequently writes a BOM, and
    a BOM on the first column name would otherwise hide ``event_id``.
    """
    import csv

    events: list[SetupEvent] = []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        delimiter = sniff_delimiter(handle)
        for row in csv.DictReader(handle, delimiter=delimiter):
            events.append(
                SetupEvent(
                    event_id=row["event_id"],
                    direction=row["direction"],
                    bar_open_time=parse_timestamp(row["bar_open_time"]),
                    bar_close_time=parse_timestamp(row["bar_close_time"]),
                    confirmed_at=parse_timestamp(row["confirmed_at"]),
                    decision_time=parse_timestamp(row["decision_time"]),
                    entry=float(row["entry"]),
                    invalidation=float(row["invalidation"]),
                    target=float(row["target"]),
                    status=row["status"],
                    quality=int(row["quality"]),
                    risk_reward=float(row["risk_reward"]),
                    engine_version=row["engine_version"],
                    parameter_version=row["parameter_version"],
                    setup_type=row.get("setup_type") or "no_trade",
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
        delimiter = sniff_delimiter(handle)
        for row in csv.DictReader(handle, delimiter=delimiter):
            bars.append(
                PriceBar(
                    open_time=parse_timestamp(row["open_time"]),
                    high=float(row["high"]),
                    low=float(row["low"]),
                )
            )
    bars.sort(key=lambda item: item.open_time)
    return bars

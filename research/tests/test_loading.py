"""Edge-case tests for the loader boundary and event validation.

The cases here are the ones that only appear when the input is
broken or adversarial: duplicated bar timestamps, an event whose
levels are on the wrong side of entry, a bar that precedes the
decision, and an empty file. Every one of them must fail loudly
or be ignored for the right reason — a quiet wrong number is the
exact failure mode this project's measurement work exists to avoid.
"""

import csv
import os
import tempfile
import unittest
from datetime import datetime, timedelta

from pab_research import (
    PriceBar,
    SetupEvent,
    evaluate_setup,
    expected_cost_r,
    filter_window,
    load_price_bars,
    load_price_bars_by_symbol,
    load_setup_events,
)

START = datetime(2026, 1, 1, 12, 0)


def make_event(**overrides):
    values = {
        "event_id": "e1",
        "direction": "long",
        "bar_open_time": START,
        "bar_close_time": START + timedelta(minutes=1),
        "confirmed_at": START + timedelta(minutes=1),
        "decision_time": START + timedelta(minutes=1),
        "entry": 100.0,
        "invalidation": 98.0,
        "target": 104.0,
        "status": "possible",
        "quality": 70,
        "risk_reward": 2.0,
    }
    values.update(overrides)
    return SetupEvent(**values)


BAR_FIELDS = ["open_time", "high", "low"]


def write_bar_csv(directory, rows, name="bars.csv", symbol_column=False):
    fields = BAR_FIELDS + (["symbol"] if symbol_column else [])
    path = os.path.join(directory, name)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return path


EVENT_FIELDS = [
    "event_id",
    "direction",
    "setup_type",
    "status",
    "bar_open_time",
    "bar_close_time",
    "confirmed_at",
    "decision_time",
    "entry",
    "invalidation",
    "target",
    "risk_reward",
    "quality",
    "engine_version",
    "parameter_version",
]


def write_event_csv(directory, rows, name="events.csv"):
    path = os.path.join(directory, name)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=EVENT_FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return path


def event_row(minutes, event_id="e1"):
    decision = START + timedelta(minutes=minutes)
    return {
        "event_id": event_id,
        "direction": "long",
        "setup_type": "second_entry",
        "status": "possible",
        "bar_open_time": (decision - timedelta(minutes=1)).isoformat(),
        "bar_close_time": decision.isoformat(),
        "confirmed_at": decision.isoformat(),
        "decision_time": decision.isoformat(),
        "entry": "100",
        "invalidation": "98",
        "target": "104",
        "risk_reward": "2",
        "quality": "70",
        "engine_version": "1.50",
        "parameter_version": "q55",
    }


class DuplicateTimestampTests(unittest.TestCase):
    def test_a_duplicated_bar_is_rejected_by_the_single_market_loader(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_bar_csv(
                directory,
                [
                    {"open_time": "2026-01-01 12:01:00", "high": 1.1, "low": 1.0},
                    {"open_time": "2026-01-01 12:02:00", "high": 1.1, "low": 1.0},
                    {"open_time": "2026-01-01 12:02:00", "high": 1.2, "low": 0.9},
                ],
            )
            with self.assertRaisesRegex(ValueError, "duplicate open_time"):
                load_price_bars(path)

    def test_a_duplicated_bar_is_rejected_per_symbol(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_bar_csv(
                directory,
                [
                    {"open_time": "2026-01-01 12:01:00", "high": 1.1, "low": 1.0, "symbol": "EURUSD"},
                    {"open_time": "2026-01-01 12:01:00", "high": 1.2, "low": 0.9, "symbol": "EURUSD"},
                ],
                symbol_column=True,
            )
            with self.assertRaisesRegex(ValueError, "EURUSD"):
                load_price_bars_by_symbol(path)

    def test_the_same_timestamp_in_two_markets_is_not_a_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_bar_csv(
                directory,
                [
                    {"open_time": "2026-01-01 12:01:00", "high": 1.1, "low": 1.0, "symbol": "EURUSD"},
                    {"open_time": "2026-01-01 12:01:00", "high": 105.0, "low": 104.0, "symbol": "USDJPY"},
                ],
                symbol_column=True,
            )
            grouped = load_price_bars_by_symbol(path)
        self.assertEqual(sorted(grouped), ["EURUSD", "USDJPY"])
        self.assertEqual(len(grouped["EURUSD"]), 1)
        self.assertEqual(len(grouped["USDJPY"]), 1)


class LookAheadBiasTests(unittest.TestCase):
    def test_a_bar_before_the_decision_is_never_used(self):
        # This bar would have hit the target (high 200 >> 104),
        # but it opens BEFORE the decision was taken, so it must
        # not count: only bars at or after decision_time are in
        # play. A look-ahead bug would report "target" here.
        early = PriceBar(START - timedelta(minutes=5), 200.0, 90.0)
        after = PriceBar(START + timedelta(minutes=1), 101.0, 99.0)
        result = evaluate_setup(make_event(), [early, after])
        self.assertEqual(result.outcome, "expired")
        self.assertAlmostEqual(result.mfe, (101.0 - 100.0) / 100.0)

    def test_an_empty_bar_history_reports_expired(self):
        result = evaluate_setup(make_event(), [])
        self.assertEqual(result.outcome, "expired")
        self.assertIsNone(result.exit_time)


class EventLevelValidationTests(unittest.TestCase):
    def test_a_long_with_a_target_below_entry_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalidation < entry < target"):
            make_event(target=99.0)

    def test_a_long_with_a_stop_above_entry_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalidation < entry < target"):
            make_event(invalidation=101.0)

    def test_a_short_with_levels_on_the_wrong_side_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "target < entry < invalidation"):
            make_event(direction="short", target=104.0, invalidation=98.0)

    def test_a_valid_short_is_accepted(self):
        event = make_event(direction="short", target=96.0, invalidation=102.0)
        self.assertEqual(event.direction, "short")

    def test_a_no_trade_row_must_not_carry_a_direction(self):
        with self.assertRaisesRegex(ValueError, "no_trade events"):
            make_event(status="no_trade", direction="long")

    def test_a_directional_row_must_not_use_none(self):
        with self.assertRaisesRegex(ValueError, "directional events"):
            make_event(direction="none")

    def test_non_positive_levels_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "positive"):
            make_event(entry=0.0)

    def test_a_no_trade_row_has_no_levels(self):
        event = make_event(
            status="no_trade",
            direction="none",
            entry=0.0,
            invalidation=0.0,
            target=0.0,
        )
        self.assertFalse(event.has_costs)
        self.assertEqual(expected_cost_r(event), 0.0)


class LoaderEdgeCaseTests(unittest.TestCase):
    def test_an_empty_file_is_an_error_not_an_empty_report(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "events.csv")
            open(path, "w").close()
            with self.assertRaisesRegex(ValueError, "empty"):
                load_setup_events(path)

    def test_a_header_only_file_loads_as_zero_events(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_event_csv(directory, [])
            self.assertEqual(load_setup_events(path), [])

    def test_events_are_sorted_by_decision_time_on_load(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_event_csv(
                directory,
                [event_row(30, "later"), event_row(5, "earlier")],
            )
            events = load_setup_events(path)
        self.assertEqual([event.event_id for event in events], ["earlier", "later"])

    def test_filter_window_bounds_are_inclusive(self):
        # Every event is built at its own decision instant,
        # with the bar timestamps kept consistent with it, so
        # the window test is not also a timing-validation test.
        def at(minutes, event_id):
            decision = START + timedelta(minutes=minutes)
            return make_event(
                event_id=event_id,
                bar_open_time=decision - timedelta(minutes=1),
                bar_close_time=decision,
                confirmed_at=decision,
                decision_time=decision,
            )

        events = [at(0, "a"), at(1, "b"), at(2, "c")]
        kept = filter_window(events, START, START + timedelta(minutes=1))
        self.assertEqual([event.event_id for event in kept], ["a", "b"])

    def test_filter_window_rejects_an_impossible_window(self):
        with self.assertRaisesRegex(ValueError, "start must not be later"):
            filter_window([make_event()], START + timedelta(minutes=1), START)


if __name__ == "__main__":
    unittest.main()

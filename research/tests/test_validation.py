import unittest
from datetime import datetime, timedelta

from pab_research import (
    IN_SAMPLE,
    OUT_OF_SAMPLE,
    PriceBar,
    SetupEvent,
    filter_window,
    group_by_instrument,
    instrument_walk_forward,
    load_setup_events,
    split_walk_forward,
)
from pab_research.validation import UNKNOWN_SYMBOL, format_fold_report

START = datetime(2026, 1, 1, 0, 0)


def make_event(index, *, symbol="EURUSD", minutes=None, **overrides):
    """One long setup that resolves on the very next bar."""
    base = START + timedelta(hours=minutes if minutes is not None else index)
    values = {
        "event_id": f"e{index}",
        "direction": "long",
        "bar_open_time": base,
        "bar_close_time": base + timedelta(minutes=1),
        "confirmed_at": base + timedelta(minutes=1),
        "decision_time": base + timedelta(minutes=1),
        "entry": 100.0,
        "invalidation": 98.0,
        "target": 104.0,
        "status": "possible",
        "quality": 70,
        "risk_reward": 2.0,
        "setup_type": "second_entry",
        "symbol": symbol,
    }
    values.update(overrides)
    return SetupEvent(**values)


def make_bars(winners, losers=()):
    """One future bar per event: winners reach the target, losers hit the stop."""
    bars = [PriceBar(event.decision_time, 105.0, 99.0) for event in winners]
    bars += [PriceBar(event.decision_time, 101.0, 97.0) for event in losers]
    return bars


class WalkForwardSplitTests(unittest.TestCase):
    def test_rejects_fewer_than_two_folds(self):
        events = [make_event(0)]
        with self.assertRaisesRegex(ValueError, "at least 2"):
            split_walk_forward(events, make_bars(events), 1)

    def test_rejects_empty_event_stream(self):
        with self.assertRaisesRegex(ValueError, "no events"):
            split_walk_forward([], [], 4)

    def test_rejects_more_folds_than_events(self):
        events = [make_event(0), make_event(1)]
        with self.assertRaisesRegex(ValueError, "cannot build 4 folds"):
            split_walk_forward(events, make_bars(events), 4)

    def test_rejects_non_positive_min_resolved(self):
        events = [make_event(i) for i in range(4)]
        with self.assertRaisesRegex(ValueError, "min_resolved"):
            split_walk_forward(events, make_bars(events), 2, 0)

    def test_blocks_alternate_and_cover_every_event_exactly_once(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        result = split_walk_forward(events, bars, 4)

        self.assertEqual(
            [fold.role for fold in result.folds],
            [IN_SAMPLE, OUT_OF_SAMPLE, IN_SAMPLE, OUT_OF_SAMPLE],
        )
        # Contiguous, non-overlapping, and nothing dropped.
        self.assertEqual(
            result.in_sample.total + result.out_of_sample.total, len(events)
        )
        self.assertEqual(
            result.in_sample.total + result.out_of_sample.total,
            sum(fold.stats.total for fold in result.folds),
        )

    def test_sorts_by_decision_time_before_splitting(self):
        shuffled = [make_event(i) for i in (3, 0, 7, 1, 6, 2, 5, 4)]
        bars = make_bars(shuffled)
        result = split_walk_forward(shuffled, bars, 4)

        ordered = sorted(shuffled, key=lambda event: event.decision_time)
        for fold in result.folds:
            self.assertLessEqual(fold.first_decision, fold.last_decision)
        self.assertEqual(result.folds[0].first_decision, ordered[0].decision_time)
        self.assertEqual(result.folds[-1].last_decision, ordered[-1].decision_time)

    def test_folds_are_chronological_and_do_not_overlap(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        result = split_walk_forward(events, bars, 4)
        for earlier, later in zip(result.folds, result.folds[1:]):
            self.assertLess(earlier.last_decision, later.first_decision)

    def test_first_fold_is_in_sample_and_second_is_out_of_sample(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        result = split_walk_forward(events, bars, 4)
        self.assertTrue(result.folds[0].is_in_sample)
        self.assertFalse(result.folds[1].is_in_sample)
        self.assertEqual(result.folds_promised, 4)


class DegradationTests(unittest.TestCase):
    def test_in_sample_wins_and_out_of_sample_loses_reports_negative_degradation(self):
        early = [make_event(i) for i in range(4)]
        late = [make_event(i) for i in range(4, 8)]
        events = early + late
        # A 2-fold split puts the winners in the in-sample block and the
        # losers in the out-of-sample block.
        bars = make_bars(early, late)
        result = split_walk_forward(events, bars, 2, min_resolved=1)

        self.assertGreater(result.in_sample.expectancy_r, 0.0)
        self.assertLess(result.out_of_sample.expectancy_r, 0.0)
        self.assertLess(result.expectancy_degradation_r, 0.0)
        self.assertLess(result.win_rate_degradation, 0.0)

    def test_uniform_sample_reports_zero_degradation(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        result = split_walk_forward(events, bars, 4, min_resolved=1)

        self.assertAlmostEqual(result.expectancy_degradation_r, 0.0)
        self.assertAlmostEqual(result.win_rate_degradation, 0.0)
        self.assertTrue(result.reliable)

    def test_unreliable_when_out_of_sample_resolves_too_few_events(self):
        events = [make_event(i) for i in range(8)]
        # Only the first three events get future bars, and all three fall in
        # the in-sample block of a 2-fold split.
        bars = make_bars(events[:3])
        result = split_walk_forward(events, bars, 2, min_resolved=3)

        self.assertEqual(result.in_sample.resolved, 3)
        self.assertEqual(result.out_of_sample.resolved, 0)
        self.assertFalse(result.reliable)
        self.assertIn("out-of-sample resolved 0 < 3", result.reason)

    def test_degradation_is_direction_agnostic(self):
        early = [make_event(i) for i in range(4)]
        late = [make_event(i) for i in range(4, 8)]
        bars = make_bars(late, early)
        result = split_walk_forward(early + late, bars, 2, min_resolved=1)

        self.assertGreater(result.expectancy_degradation_r, 0.0)


class InstrumentGroupingTests(unittest.TestCase):
    def test_groups_by_exported_symbol(self):
        events = [
            make_event(0, symbol="EURUSD"),
            make_event(1, symbol="EURUSD"),
            make_event(2, symbol="GBPUSD"),
        ]
        bars = make_bars(events)
        groups = group_by_instrument(events, bars)

        self.assertEqual(sorted(groups), ["EURUSD", "GBPUSD"])
        self.assertEqual(groups["EURUSD"].total, 2)
        self.assertEqual(groups["GBPUSD"].total, 1)

    def test_events_without_symbol_are_reported_not_dropped(self):
        events = [make_event(0, symbol=""), make_event(1, symbol="EURUSD")]
        bars = make_bars(events)
        groups = group_by_instrument(events, bars)

        self.assertEqual(groups[UNKNOWN_SYMBOL].total, 1)
        self.assertEqual(groups["EURUSD"].total, 1)
        self.assertEqual(sum(group.total for group in groups.values()), 2)

    def test_per_instrument_walk_forward_covers_every_symbol(self):
        events = [make_event(i, symbol="EURUSD") for i in range(4)]
        events += [make_event(i, symbol="GBPUSD") for i in range(4, 8)]
        bars = make_bars(events)
        results = instrument_walk_forward(events, bars, 4, min_resolved=1)

        self.assertEqual(sorted(results), ["EURUSD", "GBPUSD"])
        for result in results.values():
            self.assertEqual(result.in_sample.total + result.out_of_sample.total, 4)

    def test_symbol_too_small_for_requested_folds_falls_back_to_two(self):
        events = [make_event(i, symbol="EURUSD") for i in range(6)]
        events += [make_event(i, symbol="GBPUSD") for i in range(6, 8)]
        bars = make_bars(events)
        results = instrument_walk_forward(events, bars, 4, min_resolved=1)

        self.assertEqual(results["EURUSD"].folds_promised, 4)
        self.assertEqual(results["GBPUSD"].folds_promised, 2)


class LoaderCompatibilityTests(unittest.TestCase):
    def test_rows_without_symbol_column_still_load(self):
        import csv
        import os
        import tempfile

        path = os.path.join(tempfile.mkdtemp(), "events.csv")
        with open(path, "w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
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
            )
            writer.writerow(
                [
                    "e1",
                    "long",
                    "second_entry",
                    "probable",
                    "2026-01-01T00:00:00",
                    "2026-01-01T00:01:00",
                    "2026-01-01T00:01:00",
                    "2026-01-01T00:01:00",
                    "100",
                    "98",
                    "104",
                    "2",
                    "70",
                    "1",
                    "p",
                ]
            )

        events = load_setup_events(path)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].symbol, "")
        self.assertEqual(events[0].period, "")


class FoldReportTests(unittest.TestCase):
    def test_report_names_the_degradation_and_reliability(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        text = format_fold_report(split_walk_forward(events, bars, 4, min_resolved=1))

        self.assertIn("gross expectancy degradation", text)
        self.assertIn("net expectancy degradation", text)
        self.assertIn("reliable: yes", text)
        self.assertIn("not a profitability claim", text)

    def test_report_flags_an_unreliable_result(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events[:3])
        text = format_fold_report(split_walk_forward(events, bars, 2, min_resolved=3))

        self.assertIn("reliable: no", text)

    def test_report_shows_the_decision_time_span_of_each_fold(self):
        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)
        result = split_walk_forward(events, bars, 4, min_resolved=1)
        text = format_fold_report(result)

        self.assertIn("decision-time span per fold", text)
        for fold in result.folds:
            self.assertIn(fold.span_label, text)


class WindowFilterTests(unittest.TestCase):
    def test_keeps_only_events_inside_the_window(self):
        events = [make_event(i) for i in range(8)]
        # Boundaries are taken from real decision_times so the fixture's
        # one-minute decision offset cannot make this test ambiguous.
        kept = filter_window(events, events[2].decision_time, events[4].decision_time)

        self.assertEqual([event.event_id for event in kept], ["e2", "e3", "e4"])

    def test_bounds_are_inclusive(self):
        events = [make_event(i) for i in range(4)]
        kept = filter_window(
            events,
            events[1].decision_time,
            events[2].decision_time,
        )
        self.assertEqual([event.event_id for event in kept], ["e1", "e2"])

    def test_unbounded_on_either_side(self):
        events = [make_event(i) for i in range(8)]
        self.assertEqual(
            len(filter_window(events, start=events[5].decision_time)), 3
        )
        self.assertEqual(len(filter_window(events, end=events[1].decision_time)), 2)
        self.assertEqual(len(filter_window(events)), 8)

    def test_rejects_an_inverted_window(self):
        events = [make_event(i) for i in range(4)]
        with self.assertRaisesRegex(ValueError, "must not be later"):
            filter_window(events, START + timedelta(hours=5), START)

    def test_result_is_sorted_by_decision_time(self):
        events = [make_event(i) for i in (4, 0, 3, 1)]
        kept = filter_window(events)
        self.assertEqual(
            [event.decision_time for event in kept],
            sorted(event.decision_time for event in kept),
        )

    def test_filters_on_decision_time_not_bar_open_time(self):
        # An event opening at 00:00 but decided at 00:01 must fall in the
        # 00:01 window, not the 00:00 one.
        events = [make_event(0)]
        self.assertEqual(event_decision(events[0]), events[0].bar_open_time + timedelta(minutes=1))
        self.assertEqual(filter_window(events, start=events[0].decision_time), events)
        self.assertEqual(
            filter_window(events, end=events[0].bar_open_time), []
        )


def event_decision(event):
    return event.decision_time


class CommandLineTests(unittest.TestCase):
    def _write(self, directory):
        import csv
        import os

        events = [make_event(i) for i in range(8)]
        bars = make_bars(events)

        events_path = os.path.join(directory, "events.csv")
        with open(events_path, "w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
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
                    "symbol",
                    "period",
                ]
            )
            for event in events:
                writer.writerow(
                    [
                        event.event_id,
                        event.direction,
                        event.setup_type,
                        event.status,
                        event.bar_open_time.isoformat(),
                        event.bar_close_time.isoformat(),
                        event.confirmed_at.isoformat(),
                        event.decision_time.isoformat(),
                        event.entry,
                        event.invalidation,
                        event.target,
                        event.risk_reward,
                        event.quality,
                        "1.40",
                        "p",
                        event.symbol,
                        "M5",
                    ]
                )

        bars_path = os.path.join(directory, "bars.csv")
        with open(bars_path, "w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["open_time", "high", "low"])
            for bar in bars:
                writer.writerow([bar.open_time.isoformat(), bar.high, bar.low])
        return events_path, bars_path

    def test_window_flag_narrows_the_report(self):
        import contextlib
        import io
        import tempfile

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path, bars_path = self._write(directory)
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = main(
                    [
                        events_path,
                        bars_path,
                        "--from",
                        (START + timedelta(hours=2)).isoformat(),
                    ]
                )
        self.assertEqual(code, 0)
        self.assertIn("6 events", buffer.getvalue())
        self.assertIn("window", buffer.getvalue())

    def test_empty_window_reports_an_error_instead_of_an_empty_table(self):
        import contextlib
        import io
        import tempfile

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path, bars_path = self._write(directory)
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = main(
                    [
                        events_path,
                        bars_path,
                        "--from",
                        (START + timedelta(days=3650)).isoformat(),
                    ]
                )
        self.assertEqual(code, 1)
        self.assertIn("no events in the requested window", buffer.getvalue())

    def test_inverted_window_reports_an_error(self):
        import contextlib
        import io
        import tempfile

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path, bars_path = self._write(directory)
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = main(
                    [
                        events_path,
                        bars_path,
                        "--from",
                        (START + timedelta(hours=5)).isoformat(),
                        "--to",
                        START.isoformat(),
                    ]
                )
        self.assertEqual(code, 1)
        self.assertIn("invalid window", buffer.getvalue())

    def test_walk_forward_header_names_the_fold_count(self):
        import contextlib
        import io
        import tempfile

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path, bars_path = self._write(directory)
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = main(
                    [events_path, bars_path, "--walk-forward", "4"]
                )
        self.assertEqual(code, 0)
        self.assertIn("8 events", buffer.getvalue())
        self.assertIn("4 folds", buffer.getvalue())
        self.assertIn("decision-time span per fold", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()

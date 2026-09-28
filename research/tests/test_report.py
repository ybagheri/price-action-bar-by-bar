import csv
import os
import tempfile
import unittest
from datetime import datetime, timedelta

from pab_research import (
    PriceBar,
    SetupEvent,
    evaluate_and_summarize,
    format_report,
    group_by_setup,
    group_by_status,
    load_price_bars,
    load_setup_events,
    summarize,
)
from pab_research.outcomes import OutcomeResult

START = datetime(2026, 1, 1, 12, 0)

#: Mirrors the MQL5 export header in PriceActionBarByBar.mq5.
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

EVENT_ROW = {
    "event_id": "e1",
    "direction": "long",
    "setup_type": "second_entry",
    "status": "probable",
    "bar_open_time": START.isoformat(),
    "bar_close_time": (START + timedelta(minutes=1)).isoformat(),
    "confirmed_at": (START + timedelta(minutes=1)).isoformat(),
    "decision_time": (START + timedelta(minutes=1)).isoformat(),
    "entry": "100",
    "invalidation": "98",
    "target": "104",
    "risk_reward": "2",
    "quality": "70",
    "engine_version": "1",
    "parameter_version": "p",
}


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
        "setup_type": "second_entry",
    }
    values.update(overrides)
    return SetupEvent(**values)


def bar(minutes, high, low):
    return PriceBar(START + timedelta(minutes=minutes), high, low)


def target_result(**overrides):
    values = {
        "outcome": "target",
        "exit_time": START + timedelta(minutes=3),
        "bars_to_exit": 2,
        "mfe": 0.05,
        "mae": -0.01,
    }
    values.update(overrides)
    return OutcomeResult(**values)


def loss_result(**overrides):
    values = {
        "outcome": "invalidation",
        "exit_time": START + timedelta(minutes=2),
        "bars_to_exit": 1,
        "mfe": 0.0,
        "mae": -0.02,
    }
    values.update(overrides)
    return OutcomeResult(**values)


def no_trade_event(**overrides):
    values = {
        "event_id": "nt",
        "direction": "none",
        "entry": 0.0,
        "invalidation": 0.0,
        "target": 0.0,
        "status": "no_trade",
        "quality": 0,
        "risk_reward": 0.0,
        "setup_type": "none",
    }
    values.update(overrides)
    return make_event(**values)


class SummaryTests(unittest.TestCase):
    def test_rejects_misaligned_inputs(self):
        with self.assertRaisesRegex(ValueError, "same length"):
            summarize("g", [make_event()], [])

    def test_rejects_unknown_outcome(self):
        with self.assertRaisesRegex(ValueError, "unexpected outcome"):
            summarize("g", [make_event()], [target_result(outcome="mystery")])

    def test_win_rate_and_expectancy_use_resolved_outcomes_only(self):
        events = [
            make_event(),
            make_event(),
            make_event(),
            no_trade_event(),
        ]
        results = [
            target_result(),
            loss_result(),
            target_result(outcome="expired", exit_time=None, bars_to_exit=None),
            target_result(outcome="no_trade", exit_time=None, bars_to_exit=None, mfe=0.0, mae=0.0),
        ]
        stats = summarize("g", events, results)

        self.assertEqual(stats.total, 4)
        self.assertEqual(stats.targets, 1)
        self.assertEqual(stats.invalidations, 1)
        self.assertEqual(stats.expired, 1)
        self.assertEqual(stats.no_trade, 1)
        self.assertEqual(stats.resolved, 2)
        self.assertAlmostEqual(stats.win_rate, 0.5)
        # +2R target and -1R stop average to +0.5R across the two resolved rows.
        self.assertAlmostEqual(stats.expectancy_r, 0.5)

    def test_ambiguous_counts_as_resolved_and_zero_r(self):
        events = [make_event(), make_event()]
        results = [target_result(), target_result(outcome="ambiguous")]
        stats = summarize("g", events, results)

        self.assertEqual(stats.ambiguous, 1)
        self.assertEqual(stats.resolved, 2)
        self.assertAlmostEqual(stats.win_rate, 0.5)
        self.assertAlmostEqual(stats.expectancy_r, 1.0)

    def test_expectancy_uses_each_event_reward_risk(self):
        events = [make_event(risk_reward=4.0), make_event(risk_reward=0.5)]
        results = [target_result(), loss_result()]
        stats = summarize("g", events, results)
        self.assertAlmostEqual(stats.expectancy_r, 1.5)

    def test_empty_group_reports_zero_rather_than_dividing(self):
        stats = summarize("g", [], [])
        self.assertEqual(stats.total, 0)
        self.assertEqual(stats.win_rate, 0.0)
        self.assertEqual(stats.expectancy_r, 0.0)

    def test_averages_are_measured_over_recorded_excursions(self):
        events = [make_event(), make_event()]
        results = [target_result(mfe=0.04, mae=-0.01), loss_result(mfe=0.01, mae=-0.03)]
        stats = summarize("g", events, results)
        self.assertAlmostEqual(stats.average_mfe, 0.025)
        self.assertAlmostEqual(stats.average_mae, -0.02)
        self.assertAlmostEqual(stats.average_bars_to_exit, 1.5)


class GroupingTests(unittest.TestCase):
    def setUp(self):
        self.bars = [bar(0, 101.0, 99.0), bar(1, 105.0, 100.0)]

    def test_groups_by_setup_type(self):
        events = [
            make_event(setup_type="second_entry"),
            make_event(setup_type="second_entry"),
            make_event(setup_type="failed_breakout"),
        ]
        groups = group_by_setup(events, self.bars)

        self.assertEqual(list(groups), ["failed_breakout", "second_entry"])
        self.assertEqual(groups["second_entry"].total, 2)
        self.assertEqual(groups["failed_breakout"].total, 1)

    def test_groups_by_status(self):
        events = [
            make_event(status="probable"),
            make_event(status="possible"),
            make_event(status="probable"),
        ]
        groups = group_by_status(events, self.bars)
        self.assertEqual(groups["probable"].total, 2)
        self.assertEqual(groups["possible"].total, 1)

    def test_no_trade_rows_are_counted_not_dropped(self):
        events = [
            make_event(setup_type="second_entry"),
            no_trade_event(),
            no_trade_event(event_id="nt2"),
        ]
        groups = group_by_setup(events, self.bars)
        self.assertEqual(sum(group.total for group in groups.values()), 3)
        self.assertEqual(groups["second_entry"].total, 1)
        self.assertEqual(groups["second_entry"].no_trade, 0)
        self.assertEqual(groups["none"].total, 2)
        self.assertEqual(groups["none"].no_trade, 2)
        self.assertEqual(groups["none"].resolved, 0)

    def test_evaluate_and_summarize_uses_outcome_evaluator(self):
        events = [make_event(setup_type="trend_pullback")]
        groups = group_by_setup(events, self.bars)
        self.assertEqual(groups["trend_pullback"].targets, 1)

    def test_expired_when_no_future_bars_exist(self):
        stats = evaluate_and_summarize("g", [make_event()], [])
        self.assertEqual(stats.expired, 1)
        self.assertEqual(stats.resolved, 0)
        self.assertEqual(stats.expectancy_r, 0.0)

    def test_format_report_mentions_its_own_limits(self):
        groups = group_by_setup([make_event()], self.bars)
        text = format_report(groups)
        self.assertIn("second_entry", text)
        self.assertIn("resolved outcomes only", text)
        self.assertIn("commission", text)


class EventContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def _write_events_csv(self, overrides, drop=()):
        row = {name: value for name, value in EVENT_ROW.items() if name not in drop}
        row.update(overrides)
        path = os.path.join(self.tmp.name, "events.csv")
        with open(path, "w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=[n for n in EVENT_FIELDS if n in row])
            writer.writeheader()
            writer.writerow(row)
        return path

    def test_rejects_unknown_setup_type(self):
        with self.assertRaisesRegex(ValueError, "setup_type"):
            make_event(setup_type="moon_phase")

    def test_accepts_every_setup_type_the_engine_exports(self):
        for name in (
            "none",
            "trend_pullback",
            "second_entry",
            "range_reversal",
            "failed_breakout",
            "breakout_follow_through",
            "wedge_reversal",
        ):
            self.assertEqual(make_event(setup_type=name).setup_type, name)

    def test_loads_setup_type_from_csv(self):
        path = self._write_events_csv({"setup_type": "wedge_reversal"})
        events = load_setup_events(path)
        self.assertEqual(events[0].setup_type, "wedge_reversal")

    def test_csv_without_setup_type_column_defaults_to_none(self):
        path = self._write_events_csv({}, drop=("setup_type",))
        events = load_setup_events(path)
        self.assertEqual(events[0].setup_type, "none")

    def test_csv_with_utf8_bom_is_readable(self):
        path = os.path.join(self.tmp.name, "bom_events.csv")
        fields = [name for name in EVENT_FIELDS]
        with open(path, "w", newline="", encoding="utf-8-sig") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            writer.writerow(EVENT_ROW)

        events = load_setup_events(path)
        self.assertEqual(events[0].event_id, "e1")
        self.assertEqual(events[0].setup_type, "second_entry")

    def test_loads_price_bars_sorted_by_time(self):
        import csv

        path = os.path.join(self.tmp.name, "bars.csv")
        with open(path, "w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=["open_time", "high", "low", "close"])
            writer.writeheader()
            writer.writerow({"open_time": (START + timedelta(minutes=5)).isoformat(),
                             "high": 105, "low": 100, "close": 104})
            writer.writerow({"open_time": START.isoformat(), "high": 101, "low": 99, "close": 100})

        bars = load_price_bars(path)
        self.assertEqual([item.open_time for item in bars],
                         [START, START + timedelta(minutes=5)])

    def test_cli_prints_report_for_exported_files(self):
        import csv
        from contextlib import redirect_stdout
        from io import StringIO

        from pab_research.report import main

        events_path = os.path.join(self.tmp.name, "events.csv")
        with open(events_path, "w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(EVENT_ROW))
            writer.writeheader()
            writer.writerow(EVENT_ROW)

        bars_path = os.path.join(self.tmp.name, "bars.csv")
        with open(bars_path, "w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=["open_time", "high", "low"])
            writer.writeheader()
            writer.writerow({"open_time": (START + timedelta(minutes=1)).isoformat(),
                             "high": 105, "low": 100})
            writer.writerow({"open_time": (START + timedelta(minutes=2)).isoformat(),
                             "high": 106, "low": 101})

        buffer = StringIO()
        with redirect_stdout(buffer):
            exit_code = main([events_path, bars_path])
        output = buffer.getvalue()

        self.assertEqual(exit_code, 0)
        self.assertIn("second_entry", output)
        self.assertIn("1 events, 2 bars", output)

    def test_cli_reports_empty_export(self):
        import csv
        from contextlib import redirect_stdout
        from io import StringIO

        from pab_research.report import main

        events_path = os.path.join(self.tmp.name, "empty_events.csv")
        with open(events_path, "w", newline="", encoding="utf-8") as stream:
            csv.DictWriter(stream, fieldnames=list(EVENT_ROW)).writeheader()

        bars_path = os.path.join(self.tmp.name, "empty_bars.csv")
        with open(bars_path, "w", newline="", encoding="utf-8") as stream:
            csv.DictWriter(stream, fieldnames=["open_time", "high", "low"]).writeheader()

        buffer = StringIO()
        with redirect_stdout(buffer):
            exit_code = main([events_path, bars_path])
        self.assertEqual(exit_code, 1)
        self.assertIn("no events", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()

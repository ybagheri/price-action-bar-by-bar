"""Tests for the Phase 19 cost model.

Everything measured before Phase 19 was gross, and the measured edge was
around +0.02R while a realistic EURUSD spread against a typical stop is
several tenths of an R. These tests pin the arithmetic that decides
whether the net figure survives, and — more importantly — pin the cases
where the honest answer is "unavailable" rather than a number.

The recurring theme: a missing cost must never read as a zero cost. That
mistake produces a plausible report, not an error, which is why it needs
a test rather than a code review.
"""

import csv
import os
import tempfile
import unittest
from datetime import datetime, timedelta

from pab_research import (
    PriceBar,
    SetupEvent,
    break_even_cost,
    expected_cost_r,
    filter_window,
    format_break_even,
    format_fold_report,
    group_by_setup,
    load_setup_events,
    split_walk_forward,
    summarize,
)
from pab_research.outcomes import OutcomeResult

START = datetime(2026, 1, 1, 0, 0)

#: Mirrors the MQL5 export header from Phase 19 in
#: PriceActionBarByBar.mq5 and Experts/PabEventExport.mq5.
COST_FIELDS = [
    "spread_points",
    "cost_spread_price",
    "cost_slippage_price",
    "cost_commission_price",
    "cost_r",
    "cost_model",
]

BASE_FIELDS = [
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


def make_event(index=0, **overrides):
    """One long setup: entry 1.1000, stop 1.0980, so a 0.0020 risk."""
    base = START + timedelta(hours=index)
    values = {
        "event_id": f"e{index}",
        "direction": "long",
        "bar_open_time": base,
        "bar_close_time": base + timedelta(minutes=1),
        "confirmed_at": base + timedelta(minutes=1),
        "decision_time": base + timedelta(minutes=1),
        "entry": 1.1000,
        "invalidation": 1.0980,
        "target": 1.1040,
        "status": "possible",
        "quality": 70,
        "risk_reward": 2.0,
        "setup_type": "second_entry",
        "symbol": "EURUSD",
        "period": "M5",
    }
    values.update(overrides)
    return SetupEvent(**values)


def costed(spread_price=0.00020, slippage_price=0.0, commission_price=0.0, **overrides):
    """An event carrying what the exporter writes for a costed row.

    The MQL5 side writes both the price components and the resulting
    ``cost_r``, so a realistic fixture carries all of them. A row without
    ``cost_r`` is modelled by :func:`make_event` instead, which is exactly
    what a pre-Phase-19 export produces.
    """
    values = {
        "spread_points": 20.0,
        "cost_spread_price": spread_price,
        "cost_slippage_price": slippage_price,
        "cost_commission_price": commission_price,
        "cost_r": round(
            (spread_price + 2.0 * slippage_price + commission_price) / 0.0020, 4
        ),
    }
    values.update(overrides)
    return make_event(**values)


def target_result(**overrides):
    values = {
        "outcome": "target",
        "exit_time": START + timedelta(minutes=2),
        "bars_to_exit": 1,
        "mfe": 0.004,
        "mae": -0.0005,
    }
    values.update(overrides)
    return OutcomeResult(**values)


def loss_result(**overrides):
    values = {
        "outcome": "invalidation",
        "exit_time": START + timedelta(minutes=2),
        "bars_to_exit": 1,
        "mfe": 0.0001,
        "mae": -0.002,
    }
    values.update(overrides)
    return OutcomeResult(**values)


def _write_cost_csv(directory, cost_r="0.1000", **overrides):
    """Write one exported event row exactly as the MQL5 side writes it.

    TAB-delimited, because FILE_CSV defaults to TAB and the loader sniffs
    the delimiter off the header rather than assuming Python's comma.
    """
    path = os.path.join(directory, "events.csv")
    row = {
        "event_id": "e1",
        "direction": "long",
        "setup_type": "second_entry",
        "status": "probable",
        "bar_open_time": START.isoformat(),
        "bar_close_time": (START + timedelta(minutes=1)).isoformat(),
        "confirmed_at": (START + timedelta(minutes=1)).isoformat(),
        "decision_time": (START + timedelta(minutes=1)).isoformat(),
        "entry": "1.1000",
        "invalidation": "1.0980",
        "target": "1.1040",
        "risk_reward": "2.0",
        "quality": "70",
        "engine_version": "1.50",
        "parameter_version": "p",
        "symbol": "EURUSD",
        "period": "M5",
        "spread_points": "20.0",
        "cost_spread_price": "0.00020",
        "cost_slippage_price": "0.0",
        "cost_commission_price": "0.0",
        "cost_r": cost_r,
        "cost_model": "spread=20.00pts/0.00020000;slippage=0.00pts/0.00000000;"
                      "commission=0.00000000",
    }
    row.update(overrides)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row), delimiter="\t")
        writer.writeheader()
        writer.writerow(row)
    return path


def no_trade_event(**overrides):
    values = {
        "event_id": "nt",
        "direction": "none",
        "entry": 0.0,
        "invalidation": 0.0,
        "target": 0.0,
        "status": "no_trade",
        "setup_type": "no_trade",
        "risk_reward": 0.0,
    }
    values.update(overrides)
    return make_event(**values)


class ExpectedCostTests(unittest.TestCase):
    """The re-derivation must match the MQL5 formula in TradingCost.mqh."""

    def test_spread_only_is_measured_against_the_stop_distance(self):
        # 0.00020 spread over a 0.00200 stop is a tenth of an R. This single
        # ratio is why a +0.02R gross edge cannot survive a real spread.
        self.assertAlmostEqual(expected_cost_r(costed()), 0.10)

    def test_slippage_is_charged_on_both_sides(self):
        # 0.00005 per side, so 0.00010 round trip, plus the 0.00020 spread.
        self.assertAlmostEqual(
            expected_cost_r(costed(slippage_price=0.00005)), 0.15
        )

    def test_commission_adds_to_the_same_price_distance(self):
        self.assertAlmostEqual(
            expected_cost_r(
                costed(slippage_price=0.00005, commission_price=0.00007)
            ),
            0.185,
        )

    def test_wider_stop_costs_less_in_r(self):
        narrow = costed()
        wide = make_event(
            entry=1.1000, invalidation=1.0900, target=1.1400, risk_reward=4.0,
            spread_points=20.0, cost_spread_price=0.00020,
        )
        self.assertLess(expected_cost_r(wide), expected_cost_r(narrow))

    def test_a_row_with_no_levels_costs_nothing(self):
        # A NO TRADE is not a trade, so there is nothing to pay. This must
        # be 0.0 and not a division by zero.
        self.assertEqual(expected_cost_r(no_trade_event()), 0.0)

    def test_zero_stop_distance_does_not_divide_by_zero(self):
        event = make_event(cost_spread_price=0.00020)
        object.__setattr__(event, "invalidation", event.entry)
        self.assertEqual(expected_cost_r(event), 0.0)


class HasCostsTests(unittest.TestCase):
    def test_a_row_without_the_column_is_not_costed(self):
        self.assertFalse(make_event().has_costs)

    def test_a_row_with_the_column_is_costed(self):
        self.assertTrue(costed().has_costs)

    def test_a_blank_cost_column_is_missing_not_zero(self):
        # This is the distinction the whole phase turns on: blank means
        # "the exporter predates cost columns", and 0.0 would mean "this
        # trade was free".
        with tempfile.TemporaryDirectory() as directory:
            path = _write_cost_csv(directory, cost_r="")
            event = load_setup_events(path)[0]

        self.assertIsNone(event.cost_r)
        self.assertFalse(event.has_costs)

    def test_a_costed_row_reports_its_cost(self):
        with tempfile.TemporaryDirectory() as directory:
            event = load_setup_events(_write_cost_csv(directory))[0]
        self.assertAlmostEqual(event.cost_r, 0.10)
        self.assertTrue(event.has_costs)


class NetExpectancyTests(unittest.TestCase):
    def test_net_expectancy_subtracts_cost_from_gross(self):
        # +2R target and -1R stop average +0.5R gross; a 0.10R cost makes
        # the net +0.40R. The cost is the same on both, which is the
        # point: it is paid entering and leaving either way.
        events = [costed(), costed()]
        results = [target_result(), loss_result()]
        stats = summarize("g", events, results)

        self.assertAlmostEqual(stats.expectancy_r, 0.5)
        self.assertAlmostEqual(stats.average_cost_r, 0.10)
        self.assertAlmostEqual(stats.net_expectancy_r, 0.40)

    def test_a_cost_larger_than_the_gross_edge_turns_it_negative(self):
        # Reproduces the shape of the actual study: 41 wins on a 1.5R
        # target out of 100 is +0.025R gross, the same order as the
        # +0.02R the whole project rested on. Against a 0.10R cost the same
        # sample is a loss. Nothing about the sample changed; only the
        # arithmetic that was always owed to it.
        events = [costed(risk_reward=1.5, target=1.1030) for _ in range(100)]
        results = [target_result() for _ in range(41)]
        results += [loss_result() for _ in range(59)]
        stats = summarize("g", events, results)

        self.assertAlmostEqual(stats.expectancy_r, 0.025)
        self.assertAlmostEqual(stats.average_cost_r, 0.10)
        self.assertAlmostEqual(stats.net_expectancy_r, -0.075)

    def test_net_is_withheld_when_the_export_has_no_cost_column(self):
        # Not 0.0 and not the gross value repeated. None is the only
        # honest answer, because the number does not exist.
        stats = summarize("g", [make_event(), make_event()],
                          [target_result(), loss_result()])

        self.assertIsNone(stats.net_expectancy_r)
        self.assertEqual(stats.costed_resolved, 0)
        self.assertFalse(stats.costs_available)

    def test_net_is_withheld_when_only_some_resolved_rows_are_costed(self):
        # Averaging a cost over part of a group and dividing by the whole
        # group would compare two different denominators.
        events = [costed(), make_event()]
        results = [target_result(), loss_result()]
        stats = summarize("g", events, results)

        self.assertIsNone(stats.net_expectancy_r)
        self.assertEqual(stats.costed_resolved, 1)
        self.assertFalse(stats.costs_available)

    def test_cost_is_not_charged_on_unresolved_events(self):
        # An expired event never reached an exit, so it never paid a
        # round-trip cost. Charging one would deflate expectancy with a
        # cost that was not incurred.
        events = [costed()]
        results = [target_result(outcome="expired", exit_time=None, bars_to_exit=None)]
        stats = summarize("g", events, results)

        self.assertEqual(stats.resolved, 0)
        self.assertEqual(stats.costed_resolved, 0)
        self.assertIsNone(stats.net_expectancy_r)

    def test_a_no_trade_row_does_not_dilute_the_average_cost(self):
        events = [costed(), no_trade_event(cost_r=0.0)]
        results = [target_result(), target_result(outcome="no_trade",
                                                   exit_time=None, bars_to_exit=None,
                                                   mfe=0.0, mae=0.0)]
        stats = summarize("g", events, results)

        self.assertEqual(stats.resolved, 1)
        self.assertAlmostEqual(stats.average_cost_r, 0.10)

    def test_an_empty_group_reports_no_net_figure(self):
        stats = summarize("g", [], [])
        self.assertIsNone(stats.net_expectancy_r)


class CostMismatchTests(unittest.TestCase):
    def test_a_disagreeing_exported_cost_is_counted_not_trusted(self):
        # The exporter writes cost_r, and this module recomputes it. If
        # they ever disagree, the recomputed value is used and the
        # disagreement is reported rather than averaged away.
        event = costed(cost_r=99.0)
        stats = summarize("g", [event], [target_result()])

        self.assertEqual(stats.cost_mismatches, 1)
        self.assertAlmostEqual(stats.average_cost_r, 0.10)

    def test_rounding_in_the_export_is_not_a_mismatch(self):
        # MQL5 prints cost_r to 4 decimals; 0.1004 and 0.10 are the same
        # number and must not raise a warning on every row of a real study.
        event = costed(cost_r=0.1004)
        stats = summarize("g", [event], [target_result()])

        self.assertEqual(stats.cost_mismatches, 0)

    def test_the_report_surfaces_a_mismatch(self):
        stats = summarize("g", [costed(cost_r=99.0)], [target_result()])
        groups = {"g": stats}
        from pab_research import format_report

        text = format_report(groups)
        self.assertIn("disagrees with the", text)


class ReportCostDisclosureTests(unittest.TestCase):
    def test_a_gross_only_report_says_so_in_those_words(self):
        bars = [
            PriceBar(START + timedelta(minutes=1), 1.1100, 1.0990),
        ]
        groups = group_by_setup([make_event()], bars)
        from pab_research import format_report

        text = format_report(groups)
        self.assertIn("carries no cost column", text)
        self.assertIn("n/a", text)
        self.assertIn("GROSS", text)

    def test_a_costed_report_explains_the_net_column(self):
        from pab_research import format_report

        stats = summarize("g", [costed()], [target_result()])
        text = format_report({"g": stats})
        self.assertIn("netR subtracts", text)
        self.assertIn("assumed", text)

    def test_a_cost_larger_than_expectancy_is_visible_as_its_own_column(self):
        # costR printed beside grossR is what makes the drag legible; a net
        # number alone hides the size of what was subtracted.
        from pab_research import format_report

        stats = summarize("g", [costed()], [target_result()])
        text = format_report({"g": stats})
        self.assertIn("costR", text)
        self.assertIn("grossR", text)


class WalkForwardCostTests(unittest.TestCase):
    def _bars(self, events):
        return [PriceBar(event.decision_time, 1.1100, 1.0990) for event in events]

    def test_net_degradation_is_reported_when_costs_exist(self):
        events = [costed(index=i) for i in range(8)]
        result = split_walk_forward(events, self._bars(events), 4, min_resolved=1)

        self.assertIsNotNone(result.net_expectancy_degradation_r)
        self.assertTrue(result.costs_available)
        self.assertAlmostEqual(
            result.net_expectancy_degradation_r,
            result.expectancy_degradation_r,
        )

    def test_net_degradation_is_withheld_without_costs(self):
        events = [make_event(i) for i in range(8)]
        result = split_walk_forward(events, self._bars(events), 4, min_resolved=1)

        self.assertIsNone(result.net_expectancy_degradation_r)
        self.assertIn("no cost column", result.reason)

    def test_a_gross_degradation_is_still_reported_alongside(self):
        # The gross figure is the one with 240,000 rows behind it. Losing
        # it because costs are missing would throw away the actual finding.
        events = [make_event(i) for i in range(8)]
        result = split_walk_forward(events, self._bars(events), 4, min_resolved=1)

        self.assertAlmostEqual(result.expectancy_degradation_r, 0.0)
        self.assertIsNone(result.net_expectancy_degradation_r)

    def test_the_fold_report_names_both_degradations(self):
        events = [costed(index=i) for i in range(8)]
        text = format_fold_report(
            split_walk_forward(events, self._bars(events), 4, min_resolved=1)
        )
        self.assertIn("gross expectancy degradation", text)
        self.assertIn("net expectancy degradation", text)

    def test_the_fold_report_admits_when_net_is_unavailable(self):
        events = [make_event(i) for i in range(8)]
        text = format_fold_report(
            split_walk_forward(events, self._bars(events), 4, min_resolved=1)
        )
        self.assertIn("n/a -- the export carries no cost column", text)

    def test_a_windowed_study_keeps_its_costs(self):
        # filter_window rebuilds the event list, so a costed event that
        # survives the window must keep its cost.
        events = [costed(index=i) for i in range(4)]
        kept = filter_window(events, events[0].decision_time, events[1].decision_time)
        stats = summarize("kept", kept, [target_result()] * len(kept))

        self.assertEqual(stats.costed_resolved, 2)
        self.assertAlmostEqual(stats.net_expectancy_r, 2.0 - 0.10)


class BreakEvenTests(unittest.TestCase):
    """Break-even is how the study answers the cost question honestly.

    The Strategy Tester has no historical spread to read, so a measured
    spread is impossible in this harness and any study that states one is
    reporting its author's assumption. Solving for the cost instead makes
    the answer a property of the sample.
    """

    def _sample(self, wins, losses, risk=0.0020, entry=1.1000, rr=1.5):
        events = [
            costed(risk_reward=rr, entry=entry, invalidation=entry - risk,
                   target=entry + rr * risk)
            for _ in range(wins + losses)
        ]
        results = [target_result() for _ in range(wins)]
        results += [loss_result() for _ in range(losses)]
        return events, results

    def test_solves_for_the_cost_that_cancels_the_edge(self):
        events, results = self._sample(41, 59)
        found = break_even_cost("g", events, results)

        # +0.025R gross against a 0.0020 stop is a 0.00005 price distance,
        # which is 0.0045% of a 1.1000 entry.
        self.assertAlmostEqual(found.gross_expectancy_r, 0.025)
        self.assertAlmostEqual(found.average_risk, 0.0020)
        self.assertAlmostEqual(found.break_even_spread_fraction, 0.00005 / 1.1000)
        self.assertAlmostEqual(found.break_even_spread_percent, 0.00454545, places=5)
        self.assertTrue(found.is_meaningful)

    def test_a_breakeven_cost_exactly_zeroes_net_expectancy(self):
        # The defining property. If this does not hold, the number is
        # decoration rather than a solution.
        from pab_research.outcomes import OutcomeResult

        events, results = self._sample(41, 59)
        gross = break_even_cost("g", events, results)

        # Re-price every event at exactly the break-even spread.
        repriced = []
        for event in events:
            repriced.append(
                SetupEvent(**{**event.__dict__,
                              "cost_spread_price": gross.break_even_spread_fraction * event.entry})
            )
        stats = summarize("g", repriced, results)
        self.assertAlmostEqual(stats.net_expectancy_r, 0.0, places=6)

    def test_a_realistic_spread_clears_the_gross_edge(self):
        # 1 pip of spread on a 20-pip stop is 0.05R, twice the measured
        # edge. This is the study's actual conclusion, as an assertion.
        risk = 0.0020
        entry = 1.1000
        events = [
            costed(
                risk_reward=1.5,
                entry=entry,
                invalidation=entry - risk,
                target=entry + 1.5 * risk,
                spread_points=10.0,
                cost_spread_price=0.00010,
            )
            for _ in range(100)
        ]
        results = [target_result() for _ in range(41)]
        results += [loss_result() for _ in range(59)]
        stats = summarize("g", events, results)

        self.assertAlmostEqual(stats.expectancy_r, 0.025)
        self.assertAlmostEqual(stats.average_cost_r, 0.05)
        self.assertLess(stats.net_expectancy_r, 0.0)

    def test_a_negative_group_reports_no_break_even(self):
        # A negative gross edge has no break-even cost. Printing a negative
        # spread would read as a real measurement.
        events, results = self._sample(20, 80)
        found = break_even_cost("g", events, results)

        self.assertTrue(found.gross_is_negative)
        self.assertFalse(found.is_meaningful)
        text = format_break_even([found])
        self.assertIn("gross < 0", text)

    def test_a_group_with_nothing_resolved_reports_no_break_even(self):
        found = break_even_cost("g", [costed()], [target_result(outcome="expired",
                                                                 exit_time=None,
                                                                 bars_to_exit=None)])
        self.assertEqual(found.resolved, 0)
        self.assertIn("none resolved", format_break_even([found]))

    def test_a_wider_stop_makes_the_edge_survive_more_cost(self):
        # The same percentage edge expressed over a wider stop is a bigger
        # price distance, so it buys more spread. This is why the H1 sets,
        # with 31-36 bars to exit, are not the same claim as the M5 sets.
        tight, _ = self._sample(41, 59, risk=0.0020)
        wide, _ = self._sample(41, 59, risk=0.0040)
        tight_be = break_even_cost("tight", tight, [target_result()] * 41 + [loss_result()] * 59)
        wide_be = break_even_cost("wide", wide, [target_result()] * 41 + [loss_result()] * 59)

        self.assertAlmostEqual(wide_be.break_even_spread_fraction,
                               2 * tight_be.break_even_spread_fraction)

    def test_the_percentage_is_comparable_across_price_scales(self):
        # The same RISK FRACTION at two price scales is the same trade, and
        # must produce the same break-even percentage. A raw price distance
        # would not: 0.0020 at 1.10 and 6.18 at 3400 are the same stop, but
        # their break-even costs differ by three orders of magnitude. The
        # project was bitten by exactly this comparison in Phase 14.
        small, _ = self._sample(41, 59, risk=0.0020, entry=1.1000)
        large, _ = self._sample(41, 59, risk=6.1818, entry=3400.0)
        small_be = break_even_cost("s", small, [target_result()] * 41 + [loss_result()] * 59)
        large_be = break_even_cost("l", large, [target_result()] * 41 + [loss_result()] * 59)

        self.assertAlmostEqual(small_be.break_even_spread_percent,
                               large_be.break_even_spread_percent, places=3)
        # And the raw price distances really do differ, which is the point.
        self.assertGreater(large_be.average_risk, small_be.average_risk * 1000)

    def test_rejects_misaligned_inputs(self):
        with self.assertRaisesRegex(ValueError, "same length"):
            break_even_cost("g", [costed()], [])

    def test_the_table_names_what_the_cost_includes(self):
        events, results = self._sample(41, 59)
        text = format_break_even([break_even_cost("g", events, results)])
        self.assertIn("round-trip", text)
        self.assertIn("slippage on both", text)
        self.assertIn("no cost model was assumed", text)


class CostScenarioTests(unittest.TestCase):
    """Re-pricing the whole sample at assumed spreads.

    Break-even says where the edge dies. Scenarios say how fast, which is
    the question a reader actually has: a group that dies at 0.0003% and
    one that dies at 0.05% are both negative in practice, and only the
    second is arguably reachable.
    """

    def _sample(self, wins=41, losses=59, risk=0.0020, entry=1.1000, rr=1.5):
        """A sample plus bars that actually resolve it.

        Each event gets its own bar at its own decision time, so outcome
        evaluation is not left to chance: a bar that reaches the target
        resolves one way, a bar that breaks the stop resolves the other.
        Without that, every event would resolve on the same bar and the
        win rate would silently be 100 percent.
        """
        events = [
            make_event(index=i, risk_reward=rr, entry=entry,
                       invalidation=entry - risk, target=entry + rr * risk)
            for i in range(wins + losses)
        ]
        bars = []
        for index, event in enumerate(events):
            if index < wins:
                bars.append(PriceBar(event.decision_time, event.target + 0.0005,
                                     entry - risk / 2))
            else:
                bars.append(PriceBar(event.decision_time, entry + risk / 2,
                                     entry - risk - 0.0005))
        return events, bars

    def test_a_zero_spread_reproduces_the_gross_figure(self):
        # If this does not hold, the re-pricing path and the normal path
        # have diverged and every other number here is suspect.
        from pab_research import compare_cost_scenarios

        events, bars = self._sample()
        rows = compare_cost_scenarios(events, bars, [("free", 0.0)])

        self.assertAlmostEqual(rows[0][1], 0.025)

    def test_net_falls_as_the_assumed_spread_rises(self):
        from pab_research import compare_cost_scenarios

        events, bars = self._sample()
        rows = compare_cost_scenarios(
            events, bars,
            [("a", 0.0), ("b", 0.001), ("c", 0.005), ("d", 0.01)],
        )
        values = [value for _, value in rows]

        self.assertEqual(values, sorted(values, reverse=True))
        self.assertGreater(values[0], 0.0)
        self.assertLess(values[-1], 0.0)

    def test_the_break_even_spread_is_where_the_scenario_crosses_zero(self):
        # The two features have to agree. If a scenario at the break-even
        # spread does not come out near zero, one of them is wrong.
        from pab_research import break_even_cost, compare_cost_scenarios, evaluate_setup

        events, bars = self._sample()
        found = break_even_cost(
            "g", events, [evaluate_setup(e, bars) for e in events]
        )
        rows = compare_cost_scenarios(
            events, bars, [("breakeven", found.break_even_spread_fraction)]
        )
        self.assertAlmostEqual(rows[0][1], 0.0, places=6)

    def test_a_realistic_spread_makes_the_sample_a_large_loss(self):
        from pab_research import compare_cost_scenarios

        events, bars = self._sample()
        rows = compare_cost_scenarios(events, bars, [("0.02%", 0.0002)])
        # 0.02% of price against a 0.18% stop is about 0.11R of cost per
        # trade, against a 0.025R edge.
        self.assertLess(rows[0][1], -0.05)

    def test_the_table_labels_every_spread_as_assumed(self):
        from contextlib import redirect_stdout
        from io import StringIO

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path = _write_cost_csv(directory)
            bars_path = os.path.join(directory, "bars.csv")
            with open(bars_path, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=["open_time", "high", "low"],
                                        delimiter="\t")
                writer.writeheader()
                writer.writerow({"open_time": (START + timedelta(minutes=1)).isoformat(),
                                 "high": 1.1100, "low": 1.0990})

            buffer = StringIO()
            with redirect_stdout(buffer):
                code = main([events_path, bars_path, "--cost-scenario", "0.01"])
        output = buffer.getvalue()

        self.assertEqual(code, 0)
        self.assertIn("ASSUMED", output)
        self.assertIn("not measurements", output)


class BreakEvenGroupingTests(unittest.TestCase):
    def test_the_break_even_table_uses_the_chosen_grouping(self):
        # A mismatch here would not raise; it would print a second table
        # of different-looking numbers.
        from pab_research import group_key_of

        event = make_event(symbol="EURUSD", period="M5", setup_type="second_entry")
        self.assertEqual(group_key_of(event, "market"), "EURUSD M5")
        self.assertEqual(group_key_of(event, "instrument"), "EURUSD")
        self.assertEqual(group_key_of(event, "setup"), "second_entry")

    def test_the_cli_prints_a_break_even_table(self):
        import contextlib
        import io

        from pab_research.report import main

        with tempfile.TemporaryDirectory() as directory:
            events_path = _write_cost_csv(directory)
            bars_path = os.path.join(directory, "bars.csv")
            with open(bars_path, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=["open_time", "high", "low"],
                                        delimiter="\t")
                writer.writeheader()
                writer.writerow({"open_time": (START + timedelta(minutes=1)).isoformat(),
                                 "high": 1.1100, "low": 1.0990})

            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = main([events_path, bars_path, "--break-even"])
        output = buffer.getvalue()

        self.assertEqual(code, 0)
        self.assertIn("break-even execution cost", output)
        self.assertIn("breakEvenSpread", output)


class LoaderCostTests(unittest.TestCase):
    def test_reads_every_cost_column(self):
        with tempfile.TemporaryDirectory() as directory:
            event = load_setup_events(_write_cost_csv(directory))[0]
        self.assertEqual(event.spread_points, 20.0)
        self.assertEqual(event.cost_spread_price, 0.00020)
        self.assertEqual(event.cost_slippage_price, 0.0)
        self.assertEqual(event.cost_commission_price, 0.0)
        self.assertAlmostEqual(event.cost_r, 0.10)
        self.assertIn("spread=20.00pts", event.cost_model)

    def test_a_pre_phase19_export_still_loads_without_costs(self):
        # Every archived study on disk predates these columns. They must
        # keep loading, and they must load as GROSS.
        directory = tempfile.mkdtemp()
        path = os.path.join(directory, "events.csv")
        row = {
            "event_id": "e1",
            "direction": "long",
            "setup_type": "second_entry",
            "status": "probable",
            "bar_open_time": START.isoformat(),
            "bar_close_time": (START + timedelta(minutes=1)).isoformat(),
            "confirmed_at": (START + timedelta(minutes=1)).isoformat(),
            "decision_time": (START + timedelta(minutes=1)).isoformat(),
            "entry": "1.1000",
            "invalidation": "1.0980",
            "target": "1.1040",
            "risk_reward": "2.0",
            "quality": "70",
            "engine_version": "1.50",
            "parameter_version": "p",
        }
        with open(path, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=BASE_FIELDS, delimiter="\t")
            writer.writeheader()
            writer.writerow(row)

        event = load_setup_events(path)[0]
        self.assertFalse(event.has_costs)
        self.assertIsNone(event.cost_r)
        self.assertEqual(event.cost_model, "")


if __name__ == "__main__":
    unittest.main()

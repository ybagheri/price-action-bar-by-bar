import csv
import os
import tempfile
import unittest
from datetime import datetime, timedelta

from pab_research import (
    UNKNOWN_SYMBOL,
    BarBook,
    BarSeries,
    MissingBarHistory,
    PriceBar,
    SetupEvent,
    evaluate_setup,
    load_price_bars,
    load_price_bars_by_symbol,
    partition_by_bar_history,
)

START = datetime(2026, 1, 1, 12, 0)


def make_event(symbol="EURUSD", **overrides):
    values = {
        "event_id": f"e-{symbol}",
        "direction": "long",
        "bar_open_time": START,
        "bar_close_time": START + timedelta(minutes=1),
        "confirmed_at": START + timedelta(minutes=1),
        "decision_time": START + timedelta(minutes=1),
        "entry": 1.1000,
        "invalidation": 1.0980,
        "target": 1.1040,
        "status": "possible",
        "quality": 70,
        "risk_reward": 2.0,
        "setup_type": "second_entry",
        "symbol": symbol,
    }
    values.update(overrides)
    return SetupEvent(**values)


def eur_bars(n=5):
    # High clears the target (1.1040); the low stays above the invalidation
    # (1.0980). A bar that straddled both would resolve 'ambiguous' and prove
    # nothing about which market was used.
    return [
        PriceBar(START + timedelta(minutes=i + 1), 1.1100, 1.0995)
        for i in range(n)
    ]


def jpy_bars(n=5):
    # Two orders of magnitude away, and entirely above the EURUSD levels, so
    # measuring a EURUSD event against these would resolve 'expired' rather
    # than quietly returning the right answer by luck.
    return [
        PriceBar(START + timedelta(minutes=i + 1), 105.00, 104.90)
        for i in range(n)
    ]


class BarBookTests(unittest.TestCase):
    def test_builds_one_index_per_symbol(self):
        book = BarBook.of({"EURUSD": eur_bars(), "USDJPY": jpy_bars()})
        self.assertEqual(book.symbols(), ["EURUSD", "USDJPY"])
        self.assertEqual(len(book), 2)
        self.assertTrue(book.has("EURUSD"))
        self.assertFalse(book.has("GBPUSD"))

    def test_evaluates_an_event_against_its_own_market(self):
        book = BarBook.of({"EURUSD": eur_bars(), "USDJPY": jpy_bars()})
        # A EURUSD event must never be measured against 105.00-priced bars.
        result = evaluate_setup(make_event("EURUSD"), book)
        self.assertEqual(result.outcome, "target")
        self.assertLess(result.mfe, 0.10)

    def test_refuses_to_measure_against_a_market_it_does_not_have(self):
        book = BarBook.of({"EURUSD": eur_bars()})
        with self.assertRaises(MissingBarHistory) as caught:
            evaluate_setup(make_event("USDJPY"), book)
        self.assertIn("USDJPY", str(caught.exception))

    def test_a_plain_list_still_works(self):
        result = evaluate_setup(make_event("EURUSD"), eur_bars())
        self.assertEqual(result.outcome, "target")

    def test_a_barseries_still_works(self):
        result = evaluate_setup(make_event("EURUSD"), BarSeries.of(eur_bars()))
        self.assertEqual(result.outcome, "target")


class PartitionTests(unittest.TestCase):
    def test_splits_measurable_from_unattributable(self):
        book = BarBook.of({"EURUSD": eur_bars()})
        events = [make_event("EURUSD"), make_event("USDJPY"), make_event("EURUSD")]

        split = partition_by_bar_history(events, book)

        self.assertEqual(len(split.measurable), 2)
        self.assertEqual(len(split.unattributed), 1)
        self.assertEqual(split.unattributed[0].symbol, "USDJPY")
        self.assertEqual(split.excluded_count, 1)

    def test_nothing_is_measured_twice(self):
        book = BarBook.of({"EURUSD": eur_bars()})
        events = [make_event("EURUSD"), make_event("USDJPY")]
        split = partition_by_bar_history(events, book)
        self.assertEqual(
            len(split.measurable) + len(split.unattributed), len(events)
        )


BAR_FIELDS = ["open_time", "high", "low", "symbol", "period"]


def write_bar_csv(directory, rows):
    path = os.path.join(directory, "bars.csv")
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=BAR_FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    return path


class LoadBySymbolTests(unittest.TestCase):
    def test_groups_rows_by_their_symbol_column(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_bar_csv(
                directory,
                [
                    {
                        "open_time": "2026-01-01 12:01:00",
                        "high": 1.1,
                        "low": 1.09,
                        "symbol": "EURUSD",
                        "period": "M5",
                    },
                    {
                        "open_time": "2026-01-01 12:01:00",
                        "high": 105.0,
                        "low": 104.0,
                        "symbol": "USDJPY",
                        "period": "M5",
                    },
                ],
            )
            grouped = load_price_bars_by_symbol(path)

        self.assertEqual(sorted(grouped), ["EURUSD", "USDJPY"])
        self.assertEqual(grouped["EURUSD"][0].high, 1.1)
        self.assertEqual(grouped["USDJPY"][0].high, 105.0)

    def test_a_file_without_a_symbol_column_still_loads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "bars.csv")
            with open(path, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(
                    handle, fieldnames=["open_time", "high", "low"], delimiter="\t"
                )
                writer.writeheader()
                writer.writerow(
                    {"open_time": "2026-01-01 12:01:00", "high": 1.1, "low": 1.09}
                )
            grouped = load_price_bars_by_symbol(path)
            self.assertIn(UNKNOWN_SYMBOL, grouped)
            self.assertEqual(len(load_price_bars(path)), 1)

    def test_rows_are_sorted_within_each_symbol(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write_bar_csv(
                directory,
                [
                    {
                        "open_time": "2026-01-01 12:05:00",
                        "high": 1.2,
                        "low": 1.0,
                        "symbol": "EURUSD",
                        "period": "M5",
                    },
                    {
                        "open_time": "2026-01-01 12:01:00",
                        "high": 1.1,
                        "low": 0.9,
                        "symbol": "EURUSD",
                        "period": "M5",
                    },
                ],
            )
            grouped = load_price_bars_by_symbol(path)
        times = [bar.open_time for bar in grouped["EURUSD"]]
        self.assertEqual(times, sorted(times))


if __name__ == "__main__":
    unittest.main()

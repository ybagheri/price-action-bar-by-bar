import unittest
from datetime import datetime, timedelta

from pab_research import PriceBar, SetupEvent, evaluate_setup


def make_event(**overrides):
    start = datetime(2026, 1, 1, 12, 0)
    values = {
        "event_id": "e1",
        "direction": "long",
        "bar_open_time": start,
        "bar_close_time": start + timedelta(minutes=1),
        "confirmed_at": start + timedelta(minutes=1),
        "decision_time": start + timedelta(minutes=1),
        "entry": 100.0,
        "invalidation": 98.0,
        "target": 104.0,
        "status": "possible",
        "quality": 70,
        "risk_reward": 2.0,
    }
    values.update(overrides)
    return SetupEvent(**values)


def bar(minutes, high, low):
    return PriceBar(datetime(2026, 1, 1, 12, 1) + timedelta(minutes=minutes), high, low)


class OutcomeTests(unittest.TestCase):
    def test_rejects_future_confirmation(self):
        with self.assertRaisesRegex(ValueError, "confirmed_at"):
            make_event(confirmed_at=datetime(2026, 1, 1, 12, 2))

    def test_rejects_decision_before_close(self):
        with self.assertRaisesRegex(ValueError, "decision_time"):
            make_event(decision_time=datetime(2026, 1, 1, 12, 0, 30))

    def test_target_outcome_and_mfe_mae(self):
        result = evaluate_setup(make_event(), [bar(0, 102.0, 99.5), bar(1, 105.0, 100.5)])
        self.assertEqual(result.outcome, "target")
        self.assertEqual(result.bars_to_exit, 2)
        self.assertAlmostEqual(result.mfe, 0.05)
        self.assertAlmostEqual(result.mae, -0.005)

    def test_invalidation_for_short(self):
        event = make_event(direction="short", entry=100.0, invalidation=102.0, target=96.0)
        result = evaluate_setup(event, [bar(0, 103.0, 99.0)])
        self.assertEqual(result.outcome, "invalidation")
        self.assertLess(result.mae, 0)

    def test_same_bar_target_and_stop_is_ambiguous(self):
        result = evaluate_setup(make_event(), [bar(0, 105.0, 97.0)])
        self.assertEqual(result.outcome, "ambiguous")

    def test_no_trade_is_not_evaluated(self):
        result = evaluate_setup(make_event(status="no_trade"), [bar(0, 110.0, 90.0)])
        self.assertEqual(result.outcome, "no_trade")
        self.assertIsNone(result.exit_time)


if __name__ == "__main__":
    unittest.main()

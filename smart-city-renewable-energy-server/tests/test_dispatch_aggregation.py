import unittest

import numpy as np
import pandas as pd
from fastapi import HTTPException

from app.main import _aggregate_balance_for_dispatch
from app.optimization import compute_energy_balance


class DispatchAggregationTests(unittest.TestCase):
    def make_balance(self, days=7, minute=0):
        n = days * 96
        timestamps = pd.date_range(
            f"2026-10-29 06:{minute:02d}:00", periods=n, freq="15min", tz="UTC"
        )
        return compute_energy_balance(
            timestamps, np.linspace(2, 20, n), np.linspace(0, 25, n), np.ones(n)
        )

    def test_preserves_horizon_and_energy_at_all_quarter_hour_starts(self):
        for days in (7, 14):
            for minute in (0, 15, 30, 45):
                with self.subTest(days=days, minute=minute):
                    original = self.make_balance(days, minute)
                    result = _aggregate_balance_for_dispatch(original, 60)
                    self.assertEqual(len(result), days * 24)
                    self.assertEqual(result.utc_timestamp.iloc[0], original.utc_timestamp.iloc[0])
                    self.assertEqual(
                        result.utc_timestamp.iloc[-1] + pd.Timedelta(hours=1),
                        original.utc_timestamp.iloc[-1] + pd.Timedelta(minutes=15),
                    )
                    for column in ("load_kw_pred", "pv_kw_pred", "wind_kw_pred", "renewable_kw_pred"):
                        self.assertAlmostEqual(result[column].sum(), original[column].sum() * 0.25)

    def test_rejects_partial_hour(self):
        with self.assertRaises(HTTPException) as error:
            _aggregate_balance_for_dispatch(self.make_balance().iloc[:-1], 60)
        self.assertEqual(error.exception.status_code, 400)

    def test_rejects_missing_or_duplicate_intervals(self):
        original = self.make_balance()
        original.loc[5, "utc_timestamp"] = original.loc[4, "utc_timestamp"]
        with self.assertRaises(HTTPException) as error:
            _aggregate_balance_for_dispatch(original, 60)
        self.assertEqual(error.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()

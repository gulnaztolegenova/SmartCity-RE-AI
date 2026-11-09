"""Real-artifact regression tests; no fitting, weather requests or Firestore."""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np

from app.dp_sthpp_runtime import (
    ARTIFACT_HASHES, CALENDAR_COLUMNS, FEATURE_COLUMNS, MODEL_VERSION,
    SIGNAL_COLUMNS, TARGET_COLUMNS, DPSTHPPRuntime,
)


SERVER_ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = SERVER_ROOT / "models" / "dp_sthpp"
FIXTURE_PATH = Path(__file__).parent / "fixtures" / "dp_sthpp_golden.json"
FIXTURE_SHA256 = "87751b75676121c835e843d8ad36673d3893ababf759ed6b4163f53e3bd4bac2"


def fixture_records(example: dict, offset: str = "+00:00") -> list[dict]:
    # The export has naive timestamps. A test-only offset keeps the original
    # local calendar unchanged; this is not evidence of the research timezone.
    records = copy.deepcopy(example["context_records_source_scale"])
    for row in records:
        row["timestamp"] = row["timestamp"].replace(" ", "T") + offset
    return records


class DPSTHPPInputValidationTests(unittest.TestCase):
    def setUp(self):
        self.examples = json.loads(FIXTURE_PATH.read_text())["examples"]
        self.records = fixture_records(self.examples[0])

    def test_requires_exactly_24_hourly_records(self):
        for records in ([], self.records[:-1], self.records + self.records[:1], tuple(self.records), [None] * 24):
            with self.subTest(length=len(records)), self.assertRaises(ValueError):
                DPSTHPPRuntime._prepare(records, "historical_measurements")

    def test_rejects_missing_nonfinite_nonnumeric_and_overflowing_signals(self):
        for signal in SIGNAL_COLUMNS:
            for value in (None, "1.0", True, float("nan"), float("inf"), -float("inf"), 1e100, 10 ** 1000):
                records = copy.deepcopy(self.records)
                records[7][signal] = value
                with self.subTest(signal=signal, value=str(value)[:20]), self.assertRaises(ValueError):
                    DPSTHPPRuntime._prepare(records, "historical_measurements")
        # Python integers beyond int64 are still valid if representable in the
        # source float32 format; they must not leak NumPy's TypeError either.
        records = copy.deepcopy(self.records)
        records[0][SIGNAL_COLUMNS[0]] = 10 ** 25
        matrix, _ = DPSTHPPRuntime._prepare(records, "historical_measurements")
        self.assertTrue(np.isfinite(matrix).all())

    def test_rejects_naive_mixed_offset_off_grid_future_and_disordered_timestamps(self):
        cases = []
        for stamp in (None, "bad timestamp", "2019-08-22T01:00:00", "2019-08-22T01:30:00+00:00", "2019-08-22T01:00:00.000001+00:00"):
            records = copy.deepcopy(self.records)
            records[0]["timestamp"] = stamp
            cases.append(records)
        records = copy.deepcopy(self.records)
        records[1]["timestamp"] = records[1]["timestamp"].replace("+00:00", "+01:00")
        cases.append(records)
        records = copy.deepcopy(self.records)
        records[5]["timestamp"] = records[4]["timestamp"]
        cases.append(records)
        cases.append(list(reversed(self.records)))
        records = copy.deepcopy(self.records)
        start = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0) + timedelta(days=1)
        for i, row in enumerate(records):
            row["timestamp"] = (start + timedelta(hours=i)).isoformat()
            for name in CALENDAR_COLUMNS:
                row.pop(name)
        cases.append(records)
        for i, records in enumerate(cases):
            with self.subTest(case=i), self.assertRaises(ValueError):
                DPSTHPPRuntime._prepare(records, "historical_measurements")

    def test_calendar_is_derived_from_local_clock_and_contradictions_rejected(self):
        base, _ = DPSTHPPRuntime._prepare(self.records, "historical_measurements")
        for row in self.records:
            for name in CALENDAR_COLUMNS:
                row.pop(name)
        derived, _ = DPSTHPPRuntime._prepare(self.records, "historical_measurements")
        np.testing.assert_array_equal(base, derived)
        offset, _ = DPSTHPPRuntime._prepare(fixture_records(self.examples[0], "+05:00"), "historical_measurements")
        np.testing.assert_array_equal(base, offset)
        for name in CALENDAR_COLUMNS:
            records = copy.deepcopy(self.records)
            records[0][name] = 99
            with self.subTest(feature=name), self.assertRaises(ValueError):
                DPSTHPPRuntime._prepare(records, "historical_measurements")

    def test_exact_season_and_weekday_codes_at_boundaries(self):
        for month, expected in ((1, 3), (3, 0), (6, 1), (9, 2), (12, 3)):
            records = copy.deepcopy(self.records)
            start = datetime(2019, month, 1, tzinfo=timezone(timedelta(hours=5)))
            for i, row in enumerate(records):
                row["timestamp"] = (start + timedelta(hours=i)).isoformat()
                for name in CALENDAR_COLUMNS:
                    row.pop(name)
            matrix, _ = DPSTHPPRuntime._prepare(records, "historical_measurements")
            self.assertTrue(np.all(matrix[:, FEATURE_COLUMNS.index("season_code")] == expected))
            self.assertTrue(np.all(matrix[:, FEATURE_COLUMNS.index("dayofweek")] == start.weekday()))

    def test_rejects_declared_forecasts_imputation_and_partial_observation(self):
        for source in ("weather_forecast", "synthetic", "imputed", "", None):
            with self.subTest(source=source), self.assertRaises(ValueError):
                DPSTHPPRuntime._prepare(self.records, source)
        for observed in (None, {}, True, {name: True for name in SIGNAL_COLUMNS[:-1]}, {name: False for name in SIGNAL_COLUMNS}):
            records = copy.deepcopy(self.records)
            records[0]["observed"] = observed
            with self.subTest(observed=observed), self.assertRaises(ValueError):
                DPSTHPPRuntime._prepare(records, "historical_measurements")
        records = copy.deepcopy(self.records)
        records[0]["source_kind"] = "weather_forecast"
        with self.assertRaises(ValueError):
            DPSTHPPRuntime._prepare(records, "historical_measurements")
        for row in self.records:
            row["observed"] = {name: True for name in SIGNAL_COLUMNS}
        DPSTHPPRuntime._prepare(self.records, "historical_measurements")

    def test_refuses_unloaded_predictions(self):
        runtime = DPSTHPPRuntime(MODEL_DIR)
        self.assertFalse(runtime.is_loaded)
        self.assertFalse(runtime.meta()["model_loaded"])
        with self.assertRaisesRegex(RuntimeError, "not loaded"):
            runtime.predict(self.records)

    def test_integrity_pins_are_not_supplied_by_a_mutable_manifest(self):
        # Each mismatch must be caught before TensorFlow/weight deserialization.
        for filename in ("dp_sthpp.weights.h5", "preprocessing.json", "artifact_manifest.json", "architecture_source.txt"):
            with self.subTest(file=filename), tempfile.TemporaryDirectory() as folder:
                target = Path(folder) / "model"
                shutil.copytree(MODEL_DIR, target)
                with (target / filename).open("ab") as stream:
                    stream.write(b"\nmodified")
                with self.assertRaisesRegex(ValueError, "integrity mismatch"):
                    DPSTHPPRuntime(target).load()


class DPSTHPPRealArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if hashlib.sha256(FIXTURE_PATH.read_bytes()).hexdigest() != FIXTURE_SHA256:
            raise AssertionError("Real validation parity fixture changed")
        cls.examples = json.loads(FIXTURE_PATH.read_text())["examples"]
        cls.runtime = DPSTHPPRuntime(MODEL_DIR).load()

    def test_all_exported_real_examples_match_after_portable_cpu_reload(self):
        for example in self.examples:
            records = fixture_records(example)
            before = copy.deepcopy(records)
            result = self.runtime.predict(records)
            np.testing.assert_allclose(
                [result["predictions_raw"][name] for name in TARGET_COLUMNS],
                example["expected_regression_source_scale"], rtol=1e-5, atol=1e-3,
            )
            np.testing.assert_allclose(
                [result["extreme_probabilities_raw"][name] for name in TARGET_COLUMNS],
                example["expected_extreme_probability"], rtol=1e-5, atol=1e-6,
            )
            self.assertEqual(result["forecast_timestamp"], example["target_timestamp"].split(".")[0] + "+00:00")
            self.assertEqual(result["horizon_hours"], 1)
            self.assertEqual(result["model_version"], MODEL_VERSION)
            self.assertEqual(records, before, "Caller measurements must not be altered")

    def test_negative_prediction_and_raw_scores_are_retained_without_operational_claims(self):
        result = self.runtime.predict(fixture_records(self.examples[0]))
        self.assertLess(result["predictions_raw"][TARGET_COLUMNS[0]], 0)
        self.assertIn(TARGET_COLUMNS[0], result["negative_raw_outputs"])
        self.assertEqual(result["raw_prediction_units"], "unverified source units")
        self.assertIsNone(result["warning_probability_threshold"])
        self.assertEqual(result["extreme_thresholds_source_units"], {
            TARGET_COLUMNS[0]: 3403.9111328125, TARGET_COLUMNS[1]: 3315.598876953125,
        })
        self.assertIn("687 negative solar", " ".join(result["caveats"]))

    def test_metadata_matches_frozen_training_and_all_weights_are_cpu(self):
        meta = self.runtime.meta()
        self.assertTrue(meta["model_loaded"])
        self.assertEqual(meta["features"], list(FEATURE_COLUMNS))
        self.assertEqual(meta["required_signals"], list(SIGNAL_COLUMNS))
        self.assertEqual(meta["validated_forecast_steps"], 1)
        self.assertEqual(meta["training"]["epochs_executed"], 28)
        self.assertEqual(meta["training"]["best_validation_epoch"], 28)
        self.assertEqual(meta["historical_holdout_metrics"][0]["n"], 1746)
        self.assertAlmostEqual(meta["historical_holdout_metrics"][0]["R2"], 0.8948397636413574)
        self.assertEqual(meta["checkpoint_sha256"], ARTIFACT_HASHES["dp_sthpp.weights.h5"])
        self.assertEqual(self.runtime.model.count_params(), 831730)
        self.assertTrue(all("CPU:" in str(getattr(w, "value", w).device) for w in self.runtime.model.weights))
        # Responses cannot be used to mutate the runtime's provenance.
        meta["training"]["epochs_executed"] = 0
        self.assertEqual(self.runtime.meta()["training"]["epochs_executed"], 28)

    def test_repeated_and_concurrent_predictions_are_identical(self):
        records = fixture_records(self.examples[0], "+05:00")
        expected = self.runtime.predict(records)
        with ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(lambda _: self.runtime.predict(records), range(3)))
        for result in results:
            self.assertEqual(result, expected)
        self.assertTrue(expected["forecast_timestamp"].endswith("+05:00"))


if __name__ == "__main__":
    unittest.main()

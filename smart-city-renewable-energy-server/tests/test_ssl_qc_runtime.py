"""Portable checks against the freshly trained bundle and exported notebook code.

Only hash-verified inference definitions are evaluated. No scientific project,
training execution, network request or mutable research checkout is needed.
"""
from __future__ import annotations

import ast
import copy
import hashlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from typing import Optional
from unittest.mock import patch

import numpy as np
import pandas as pd
import torch
from torch import nn

from app.ssl_qc_runtime import ARTIFACT_HASHES, FEATURE_COLUMNS, SIGNAL_COLUMNS, SSLQCRuntime


MODEL_DIR = Path(__file__).resolve().parents[1] / "models" / "ssl_qc"
GOLDEN_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "ssl_qc_golden.json"


def measurement_records(runtime):
    """Technical finite-input fixture, not scientific performance evidence."""
    start = datetime(2019, 2, 1, tzinfo=timezone.utc)
    values = {name: runtime.preprocessor["features"][name]["median"] for name in SIGNAL_COLUMNS}
    return [{**values, "timestamp": (start + timedelta(hours=i)).isoformat()} for i in range(24)]


class SSLQCRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(1)
        cls.runtime = SSLQCRuntime(MODEL_DIR).load()

    def setUp(self):
        self.records = measurement_records(self.runtime)

    def test_real_cpu_inference_is_deterministic_and_honestly_labelled(self):
        result = self.runtime.score(self.records)
        again = self.runtime.score(self.records)
        self.assertEqual(result["qc_score"], again["qc_score"])
        self.assertEqual(result["components"], again["components"])
        self.assertFalse(result["score_is_probability"])
        self.assertEqual(result["role"], "retrospective_reconstruction_diagnostic")
        self.assertEqual(result["diagnostic_cutoff"], 3.2255731055094277)
        self.assertIn("73.15%", " ".join(result["calibration_caveats"]))
        self.assertTrue(np.isfinite(list(result["components"].values())).all())
        self.assertEqual(next(self.runtime.model.parameters()).device.type, "cpu")

    def test_mask_identity_depends_on_window_id_and_repeat_not_global_rng(self):
        pack, _ = self.runtime._prepare(self.records, 7001, "historical_measurements")
        a = self.runtime._mask(pack, 0)
        self.assertEqual(int(a.sum()), 94)
        self.assertTrue(np.array_equal(a, self.runtime._mask(pack, 0)))
        self.assertFalse(np.array_equal(a, self.runtime._mask(pack, 1)))

    def test_weather_only_and_unobserved_generation_fail_closed(self):
        for name in ("kWh_solar_power_solar", "kWh_wind_power_wind"):
            records = copy.deepcopy(self.records)
            del records[0][name]
            with self.assertRaisesRegex(ValueError, "observed signal"):
                self.runtime.score(records)
            records = copy.deepcopy(self.records)
            records[0]["observed"] = {column: column != name for column in SIGNAL_COLUMNS}
            with self.assertRaisesRegex(ValueError, "marked observed"):
                self.runtime.score(records)
        with self.assertRaisesRegex(ValueError, "historical_measurements only"):
            self.runtime.score(self.records, source_kind="weather_forecast")

    def test_nonfinite_values_and_all_null_generation_fail_closed(self):
        for value in (None, float("nan"), float("inf"), True, "1.0", 10**1000):
            records = copy.deepcopy(self.records)
            for row in records:
                row["kWh_solar_power_solar"] = value
            with self.assertRaisesRegex(ValueError, "observed signal"):
                self.runtime.score(records)

    def test_row_declarations_cannot_override_measurement_provenance(self):
        for field, value in (("source_kind", "weather_forecast"), ("source_kind", "imputed"), ("observed", None)):
            records = copy.deepcopy(self.records)
            records[0][field] = value
            with self.assertRaises(ValueError):
                self.runtime.score(records)

    def test_hourly_timestamps_and_historical_boundary_are_enforced(self):
        for replacement in (self.records[0]["timestamp"], "2019-02-01T02:30:00+00:00", "2019-02-01T01:00:00"):
            records = copy.deepcopy(self.records)
            records[1]["timestamp"] = replacement
            with self.assertRaises(ValueError):
                self.runtime.score(records)
        start = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0) + timedelta(days=1)
        for i, row in enumerate(self.records):
            row["timestamp"] = (start + timedelta(hours=i)).isoformat()
        with self.assertRaisesRegex(ValueError, "retrospective"):
            self.runtime.score(self.records)

    def test_regularly_spaced_half_hour_windows_are_rejected(self):
        for row in self.records:
            stamp = datetime.fromisoformat(row["timestamp"]) + timedelta(minutes=30)
            row["timestamp"] = stamp.isoformat()
        with self.assertRaisesRegex(ValueError, "exact whole hours"):
            self.runtime.score(self.records)

    def test_input_size_aliases_and_window_id_are_checked(self):
        with self.assertRaisesRegex(ValueError, "exactly 24"):
            self.runtime.score(self.records[:-1])
        with self.assertRaisesRegex(ValueError, "window_id"):
            self.runtime.score(self.records, window_id=-1)
        self.records[0]["relative_humidity_solar"] = 90.0
        with self.assertRaisesRegex(ValueError, "Humidity aliases"):
            self.runtime.score(self.records)

    def test_integrity_failure_occurs_before_any_deserialization(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ARTIFACT_HASHES:
                shutil.copyfile(MODEL_DIR / name, Path(directory) / name)
            target = Path(directory) / "state.pt"
            data = bytearray(target.read_bytes())
            data[-1] ^= 1
            target.write_bytes(data)
            with patch("app.ssl_qc_runtime.joblib.load") as joblib_load, patch("app.ssl_qc_runtime.torch.load") as torch_load:
                with self.assertRaisesRegex(ValueError, "integrity mismatch"):
                    SSLQCRuntime(directory).load()
                joblib_load.assert_not_called()
                torch_load.assert_not_called()

    def test_portable_frozen_golden_without_scientific_project(self):
        """Real canonical rows and notebook-derived expected values ship here.

        Mask/preprocessing bytes are deterministic. A small floating-point
        tolerance permits CPU architecture differences in neural/sklearn math.
        """
        fixture = json.loads(GOLDEN_FIXTURE.read_text())
        self.assertEqual(fixture["source_dataset_sha256"], self.runtime.meta()["source_dataset_sha256"])
        self.assertEqual(hashlib.sha256(GOLDEN_FIXTURE.read_bytes()).hexdigest(), ARTIFACT_HASHES["golden_inference.json"])
        self.assertEqual(fixture["run_id"], self.runtime.meta()["model_version"])
        self.assertEqual(fixture["checkpoint_sha256"], ARTIFACT_HASHES["state.pt"])
        self.assertEqual(fixture["preprocessor_sha256"], ARTIFACT_HASHES["preprocessor.json"])
        self.assertEqual(fixture["qc_system_sha256"], ARTIFACT_HASHES["qc_system.joblib"])
        for case in fixture["cases"]:
            with self.subTest(window_id=case["window_id"]):
                prepared, _ = self.runtime._prepare(case["records"], case["window_id"], "historical_measurements")
                expected = case["expected"]
                self.assertEqual(
                    hashlib.sha256(prepared["W"].astype("<f4").tobytes()).hexdigest(),
                    expected["preprocessed_float32_le_sha256"],
                )
                for repeat, expected_hash in enumerate(expected["mask_sha256"]):
                    self.assertEqual(hashlib.sha256(self.runtime._mask(prepared, repeat).tobytes()).hexdigest(), expected_hash)
                actual = self.runtime.score(case["records"], window_id=case["window_id"])
                np.testing.assert_allclose(actual["qc_score"], expected["qc_score"], rtol=1e-5, atol=1e-6)
                for name, value in expected["components"].items():
                    np.testing.assert_allclose(actual["components"][name], value, rtol=1e-5, atol=1e-6)

    def test_parity_with_exported_training_definitions(self):
        """Execute only verified inference definitions, never training statements."""
        source_path = MODEL_DIR / "architecture_source.txt"
        self.assertEqual(hashlib.sha256(source_path.read_bytes()).hexdigest(), ARTIFACT_HASHES["architecture_source.txt"])
        tree = ast.parse(source_path.read_text())
        wanted = {
            "transform_frame", "exact_masks", "masked_input", "per_window_error",
            "predict_neural", "extract_embeddings", "DualAxisMaskedReconstructor",
            "apply_robust_z", "repeated_window_rmse", "qc_components",
        }
        definitions = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in wanted]
        self.assertEqual({node.name for node in definitions}, wanted)
        environment = {
            "np": np, "pd": pd, "torch": torch, "nn": nn,
            "Optional": Optional, "Path": Path,
            "SIGNAL_COLS": list(SIGNAL_COLUMNS), "FEATURE_COLS": list(FEATURE_COLUMNS),
            "TARGETS": list(SIGNAL_COLUMNS[-2:]), "device": torch.device("cpu"),
            "CFG": {"qc": {"batch_size": 64, "mc_passes": 0}, "evaluation": {"batch_size": 128}},
        }
        exec(compile(ast.Module(body=definitions, type_ignores=[]), str(source_path), "exec"), environment)
        with torch.random.fork_rng(devices=[]):
            source_model = environment["DualAxisMaskedReconstructor"](24, 13, 96, 4, 2, 2, 0.1, "FULL")
        weights = (MODEL_DIR / "state.pt").read_bytes()
        self.assertEqual(hashlib.sha256(weights).hexdigest(), ARTIFACT_HASHES["state.pt"])
        source_model.load_state_dict(torch.load(io.BytesIO(weights), map_location="cpu", weights_only=True))
        source_model.eval()
        fixture = json.loads(GOLDEN_FIXTURE.read_text())
        for case in fixture["cases"]:
            raw = pd.DataFrame(case["records"])
            raw["timestamp"] = pd.to_datetime(raw["timestamp"])
            prepared, _ = self.runtime._prepare(case["records"], case["window_id"], "historical_measurements")
            canonical = environment["transform_frame"](raw, self.runtime.preprocessor).to_numpy()[None]
            np.testing.assert_array_equal(prepared["W"], canonical)
            for repeat in range(5):
                expected_mask = environment["exact_masks"](prepared, 0.3, 42, repeat)
                np.testing.assert_array_equal(self.runtime._mask(prepared, repeat), expected_mask)
            expected, parts = environment["qc_components"](source_model, self.runtime.system, prepared, 0.3, 42, 5)
            actual = self.runtime.score(case["records"], window_id=case["window_id"])
            np.testing.assert_allclose(actual["qc_score"], expected[0], rtol=1e-7, atol=1e-7)
            for name, values in parts.items():
                np.testing.assert_allclose(actual["components"][name], values[0], rtol=1e-7, atol=1e-7)


if __name__ == "__main__":
    unittest.main()

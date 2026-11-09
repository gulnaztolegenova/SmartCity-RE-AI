"""HTTP integration contract for retrospective SSL-QC diagnostics.

These tests isolate routing and validation from neural inference. Golden tests
for the actual frozen artifacts live in test_ssl_qc_runtime.py.

Run from the server directory: python -m unittest discover -s tests -v
"""

from __future__ import annotations

import asyncio
import copy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient

from app import main


def historical_records() -> list[dict]:
    start = datetime(2019, 8, 1, tzinfo=timezone.utc)
    return [
        {
            "timestamp": (start + timedelta(hours=i)).isoformat(),
            "temperature_solar": 20.0,
            "humidity_solar": 0.01,
            "surface_irradiance_solar": 200.0,
            "toa_irradiance_solar": 500.0,
            "kWh_solar_power_solar": 800.0,
            "specific_humidity_solar": 0.01,
            "relative_humidity_solar": 1.0,
            "air_density_wind": 1.225,
            "wind_speed_wind": 5.0,
            "kWh_wind_power_wind": 300.0,
        }
        for i in range(24)
    ]


class SSLQCAPIContractTests(unittest.TestCase):
    def setUp(self):
        self.metadata = {
            "model_name": "SSL-QC",
            "model_version": "frozen-test-version",
            "role": "retrospective_reconstruction_diagnostic",
            "source_kind": "historical_measurements",
        }
        self.result = {
            **self.metadata,
            "n": 24,
            "qc_score": 1.25,
            "components": {"rmse": 0.1, "nll": 0.2, "distance": 0.3},
            "normalized_components": {"rmse": 0.2, "nll": 0.4, "distance": 0.65},
            "diagnostic_cutoff": 1.5,
            "above_reference_cutoff": False,
            "caveats": ["A diagnostic score is not an extreme-generation probability."],
        }
        self.runtime = SimpleNamespace(
            is_loaded=True,
            model_name="SSL-QC",
            model_version="frozen-test-version",
            meta=Mock(return_value=copy.deepcopy(self.metadata)),
            score=Mock(return_value=copy.deepcopy(self.result)),
        )
        self.qc_patch = patch.object(main, "ssl_qc_runtime", self.runtime)
        self.qc_patch.start()
        self.addCleanup(self.qc_patch.stop)
        # No lifespan here: route tests must not load models or contact services.
        self.client = TestClient(main.app)
        self.addCleanup(self.client.close)

    def test_metadata_describes_qc_role_without_relabeling_forecasts(self):
        response = self.client.get("/qc/meta")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), self.metadata)
        self.runtime.meta.assert_called_once_with()
        self.runtime.score.assert_not_called()

    def test_score_forwards_original_records_and_explicit_window_identity(self):
        records = historical_records()
        response = self.client.post(
            "/qc/score",
            json={"records": records, "window_id": 42, "source_kind": "historical_measurements"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), self.result)
        self.runtime.score.assert_called_once_with(
            records, window_id=42, source_kind="historical_measurements"
        )
        self.assertNotIn("p_extreme", response.json())
        self.assertNotIn("y_pred", response.json())

    def test_default_window_identity_and_source_are_stable(self):
        records = historical_records()
        response = self.client.post("/qc/score", json={"records": records})
        self.assertEqual(response.status_code, 200)
        self.runtime.score.assert_called_once_with(
            records, window_id=0, source_kind="historical_measurements"
        )

    def test_schema_rejects_wrong_window_lengths_before_inference(self):
        for size in (0, 23, 25):
            with self.subTest(size=size):
                records = (historical_records() + historical_records())[:size]
                response = self.client.post("/qc/score", json={"records": records})
                self.assertEqual(response.status_code, 422)
        self.runtime.score.assert_not_called()

    def test_schema_rejects_forecast_source_before_inference(self):
        for source_kind in ("forecast", "open_meteo", "model_predictions"):
            with self.subTest(source_kind=source_kind):
                response = self.client.post(
                    "/qc/score",
                    json={"records": historical_records(), "source_kind": source_kind},
                )
                self.assertEqual(response.status_code, 422)
        self.runtime.score.assert_not_called()

    def test_schema_rejects_invalid_window_identity(self):
        for window_id in (-1, 1_000_000_001, True, 1.5, "42"):
            with self.subTest(window_id=window_id):
                response = self.client.post(
                    "/qc/score", json={"records": historical_records(), "window_id": window_id}
                )
                self.assertEqual(response.status_code, 422)
        self.runtime.score.assert_not_called()

    def test_schema_rejects_unrecognized_top_level_options(self):
        response = self.client.post(
            "/qc/score", json={"records": historical_records(), "allow_forecast_inputs": True}
        )
        self.assertEqual(response.status_code, 422)
        self.runtime.score.assert_not_called()

    def test_runtime_scientific_validation_is_a_422_not_a_successful_fallback(self):
        self.runtime.score.side_effect = ValueError("Measured generation is required for SSL-QC")
        response = self.client.post("/qc/score", json={"records": historical_records()})
        self.assertEqual(response.status_code, 422)
        self.assertIn("Measured generation", response.json()["detail"])
        self.assertNotIn("qc_score", response.json())

    def test_missing_or_unloaded_qc_returns_503(self):
        for runtime in (None, SimpleNamespace(is_loaded=False)):
            with self.subTest(runtime=runtime), patch.object(main, "ssl_qc_runtime", runtime):
                self.assertEqual(self.client.get("/qc/meta").status_code, 503)
                response = self.client.post("/qc/score", json={"records": historical_records()})
                self.assertEqual(response.status_code, 503)
        self.runtime.score.assert_not_called()

    def test_health_reports_qc_and_forecasting_independently(self):
        renewable = SimpleNamespace(
            is_loaded=True, model_name="DP-STH++", model_version="weather-v1"
        )
        with patch.object(main, "runtime", renewable):
            payload = self.client.get("/health").json()
        self.assertTrue(payload["ssl_qc_model_loaded"])
        self.assertTrue(payload["model_loaded"])
        self.assertEqual(payload["model_name"], "DP-STH++")
        self.assertEqual(payload["model_version"], "weather-v1")
        with patch.object(main, "ssl_qc_runtime", None):
            self.assertFalse(self.client.get("/health").json()["ssl_qc_model_loaded"])

    def test_root_lists_qc_routes_and_preserves_existing_routes(self):
        payload = self.client.get("/").json()
        for route in ("/qc/meta", "/qc/score", "/forecast/7d", "/forecast/14d", "/load/meta", "/energy/balance", "/optimize"):
            self.assertIn(route, payload["endpoints"])

    def test_startup_fails_if_the_required_qc_artifact_cannot_load(self):
        renewable_loader = Mock()
        renewable_loader.load.return_value = SimpleNamespace(is_loaded=True)
        load_loader = Mock()
        load_loader.load.return_value = SimpleNamespace(is_loaded=True)
        qc_loader = Mock()
        qc_loader.load.side_effect = FileNotFoundError("SSL-QC artifact unavailable")
        with (
            patch.object(main, "WeatherModelRuntime", return_value=renewable_loader),
            patch.object(main, "LoadModelRuntime", return_value=load_loader),
            patch.object(main, "SSLQCRuntime", return_value=qc_loader),
            patch.object(main, "runtime"),
            patch.object(main, "load_runtime"),
            self.assertRaisesRegex(FileNotFoundError, "SSL-QC artifact unavailable"),
        ):
            # Exercise the registered startup callable directly: a failed
            # TestClient lifespan leaks AnyIO streams in the pinned Starlette.
            asyncio.run(main._startup())


if __name__ == "__main__":
    unittest.main()

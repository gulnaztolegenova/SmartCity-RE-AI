"""Joint routing must run both real tasks without claiming QC edits a forecast."""
import copy
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from app import main


class GenerationAPIContractTests(unittest.TestCase):
    def setUp(self):
        self.records = [{"timestamp": f"2019-01-02T{h:02d}:00:00+00:00"} for h in range(24)]
        self.events = []
        self.qc_result = {"above_reference_cutoff": True, "qc_score": 4.5}
        self.dp_result = {"model_name": "DP-STH++", "raw_predictions": {"solar": -0.25, "wind": 20.0}}
        self.qc = SimpleNamespace(is_loaded=True, score=Mock(side_effect=self.score), meta=Mock(return_value={"model_name": "SSL-QC / DualAxis"}))
        self.dp = SimpleNamespace(is_loaded=True, predict=Mock(side_effect=self.predict), meta=Mock(return_value={"model_name": "DP-STH++"}))
        for name, value in (("ssl_qc_runtime", self.qc), ("dp_sthpp_runtime", self.dp)):
            p = patch.object(main, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.client = TestClient(main.app)
        self.addCleanup(self.client.close)

    def score(self, records, **kwargs):
        self.events.append("QC")
        return copy.deepcopy(self.qc_result)

    def predict(self, records, **kwargs):
        self.events.append("DP")
        return copy.deepcopy(self.dp_result)

    def test_joint_request_calls_both_and_preserves_negative_raw_forecast(self):
        body = {"records": self.records, "window_id": 123}
        response = self.client.post("/generation/analyze", json=body)
        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertEqual(self.events, ["QC", "DP"])
        self.qc.score.assert_called_once_with(self.records, window_id=123, source_kind="historical_measurements")
        self.dp.predict.assert_called_once_with(self.records, source_kind="historical_measurements")
        self.assertEqual(result["forecast"], self.dp_result)
        self.assertEqual(result["quality"], self.qc_result)
        self.assertFalse(result["forecast_modified_by_qc"])
        self.assertFalse(result["operational_fault_alarm"])
        self.assertEqual(result["quality_advisory"], "above_research_reference")

    def test_invalid_qc_input_stops_joint_request_before_forecasting(self):
        self.qc.score.side_effect = ValueError("Missing observed generation")
        response = self.client.post("/generation/analyze", json={"records": self.records})
        self.assertEqual(response.status_code, 422)
        self.dp.predict.assert_not_called()

    def test_either_unavailable_model_prevents_partial_success(self):
        for name in ("ssl_qc_runtime", "dp_sthpp_runtime"):
            with patch.object(main, name, None):
                self.assertEqual(self.client.post("/generation/analyze", json={"records": self.records}).status_code, 503)
                self.assertEqual(self.client.get("/generation/meta").status_code, 503)
        self.qc.score.assert_not_called()
        self.dp.predict.assert_not_called()

    def test_no_model_selector_capacity_or_multiday_override(self):
        for option in ({"days": 14}, {"model": "DualAxis"}, {"capacity_kw": 20}, {"source_kind": "weather_forecast"}):
            with self.subTest(option=option):
                r = self.client.post("/generation/analyze", json={"records": self.records, **option})
                self.assertEqual(r.status_code, 422)
        self.dp.predict.assert_not_called()
        self.qc.score.assert_not_called()

    def test_dedicated_prediction_calls_only_dp(self):
        response = self.client.post("/generation/predict", json={"records": self.records})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), self.dp_result)
        self.qc.score.assert_not_called()
        self.assertEqual(self.events, ["DP"])

    def test_metadata_distinguishes_weather_adaptation_from_article_weights(self):
        result = self.client.get("/generation/meta").json()
        self.assertEqual(result["forecast_model"]["model_name"], "DP-STH++")
        self.assertTrue(result["weather_forecast_endpoints"]["uses_dp_sthpp"])
        self.assertTrue(result["weather_forecast_endpoints"]["uses_ssl_qc"])
        self.assertIn("adaptation", result["weather_forecast_endpoints"]["variant"])

    def test_bad_dp_input_returns_422_without_fallback(self):
        self.dp.predict.side_effect = ValueError("Invalid observed history")
        for endpoint in ("/generation/predict", "/generation/analyze"):
            self.assertEqual(self.client.post(endpoint, json={"records": self.records}).status_code, 422)


if __name__ == "__main__":
    unittest.main()

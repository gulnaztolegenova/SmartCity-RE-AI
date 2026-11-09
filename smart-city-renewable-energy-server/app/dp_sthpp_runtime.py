"""Frozen DP-STH++ v3 CPU inference for one step after 24 observed hours.

The constructor reproduces the reviewed source architecture without loading
serialized Lambda code or an optimizer. Source data units and timezone were
not verified, so this runtime performs no site-capacity or energy-unit conversion.
"""
from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import numpy as np


MODEL_VERSION = "dp-sthpp-v3-csv-cpu-20261013T143156623652Z"
FEATURE_COLUMNS = (
    "temperature_solar", "relative_humidity_solar", "surface_irradiance_solar",
    "toa_irradiance_solar", "air_density_wind", "wind_speed_wind",
    "hour", "dayofweek", "month", "season_code",
    "kWh_solar_power_solar", "kWh_wind_power_wind",
)
CALENDAR_COLUMNS = ("hour", "dayofweek", "month", "season_code")
SIGNAL_COLUMNS = tuple(name for name in FEATURE_COLUMNS if name not in CALENDAR_COLUMNS)
TARGET_COLUMNS = ("kWh_solar_power_solar", "kWh_wind_power_wind")
ARTIFACT_HASHES = {
    "dp_sthpp.weights.h5": "122967a1dae455cdfd5a9df258ede46b82f60e955e4abb6c0f44dccb63155ee4",
    "preprocessing.json": "f1fe2d6b00fa0f0d3ffaeeea8e7a19c45dd6c5f47f5491b67bd1015318e0dd0f",
    "architecture_source.txt": "0fa9685c11a829f90c07b2365324f3020410b07bf6ba269d33cf9a917167a888",
    "architecture_spec.json": "219f885c1739083bc27232d7463ca20df6cdf4e1b47426912dfae1fe8d42736b",
    "artifact_manifest.json": "ec8da0759dd2193fa00202030e2225168ca57514812306d3acef44c8ae4b5e23",
    "protocol.json": "ae66e5044b4b783acd5b3463e723fdd24b62a527d94d2de2f01fe88aa825068b",
    "environment.json": "f6522281b6d0e0c6c75c179d41567803a5d8a7be2ad0db05e582bc17825c4fe3",
    "reload_validation.json": "ee882baaed0303010843e080eae89032bebf9842d5024ba53e7618f00f54d8a9",
    "training_summary.json": "3d4ae6f341c713c2325f064e17793817138e1cde1e584b0718736a933d821283",
    "source_validation.json": "a4718b84d36e77833755905cd120406d83546e120df4114d549799e9bf94f474",
}
CAVEATS = (
    "Only a one-hour-ahead forecast with 24 observed prior hours was evaluated; recursive 7/14-day forecasting is not validated.",
    "Raw outputs retain the canonical dataset scale. Legacy kWh column names do not establish physical units, installed capacity, or site-transfer calibration.",
    "Negative regression outputs are preserved, without clipping. Historical holdout contained 687 negative solar and 23 negative wind predictions out of 1746 per target.",
    "Extreme outputs are raw sigmoid scores for exceeding the fit-split q90 generation threshold, not calibrated warning probabilities or fault probabilities.",
    "The historical holdout is retrospective and previously explored; metrics do not establish independent prospective or new-site performance.",
    "All eight signals must be observed measurements in the source feature scale. The source relative_humidity_solar alias is not verified meteorological RH percent; Open-Meteo substitution is unsupported.",
    "The source timezone is unspecified. Calendar features follow the supplied local clock with a common explicit UTC offset; that offset does not establish source-site alignment.",
    "Measurement provenance is declared by the caller and cannot be independently established from numerical records alone.",
)


def _build_model(tf: Any) -> Any:
    """Inference equivalent of architecture_source.txt, fixed v3 parameters.

    Layer order, all weight-bearing layers and the original residual scaling
    are retained. Compilation/loss functions are unnecessary for prediction.
    """
    layers = tf.keras.layers

    class LossScaleLayer(layers.Layer):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.log_var_solar_reg = self.add_weight(name="log_var_solar_reg", shape=(), initializer="zeros", trainable=True)
            self.log_var_wind_reg = self.add_weight(name="log_var_wind_reg", shape=(), initializer="zeros", trainable=True)

        def call(self, inputs):
            return inputs

    def transformer_block(x):
        x_ln = layers.LayerNormalization()(x)
        attn = layers.MultiHeadAttention(num_heads=4, key_dim=40)(x_ln, x_ln, use_causal_mask=True)
        attn = layers.Dropout(0.15)(attn)
        x = layers.Add()([x, attn])
        y_ln = layers.LayerNormalization()(x)
        ff = layers.Dense(256, activation="relu")(y_ln)
        ff = layers.Dropout(0.15)(ff)
        ff = layers.Dense(160)(ff)
        return layers.Add()([x, ff])

    seq_in = layers.Input(shape=(24, 12), name="seq_in")
    flat_in = layers.Input(shape=(12,), name="flat_in")
    b1 = layers.LSTM(128, return_sequences=True)(seq_in)
    b1 = layers.Dropout(0.15 * 0.5)(b1)
    b1 = layers.LSTM(64, return_sequences=True)(b1)
    b1 = layers.GlobalAveragePooling1D()(b1)
    b2 = layers.GRU(128, return_sequences=True)(seq_in)
    b2 = layers.Dropout(0.15 * 0.5)(b2)
    b2 = layers.GRU(64, return_sequences=True)(b2)
    b2 = layers.GlobalAveragePooling1D()(b2)
    b3 = layers.Conv1D(128, kernel_size=3, dilation_rate=1, padding="causal", activation="relu")(seq_in)
    b3 = layers.Conv1D(128, kernel_size=3, dilation_rate=2, padding="causal", activation="relu")(b3)
    b3 = layers.Conv1D(64, kernel_size=3, dilation_rate=4, padding="causal", activation="relu")(b3)
    b3 = layers.GlobalAveragePooling1D()(b3)
    b4 = layers.Dense(160)(seq_in)
    b4 = transformer_block(b4)
    b4 = transformer_block(b4)
    b4 = layers.GlobalAveragePooling1D()(b4)
    p1 = layers.Dense(96, activation="relu")(b1)
    p2 = layers.Dense(96, activation="relu")(b2)
    p3 = layers.Dense(96, activation="relu")(b3)
    p4 = layers.Dense(96, activation="relu")(b4)
    gate = layers.Dense(4, activation="softmax", name="branch_gate")(flat_in)
    g1 = layers.Lambda(lambda x: tf.expand_dims(x[:, 0], axis=-1))(gate)
    g2 = layers.Lambda(lambda x: tf.expand_dims(x[:, 1], axis=-1))(gate)
    g3 = layers.Lambda(lambda x: tf.expand_dims(x[:, 2], axis=-1))(gate)
    g4 = layers.Lambda(lambda x: tf.expand_dims(x[:, 3], axis=-1))(gate)
    w1 = layers.Multiply()([p1, g1])
    w2 = layers.Multiply()([p2, g2])
    w3 = layers.Multiply()([p3, g3])
    w4 = layers.Multiply()([p4, g4])
    z = layers.Concatenate()([w1, w2, w3, w4, flat_in])
    z = layers.LayerNormalization()(z)
    z = layers.Dense(224, activation="relu")(z)
    z = layers.Dropout(0.15)(z)
    z = layers.Dense(128, activation="relu")(z)
    z = layers.Dropout(0.15 * 0.8)(z)
    z = LossScaleLayer(name="loss_scales")(z)
    last_targets = layers.Lambda(lambda x: x[:, -1, -2:], name="last_targets")(seq_in)
    last_solar = layers.Lambda(lambda x: x[:, 0:1])(last_targets)
    last_wind = layers.Lambda(lambda x: x[:, 1:2])(last_targets)
    delta_solar = layers.Dense(1, name="delta_solar")(z)
    delta_wind = layers.Dense(1, name="delta_wind")(z)
    solar_reg = layers.Add(name="solar_reg")([delta_solar, last_solar])
    wind_reg = layers.Add(name="wind_reg")([delta_wind, last_wind])
    cls = layers.Dense(96, activation="relu")(z)
    cls = layers.Dropout(0.15 * 0.8)(cls)
    solar_ext = layers.Dense(1, activation="sigmoid", name="solar_ext")(cls)
    wind_ext = layers.Dense(1, activation="sigmoid", name="wind_ext")(cls)
    return tf.keras.Model(inputs=[seq_in, flat_in], outputs=[solar_reg, wind_reg, solar_ext, wind_ext], name="DP_STHPP")


class DPSTHPPRuntime:
    """Hash-verified, CPU-only trained model; no weather or synthetic fallback."""

    def __init__(self, model_dir: str | Path = "models/dp_sthpp"):
        self.model_dir = Path(model_dir)
        self.model = None
        self.preprocessor: dict[str, Any] = {}
        self.manifest: dict[str, Any] = {}
        self._tf = None
        self._lock = threading.RLock()

    @property
    def is_loaded(self) -> bool:
        return self.model is not None

    def load(self) -> "DPSTHPPRuntime":
        with self._lock:
            # The same verified bytes are used to parse JSON and load weights.
            checked = {}
            for filename, expected in ARTIFACT_HASHES.items():
                content = (self.model_dir / filename).read_bytes()
                if hashlib.sha256(content).hexdigest() != expected:
                    raise ValueError(f"DP-STH++ artifact integrity mismatch: {filename}")
                checked[filename] = content
            prep = json.loads(checked["preprocessing.json"])
            spec = json.loads(checked["architecture_spec.json"])
            manifest = json.loads(checked["artifact_manifest.json"])
            if (prep["sequence_feature_order"] != list(FEATURE_COLUMNS)
                    or prep["target_order"] != list(TARGET_COLUMNS)
                    or spec["feature_order"] != list(FEATURE_COLUMNS)
                    or manifest["run_id"] != MODEL_VERSION):
                raise ValueError("DP-STH++ feature order or model version mismatch")
            # Lazy import allows read-only metadata/health imports without TF
            # initialization; the parent process sets its own thread policy.
            import tensorflow as tf
            if tf.__version__ != "2.18.1" or tf.keras.__version__ != "3.12.1":
                raise RuntimeError("DP-STH++ requires validated TensorFlow 2.18.1 and Keras 3.12.1")
            with tf.device("/CPU:0"):
                model = _build_model(tf)
                if model.count_params() != spec["parameter_count"]:
                    raise ValueError("DP-STH++ architecture parameter count mismatch")
                # Keras requires a filename for HDF5; snapshot already verified
                # bytes in a private temporary file rather than reopening input.
                with tempfile.TemporaryDirectory(prefix="dp-sthpp-weights-") as directory:
                    path = Path(directory) / "dp_sthpp.weights.h5"
                    path.write_bytes(checked["dp_sthpp.weights.h5"])
                    model.load_weights(path)
                model.trainable = False
            if any("CPU:" not in str(getattr(w, "value", w).device) for w in model.weights):
                raise RuntimeError("DP-STH++ weights were not loaded on CPU")
            self.preprocessor, self.manifest = prep, manifest
            self._tf, self.model = tf, model
        return self

    def meta(self) -> dict[str, Any]:
        return {
            "model_name": "DP-STH++", "model_version": MODEL_VERSION,
            "model_loaded": self.is_loaded,
            "role": "one_step_generation_forecast_from_observed_history",
            "architecture": "LSTM + GRU + causal Conv1D + causal Transformer; context gating and residual heads",
            "execution_backend": "CPU", "tensorflow": "2.18.1", "keras": "3.12.1",
            "checkpoint_sha256": ARTIFACT_HASHES["dp_sthpp.weights.h5"],
            "preprocessor_sha256": ARTIFACT_HASHES["preprocessing.json"],
            "architecture_source_sha256": ARTIFACT_HASHES["architecture_source.txt"],
            "source_dataset_sha256": "2771dd8b57aa43bc79944a9e8b2eb72d1214674056e601b997038fea164f1204",
            "required_signals": list(SIGNAL_COLUMNS), "features": list(FEATURE_COLUMNS),
            "derived_calendar_features": list(CALENDAR_COLUMNS),
            "season_codes": {"spring": 0, "summer": 1, "autumn": 2, "winter": 3},
            "context_rows": 24, "step_minutes": 60, "horizon_hours": 1,
            "validated_forecast_steps": 1, "requires_observed_generation": True,
            "source_kind": "historical_measurements", "allows_missing_values": False,
            "raw_prediction_units": "unverified source units", "capacity_scaling": "none",
            "negative_output_policy": "preserved_without_clipping",
            "extreme_quantile": 0.9, "extreme_threshold_comparison": ">=",
            "extreme_probability_calibration": "raw_sigmoid_not_calibrated",
            "warning_probability_threshold": None,
            "historical_holdout_metrics": copy.deepcopy(self.manifest.get("historical_holdout_metrics", [])),
            "training": copy.deepcopy(self.manifest.get("training", {})),
            "caveats": list(CAVEATS),
        }

    @staticmethod
    def _prepare(records: list[dict[str, Any]], source_kind: str) -> tuple[np.ndarray, list[datetime]]:
        if source_kind != "historical_measurements":
            raise ValueError("DP-STH++ accepts historical_measurements only; forecast or imputed inputs are unsupported")
        if not isinstance(records, list) or len(records) != 24 or not all(isinstance(row, dict) for row in records):
            raise ValueError("DP-STH++ requires exactly 24 hourly observed measurement records")
        parsed = []
        matrix = np.empty((24, len(FEATURE_COLUMNS)), dtype=np.float32)
        for i, row in enumerate(records):
            stamp = row.get("timestamp")
            if not isinstance(stamp, str):
                raise ValueError("Every measurement timestamp must be an ISO-8601 string with an explicit UTC offset")
            try:
                dt = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError as exc:
                raise ValueError("Invalid ISO-8601 measurement timestamp") from exc
            if dt.tzinfo is None or dt.utcoffset() is None:
                raise ValueError("Measurement timestamps must include an explicit UTC offset")
            if dt.minute or dt.second or dt.microsecond:
                raise ValueError("Measurements must fall on whole-hour timestamps")
            if parsed and dt.utcoffset() != parsed[0].utcoffset():
                raise ValueError("All timestamps must use the same UTC offset for local calendar features")
            if parsed and dt - parsed[-1] != timedelta(hours=1):
                raise ValueError("Measurement timestamps must be ascending and exactly one hour apart")
            parsed.append(dt)
            if row.get("source_kind", "historical_measurements") != "historical_measurements":
                raise ValueError("Forecast, imputed, and synthetic rows are unsupported")
            observed = row.get("observed")
            if "observed" in row and (not isinstance(observed, dict) or any(observed.get(c) is not True for c in SIGNAL_COLUMNS)):
                raise ValueError("Every required signal must be marked observed; imputed/forecast generation is unsupported")
            season = 3 if dt.month in (12, 1, 2) else (dt.month - 3) // 3
            calendar = {"hour": dt.hour, "dayofweek": dt.weekday(), "month": dt.month, "season_code": season}
            for name, expected in calendar.items():
                if name in row and (isinstance(row[name], bool) or not isinstance(row[name], (int, float)) or row[name] != expected):
                    raise ValueError(f"Calendar feature {name} contradicts the measurement timestamp")
            for j, name in enumerate(FEATURE_COLUMNS):
                value = calendar[name] if name in calendar else row.get(name)
                if isinstance(value, bool) or not isinstance(value, (float, int)):
                    raise ValueError(f"Missing or nonfinite observed signal: {name}")
                try:
                    number = float(value)
                except (OverflowError, ValueError) as exc:
                    raise ValueError(f"Observed signal exceeds the supported numeric range: {name}") from exc
                if abs(number) > float(np.finfo(np.float32).max):
                    raise ValueError(f"Observed signal exceeds the supported float32 range: {name}")
                if not np.isfinite(number):
                    raise ValueError(f"Missing or nonfinite observed signal: {name}")
                matrix[i, j] = number
        if parsed[-1].astimezone(timezone.utc) > datetime.now(timezone.utc):
            raise ValueError("Historical measurement records cannot contain future timestamps")
        return matrix, parsed

    def predict(self, records: list[dict[str, Any]], *, source_kind: str = "historical_measurements") -> dict[str, Any]:
        with self._lock:
            if not self.is_loaded:
                raise RuntimeError("DP-STH++ model is not loaded")
            matrix, parsed = self._prepare(records, source_kind)
            # Same JSON transform used by the export's CPU reload validation.
            with np.errstate(over="ignore", invalid="ignore"):
                scaled = ((matrix - np.asarray(self.preprocessor["x"]["mean"])) / np.asarray(self.preprocessor["x"]["scale"])).astype(np.float32)
            if not np.isfinite(scaled).all():
                raise ValueError("Observed input is nonfinite after frozen scaling")
            with self._tf.device("/CPU:0"):
                outputs = self.model({"seq_in": scaled[None], "flat_in": scaled[-1:]}, training=False)
            if len(outputs) != 4 or any(tuple(x.shape) != (1, 1) for x in outputs):
                raise RuntimeError("DP-STH++ produced an invalid output shape")
            if any("CPU:" not in str(x.device) for x in outputs):
                raise RuntimeError("DP-STH++ prediction did not execute on CPU")
            regression = np.array([float(outputs[0][0, 0]), float(outputs[1][0, 0])])
            raw = regression * np.asarray(self.preprocessor["y"]["scale"]) + np.asarray(self.preprocessor["y"]["mean"])
            probability = np.array([float(outputs[2][0, 0]), float(outputs[3][0, 0])])
            if not np.isfinite(raw).all() or not np.isfinite(probability).all() or ((probability < 0) | (probability > 1)).any():
                raise RuntimeError("DP-STH++ produced invalid or nonfinite predictions")
            return {
                "model_name": "DP-STH++", "model_version": MODEL_VERSION,
                "role": "one_step_generation_forecast_from_observed_history",
                "source_kind": source_kind, "context_rows": 24,
                "context_start": parsed[0].isoformat(), "context_end": parsed[-1].isoformat(),
                "forecast_timestamp": (parsed[-1] + timedelta(hours=1)).isoformat(),
                "horizon_hours": 1, "step_minutes": 60,
                "raw_prediction_units": "unverified source units",
                "predictions_raw": dict(zip(TARGET_COLUMNS, map(float, raw))),
                "negative_raw_outputs": [name for name, value in zip(TARGET_COLUMNS, raw) if value < 0],
                "extreme_probabilities_raw": dict(zip(TARGET_COLUMNS, map(float, probability))),
                "extreme_thresholds_source_units": dict(zip(TARGET_COLUMNS, self.preprocessor["extreme_thresholds_source_units"])),
                "extreme_quantile": 0.9, "extreme_threshold_comparison": ">=",
                "warning_probability_threshold": None,
                "checkpoint_sha256": ARTIFACT_HASHES["dp_sthpp.weights.h5"],
                "preprocessor_sha256": ARTIFACT_HASHES["preprocessing.json"],
                "caveats": list(CAVEATS),
            }

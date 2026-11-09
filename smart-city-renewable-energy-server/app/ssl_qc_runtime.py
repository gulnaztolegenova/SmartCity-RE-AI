"""Fresh-trained Gulnaz_T_N2_DualAxis inference for observed historical 24-hour windows.

This is retrospective reconstruction/QC, not forecasting or a fault detector.
The notebook implementation and fitted preprocessing/calibration remain fixed.
"""
from __future__ import annotations

import hashlib
import io
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
import torch
from torch import nn


SIGNAL_COLUMNS = (
    "surface_irradiance_solar", "toa_irradiance_solar", "temperature_solar",
    "humidity_solar", "relative_humidity_solar", "specific_humidity_solar",
    "wind_speed_wind", "air_density_wind", "kWh_solar_power_solar",
    "kWh_wind_power_wind",
)
FEATURE_COLUMNS = (*SIGNAL_COLUMNS, "hour", "month", "doy")
ARTIFACT_HASHES = {
    "architecture_source.txt": "b9fe1946616c93e8570e50c315d406d0a22983f89fd406f79a26e99abdd53fbc",
    "environment.json": "fe8ab0f10a64f6e1c0892dcec1d040b43ececc128ba11ce805f730ff978241ce",
    "state.pt": "e08dd4cd2076a797ff024a9abb66bb185795b6757e37df2710f3652ea364290f",
    "metadata.json": "01950fbf11abc0ce0b220ca238c648a3ba05ffdf31cdf232b1963d8a83685a77",
    "preprocessor.json": "6928855c004af1360324bb856285d11b0303a1512311ae932cfed4ba746385e4",
    "qc_system.joblib": "12b7a1d077f574eaae711fa9bf43633b8ef953e3ae1125d3652742d3c37d85d8",
    "frozen_calibration.json": "a600c9f2a1cc546f78f5398022ed0867399dee6c5037645314c158b9899e1855",
    "training_specification.json": "670acf4ab8f1ef52530a38924d807d528c4091d3985e0345f31d9959f68b4c0c",
    "frozen_before_holdout.json": "bae6b03ed1cf95b0b7588d32290a9af7baf9d7182de62f0337d0299fc38bac37",
    "holdout_evaluation.json": "95c9ba18b4ec8b0235864da95b7cdd5cb5400441337e5a20ad39c2bf56aa1be1",
    "golden_inference.json": "2d4aba5c220625731b553c723ee74a007e20dcd9965b012c2da0851b0fa8933e",
    "reload_verification.json": "a2b6246c28abababd082e4134e3021b47c62b9fdbe3388975e672d90d5d4b9f0",
    "history.csv": "45d1e257559915c498337bdb40c73e630e7f64303f9432eea4dba0a9202881cd",
    "provenance.json": "4862b49fdd2722974c0ce725b857c2a7f7ee4436b35d6e8e8e6be06d72e3ccc7",
    "completion.json": "bc58501e3b71381378cfc5b3aff6783d5ea0e18f5766e9dec1a98feca5fe17cd"
}
CALIBRATION_CAVEATS = [
    "A reconstruction diagnostic, not a probability or a confirmed equipment/sensor fault.",
    "The reference threshold is the validation 99th percentile; validation also selected the checkpoint.",
    "73.15% of unmodified retrospective holdout windows in this fresh training run exceeded this threshold; distribution shift is material.",
    "The source physical units, site and timezone are unspecified; legacy kWh column names do not verify units.",
    "No calibration for Open-Meteo forecasts, new sites, absent generation channels or operating faults is established.",
    "Input clipping can suppress extreme deviations; original values are not silently replaced in the caller's data.",
]


class DualAxisMaskedReconstructor(nn.Module):
    """Exact FULL architecture from the verified fresh-training export source."""

    def __init__(self) -> None:
        super().__init__()
        self.L, self.D, self.d_model = 24, 13, 96
        self.val_proj = nn.Linear(1, 96)
        self.time_pos = nn.Parameter(torch.zeros(24, 96))
        self.feat_emb = nn.Parameter(torch.zeros(13, 96))

        def encoder() -> nn.TransformerEncoder:
            layer = nn.TransformerEncoderLayer(
                96, 4, dim_feedforward=384, dropout=0.1,
                batch_first=True, activation="gelu", norm_first=True,
            )
            return nn.TransformerEncoder(layer, num_layers=2, enable_nested_tensor=False)

        self.temporal = encoder()
        self.feature = encoder()
        self.out_proj = nn.Linear(96, 1)

    def tokens(self, x: torch.Tensor) -> torch.Tensor:
        b, length, d = x.shape
        if (length, d) != (self.L, self.D):
            raise ValueError("DualAxis requires 24 hourly rows and 13 ordered features")
        tok = self.val_proj(x.unsqueeze(-1)) + self.time_pos[None, :, None, :] + self.feat_emb[None, None, :, :]
        tok = self.temporal(tok.permute(0, 2, 1, 3).reshape(b * d, length, self.d_model))
        tok = tok.reshape(b, d, length, self.d_model).permute(0, 2, 1, 3).contiguous()
        tok = self.feature(tok.reshape(b * length, d, self.d_model))
        return tok.reshape(b, length, d, self.d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.out_proj(self.tokens(x)).squeeze(-1)

    def get_embedding(self, x: torch.Tensor) -> torch.Tensor:
        return self.tokens(x).mean(dim=(1, 2))


class SSLQCRuntime:
    """An immutable, hash-verified CPU model and research QC calibration."""

    def __init__(self, model_dir: str | Path):
        self.model_dir = Path(model_dir)
        self.model: DualAxisMaskedReconstructor | None = None
        self.preprocessor: dict[str, Any] = {}
        self.system: dict[str, Any] = {}

    @property
    def is_loaded(self) -> bool:
        return self.model is not None

    def load(self) -> "SSLQCRuntime":
        # Hash all bytes before any pickle deserialization. Read from those same
        # verified bytes to avoid a file substitution between checking and loading.
        checked = {}
        for filename, expected in ARTIFACT_HASHES.items():
            content = (self.model_dir / filename).read_bytes()
            if hashlib.sha256(content).hexdigest() != expected:
                raise ValueError(f"SSL-QC artifact integrity mismatch: {filename}")
            checked[filename] = content
        parameters = json.loads(checked["preprocessor.json"])
        if parameters["cols"] != list(SIGNAL_COLUMNS):
            raise ValueError("SSL-QC preprocessing feature order does not match the checkpoint")
        calibration = json.loads(checked["frozen_calibration.json"])
        metadata = json.loads(checked["metadata.json"])
        provenance = json.loads(checked["provenance.json"])
        completion = json.loads(checked["completion.json"])
        if (
            metadata["run_id"] != self.meta()["model_version"]
            or provenance["run_id"] != metadata["run_id"]
            or calibration["run_id"] != metadata["run_id"]
            or completion["run_id"] != metadata["run_id"]
            or completion["status"] != "complete"
            or not completion["fresh_training_completed"]
            or not completion["new_qc_calibration_completed"]
            or completion["provenance_sha256"] != ARTIFACT_HASHES["provenance.json"]
            or metadata["checkpoint_hash"] != ARTIFACT_HASHES["state.pt"]
            or metadata["preprocessor_hash"] != ARTIFACT_HASHES["preprocessor.json"]
            or calibration["checkpoint_hash"] != ARTIFACT_HASHES["state.pt"]
            or calibration["preprocessor_hash"] != ARTIFACT_HASHES["preprocessor.json"]
            or calibration["qc_system_hash"] != ARTIFACT_HASHES["qc_system.joblib"]
        ):
            raise ValueError("SSL-QC artifacts do not describe one completed training/calibration run")
        # Initialization is overwritten by the trained weights. Keep its random
        # draws from perturbing any other models' process-level CPU RNG state.
        with torch.random.fork_rng(devices=[]):
            model = DualAxisMaskedReconstructor()
        model.load_state_dict(torch.load(io.BytesIO(checked["state.pt"]), map_location="cpu", weights_only=True), strict=True)
        model.eval()
        system = joblib.load(io.BytesIO(checked["qc_system.joblib"]))
        if system["weights"] != calibration["qc_weights"] or system["cutoff"] != calibration["qc_cutoff"]:
            raise ValueError("SSL-QC calibration does not match the frozen artifact")
        self.preprocessor, self.system, self.model = parameters, system, model
        return self

    def meta(self) -> dict[str, Any]:
        return {
            "model_name": "SSL-QC / DualAxis",
            "model_version": "dualaxis-full-seed42-20261013T144409613629Z",
            "role": "retrospective_reconstruction_diagnostic",
            "model_loaded": self.is_loaded,
            "architecture": "DualAxis FULL, temporal then feature attention",
            "checkpoint_sha256": ARTIFACT_HASHES["state.pt"],
            "preprocessor_sha256": ARTIFACT_HASHES["preprocessor.json"],
            "calibration_sha256": ARTIFACT_HASHES["qc_system.joblib"],
            "provenance_sha256": ARTIFACT_HASHES["provenance.json"],
            "training_epochs": 25,
            "best_epoch": 25,
            "fresh_training": True,
            "fresh_qc_calibration": True,
            "source_project": "Gulnaz_T_N2_DualAxis",
            "source_dataset_sha256": "2771dd8b57aa43bc79944a9e8b2eb72d1214674056e601b997038fea164f1204",
            "required_signals": list(SIGNAL_COLUMNS),
            "features": list(FEATURE_COLUMNS),
            "context_rows": 24,
            "step_minutes": 60,
            "requires_observed_generation": True,
            "allows_missing_values": False,
            "source_units": "unspecified",
            "timestamp_policy": "Explicit common UTC offset; calendar uses supplied local clock; source timezone unspecified",
            "mask_rate": 0.3,
            "mask_repeats": 5,
            "mask_seed": 42,
            "qc_weights": {"rmse": 0.7, "nll": 0.2, "distance": 0.1},
            "diagnostic_cutoff": 3.2255731055094277,
            "retrospective_holdout_fraction_above_cutoff": 0.7314814814814815,
            "score_is_probability": False,
            "calibration_status": "research_reference_only_not_validated_for_new_sites",
            "calibration_caveats": list(CALIBRATION_CAVEATS),
        }

    def _prepare(self, records: list[dict[str, Any]], window_id: int, source_kind: str) -> tuple[dict[str, Any], dict[str, int]]:
        if source_kind != "historical_measurements":
            raise ValueError("SSL-QC accepts historical_measurements only; forecast weather/generation is unsupported")
        if isinstance(window_id, bool) or not isinstance(window_id, int) or not 0 <= window_id <= 2**63 - 1:
            raise ValueError("window_id must be an integer between 0 and 2**63-1")
        if not isinstance(records, list) or len(records) != 24 or not all(isinstance(row, dict) for row in records):
            raise ValueError("SSL-QC requires exactly 24 hourly measurement records")
        parsed = []
        values = np.empty((24, len(SIGNAL_COLUMNS)), dtype=float)
        for i, row in enumerate(records):
            stamp = row.get("timestamp")
            if not isinstance(stamp, str):
                raise ValueError("Each timestamp must be an ISO-8601 string with a UTC offset")
            try:
                dt = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError as exc:
                raise ValueError("Invalid ISO-8601 measurement timestamp") from exc
            if dt.tzinfo is None or dt.utcoffset() is None:
                raise ValueError("Measurement timestamps must include an explicit UTC offset")
            if dt.minute or dt.second or dt.microsecond:
                raise ValueError("Measurement timestamps must fall on exact whole hours")
            if parsed and dt.utcoffset() != parsed[0].utcoffset():
                raise ValueError("All timestamps must use the same UTC offset for calendar features")
            parsed.append(dt)
            if row.get("source_kind", "historical_measurements") != "historical_measurements":
                raise ValueError("Forecast, imputed and synthetic rows are unsupported")
            observed = row.get("observed")
            if "observed" in row and (not isinstance(observed, dict) or any(observed.get(c) is not True for c in SIGNAL_COLUMNS)):
                raise ValueError("Every required signal must be marked observed; imputed/forecast generation is unsupported")
            for j, name in enumerate(SIGNAL_COLUMNS):
                value = row.get(name)
                if isinstance(value, bool) or not isinstance(value, (float, int)):
                    raise ValueError(f"Missing or nonfinite observed signal: {name}")
                try:
                    value = float(value)
                except (TypeError, ValueError, OverflowError) as exc:
                    raise ValueError(f"Missing or nonfinite observed signal: {name}") from exc
                if not np.isfinite(value):
                    raise ValueError(f"Missing or nonfinite observed signal: {name}")
                values[i, j] = value
        timestamps = pd.DatetimeIndex(parsed).as_unit("ns")
        if not np.all(np.diff(timestamps.asi8) == pd.Timedelta(hours=1).value):
            raise ValueError("Measurement timestamps must be ascending, unique and exactly one hour apart")
        if parsed[-1].astimezone(timezone.utc) > datetime.now(timezone.utc):
            raise ValueError("SSL-QC is retrospective; future measurement timestamps are unsupported")
        if not np.allclose(values[:, 5], values[:, 3], rtol=1e-6, atol=1e-8) or not np.allclose(values[:, 4], 100 * values[:, 3], rtol=1e-6, atol=1e-8):
            raise ValueError("Humidity aliases must match source semantics: specific=humidity; relative=100*humidity")
        transformed = np.empty((24, 13), dtype=np.float32)
        outside = {}
        for j, name in enumerate(SIGNAL_COLUMNS):
            p = self.preprocessor["features"][name]
            raw = values[:, j]
            outside[name] = int(((raw < p["clip_lo"]) | (raw > p["clip_hi"])).sum())
            clipped = np.clip(raw, p["clip_lo"], p["clip_hi"])
            logged = np.sign(clipped) * np.log1p(np.abs(clipped))
            transformed[:, j] = (logged - p["min"]) / p["denom"]
        transformed[:, 10] = timestamps.hour / 23.0
        transformed[:, 11] = (timestamps.month - 1) / 11.0
        transformed[:, 12] = (timestamps.dayofyear - 1) / 365.0
        return {
            "W": transformed[None],
            "observed": np.ones((1, 24, 13), dtype=bool),
            "window_id": np.array([window_id], dtype=np.int64),
            "window_start": timestamps[0].isoformat(),
            "window_end": timestamps[-1].isoformat(),
        }, outside

    @staticmethod
    def _mask(pack: dict[str, Any], repeat: int) -> np.ndarray:
        # Same exact-count mask as notebook 02, including calendar cells.
        # Only the ten signal channels enter reconstruction RMSE.
        observed = pack["observed"]
        mask = np.zeros_like(observed, dtype=bool)
        for i, wid in enumerate(pack["window_id"]):
            rng = np.random.default_rng(np.random.SeedSequence([42, repeat, int(wid)]))
            valid = np.flatnonzero(observed[i].ravel())
            k = min(max(1, int(round(0.3 * len(valid)))), len(valid) - 1)
            mask[i].ravel()[rng.choice(valid, k, replace=False)] = True
        return mask

    @torch.inference_mode()
    def score(self, records: list[dict[str, Any]], *, window_id: int = 0, source_kind: str = "historical_measurements") -> dict[str, Any]:
        if self.model is None:
            raise RuntimeError("SSLQCRuntime is not loaded")
        pack, outside = self._prepare(records, window_id, source_kind)
        values = pack["W"]
        repeated = []
        for repeat in range(5):
            mask = self._mask(pack, repeat)
            prediction = self.model(torch.from_numpy(np.where(mask, 0.0, values))).numpy()
            error = (prediction.astype(float) - values.astype(float))[:, :, :10]
            selected = mask[:, :, :10]
            repeated.append(np.sqrt((error**2 * selected).sum((1, 2)) / selected.sum((1, 2))))
        embedding = self.model.get_embedding(torch.from_numpy(values)).numpy()
        z = self.system["projection"].transform(self.system["scaler"].transform(embedding))
        components = {
            "rmse": float(np.mean(repeated, axis=0)[0]),
            "nll": float(-self.system["gmm"].score_samples(z)[0]),
            "distance": float(np.min(self.system["centroids"].transform(z), axis=1)[0]),
        }
        normalized = {
            name: (value - self.system["normalization"][name]["median"]) / self.system["normalization"][name]["scale"]
            for name, value in components.items()
        }
        score = float(sum(self.system["weights"][name] * value for name, value in normalized.items()))
        if not np.isfinite([score, *components.values(), *normalized.values()]).all():
            raise RuntimeError("SSL-QC produced nonfinite diagnostic values")
        return {
            **self.meta(),
            "source_kind": source_kind,
            "n": 24,
            "window_id": window_id,
            "window_start": pack["window_start"],
            "window_end": pack["window_end"],
            "qc_score": score,
            "components": components,
            "normalized_components": normalized,
            "above_reference_cutoff": bool(score > self.system["cutoff"]),
            "values_outside_training_clip_bounds": outside,
        }

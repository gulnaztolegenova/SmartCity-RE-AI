from __future__ import annotations

import os
import warnings
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import joblib
import numpy as np
import pandas as pd

from app.load_features import (
    FEATURE_COLUMNS,
    LAG_STEPS,
    ROLLING_WINDOWS,
    STEP_HOURS,
    STEP_MINUTES,
    scale_templates,
    seed_history_values,
)


class LoadModelRuntime:
    def __init__(self, model_dir: str):
        self.model_dir = model_dir
        self.bundle: Optional[Dict[str, Any]] = None
        self.model: Any = None

    def load(self) -> "LoadModelRuntime":
        bundle_path = os.path.join(self.model_dir, "load_forecast_bundle.joblib")
        if not os.path.exists(bundle_path):
            raise FileNotFoundError(f"Load forecast bundle not found: {bundle_path}")

        with warnings.catch_warnings():
            warnings.filterwarnings(
                "ignore",
                message=".*If you are loading a serialized model.*",
                category=UserWarning,
            )
            bundle = joblib.load(bundle_path)
        required = [
            "model_type",
            "model_name",
            "model_version",
            "selected_profile_id",
            "templates",
            "metrics_summary",
            "feature_columns",
        ]
        for key in required:
            if key not in bundle:
                raise ValueError(f"load bundle missing key '{key}'")

        self.bundle = bundle
        self.model = bundle.get("model")
        return self

    @property
    def is_loaded(self) -> bool:
        return self.bundle is not None

    @property
    def model_type(self) -> str:
        assert self.bundle is not None
        return str(self.bundle["model_type"])

    @property
    def model_name(self) -> str:
        assert self.bundle is not None
        return str(self.bundle["model_name"])

    @property
    def model_version(self) -> str:
        assert self.bundle is not None
        return str(self.bundle["model_version"])

    @property
    def selected_profile_id(self) -> str:
        assert self.bundle is not None
        return str(self.bundle["selected_profile_id"])

    @property
    def source_dataset(self) -> str:
        assert self.bundle is not None
        return str(self.bundle.get("source_dataset", "household_data_15min_singleindex.csv"))

    @property
    def metrics_summary(self) -> Dict[str, Any]:
        assert self.bundle is not None
        return dict(self.bundle.get("metrics_summary", {}))

    @property
    def feature_columns(self) -> List[str]:
        assert self.bundle is not None
        cols = list(self.bundle.get("feature_columns", FEATURE_COLUMNS))
        if not cols:
            cols = list(FEATURE_COLUMNS)
        return cols

    @property
    def templates(self) -> Dict[str, Any]:
        assert self.bundle is not None
        return dict(self.bundle["templates"])

    @property
    def candidate_profiles(self) -> List[Dict[str, Any]]:
        assert self.bundle is not None
        return list(self.bundle.get("candidate_profiles", []))

    @property
    def benchmark_profile_stats(self) -> Dict[str, Any]:
        assert self.bundle is not None
        return dict(self.bundle.get("benchmark_profile_stats", {}))

    def meta(self) -> Dict[str, Any]:
        return {
            "model_name": self.model_name,
            "model_version": self.model_version,
            "model_type": self.model_type,
            "selected_profile_id": self.selected_profile_id,
            "source_dataset": self.source_dataset,
            "step_minutes": STEP_MINUTES,
            "target_name": "Local electric load",
            "target_unit": "kW",
            "feature_columns": self.feature_columns,
            "candidate_profiles": self.candidate_profiles,
            "metrics_summary": self.metrics_summary,
            "benchmark_profile_stats": self.benchmark_profile_stats,
        }

    def forecast(
        self,
        *,
        days: int,
        start_time: Optional[datetime] = None,
        scale_factor: float = 1.0,
    ) -> Dict[str, Any]:
        if self.bundle is None:
            raise RuntimeError("LoadModelRuntime is not loaded")
        if days < 1:
            raise ValueError("days must be >= 1")

        st = _ceil_to_step_utc(start_time or datetime.utcnow(), STEP_MINUTES)
        periods = int(days * 24 * 60 / STEP_MINUTES)
        timestamps = pd.date_range(start=st, periods=periods, freq=f"{STEP_MINUTES}min", tz="UTC")
        scaled_templates = scale_templates(self.templates, scale_factor)
        history_values = list(seed_history_values(st.to_pydatetime(), templates=scaled_templates).values())
        if not history_values:
            raise RuntimeError("Load forecast history seed is empty")
        max_history = max(max(LAG_STEPS), max(ROLLING_WINDOWS))
        if len(history_values) < max_history:
            raise RuntimeError("Load forecast history seed is shorter than required lag window")
        rolling_sums = {
            window: float(np.sum(history_values[-window:], dtype=float))
            for window in ROLLING_WINDOWS
        }

        load_kw_pred: List[float] = []
        for ts in timestamps:
            if self.model_type == "seasonal_template":
                pred_kw = rolling_sums[96] / 96.0
            else:
                if self.model is None:
                    raise RuntimeError("load forecast model object is missing from the bundle")
                row = _build_feature_vector(ts.to_pydatetime(), history_values, rolling_sums)
                pred_kw = float(self.model.predict(row.reshape(1, -1))[0])
            pred_kw = max(pred_kw, 0.0)
            history_values.append(pred_kw)
            for window in ROLLING_WINDOWS:
                rolling_sums[window] += pred_kw - history_values[-(window + 1)]
            load_kw_pred.append(pred_kw)

        load_kwh_step_pred = (np.asarray(load_kw_pred, dtype=float) * STEP_HOURS).tolist()
        return {
            "n": len(load_kw_pred),
            "step_minutes": STEP_MINUTES,
            "timestamps": [ts.isoformat() for ts in timestamps],
            "load_kw_pred": [float(v) for v in load_kw_pred],
            "load_kwh_step_pred": [float(v) for v in load_kwh_step_pred],
            "horizon_days": int(days),
            "model_name": self.model_name,
            "model_version": self.model_version,
            "model_type": self.model_type,
            "source_profile_id": self.selected_profile_id,
            "source_dataset": self.source_dataset,
            "scale_factor": float(scale_factor),
            "metrics_summary": self.metrics_summary,
        }


def _ceil_to_step_utc(dt: datetime, step_minutes: int) -> pd.Timestamp:
    if dt.tzinfo is None:
        ts = pd.Timestamp(dt, tz="UTC")
    else:
        ts = pd.Timestamp(dt).tz_convert("UTC")
    ts = ts.replace(second=0, microsecond=0)
    remainder = ts.minute % step_minutes
    if remainder == 0:
        return ts
    return ts + timedelta(minutes=(step_minutes - remainder))


def _build_feature_vector(
    ts: datetime,
    history_values: List[float],
    rolling_sums: Dict[int, float],
) -> np.ndarray:
    minute_of_day = ts.hour * 60 + ts.minute
    quarter_of_day = int(minute_of_day // STEP_MINUTES)
    dayofweek = int(ts.weekday())
    weekofyear = int(ts.isocalendar().week)
    month = int(ts.month)
    dayofyear = int(ts.timetuple().tm_yday)
    hour = int(ts.hour)
    is_weekend = 1 if dayofweek in (5, 6) else 0
    is_business_hour = 1 if (not is_weekend and 8 <= hour < 18) else 0

    slot_angle = 2.0 * np.pi * quarter_of_day / 96.0
    dow_angle = 2.0 * np.pi * dayofweek / 7.0
    woy_angle = 2.0 * np.pi * (weekofyear - 1.0) / 53.0

    feature_values = [
        float(quarter_of_day),
        float(hour),
        float(dayofweek),
        float(weekofyear),
        float(month),
        float(dayofyear),
        float(is_weekend),
        float(is_business_hour),
        float(np.sin(slot_angle)),
        float(np.cos(slot_angle)),
        float(np.sin(dow_angle)),
        float(np.cos(dow_angle)),
        float(np.sin(woy_angle)),
        float(np.cos(woy_angle)),
    ]
    feature_values.extend(float(history_values[-lag]) for lag in LAG_STEPS)
    feature_values.extend(float(rolling_sums[window] / window) for window in ROLLING_WINDOWS)
    return np.asarray(feature_values, dtype=float)

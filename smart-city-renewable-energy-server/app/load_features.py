from __future__ import annotations

from datetime import datetime, timedelta
from typing import Dict, Mapping, Sequence

import numpy as np
import pandas as pd

STEP_MINUTES = 15
STEP_HOURS = STEP_MINUTES / 60.0
LAG_STEPS = (1, 4, 96, 192, 672)
ROLLING_WINDOWS = (4, 12, 96, 672)

CALENDAR_FEATURE_COLUMNS = [
    "quarter_of_day",
    "hour",
    "dayofweek",
    "weekofyear",
    "month",
    "dayofyear",
    "is_weekend",
    "is_business_hour",
    "sin_slot",
    "cos_slot",
    "sin_dow",
    "cos_dow",
    "sin_weekofyear",
    "cos_weekofyear",
]

LAG_FEATURE_COLUMNS = [f"lag_{lag}" for lag in LAG_STEPS]
ROLLING_FEATURE_COLUMNS = [f"rolling_mean_{window}" for window in ROLLING_WINDOWS]
FEATURE_COLUMNS = CALENDAR_FEATURE_COLUMNS + LAG_FEATURE_COLUMNS + ROLLING_FEATURE_COLUMNS


def _utc_datetime_obj(value: object) -> datetime:
    ts = pd.Timestamp(value)
    if ts.tzinfo is None:
        ts = ts.tz_localize("UTC")
    else:
        ts = ts.tz_convert("UTC")
    return ts.to_pydatetime()


def _to_utc_series(values: Sequence[object]) -> pd.Series:
    series = pd.to_datetime(pd.Series(values), errors="coerce", utc=True)
    if series.isna().any():
        raise ValueError("timestamp parsing failed for one or more rows")
    return series


def add_calendar_features(
    frame: pd.DataFrame,
    *,
    timestamp_col: str = "utc_timestamp",
) -> pd.DataFrame:
    if timestamp_col not in frame.columns:
        raise KeyError(f"Missing required timestamp column '{timestamp_col}'")

    out = frame.copy()
    ts = _to_utc_series(out[timestamp_col])
    minute_of_day = ts.dt.hour * 60 + ts.dt.minute
    quarter_of_day = (minute_of_day // STEP_MINUTES).astype(int)
    dayofweek = ts.dt.dayofweek.astype(int)
    weekofyear = ts.dt.isocalendar().week.astype(int)
    month = ts.dt.month.astype(int)
    dayofyear = ts.dt.dayofyear.astype(int)
    hour = ts.dt.hour.astype(int)

    out["quarter_of_day"] = quarter_of_day
    out["hour"] = hour
    out["dayofweek"] = dayofweek
    out["weekofyear"] = weekofyear
    out["month"] = month
    out["dayofyear"] = dayofyear
    out["is_weekend"] = dayofweek.isin([5, 6]).astype(int)
    out["is_business_hour"] = (
        (~dayofweek.isin([5, 6])) & hour.between(8, 18, inclusive="left")
    ).astype(int)

    slot_angle = 2.0 * np.pi * quarter_of_day.to_numpy(dtype=float) / 96.0
    dow_angle = 2.0 * np.pi * dayofweek.to_numpy(dtype=float) / 7.0
    woy_angle = 2.0 * np.pi * (weekofyear.to_numpy(dtype=float) - 1.0) / 53.0

    out["sin_slot"] = np.sin(slot_angle)
    out["cos_slot"] = np.cos(slot_angle)
    out["sin_dow"] = np.sin(dow_angle)
    out["cos_dow"] = np.cos(dow_angle)
    out["sin_weekofyear"] = np.sin(woy_angle)
    out["cos_weekofyear"] = np.cos(woy_angle)
    return out


def build_supervised_frame(
    frame: pd.DataFrame,
    *,
    timestamp_col: str = "utc_timestamp",
    target_col: str = "load_kw",
    dropna: bool = True,
) -> pd.DataFrame:
    if target_col not in frame.columns:
        raise KeyError(f"Missing required target column '{target_col}'")

    out = add_calendar_features(frame, timestamp_col=timestamp_col)
    target = pd.to_numeric(out[target_col], errors="coerce")

    for lag in LAG_STEPS:
        out[f"lag_{lag}"] = target.shift(lag)

    lag1 = target.shift(1)
    for window in ROLLING_WINDOWS:
        out[f"rolling_mean_{window}"] = lag1.rolling(window=window, min_periods=window).mean()

    if dropna:
        out = out.dropna(subset=FEATURE_COLUMNS + [target_col]).reset_index(drop=True)
    return out


def derive_profile_templates(
    frame: pd.DataFrame,
    *,
    timestamp_col: str = "utc_timestamp",
    target_col: str = "load_kw",
) -> Dict[str, object]:
    base = add_calendar_features(frame[[timestamp_col, target_col]].copy(), timestamp_col=timestamp_col)
    base[target_col] = pd.to_numeric(base[target_col], errors="coerce")
    base = base.dropna(subset=[target_col]).reset_index(drop=True)

    if base.empty:
        raise ValueError("Cannot derive templates from an empty target series")

    dow_slot = base.groupby(["dayofweek", "quarter_of_day"])[target_col].median().to_dict()
    month_slot = base.groupby(["month", "quarter_of_day"])[target_col].median().to_dict()
    slot_only = base.groupby(["quarter_of_day"])[target_col].median().to_dict()

    return {
        "dow_slot_median": dow_slot,
        "month_slot_median": month_slot,
        "slot_median": slot_only,
        "global_median": float(base[target_col].median()),
    }


def scale_templates(templates: Mapping[str, object], scale_factor: float) -> Dict[str, object]:
    factor = float(scale_factor)
    scaled: Dict[str, object] = {}
    for key, value in templates.items():
        if isinstance(value, dict):
            scaled[key] = {inner_key: float(inner_value) * factor for inner_key, inner_value in value.items()}
        elif isinstance(value, (int, float, np.integer, np.floating)):
            scaled[key] = float(value) * factor
        else:
            scaled[key] = value
    return scaled


def template_value_for_timestamp(ts: datetime, templates: Mapping[str, object]) -> float:
    ts_utc = pd.Timestamp(_utc_datetime_obj(ts))
    quarter_of_day = int((ts_utc.hour * 60 + ts_utc.minute) // STEP_MINUTES)
    dayofweek = int(ts_utc.dayofweek)
    month = int(ts_utc.month)

    dow_slot = templates.get("dow_slot_median", {})
    month_slot = templates.get("month_slot_median", {})
    slot_only = templates.get("slot_median", {})
    global_median = float(templates.get("global_median", 0.0) or 0.0)

    if (dayofweek, quarter_of_day) in dow_slot:
        return float(dow_slot[(dayofweek, quarter_of_day)])
    if (month, quarter_of_day) in month_slot:
        return float(month_slot[(month, quarter_of_day)])
    if quarter_of_day in slot_only:
        return float(slot_only[quarter_of_day])
    return global_median


def seed_history_values(
    start_ts: datetime,
    *,
    templates: Mapping[str, object],
    max_lag: int | None = None,
) -> Dict[datetime, float]:
    max_required_lag = max_lag if max_lag is not None else max(max(LAG_STEPS), max(ROLLING_WINDOWS))
    seeded: Dict[datetime, float] = {}
    delta = timedelta(minutes=STEP_MINUTES)

    for step_back in range(max_required_lag, 0, -1):
        ts = (pd.Timestamp(_utc_datetime_obj(start_ts)) - delta * step_back).to_pydatetime()
        seeded[ts] = template_value_for_timestamp(ts, templates)
    return seeded


def build_recursive_feature_row(
    ts: datetime,
    *,
    history_values: Mapping[datetime, float],
    templates: Mapping[str, object],
) -> pd.DataFrame:
    ts_utc = _utc_datetime_obj(ts)
    base = add_calendar_features(pd.DataFrame({"utc_timestamp": [ts_utc]}))
    delta = timedelta(minutes=STEP_MINUTES)

    def get_value(at_ts: datetime) -> float:
        key = _utc_datetime_obj(at_ts)
        if key in history_values:
            return float(history_values[key])
        return template_value_for_timestamp(key, templates)

    for lag in LAG_STEPS:
        base[f"lag_{lag}"] = get_value(ts_utc - delta * lag)

    for window in ROLLING_WINDOWS:
        values = [get_value(ts_utc - delta * step) for step in range(1, window + 1)]
        base[f"rolling_mean_{window}"] = float(np.mean(values))

    return base[FEATURE_COLUMNS]

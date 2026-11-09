"""Versioned weather-only contract shared by training and serving.

Generation columns and the source dataset's ambiguous humidity alias are never
inputs. Windows end at the weather hour being estimated, including that hour.
Future windows contain forecast weather, not future observed generation.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

BASE_COLUMNS = ["temperature_solar", "surface_irradiance_solar", "toa_irradiance_solar",
                "air_density_wind", "wind_speed_wind"]
FEATURE_COLUMNS = BASE_COLUMNS + ["hour_sin", "hour_cos", "doy_sin", "doy_cos",
                                 "clearness_index", "solar_reference", "wind_reference"]
TARGET_COLUMNS = ["kWh_solar_power_solar", "kWh_wind_power_wind"]
LOOKBACK = 24


def weather_matrix(frame: pd.DataFrame, reference_coefficients=(1.0, 1.0)):
    ts = pd.to_datetime(frame["timestamp"], errors="raise")
    values = frame[BASE_COLUMNS].to_numpy(dtype=np.float32)
    if not np.isfinite(values).all():
        raise ValueError("Weather contains missing or nonfinite required values")
    if len(ts) > 1 and not (ts.diff().iloc[1:] == pd.Timedelta(hours=1)).all():
        raise ValueError("Weather must contain consecutive hourly timestamps")
    temp, solar, toa, rho, wind = values.T
    if ((solar < 0) | (toa < 0) | (wind < 0) | (rho <= 0)).any():
        raise ValueError("Weather contains invalid irradiance, density or wind speed")
    h = ts.dt.hour.to_numpy() * (2 * np.pi / 24)
    d = (ts.dt.dayofyear.to_numpy() - 1) * (2 * np.pi / 365.25)
    clear = np.divide(solar, toa, out=np.zeros_like(solar), where=toa > 1)
    refs = np.column_stack((solar / 1000, (np.clip(wind, 0, 12) / 12) ** 3 * rho / 1.225))
    refs = refs * np.asarray(reference_coefficients)
    result = np.column_stack((values, np.sin(h), np.cos(h), np.sin(d), np.cos(d),
                              np.clip(clear, 0, 2), refs)).astype(np.float32)
    if not np.isfinite(result).all():
        raise ValueError("Weather features exceed supported range")
    return result, refs.astype(np.float32)


def hourly_windows(matrix: np.ndarray) -> np.ndarray:
    if len(matrix) < LOOKBACK:
        raise ValueError("At least 24 weather hours are required")
    return np.stack([matrix[i-LOOKBACK+1:i+1] for i in range(LOOKBACK-1, len(matrix))])

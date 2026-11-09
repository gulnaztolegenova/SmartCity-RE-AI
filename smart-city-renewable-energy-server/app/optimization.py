from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Dict, Iterable, List, Mapping, Sequence, Tuple

import numpy as np
import pandas as pd
from scipy.optimize import linprog


@dataclass
class BatteryScenario:
    enabled: bool = False
    battery_capacity_kwh: float = 0.0
    soc_min: float = 0.1
    soc_max: float = 0.9
    soc_init: float = 0.5
    charge_power_kw: float = 0.0
    discharge_power_kw: float = 0.0
    eta_charge: float = 0.95
    eta_discharge: float = 0.95
    label: str = "no_battery"

    def usable_capacity_bounds(self) -> Tuple[float, float, float]:
        min_kwh = self.battery_capacity_kwh * self.soc_min
        max_kwh = self.battery_capacity_kwh * self.soc_max
        init_kwh = self.battery_capacity_kwh * self.soc_init
        init_kwh = float(np.clip(init_kwh, min_kwh, max_kwh))
        return min_kwh, max_kwh, init_kwh

    def to_dict(self) -> Dict[str, float | bool | str]:
        return asdict(self)


def _as_array(values: Sequence[float]) -> np.ndarray:
    arr = np.asarray(values, dtype=float)
    return np.nan_to_num(arr, nan=0.0, posinf=0.0, neginf=0.0)


def compute_energy_balance(
    timestamps: Sequence[object],
    load_kw: Sequence[float],
    pv_kw: Sequence[float],
    wind_kw: Sequence[float] | None = None,
) -> pd.DataFrame:
    n = min(len(timestamps), len(load_kw), len(pv_kw))
    if wind_kw is not None:
        n = min(n, len(wind_kw))
    ts = pd.to_datetime(list(timestamps)[:n], errors="coerce", utc=True)
    if ts.isna().any():
        raise ValueError("timestamps contain invalid values")

    load_arr = np.clip(_as_array(load_kw)[:n], 0.0, None)
    pv_arr = np.clip(_as_array(pv_kw)[:n], 0.0, None)
    wind_arr = np.zeros(n, dtype=float) if wind_kw is None else np.clip(_as_array(wind_kw)[:n], 0.0, None)
    renewable_arr = pv_arr + wind_arr
    net_arr = load_arr - renewable_arr

    return pd.DataFrame(
        {
            "utc_timestamp": ts,
            "load_kw_pred": load_arr,
            "pv_kw_pred": pv_arr,
            "wind_kw_pred": wind_arr,
            "renewable_kw_pred": renewable_arr,
            "net_load_kw": net_arr,
            "grid_import_kw_before": np.clip(net_arr, 0.0, None),
            "grid_export_kw_before": np.clip(-net_arr, 0.0, None),
            "deficit_kw": np.clip(net_arr, 0.0, None),
            "surplus_kw": np.clip(-net_arr, 0.0, None),
        }
    )


def optimize_dispatch(
    timestamps: Sequence[object],
    load_kw: Sequence[float],
    pv_kw: Sequence[float],
    *,
    battery: BatteryScenario,
    step_minutes: int = 15,
    wind_kw: Sequence[float] | None = None,
) -> Tuple[pd.DataFrame, Dict[str, object]]:
    balance = compute_energy_balance(timestamps, load_kw, pv_kw, wind_kw=wind_kw)
    dt_hours = step_minutes / 60.0

    if not battery.enabled or battery.battery_capacity_kwh <= 0.0:
        balance["grid_import_kw_after"] = balance["grid_import_kw_before"]
        balance["grid_export_kw_after"] = balance["grid_export_kw_before"]
        balance["battery_charge_kw"] = 0.0
        balance["battery_discharge_kw"] = 0.0
        balance["soc_kwh"] = 0.0
        return balance, _build_summary(balance, battery=battery, step_minutes=step_minutes, optimized=False)

    result = _solve_lexicographic_dispatch(balance["net_load_kw"].to_numpy(dtype=float), battery, dt_hours)
    balance["grid_import_kw_after"] = result["grid_import_kw"]
    balance["grid_export_kw_after"] = result["grid_export_kw"]
    balance["battery_charge_kw"] = result["battery_charge_kw"]
    balance["battery_discharge_kw"] = result["battery_discharge_kw"]
    balance["soc_kwh"] = result["soc_kwh"]
    return balance, _build_summary(balance, battery=battery, step_minutes=step_minutes, optimized=True)


def _build_summary(
    balance: pd.DataFrame,
    *,
    battery: BatteryScenario,
    step_minutes: int,
    optimized: bool,
) -> Dict[str, object]:
    dt_hours = step_minutes / 60.0

    def energy(col: str) -> float:
        return float(balance[col].to_numpy(dtype=float).sum() * dt_hours)

    before_import = energy("grid_import_kw_before")
    after_import = energy("grid_import_kw_after")
    before_export = energy("grid_export_kw_before")
    after_export = energy("grid_export_kw_after")
    total_load = energy("load_kw_pred")
    total_pv = energy("pv_kw_pred")
    total_wind = energy("wind_kw_pred")
    total_renewable = energy("renewable_kw_pred")
    peak_before = float(balance["grid_import_kw_before"].max())
    peak_after = float(balance["grid_import_kw_after"].max())
    throughput = float(
        (balance["battery_charge_kw"].to_numpy(dtype=float) + balance["battery_discharge_kw"].to_numpy(dtype=float)).sum()
        * dt_hours
    )
    self_sufficiency_before = 1.0 - (before_import / total_load) if total_load > 1e-9 else 0.0
    self_sufficiency_after = 1.0 - (after_import / total_load) if total_load > 1e-9 else 0.0
    self_consumption_before = (total_renewable - before_export) / total_renewable if total_renewable > 1e-9 else 0.0
    self_consumption_after = (total_renewable - after_export) / total_renewable if total_renewable > 1e-9 else 0.0

    return {
        "optimized": optimized,
        "objective_type": "lexicographic_physical_constraints",
        "objective_summary": {
            "stage_1": "minimize_total_grid_import_kwh",
            "stage_2": "minimize_peak_grid_import_kw",
            "stage_3": "minimize_battery_throughput_kwh",
        },
        "scenario_parameters": battery.to_dict(),
        "total_load_kwh": total_load,
        "total_pv_kwh": total_pv,
        "total_wind_kwh": total_wind,
        "total_renewable_kwh": total_renewable,
        "total_deficit_kwh": before_import,
        "total_surplus_kwh": before_export,
        "total_grid_import_kwh_before": before_import,
        "total_grid_import_kwh_after": after_import,
        "grid_import_reduction_kwh": before_import - after_import,
        "grid_import_reduction_pct": ((before_import - after_import) / before_import * 100.0) if before_import > 0 else 0.0,
        "total_grid_export_kwh_before": before_export,
        "total_grid_export_kwh_after": after_export,
        "grid_export_reduction_kwh": before_export - after_export,
        "peak_before_kw": peak_before,
        "peak_after_kw": peak_after,
        "peak_reduction_kw": peak_before - peak_after,
        "peak_reduction_pct": ((peak_before - peak_after) / peak_before * 100.0) if peak_before > 0 else 0.0,
        "battery_throughput_kwh": throughput,
        "self_sufficiency_ratio_before": self_sufficiency_before,
        "self_sufficiency_ratio_after": self_sufficiency_after,
        "self_consumption_ratio_before": self_consumption_before,
        "self_consumption_ratio_after": self_consumption_after,
        "optimization_gain_kwh": before_import - after_import,
    }


def _solve_lexicographic_dispatch(
    net_load_kw: np.ndarray,
    battery: BatteryScenario,
    dt_hours: float,
) -> Dict[str, np.ndarray]:
    n = int(net_load_kw.size)
    if n == 0:
        raise ValueError("net_load_kw is empty")

    min_soc_kwh, max_soc_kwh, init_soc_kwh = battery.usable_capacity_bounds()

    g_import = slice(0, n)
    g_export = slice(n, 2 * n)
    charge = slice(2 * n, 3 * n)
    discharge = slice(3 * n, 4 * n)
    soc = slice(4 * n, 5 * n + 1)
    peak_index = 5 * n + 1
    var_count = peak_index + 1

    bounds: List[Tuple[float | None, float | None]] = []
    bounds.extend([(0.0, None)] * n)  # grid import
    bounds.extend([(0.0, None)] * n)  # grid export
    bounds.extend([(0.0, float(battery.charge_power_kw))] * n)
    bounds.extend([(0.0, float(battery.discharge_power_kw))] * n)
    bounds.append((init_soc_kwh, init_soc_kwh))
    bounds.extend([(min_soc_kwh, max_soc_kwh)] * n)
    bounds.append((0.0, None))  # peak

    a_eq: List[np.ndarray] = []
    b_eq: List[float] = []

    for idx, net_value in enumerate(net_load_kw):
        row = np.zeros(var_count, dtype=float)
        row[g_import.start + idx] = 1.0
        row[g_export.start + idx] = -1.0
        row[charge.start + idx] = -1.0
        row[discharge.start + idx] = 1.0
        a_eq.append(row)
        b_eq.append(float(net_value))

    for idx in range(n):
        row = np.zeros(var_count, dtype=float)
        row[soc.start + idx + 1] = 1.0
        row[soc.start + idx] = -1.0
        row[charge.start + idx] = -battery.eta_charge * dt_hours
        row[discharge.start + idx] = dt_hours / max(battery.eta_discharge, 1e-9)
        a_eq.append(row)
        b_eq.append(0.0)

    a_eq_arr = np.vstack(a_eq)
    b_eq_arr = np.asarray(b_eq, dtype=float)

    a_ub_peak = []
    b_ub_peak = []
    for idx in range(n):
        row = np.zeros(var_count, dtype=float)
        row[g_import.start + idx] = 1.0
        row[peak_index] = -1.0
        a_ub_peak.append(row)
        b_ub_peak.append(0.0)

    def solve(c: np.ndarray, extra_a_ub: List[np.ndarray] | None = None, extra_b_ub: List[float] | None = None):
        a_ub = list(a_ub_peak)
        b_ub = list(b_ub_peak)
        if extra_a_ub:
            a_ub.extend(extra_a_ub)
            b_ub.extend(extra_b_ub or [])
        res = linprog(
            c=c,
            A_ub=np.vstack(a_ub) if a_ub else None,
            b_ub=np.asarray(b_ub, dtype=float) if b_ub else None,
            A_eq=a_eq_arr,
            b_eq=b_eq_arr,
            bounds=bounds,
            method="highs",
        )
        if not res.success:
            raise RuntimeError(f"Optimization failed: {res.message}")
        return res

    c1 = np.zeros(var_count, dtype=float)
    c1[g_import] = dt_hours
    res1 = solve(c1)
    total_import_opt = float(c1 @ res1.x)

    c2 = np.zeros(var_count, dtype=float)
    c2[peak_index] = 1.0
    row_import_cap = np.zeros(var_count, dtype=float)
    row_import_cap[g_import] = dt_hours
    res2 = solve(c2, extra_a_ub=[row_import_cap], extra_b_ub=[total_import_opt + 1e-7])
    peak_opt = float(res2.x[peak_index])

    c3 = np.zeros(var_count, dtype=float)
    c3[charge] = dt_hours
    c3[discharge] = dt_hours
    row_peak_cap = np.zeros(var_count, dtype=float)
    row_peak_cap[peak_index] = 1.0
    res3 = solve(
        c3,
        extra_a_ub=[row_import_cap, row_peak_cap],
        extra_b_ub=[total_import_opt + 1e-7, peak_opt + 1e-7],
    )

    x = res3.x
    soc_path = x[soc]
    return {
        "grid_import_kw": x[g_import],
        "grid_export_kw": x[g_export],
        "battery_charge_kw": x[charge],
        "battery_discharge_kw": x[discharge],
        "soc_kwh": soc_path[1:],
    }

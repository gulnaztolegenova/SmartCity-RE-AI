# smart-city-renewable-energy-server/app/main.py
import os

# Set before native ML imports. One OpenMP worker per request avoids nested
# pools across scikit-learn, XGBoost and PyTorch; HTTP requests can run in parallel.
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("TF_NUM_INTRAOP_THREADS", "1")
os.environ.setdefault("TF_NUM_INTEROP_THREADS", "1")
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")

from datetime import datetime, timedelta, timezone as dt_timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Tuple

import httpx
import numpy as np
import pandas as pd
import torch
from fastapi import BackgroundTasks, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, Field

from app.firestore_store import FirestoreStore
from app.load_runtime import LoadModelRuntime
from app.optimization import BatteryScenario, compute_energy_balance, optimize_dispatch
from app.weather_runtime import WeatherModelRuntime, site_energy_adapter
from app.ssl_qc_runtime import SSLQCRuntime
from app.dp_sthpp_runtime import DPSTHPPRuntime


# =========================
# Settings
# =========================
SERVICE_NAME = os.getenv("SERVICE_NAME", "smart-city-renewable-energy-server")
API_TITLE = os.getenv("API_TITLE", "Smart City Renewable Energy Forecast API")
DEFAULT_MODEL_DIR = str(Path(__file__).resolve().parents[1] / "models")
MODEL_DIR = os.getenv("MODEL_DIR", DEFAULT_MODEL_DIR)
LOAD_MODEL_DIR = os.getenv("LOAD_MODEL_DIR", MODEL_DIR)
SSL_QC_MODEL_DIR = os.getenv("SSL_QC_MODEL_DIR", str(Path(MODEL_DIR) / "ssl_qc"))
DP_STHPP_MODEL_DIR = os.getenv("DP_STHPP_MODEL_DIR", str(Path(MODEL_DIR) / "dp_sthpp"))

OPEN_METEO_BASE_URL = os.getenv("OPEN_METEO_BASE_URL", "https://api.open-meteo.com/v1/forecast")
DEFAULT_TIMEZONE = os.getenv("OPEN_METEO_TIMEZONE", "auto")  # "auto" OR "Asia/Almaty" etc.

# CORS (Flutter Web)
CORS_ALLOW_ORIGINS = os.getenv("CORS_ALLOW_ORIGINS", "*")  # e.g. "https://your-domain.com,https://localhost:5000"


# =========================
# App
# =========================
app = FastAPI(title=API_TITLE, version="4.0.0")

allow_all_origins = CORS_ALLOW_ORIGINS.strip() == "*"

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if allow_all_origins else [o.strip() for o in CORS_ALLOW_ORIGINS.split(",") if o.strip()],
    allow_credentials=not allow_all_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

runtime: Optional[WeatherModelRuntime] = None
load_runtime: Optional[LoadModelRuntime] = None
ssl_qc_runtime: Optional[SSLQCRuntime] = None
dp_sthpp_runtime: Optional[DPSTHPPRuntime] = None
firestore_store: Optional[FirestoreStore] = None
_http: Optional[httpx.AsyncClient] = None


# =========================
# Schemas
# =========================
class ApiModel(BaseModel):
    model_config = ConfigDict(protected_namespaces=())


class PredictRequest(ApiModel):
    records: List[Dict[str, Any]] = Field(
        ...,
        description="List of feature dicts. Keys must match model meta['num_cols']. "
                    "Required timestamp: consecutive ISO hourly values; at least 24 rows.",
    )
    inverse_y: bool = Field(
        default=True,
        description="Compatibility parameter; weather-v1 requires true and returns normalized source generation here.",
    )


class QCScoreRequest(ApiModel):
    model_config = ConfigDict(protected_namespaces=(), extra="forbid")
    records: List[Dict[str, Any]] = Field(
        ..., min_length=24, max_length=24,
        description="24 consecutive historical hourly measurements in the canonical QC schema. "
                    "Measured solar and wind generation are required; see /qc/meta.",
    )
    source_kind: Literal["historical_measurements"] = "historical_measurements"
    window_id: int = Field(default=0, ge=0, le=1_000_000_000, strict=True)


class ObservedForecastRequest(ApiModel):
    model_config = ConfigDict(protected_namespaces=(), extra="forbid")
    records: List[Dict[str, Any]] = Field(
        ..., min_length=24, max_length=24,
        description="24 consecutive measured hours including actual solar/wind generation. "
                    "The forecast target is one hour after the final record; see /generation/meta.",
    )
    source_kind: Literal["historical_measurements"] = "historical_measurements"


class GenerationAnalysisRequest(ObservedForecastRequest):
    window_id: int = Field(default=0, ge=0, le=1_000_000_000, strict=True)


class PredictResponse(ApiModel):
    n: int
    y_pred: List[float]
    p_extreme: List[float]
    solar_pred: List[float]
    wind_pred: List[float]
    solar_p_extreme: List[float]
    wind_p_extreme: List[float]
    x_input_mode: str
    n_timesteps: int
    features: List[str]
    target_name: str
    target_unit: str
    target_transform: str
    wind_target_name: str
    wind_target_unit: str
    model_name: str
    model_version: str


class ForecastResponse(ApiModel):
    n: int
    step_minutes: int
    timezone: str
    times: List[str]
    y_pred: List[float]
    p_extreme: List[float]
    solar_pred: List[float] = Field(default_factory=list)
    wind_pred: List[float] = Field(default_factory=list)
    solar_p_extreme: List[float] = Field(default_factory=list)
    wind_p_extreme: List[float] = Field(default_factory=list)
    x_input_mode: str
    n_timesteps: int
    features: List[str]
    target_name: str
    target_unit: str
    target_transform: str
    wind_target_name: str = "Wind generation forecast"
    wind_target_unit: str = "Wh_per_step"
    model_name: str
    model_version: str
    source: str
    calibration: Optional["CalibrationResponse"] = None
    quality: Dict[str, Any] = Field(default_factory=dict)
    provenance: Dict[str, Any] = Field(default_factory=dict)


class CalibrationResponse(ApiModel):
    enabled: bool
    method: str
    version: str
    capacity_kw: float
    tilt_deg: float
    azimuth_deg: float
    raw_model_total_kwh: float
    baseline_total_kwh: float
    calibrated_total_kwh: float
    scale_factor: float
    notes: List[str] = Field(default_factory=list)


ForecastResponse.model_rebuild()


class MeteoHourlyPayload(ApiModel):
    time: List[str]
    temperature_2m: List[float]
    relative_humidity_2m: List[float]
    pressure_msl: List[float]
    wind_speed_10m: List[float]
    precipitation: List[float]
    cloud_cover: List[float]
    shortwave_radiation: List[float]
    weather_code: List[int]


class MeteoResponse(ApiModel):
    n: int
    step_minutes: int
    timezone: str
    source: str
    hourly: MeteoHourlyPayload


class MetaResponse(ApiModel):
    model_name: str
    model_version: str
    n_timesteps: int
    x_input_mode: str
    y_transform: str
    winsor_limits: Tuple[float, float]
    target_name: str
    target_unit: str
    wind_target_name: str
    wind_target_unit: str
    features: List[str]
    engineered_feature_count: int
    solar_extreme_threshold: float
    wind_extreme_threshold: float
    quality_model: str
    quality_model_version: str
    forecast_strategy: str
    original_article_weights: bool
    energy_basis: str
    operational_horizon_accuracy_validated: bool
    training_manifest: Dict[str, Any]


class LoadMetaResponse(ApiModel):
    model_name: str
    model_version: str
    model_type: str
    selected_profile_id: str
    source_dataset: str
    step_minutes: int
    target_name: str
    target_unit: str
    feature_columns: List[str]
    metrics_summary: Dict[str, Any]
    candidate_profiles: List[Dict[str, Any]]
    benchmark_profile_stats: Dict[str, Any]


class LoadForecastResponse(ApiModel):
    n: int
    step_minutes: int
    timestamps: List[str]
    load_kw_pred: List[float]
    load_kwh_step_pred: List[float]
    horizon_days: int
    model_name: str
    model_version: str
    model_type: str
    source_profile_id: str
    source_dataset: str
    scale_factor: float
    scaling_mode: str
    metrics_summary: Dict[str, Any]
    firestore_persisted: bool = False
    firestore_error: Optional[str] = None


class LoadAssignRequest(ApiModel):
    device_id: str = Field(..., min_length=1)
    profile_id: Optional[str] = None
    scaling_mode: str = "scenario_scale_factor"
    scale_factor: float = Field(default=1.0, gt=0.0, le=1000.0)
    source_dataset: str = "household_data_15min_singleindex.csv"


class LoadAssignResponse(ApiModel):
    device_id: str
    profile_id: str
    source_dataset: str
    source_type: str
    scaling_mode: str
    scale_factor: float
    assigned_at: str
    firestore_persisted: bool
    firestore_error: Optional[str] = None


class EnergyBalanceResponse(ApiModel):
    n: int
    step_minutes: int
    timestamps: List[str]
    pv_kw_pred: List[float]
    wind_kw_pred: List[float]
    renewable_kw_pred: List[float]
    load_kw_pred: List[float]
    net_load_kw: List[float]
    deficit_kw: List[float]
    surplus_kw: List[float]
    load_model_name: str
    load_model_version: str
    pv_source: str
    source_profile_id: str
    scale_factor: float
    scaling_mode: str
    total_pv_kwh: float
    total_wind_kwh: float
    total_renewable_kwh: float
    total_load_kwh: float
    total_net_kwh: float
    total_deficit_kwh: float
    total_surplus_kwh: float
    firestore_persisted: bool = False
    firestore_error: Optional[str] = None


class BatteryScenarioPayload(ApiModel):
    enabled: bool = False
    battery_capacity_kwh: float = Field(default=0.0, ge=0.0, le=1000.0)
    soc_min: float = Field(default=0.10, ge=0.0, le=1.0)
    soc_max: float = Field(default=0.90, ge=0.0, le=1.0)
    soc_init: float = Field(default=0.50, ge=0.0, le=1.0)
    charge_power_kw: float = Field(default=0.0, ge=0.0, le=1000.0)
    discharge_power_kw: float = Field(default=0.0, ge=0.0, le=1000.0)
    eta_charge: float = Field(default=0.95, gt=0.0, le=1.0)
    eta_discharge: float = Field(default=0.95, gt=0.0, le=1.0)
    label: str = "scenario battery"


class OptimizeRequest(ApiModel):
    lat: float = Field(..., ge=-90.0, le=90.0)
    lon: float = Field(..., ge=-180.0, le=180.0)
    days: int = Field(default=7, ge=1, le=14)
    start_time: Optional[str] = None
    timezone: str = DEFAULT_TIMEZONE
    device_id: Optional[str] = None
    profile_id: Optional[str] = None
    scale_factor: Optional[float] = Field(default=None, gt=0.0, le=1000.0)
    capacity_kw: Optional[float] = Field(default=None, gt=0.0, le=100000.0)
    tilt_deg: Optional[float] = Field(default=None, ge=0.0, le=90.0)
    azimuth_deg: Optional[float] = Field(default=None, ge=0.0, le=360.0)
    wind_capacity_kw: Optional[float] = Field(default=None, gt=0.0, le=100000.0)
    wind_hub_height_m: Optional[float] = Field(default=None, ge=10.0, le=300.0)
    wind_reference_height_m: Optional[float] = Field(default=None, ge=2.0, le=200.0)
    wind_cut_in_ms: Optional[float] = Field(default=None, ge=0.1, le=10.0)
    wind_rated_ms: Optional[float] = Field(default=None, ge=2.0, le=40.0)
    wind_cut_out_ms: Optional[float] = Field(default=None, ge=5.0, le=60.0)
    dispatch_step_minutes: int = Field(default=60, ge=60, le=60)
    balance_step_minutes: int = Field(default=15, ge=15, le=60)
    timestamps: Optional[List[str]] = None
    pv_kw_pred: Optional[List[float]] = None
    wind_kw_pred: Optional[List[float]] = None
    load_kw_pred: Optional[List[float]] = None
    battery: BatteryScenarioPayload = Field(default_factory=BatteryScenarioPayload)


class OptimizeResponse(ApiModel):
    n: int
    step_minutes: int
    timestamps: List[str]
    pv_kw_pred: List[float]
    wind_kw_pred: List[float]
    renewable_kw_pred: List[float]
    load_kw_pred: List[float]
    net_load_kw: List[float]
    grid_import_kw_before: List[float]
    grid_import_kw_after: List[float]
    peak_before_kw: float
    peak_after_kw: float
    battery_charge_kw: List[float]
    battery_discharge_kw: List[float]
    soc_kwh: List[float]
    objective_summary: Dict[str, Any]
    scenario_parameters: Dict[str, Any]
    load_model_name: str
    load_model_version: str
    pv_source: str
    source_profile_id: str
    scale_factor: float
    scaling_mode: str
    total_pv_kwh: float
    total_wind_kwh: float
    total_renewable_kwh: float
    total_load_kwh: float
    total_deficit_kwh: float
    total_surplus_kwh: float
    total_grid_import_kwh_before: float
    total_grid_import_kwh_after: float
    grid_import_reduction_kwh: float
    grid_import_reduction_pct: float
    self_sufficiency_ratio_before: float
    self_sufficiency_ratio_after: float
    self_consumption_ratio_before: float
    self_consumption_ratio_after: float
    optimization_gain_kwh: float
    firestore_persisted: bool = False
    firestore_error: Optional[str] = None


# =========================
# Startup/Shutdown
# =========================
@app.on_event("startup")
async def _startup():
    global runtime, load_runtime, ssl_qc_runtime, dp_sthpp_runtime, firestore_store, _http
    # Set once, before inference; do not change the process-wide pool per request.
    torch.set_num_threads(int(os.getenv("SSL_QC_CPU_THREADS", "1")))
    runtime = WeatherModelRuntime(Path(MODEL_DIR) / "weather_v1").load()
    # Integrity/schema failures must prevent this revision from serving as ready.
    ssl_qc_runtime = SSLQCRuntime(SSL_QC_MODEL_DIR).load()
    dp_sthpp_runtime = DPSTHPPRuntime(DP_STHPP_MODEL_DIR).load()
    try:
        load_runtime = LoadModelRuntime(LOAD_MODEL_DIR).load()
    except Exception as exc:
        load_runtime = None
        print(f"[startup] load runtime unavailable: {exc}")
    firestore_store = FirestoreStore()
    _http = httpx.AsyncClient(timeout=httpx.Timeout(20.0, connect=10.0))


@app.on_event("shutdown")
async def _shutdown():
    global _http
    if _http is not None:
        await _http.aclose()
        _http = None


# =========================
# Health
# =========================
@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": SERVICE_NAME,
        "api": API_TITLE,
        "model_name": runtime.model_name if runtime is not None else "unavailable",
        "model_version": runtime.model_version if runtime is not None else "unknown",
        "model_loaded": runtime is not None and runtime.is_loaded,
        "weather_quality_model": "DualAxis",
        "weather_quality_loaded": runtime is not None and runtime.is_loaded,
        "load_model_loaded": load_runtime is not None and load_runtime.is_loaded,
        "ssl_qc_model_loaded": ssl_qc_runtime is not None and ssl_qc_runtime.is_loaded,
        "dp_sthpp_model_loaded": dp_sthpp_runtime is not None and dp_sthpp_runtime.is_loaded,
        "model_dir": MODEL_DIR,
        "load_model_dir": LOAD_MODEL_DIR,
        "open_meteo_base_url": OPEN_METEO_BASE_URL,
        "firestore_enabled": firestore_store.enabled if firestore_store is not None else False,
        "firestore_error": firestore_store.error if firestore_store is not None else None,
    }


@app.get("/")
def root():
    return {
        "service": SERVICE_NAME,
        "api": API_TITLE,
        "version": app.version,
        "endpoints": [
            "/health",
            "/meta",
            "/qc/meta",
            "/qc/score",
            "/generation/meta",
            "/generation/predict",
            "/generation/analyze",
            "/forecast/7d",
            "/forecast/14d",
            "/meteo",
            "/load/meta",
            "/load/forecast/7d",
            "/load/forecast/14d",
            "/load/assign-profile",
            "/energy/balance",
            "/optimize",
        ],
        "forecast_outputs": ["solar_pred", "wind_pred", "solar_p_extreme", "wind_p_extreme"],
    }


def _ceil_to_step(dt: datetime, step_minutes: int) -> datetime:
    """
    Align timestamp up to the nearest step boundary.
    Example: 12:07 with step=15 -> 12:15.
    """
    base = dt.replace(second=0, microsecond=0)
    rem = base.minute % step_minutes
    if rem == 0:
        return base
    return base + timedelta(minutes=(step_minutes - rem))


def _as_utc_timestamp(value: datetime) -> pd.Timestamp:
    ts = pd.Timestamp(value)
    if ts.tzinfo is None:
        return ts.tz_localize("UTC")
    return ts.tz_convert("UTC")


def _resample_generation_forecast(
    *,
    times: List[str],
    solar_pred: List[float],
    solar_ext: List[float],
    wind_pred: List[float],
    wind_ext: List[float],
    requested_step_minutes: int,
) -> Tuple[List[str], List[float], List[float], List[float], List[float]]:
    """Resample native hourly renewable predictions to the public API step.

    The weather variant was trained on hourly records. For 15/30-minute
    API consumers we keep the physical interpretation as average kW and forward
    fill the hourly generation level into sub-hourly slots.
    """
    if requested_step_minutes == 60:
        return times, solar_pred, solar_ext, wind_pred, wind_ext
    if requested_step_minutes not in (15, 30):
        raise HTTPException(status_code=400, detail="step_minutes must be one of: 15, 30, 60")
    if not times:
        return [], [], [], [], []

    idx = pd.to_datetime(pd.Series(times), errors="coerce", utc=True)
    if idx.isna().any():
        raise HTTPException(status_code=500, detail="Cannot resample forecast: invalid timestamps")

    frame = pd.DataFrame(
        {
            "solar_pred": np.asarray(solar_pred, dtype=float),
            "solar_ext": np.asarray(solar_ext, dtype=float),
            "wind_pred": np.asarray(wind_pred, dtype=float),
            "wind_ext": np.asarray(wind_ext, dtype=float),
        },
        index=pd.DatetimeIndex(idx),
    ).sort_index()

    start = frame.index[0]
    end = frame.index[-1] + pd.Timedelta(hours=1) - pd.Timedelta(minutes=requested_step_minutes)
    out_index = pd.date_range(start=start, end=end, freq=f"{requested_step_minutes}min", tz="UTC")
    out = frame.reindex(out_index, method="ffill").fillna(0.0)
    out = out.replace([np.inf, -np.inf], np.nan).fillna(0.0)
    energy_split_factor = 60.0 / float(requested_step_minutes)
    if energy_split_factor > 1.0:
        out["solar_pred"] = out["solar_pred"] / energy_split_factor
        out["wind_pred"] = out["wind_pred"] / energy_split_factor

    return (
        [ts.isoformat() for ts in out.index],
        np.clip(out["solar_pred"].to_numpy(dtype=float), 0.0, None).tolist(),
        np.clip(out["solar_ext"].to_numpy(dtype=float), 0.0, 1.0).tolist(),
        np.clip(out["wind_pred"].to_numpy(dtype=float), 0.0, None).tolist(),
        np.clip(out["wind_ext"].to_numpy(dtype=float), 0.0, 1.0).tolist(),
    )


@app.get("/meta", response_model=MetaResponse)
def meta():
    if runtime is None:
        raise HTTPException(status_code=503, detail="Model runtime not loaded")
    renewable_meta = runtime.meta()
    return MetaResponse(
        model_name=runtime.model_name,
        model_version=runtime.model_version,
        n_timesteps=runtime.n_timesteps,
        x_input_mode=runtime.x_input_mode,
        y_transform=runtime.y_transform,
        winsor_limits=runtime.winsor_limits,
        target_name=runtime.target_name,
        target_unit=runtime.target_unit,
        wind_target_name=runtime.wind_target_name,
        wind_target_unit=runtime.wind_target_unit,
        features=renewable_meta["features"],
        engineered_feature_count=int(renewable_meta["engineered_feature_count"]),
        solar_extreme_threshold=float(renewable_meta["solar_extreme_threshold"]),
        wind_extreme_threshold=float(renewable_meta["wind_extreme_threshold"]),
        **{key: renewable_meta[key] for key in ["quality_model", "quality_model_version", "forecast_strategy",
            "original_article_weights", "energy_basis", "operational_horizon_accuracy_validated", "training_manifest"]},
    )


@app.get("/qc/meta")
def qc_meta():
    if ssl_qc_runtime is None or not ssl_qc_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="SSL-QC runtime not loaded")
    return ssl_qc_runtime.meta()


@app.post("/qc/score")
def qc_score(req: QCScoreRequest):
    if ssl_qc_runtime is None or not ssl_qc_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="SSL-QC runtime not loaded")
    try:
        return ssl_qc_runtime.score(
            req.records, window_id=req.window_id, source_kind=req.source_kind,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.get("/generation/meta")
def generation_meta():
    if dp_sthpp_runtime is None or not dp_sthpp_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="DP-STH++ runtime not loaded")
    if ssl_qc_runtime is None or not ssl_qc_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="SSL-QC runtime not loaded")
    return {
        "forecast_model": dp_sthpp_runtime.meta(),
        "quality_model": ssl_qc_runtime.meta(),
        "combined_endpoint": "/generation/analyze",
        "execution_order": ["SSL-QC", "DP-STH++"],
        "input_policy": "Same observed history; independent frozen preprocessing per model",
        "quality_policy": "Return advisory QC alongside the unchanged raw forecast; no automatic correction or suppression",
        "model_selection": "Server routes by task; no interchangeable forecasting-model selector",
        "telemetry_ingestion": "Caller must supply real measurements; automatic site acquisition is not configured",
        "weather_forecast_endpoints": {
            "paths": ["/forecast", "/forecast/7d", "/forecast/14d"],
            "model_name": runtime.model_name if runtime is not None else "unavailable",
            "uses_dp_sthpp": True,
            "uses_ssl_qc": True,
            "model_version": runtime.model_version if runtime else None,
            "quality_model": "DualAxis",
            "variant": "weather-only adaptation; original article weights remain on observed-history endpoints",
        },
    }


@app.post("/generation/predict")
def observed_generation_predict(req: ObservedForecastRequest):
    if dp_sthpp_runtime is None or not dp_sthpp_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="DP-STH++ runtime not loaded")
    try:
        return dp_sthpp_runtime.predict(req.records, source_kind=req.source_kind)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post("/generation/analyze")
def generation_analyze(req: GenerationAnalysisRequest):
    if dp_sthpp_runtime is None or not dp_sthpp_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="DP-STH++ runtime not loaded")
    if ssl_qc_runtime is None or not ssl_qc_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="SSL-QC runtime not loaded")
    try:
        quality = ssl_qc_runtime.score(
            req.records, window_id=req.window_id, source_kind=req.source_kind,
        )
        forecast_result = dp_sthpp_runtime.predict(req.records, source_kind=req.source_kind)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {
        "pipeline": "observed-history-qc-and-one-hour-forecast",
        "execution_order": ["SSL-QC", "DP-STH++"],
        "source_kind": req.source_kind,
        "quality": quality,
        "forecast": forecast_result,
        "quality_advisory": "above_research_reference" if quality["above_reference_cutoff"] else "within_research_reference",
        "forecast_modified_by_qc": False,
        "operational_fault_alarm": False,
        "notes": [
            "Both models used the same measured history, each with its own trained preprocessing.",
            "QC is an advisory diagnostic; its threshold has not been validated as a fault alarm.",
            "QC uses frozen internal input clipping; caller observations and raw forecast outputs remain unchanged.",
            "No forecast imputation, output clipping, capacity scaling, multi-day recursion or model substitution is performed.",
        ],
    }


@app.get("/load/meta", response_model=LoadMetaResponse)
def load_meta():
    if load_runtime is None or not load_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="Load runtime not loaded")
    meta_payload = load_runtime.meta()
    return LoadMetaResponse(**meta_payload)


# =========================
# Manual Predict (kept for debugging)
# =========================
@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest):
    if runtime is None:
        raise HTTPException(status_code=503, detail="Model runtime not loaded")

    try:
        if not req.inverse_y:
            raise ValueError("inverse_y=false is not supported by weather-v1")
        out = runtime.predict_weather(pd.DataFrame(req.records))
        solar, wind = out["normalized"].T
        ps, pw = out["extreme_scores"].T
        return PredictResponse(n=len(solar), y_pred=solar.tolist(), solar_pred=solar.tolist(), wind_pred=wind.tolist(),
            p_extreme=ps.tolist(), solar_p_extreme=ps.tolist(), wind_p_extreme=pw.tolist(),
            x_input_mode=runtime.x_input_mode, n_timesteps=24, features=runtime.meta()["features"],
            target_name="Normalized solar generation", wind_target_name="Normalized wind generation",
            target_unit="reference_normalized_source_generation", wind_target_unit="reference_normalized_source_generation",
            target_transform="fit-only reference normalization", model_name=runtime.model_name, model_version=runtime.model_version)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# =========================
# Forecast (Open-Meteo -> features -> model)
# =========================
@app.get("/forecast", response_model=ForecastResponse)
async def forecast(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    days: int = Query(7, ge=1, le=16, description="Forecast horizon in days (Open-Meteo typically supports up to 16)"),
    start_time: Optional[str] = Query(
        None,
        description="ISO datetime; omitted means now UTC. Naive values mean UTC. Use an explicit offset for local time.",
    ),
    timezone: str = Query(DEFAULT_TIMEZONE, description="Open-Meteo timezone param: 'auto' or IANA name (e.g., Asia/Almaty)"),
    step_minutes: int = Query(15, ge=15, le=60, description="Output step: 15, 30 or 60 minutes. Sub-hourly steps split hourly model energy."),
    inverse_y: bool = Query(True, description="Compatibility parameter; must be true. Output is physical site Wh per step."),
    capacity_kw: Optional[float] = Query(
        None,
        gt=0.0,
        le=100000.0,
        description="Installed PV capacity in kW for the explicit physical site-energy adapter.",
    ),
    tilt_deg: Optional[float] = Query(
        None,
        ge=0.0,
        le=90.0,
        description="Panel tilt in degrees. Optional but recommended for capacity-aware calibration.",
    ),
    azimuth_deg: Optional[float] = Query(
        None,
        ge=0.0,
        le=360.0,
        description="Panel azimuth in degrees where 180=south. Optional but recommended for capacity-aware calibration.",
    ),
    wind_capacity_kw: Optional[float] = Query(
        None,
        gt=0.0,
        le=100000.0,
        description="Installed wind turbine capacity in kW. Enables wind power-curve adaptation.",
    ),
    wind_hub_height_m: float = Query(
        80.0,
        ge=10.0,
        le=300.0,
        description="Wind turbine hub height in meters.",
    ),
    wind_reference_height_m: float = Query(
        10.0,
        ge=2.0,
        le=200.0,
        description="Reference height of Open-Meteo wind speed in meters.",
    ),
    wind_cut_in_ms: float = Query(3.0, ge=0.1, le=10.0),
    wind_rated_ms: float = Query(12.0, ge=2.0, le=40.0),
    wind_cut_out_ms: float = Query(25.0, ge=5.0, le=60.0),
):
    if runtime is None:
        raise HTTPException(status_code=503, detail="Model runtime not loaded")
    if _http is None:
        raise HTTPException(status_code=503, detail="HTTP client not ready")

    if step_minutes not in (15, 30, 60):
        raise HTTPException(status_code=400, detail="step_minutes must be one of: 15, 30, 60")

    requested_step_minutes = int(step_minutes)
    model_step_minutes = 60  # Weather variant uses native hourly windows.
    if not inverse_y:
        raise HTTPException(status_code=422, detail="Weather forecasts return site energy; inverse_y=false is unsupported")
    if capacity_kw is None and wind_capacity_kw is None:
        raise HTTPException(status_code=422, detail="Installed solar and/or wind capacity is required for site energy")

    # Parse start_time. The renewable model runs hourly; finer API steps are
    # produced by resampling hourly predictions back to 15/30-minute grids.
    try:
        if start_time:
            st = datetime.fromisoformat(start_time)
        else:
            st = datetime.now(dt_timezone.utc)
        st = _ceil_to_step(st, model_step_minutes)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid start_time. Use ISO format.")

    # We fetch with native hourly lookback for lag/rolling context.
    n_back = max(1, int(getattr(runtime, "n_timesteps", 1)))
    lookback_minutes = n_back * model_step_minutes
    fetch_start = st - timedelta(minutes=lookback_minutes)
    fetch_end = st + timedelta(days=days)

    try:
        df_all, tz_used = await _build_features_from_open_meteo(
            client=_http,
            lat=lat,
            lon=lon,
            start_dt=fetch_start,
            end_dt=fetch_end,
            timezone=timezone,
            step_minutes=model_step_minutes,
            required_cols=runtime.num_cols,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Open-Meteo build failed: {e}")

    # Retain exactly 23 context hours + the requested horizon. Weather timestamps
    # retain their local timezone for calendar inputs and solar geometry.
    df_all = df_all.sort_values("timestamp").reset_index(drop=True)
    ts_all = pd.to_datetime(df_all["timestamp"], errors="coerce", utc=True)
    st_utc = _as_utc_timestamp(st)
    horizon_end_utc = st_utc + pd.Timedelta(days=days)
    keep = (ts_all >= st_utc - pd.Timedelta(hours=23)) & (ts_all < horizon_end_utc)
    df_all = df_all.loc[keep].reset_index(drop=True)
    if len(df_all) != days * 24 + 23:
        raise HTTPException(status_code=502, detail="Weather provider did not return the full hourly context and horizon")
    df_h = df_all.iloc[23:].reset_index(drop=True)
    try:
        out = await run_in_threadpool(runtime.predict_weather, df_all)
        normalized = out["normalized"]
        reference = out["reference"]
        solar_base = np.zeros(len(df_h))
        wind_base = np.zeros(len(df_h))
        if capacity_kw:
            solar_base = _physical_baseline_step_kwh(df_h=df_h, lat=lat, capacity_kw=float(capacity_kw),
                step_minutes=60, tilt_deg=float(tilt_deg if tilt_deg is not None else _default_tilt_deg(lat)),
                azimuth_deg=float(azimuth_deg if azimuth_deg is not None else 180.0))
        if wind_capacity_kw:
            wind_base = _wind_power_curve_step_kwh(df_h=df_h, capacity_kw=float(wind_capacity_kw), step_minutes=60,
                hub_height_m=wind_hub_height_m, reference_height_m=wind_reference_height_m,
                cut_in_ms=wind_cut_in_ms, rated_ms=wind_rated_ms, cut_out_ms=wind_cut_out_ms)
        solar, solar_factor = site_energy_adapter(normalized[:,0], reference[:,0], solar_base, capacity_kw or 0)
        wind, wind_factor = site_energy_adapter(normalized[:,1], reference[:,1], wind_base, wind_capacity_kw or 0)
        if not np.isfinite(solar).all() or not np.isfinite(wind).all():
            raise ValueError("Nonfinite site-energy estimate")
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"Weather-model input or site parameters invalid: {exc}") from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Weather-model prediction failed: {exc}") from exc

    if not capacity_kw:
        out["extreme_scores"][:, 0] = 0
    if not wind_capacity_kw:
        out["extreme_scores"][:, 1] = 0
    hourly_times = [pd.Timestamp(t).tz_convert("UTC").isoformat() for t in df_h.timestamp]
    times, solar, solar_ext, wind, wind_ext = _resample_generation_forecast(
        times=hourly_times, solar_pred=(solar*1000).tolist(), solar_ext=out["extreme_scores"][:,0].tolist(),
        wind_pred=(wind*1000).tolist(), wind_ext=out["extreme_scores"][:,1].tolist(),
        requested_step_minutes=requested_step_minutes)
    metadata = runtime.meta()
    return ForecastResponse(n=len(times), step_minutes=requested_step_minutes, timezone=str(tz_used), times=times,
        y_pred=solar, solar_pred=solar, wind_pred=wind, p_extreme=solar_ext,
        solar_p_extreme=solar_ext, wind_p_extreme=wind_ext, x_input_mode=runtime.x_input_mode,
        n_timesteps=24, features=metadata["features"], target_name=runtime.target_name, target_unit=runtime.target_unit,
        target_transform=runtime.y_transform, wind_target_name=runtime.wind_target_name,
        wind_target_unit=runtime.wind_target_unit, model_name=runtime.model_name, model_version=runtime.model_version,
        source="open-meteo+dp-sthpp-weather-v1+dualaxis-weather-v1+physical-site-adapter",
        quality=out["quality"], provenance={
            "forecast_strategy": metadata["forecast_strategy"], "generation_history_required": False,
            "original_article_weights": False, "raw_model_unit": metadata["raw_prediction_unit"],
            "energy_basis": metadata["energy_basis"], "site_telemetry_calibrated": False,
            "operational_7_14_day_accuracy_validated": False, "extreme_scores_are_calibrated_probabilities": False,
            "subhourly_output": "constant hourly mean power; not independent 15/30-minute model predictions",
            "correction_bounds": [0.25, 2.0], "solar_correction_mean": float(np.mean(solar_factor)),
            "wind_correction_mean": float(np.mean(wind_factor)),
            "weights_sha256": {k:v for k,v in metadata["training_manifest"]["files"].items() if k.endswith((".h5", ".pt"))},
        })


@app.get("/forecast/7d", response_model=ForecastResponse)
async def forecast_7d(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    start_time: Optional[str] = Query(None),
    timezone: str = Query(DEFAULT_TIMEZONE),
    step_minutes: int = Query(15, ge=15, le=60),
    inverse_y: bool = Query(True),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    tilt_deg: Optional[float] = Query(None, ge=0.0, le=90.0),
    azimuth_deg: Optional[float] = Query(None, ge=0.0, le=360.0),
    wind_capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    wind_hub_height_m: float = Query(80.0, ge=10.0, le=300.0),
    wind_reference_height_m: float = Query(10.0, ge=2.0, le=200.0),
    wind_cut_in_ms: float = Query(3.0, ge=0.1, le=10.0),
    wind_rated_ms: float = Query(12.0, ge=2.0, le=40.0),
    wind_cut_out_ms: float = Query(25.0, ge=5.0, le=60.0),
):
    return await forecast(
        lat=lat,
        lon=lon,
        days=7,
        start_time=start_time,
        timezone=timezone,
        step_minutes=step_minutes,
        inverse_y=inverse_y,
        capacity_kw=capacity_kw,
        tilt_deg=tilt_deg,
        azimuth_deg=azimuth_deg,
        wind_capacity_kw=wind_capacity_kw,
        wind_hub_height_m=wind_hub_height_m,
        wind_reference_height_m=wind_reference_height_m,
        wind_cut_in_ms=wind_cut_in_ms,
        wind_rated_ms=wind_rated_ms,
        wind_cut_out_ms=wind_cut_out_ms,
    )


@app.get("/forecast/14d", response_model=ForecastResponse)
async def forecast_14d(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    start_time: Optional[str] = Query(None),
    timezone: str = Query(DEFAULT_TIMEZONE),
    step_minutes: int = Query(15, ge=15, le=60),
    inverse_y: bool = Query(True),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    tilt_deg: Optional[float] = Query(None, ge=0.0, le=90.0),
    azimuth_deg: Optional[float] = Query(None, ge=0.0, le=360.0),
    wind_capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    wind_hub_height_m: float = Query(80.0, ge=10.0, le=300.0),
    wind_reference_height_m: float = Query(10.0, ge=2.0, le=200.0),
    wind_cut_in_ms: float = Query(3.0, ge=0.1, le=10.0),
    wind_rated_ms: float = Query(12.0, ge=2.0, le=40.0),
    wind_cut_out_ms: float = Query(25.0, ge=5.0, le=60.0),
):
    return await forecast(
        lat=lat,
        lon=lon,
        days=14,
        start_time=start_time,
        timezone=timezone,
        step_minutes=step_minutes,
        inverse_y=inverse_y,
        capacity_kw=capacity_kw,
        tilt_deg=tilt_deg,
        azimuth_deg=azimuth_deg,
        wind_capacity_kw=wind_capacity_kw,
        wind_hub_height_m=wind_hub_height_m,
        wind_reference_height_m=wind_reference_height_m,
        wind_cut_in_ms=wind_cut_in_ms,
        wind_rated_ms=wind_rated_ms,
        wind_cut_out_ms=wind_cut_out_ms,
    )


def _utc_iso_now() -> str:
    return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def _benchmark_profile_stats() -> Dict[str, Any]:
    if load_runtime is None or not load_runtime.is_loaded:
        return {}
    return load_runtime.benchmark_profile_stats


def _recommended_scale_factor_for_capacity(capacity_kw: Optional[float]) -> Optional[float]:
    if capacity_kw is None or capacity_kw <= 0.0:
        return None
    stats = _benchmark_profile_stats()
    ref_kw = float(stats.get("pv_capacity_reference_kw", 0.0) or 0.0)
    if ref_kw <= 0.0:
        return None
    return float(capacity_kw) / ref_kw


def _default_battery_scenario_for_scale(scale_factor: float) -> BatteryScenario:
    stats = _benchmark_profile_stats()
    ref = stats.get("reference_battery_scenario") or {}
    capacity = float(ref.get("battery_capacity_kwh", 0.0) or 0.0) * scale_factor
    charge = float(ref.get("charge_power_kw", 0.0) or 0.0) * scale_factor
    discharge = float(ref.get("discharge_power_kw", 0.0) or 0.0) * scale_factor
    return BatteryScenario(
        enabled=True,
        battery_capacity_kwh=max(capacity, 0.0),
        soc_min=float(ref.get("soc_min", 0.10)),
        soc_max=float(ref.get("soc_max", 0.90)),
        soc_init=float(ref.get("soc_init", 0.50)),
        charge_power_kw=max(charge, 0.0),
        discharge_power_kw=max(discharge, 0.0),
        eta_charge=float(ref.get("eta_charge", 0.95)),
        eta_discharge=float(ref.get("eta_discharge", 0.95)),
        label=str(ref.get("label", "benchmark-scaled storage scenario")),
    )


def _balance_totals(balance_df: pd.DataFrame, *, step_minutes: int) -> Dict[str, float]:
    step_h = step_minutes / 60.0
    total_pv = float(balance_df["pv_kw_pred"].astype(float).sum() * step_h)
    total_wind = float(balance_df["wind_kw_pred"].astype(float).sum() * step_h)
    total_renewable = float(balance_df["renewable_kw_pred"].astype(float).sum() * step_h)
    total_load = float(balance_df["load_kw_pred"].astype(float).sum() * step_h)
    total_net = float(balance_df["net_load_kw"].astype(float).sum() * step_h)
    total_deficit = float(balance_df["deficit_kw"].astype(float).sum() * step_h)
    total_surplus = float(balance_df["surplus_kw"].astype(float).sum() * step_h)
    return {
        "total_pv_kwh": total_pv,
        "total_wind_kwh": total_wind,
        "total_renewable_kwh": total_renewable,
        "total_load_kwh": total_load,
        "total_net_kwh": total_net,
        "total_deficit_kwh": total_deficit,
        "total_surplus_kwh": total_surplus,
    }


def _resolve_load_assignment(
    *,
    device_id: Optional[str],
    profile_id: Optional[str],
    scale_factor: Optional[float],
    capacity_kw: Optional[float] = None,
    scaling_mode: str = "scenario_scale_factor",
) -> Dict[str, Any]:
    if load_runtime is None or not load_runtime.is_loaded:
        raise HTTPException(status_code=503, detail="Load runtime not loaded")

    resolved_profile = load_runtime.selected_profile_id
    resolved_scale: Optional[float] = None
    resolved_scaling_mode = scaling_mode
    stored_default_scale = False

    if device_id and firestore_store is not None:
        stored = firestore_store.get_load_profile_assignment(device_id)
        if stored:
            resolved_profile = str(stored.get("profile_id", resolved_profile))
            stored_scale = stored.get("scale_factor")
            if stored_scale is not None:
                resolved_scale = float(stored_scale)
            resolved_scaling_mode = str(stored.get("scaling_mode", resolved_scaling_mode))
            stored_default_scale = (
                resolved_scale is not None
                and abs(float(resolved_scale) - 1.0) <= 1e-9
                and resolved_scaling_mode == "scenario_scale_factor"
            )

    if profile_id:
        if profile_id != load_runtime.selected_profile_id:
            raise HTTPException(
                status_code=422,
                detail=(
                    "This deployment bundle currently supports the scientifically selected benchmark profile "
                    f"'{load_runtime.selected_profile_id}' only."
                ),
            )
        resolved_profile = profile_id

    if scale_factor is not None:
        resolved_scale = float(scale_factor)
        resolved_scaling_mode = scaling_mode

    recommended = _recommended_scale_factor_for_capacity(capacity_kw)
    if recommended is not None and (resolved_scale is None or stored_default_scale):
        resolved_scale = recommended
        resolved_scaling_mode = "pv_capacity_ratio_to_profile_peak"

    if resolved_scale is None:
        resolved_scale = 1.0

    return {
        "profile_id": resolved_profile,
        "scale_factor": resolved_scale,
        "scaling_mode": resolved_scaling_mode,
        "source_dataset": load_runtime.source_dataset,
        "source_type": "OPSD_household_15min",
    }


def _target_values_to_step_kw(
    values: np.ndarray,
    *,
    step_minutes: int,
    target_unit: str,
) -> np.ndarray:
    step_kwh = _target_values_to_step_kwh(values, step_minutes=step_minutes, target_unit=target_unit)
    step_h = step_minutes / 60.0
    return np.nan_to_num(step_kwh / max(step_h, 1e-9), nan=0.0, posinf=0.0, neginf=0.0)


def _coerce_start_time_utc(start_time: Optional[str], step_minutes: int) -> datetime:
    try:
        if start_time:
            st = datetime.fromisoformat(start_time)
        else:
            st = datetime.utcnow()
        if getattr(st, "tzinfo", None) is None:
            ts = pd.Timestamp(st, tz="UTC")
        else:
            ts = pd.Timestamp(st).tz_convert("UTC")
        ts = ts.to_pydatetime()
        return _ceil_to_step(ts, step_minutes)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid start_time. Use ISO format.")


def _aggregate_balance_for_dispatch(balance_df: pd.DataFrame, step_minutes: int) -> pd.DataFrame:
    if step_minutes == 15:
        return balance_df.copy()
    if step_minutes != 60:
        raise HTTPException(status_code=400, detail="dispatch step_minutes must be 15 or 60")

    out = balance_df.copy()
    timestamps = pd.to_datetime(out["utc_timestamp"], utc=True)
    if out.empty or len(out) % 4 != 0:
        raise HTTPException(status_code=400, detail="Hourly dispatch requires complete groups of four 15-minute intervals")
    if not timestamps.diff().iloc[1:].eq(pd.Timedelta(minutes=15)).all():
        raise HTTPException(status_code=400, detail="Dispatch inputs must be consecutive 15-minute intervals")
    # Anchor each full hour to the actual forecast start. Rounding to wall-clock
    # hours creates two partial buckets and overcounts energy when starting at
    # :15, :30 or :45 while the optimizer assumes 60 minutes per bucket.
    origin = timestamps.iloc[0]
    out["dispatch_timestamp"] = origin + (timestamps - origin).dt.floor("h")
    grouped = (
        out.groupby("dispatch_timestamp", as_index=False)
        .agg(
            {
                "pv_kw_pred": "mean",
                "wind_kw_pred": "mean",
                "renewable_kw_pred": "mean",
                "load_kw_pred": "mean",
                "net_load_kw": "mean",
                "grid_import_kw_before": "mean",
                "grid_export_kw_before": "mean",
                "deficit_kw": "mean",
                "surplus_kw": "mean",
            }
        )
        .rename(columns={"dispatch_timestamp": "utc_timestamp"})
    )
    return grouped


def _build_energy_balance_from_arrays(
    *,
    timestamps: List[str],
    load_kw_pred: List[float],
    pv_kw_pred: List[float],
    wind_kw_pred: Optional[List[float]] = None,
    step_minutes: int,
) -> pd.DataFrame:
    if step_minutes != 15:
        raise HTTPException(status_code=400, detail="Only 15-minute balance inputs are supported")
    if not timestamps or not load_kw_pred or not pv_kw_pred:
        raise HTTPException(status_code=400, detail="timestamps, load_kw_pred, and pv_kw_pred are required for direct optimization inputs")
    n = min(len(timestamps), len(load_kw_pred), len(pv_kw_pred))
    if wind_kw_pred is not None:
        n = min(n, len(wind_kw_pred))
    if n == 0:
        raise HTTPException(status_code=400, detail="Direct optimization inputs are empty")
    return compute_energy_balance(
        timestamps=timestamps[:n],
        load_kw=load_kw_pred[:n],
        pv_kw=pv_kw_pred[:n],
        wind_kw=wind_kw_pred[:n] if wind_kw_pred is not None else None,
    )


async def _build_energy_balance_dataframe(
    *,
    lat: float,
    lon: float,
    days: int,
    start_time: Optional[str],
    timezone: str,
    device_id: Optional[str],
    profile_id: Optional[str],
    scale_factor: Optional[float],
    capacity_kw: Optional[float],
    tilt_deg: Optional[float],
    azimuth_deg: Optional[float],
    wind_capacity_kw: Optional[float] = None,
    wind_hub_height_m: Optional[float] = None,
    wind_reference_height_m: Optional[float] = None,
    wind_cut_in_ms: Optional[float] = None,
    wind_rated_ms: Optional[float] = None,
    wind_cut_out_ms: Optional[float] = None,
) -> Tuple[pd.DataFrame, Dict[str, Any], ForecastResponse, Dict[str, Any]]:
    resolved = _resolve_load_assignment(
        device_id=device_id,
        profile_id=profile_id,
        scale_factor=scale_factor,
        capacity_kw=capacity_kw,
    )
    start_utc = _coerce_start_time_utc(start_time, 60)
    start_ts = pd.Timestamp(start_utc)
    if start_ts.tzinfo is None:
        start_ts = start_ts.tz_localize("UTC")
    else:
        start_ts = start_ts.tz_convert("UTC")
    load_payload = load_runtime.forecast(days=days, start_time=start_utc, scale_factor=resolved["scale_factor"])
    pv_payload = await forecast(
        lat=lat,
        lon=lon,
        days=days,
        start_time=start_ts.isoformat(),
        timezone=timezone,
        step_minutes=15,
        inverse_y=True,
        capacity_kw=capacity_kw,
        tilt_deg=tilt_deg,
        azimuth_deg=azimuth_deg,
        wind_capacity_kw=wind_capacity_kw,
        wind_hub_height_m=float(wind_hub_height_m if wind_hub_height_m is not None else 80.0),
        wind_reference_height_m=float(wind_reference_height_m if wind_reference_height_m is not None else 10.0),
        wind_cut_in_ms=float(wind_cut_in_ms if wind_cut_in_ms is not None else 3.0),
        wind_rated_ms=float(wind_rated_ms if wind_rated_ms is not None else 12.0),
        wind_cut_out_ms=float(wind_cut_out_ms if wind_cut_out_ms is not None else 25.0),
    )

    pv_kw = _target_values_to_step_kw(
        np.asarray(pv_payload.y_pred, dtype=float),
        step_minutes=pv_payload.step_minutes,
        target_unit=pv_payload.target_unit,
    )
    wind_kw = _target_values_to_step_kw(
        np.asarray(pv_payload.wind_pred, dtype=float),
        step_minutes=pv_payload.step_minutes,
        target_unit=pv_payload.wind_target_unit,
    )
    n = min(len(load_payload["timestamps"]), len(pv_kw))
    n = min(n, len(wind_kw))
    balance_df = compute_energy_balance(
        timestamps=load_payload["timestamps"][:n],
        load_kw=load_payload["load_kw_pred"][:n],
        pv_kw=pv_kw[:n].tolist(),
        wind_kw=wind_kw[:n].tolist(),
    )
    return balance_df, load_payload, pv_payload, resolved


@app.post("/load/assign-profile", response_model=LoadAssignResponse)
def load_assign_profile(req: LoadAssignRequest):
    resolved = _resolve_load_assignment(
        device_id=req.device_id,
        profile_id=req.profile_id,
        scale_factor=req.scale_factor,
        scaling_mode=req.scaling_mode,
    )
    payload = {
        "profile_id": resolved["profile_id"],
        "source_dataset": req.source_dataset or resolved["source_dataset"],
        "source_type": resolved["source_type"],
        "scaling_mode": req.scaling_mode,
        "scale_factor": float(req.scale_factor),
    }
    persisted = False
    firestore_error: Optional[str] = None
    if firestore_store is not None:
        persisted = firestore_store.save_load_profile_assignment(req.device_id, payload)
        firestore_error = firestore_store.error
    return LoadAssignResponse(
        device_id=req.device_id,
        profile_id=payload["profile_id"],
        source_dataset=payload["source_dataset"],
        source_type=payload["source_type"],
        scaling_mode=payload["scaling_mode"],
        scale_factor=payload["scale_factor"],
        assigned_at=_utc_iso_now(),
        firestore_persisted=persisted,
        firestore_error=firestore_error,
    )


@app.get("/load/forecast", response_model=LoadForecastResponse)
def load_forecast(
    background_tasks: BackgroundTasks,
    days: int = Query(7, ge=1, le=14),
    start_time: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None),
    profile_id: Optional[str] = Query(None),
    scale_factor: Optional[float] = Query(None, gt=0.0, le=1000.0),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
):
    resolved = _resolve_load_assignment(
        device_id=device_id,
        profile_id=profile_id,
        scale_factor=scale_factor,
        capacity_kw=capacity_kw,
    )
    start_utc = _coerce_start_time_utc(start_time, 15)
    out = load_runtime.forecast(days=days, start_time=start_utc, scale_factor=resolved["scale_factor"])

    persisted = False
    firestore_error: Optional[str] = None
    if device_id and firestore_store is not None:
        background_tasks.add_task(
            firestore_store.save_load_forecast,
            device_id,
            days,
            {
                **out,
                "scaling_mode": resolved["scaling_mode"],
                "source_type": resolved["source_type"],
            },
        )
        persisted = True

    return LoadForecastResponse(
        **out,
        scaling_mode=resolved["scaling_mode"],
        firestore_persisted=persisted,
        firestore_error=firestore_error,
    )


@app.get("/load/forecast/7d", response_model=LoadForecastResponse)
def load_forecast_7d(
    background_tasks: BackgroundTasks,
    start_time: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None),
    profile_id: Optional[str] = Query(None),
    scale_factor: Optional[float] = Query(None, gt=0.0, le=1000.0),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
):
    return load_forecast(
        background_tasks=background_tasks,
        days=7,
        start_time=start_time,
        device_id=device_id,
        profile_id=profile_id,
        scale_factor=scale_factor,
        capacity_kw=capacity_kw,
    )


@app.get("/load/forecast/14d", response_model=LoadForecastResponse)
def load_forecast_14d(
    background_tasks: BackgroundTasks,
    start_time: Optional[str] = Query(None),
    device_id: Optional[str] = Query(None),
    profile_id: Optional[str] = Query(None),
    scale_factor: Optional[float] = Query(None, gt=0.0, le=1000.0),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
):
    return load_forecast(
        background_tasks=background_tasks,
        days=14,
        start_time=start_time,
        device_id=device_id,
        profile_id=profile_id,
        scale_factor=scale_factor,
        capacity_kw=capacity_kw,
    )


@app.get("/energy/balance", response_model=EnergyBalanceResponse)
async def energy_balance(
    background_tasks: BackgroundTasks,
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    days: int = Query(7, ge=1, le=14),
    start_time: Optional[str] = Query(None),
    timezone: str = Query(DEFAULT_TIMEZONE),
    device_id: Optional[str] = Query(None),
    profile_id: Optional[str] = Query(None),
    scale_factor: Optional[float] = Query(None, gt=0.0, le=1000.0),
    capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    tilt_deg: Optional[float] = Query(None, ge=0.0, le=90.0),
    azimuth_deg: Optional[float] = Query(None, ge=0.0, le=360.0),
    wind_capacity_kw: Optional[float] = Query(None, gt=0.0, le=100000.0),
    wind_hub_height_m: Optional[float] = Query(None, ge=10.0, le=300.0),
    wind_reference_height_m: Optional[float] = Query(None, ge=2.0, le=200.0),
    wind_cut_in_ms: Optional[float] = Query(None, ge=0.1, le=10.0),
    wind_rated_ms: Optional[float] = Query(None, ge=2.0, le=40.0),
    wind_cut_out_ms: Optional[float] = Query(None, ge=5.0, le=60.0),
):
    balance_df, load_payload, pv_payload, resolved = await _build_energy_balance_dataframe(
        lat=lat,
        lon=lon,
        days=days,
        start_time=start_time,
        timezone=timezone,
        device_id=device_id,
        profile_id=profile_id,
        scale_factor=scale_factor,
        capacity_kw=capacity_kw,
        tilt_deg=tilt_deg,
        azimuth_deg=azimuth_deg,
        wind_capacity_kw=wind_capacity_kw,
        wind_hub_height_m=wind_hub_height_m,
        wind_reference_height_m=wind_reference_height_m,
        wind_cut_in_ms=wind_cut_in_ms,
        wind_rated_ms=wind_rated_ms,
        wind_cut_out_ms=wind_cut_out_ms,
    )
    totals = _balance_totals(balance_df, step_minutes=15)

    persisted = False
    firestore_error: Optional[str] = None
    if device_id and firestore_store is not None:
        background_tasks.add_task(
            firestore_store.save_energy_balance,
            device_id,
            {
                "timestamps": balance_df["utc_timestamp"].dt.strftime("%Y-%m-%dT%H:%M:%SZ").tolist(),
                "pv_kw_pred": balance_df["pv_kw_pred"].astype(float).tolist(),
                "wind_kw_pred": balance_df["wind_kw_pred"].astype(float).tolist(),
                "renewable_kw_pred": balance_df["renewable_kw_pred"].astype(float).tolist(),
                "load_kw_pred": balance_df["load_kw_pred"].astype(float).tolist(),
                "net_load_kw": balance_df["net_load_kw"].astype(float).tolist(),
                "deficit_kw": balance_df["deficit_kw"].astype(float).tolist(),
                "surplus_kw": balance_df["surplus_kw"].astype(float).tolist(),
                "load_model_name": load_payload["model_name"],
                "load_model_version": load_payload["model_version"],
                "pv_source": pv_payload.source,
                "source_profile_id": resolved["profile_id"],
                "scale_factor": resolved["scale_factor"],
                "scaling_mode": resolved["scaling_mode"],
                **totals,
            },
        )
        persisted = True

    return EnergyBalanceResponse(
        n=int(len(balance_df)),
        step_minutes=15,
        timestamps=balance_df["utc_timestamp"].dt.strftime("%Y-%m-%dT%H:%M:%SZ").tolist(),
        pv_kw_pred=balance_df["pv_kw_pred"].astype(float).tolist(),
        wind_kw_pred=balance_df["wind_kw_pred"].astype(float).tolist(),
        renewable_kw_pred=balance_df["renewable_kw_pred"].astype(float).tolist(),
        load_kw_pred=balance_df["load_kw_pred"].astype(float).tolist(),
        net_load_kw=balance_df["net_load_kw"].astype(float).tolist(),
        deficit_kw=balance_df["deficit_kw"].astype(float).tolist(),
        surplus_kw=balance_df["surplus_kw"].astype(float).tolist(),
        load_model_name=load_payload["model_name"],
        load_model_version=load_payload["model_version"],
        pv_source=pv_payload.source,
        source_profile_id=resolved["profile_id"],
        scale_factor=float(resolved["scale_factor"]),
        scaling_mode=resolved["scaling_mode"],
        total_pv_kwh=float(totals["total_pv_kwh"]),
        total_wind_kwh=float(totals["total_wind_kwh"]),
        total_renewable_kwh=float(totals["total_renewable_kwh"]),
        total_load_kwh=float(totals["total_load_kwh"]),
        total_net_kwh=float(totals["total_net_kwh"]),
        total_deficit_kwh=float(totals["total_deficit_kwh"]),
        total_surplus_kwh=float(totals["total_surplus_kwh"]),
        firestore_persisted=persisted,
        firestore_error=firestore_error,
    )


@app.post("/optimize", response_model=OptimizeResponse)
async def optimize(req: OptimizeRequest, background_tasks: BackgroundTasks):
    if req.timestamps and req.load_kw_pred and req.pv_kw_pred:
        resolved = _resolve_load_assignment(
            device_id=req.device_id,
            profile_id=req.profile_id,
            scale_factor=req.scale_factor,
            capacity_kw=req.capacity_kw,
        )
        balance_df = _build_energy_balance_from_arrays(
            timestamps=req.timestamps,
            load_kw_pred=req.load_kw_pred,
            pv_kw_pred=req.pv_kw_pred,
            wind_kw_pred=req.wind_kw_pred,
            step_minutes=req.balance_step_minutes,
        )
        load_payload = {
            "model_name": load_runtime.model_name if load_runtime is not None else "load-model",
            "model_version": load_runtime.model_version if load_runtime is not None else "v1",
        }
        pv_source = "client-aligned-pv-forecast"
    else:
        balance_df, load_payload, pv_payload, resolved = await _build_energy_balance_dataframe(
            lat=req.lat,
            lon=req.lon,
            days=req.days,
            start_time=req.start_time,
            timezone=req.timezone,
            device_id=req.device_id,
            profile_id=req.profile_id,
            scale_factor=req.scale_factor,
            capacity_kw=req.capacity_kw,
            tilt_deg=req.tilt_deg,
            azimuth_deg=req.azimuth_deg,
            wind_capacity_kw=req.wind_capacity_kw,
            wind_hub_height_m=req.wind_hub_height_m,
            wind_reference_height_m=req.wind_reference_height_m,
            wind_cut_in_ms=req.wind_cut_in_ms,
            wind_rated_ms=req.wind_rated_ms,
            wind_cut_out_ms=req.wind_cut_out_ms,
        )
        pv_source = pv_payload.source
    dispatch_balance = _aggregate_balance_for_dispatch(balance_df, req.dispatch_step_minutes)
    battery_payload = req.battery.model_dump()
    use_auto_battery = battery_payload.get("enabled", False) and (
        battery_payload.get("battery_capacity_kwh", 0.0) <= 0.0
        or battery_payload.get("charge_power_kw", 0.0) <= 0.0
        or battery_payload.get("discharge_power_kw", 0.0) <= 0.0
    )
    if use_auto_battery:
        battery = _default_battery_scenario_for_scale(float(resolved["scale_factor"]))
    else:
        battery = BatteryScenario(**battery_payload)
    optimized_df, summary = optimize_dispatch(
        timestamps=dispatch_balance["utc_timestamp"],
        load_kw=dispatch_balance["load_kw_pred"],
        pv_kw=dispatch_balance["pv_kw_pred"],
        wind_kw=dispatch_balance["wind_kw_pred"],
        battery=battery,
        step_minutes=req.dispatch_step_minutes,
    )

    persisted = False
    firestore_error: Optional[str] = None
    if req.device_id and firestore_store is not None:
        background_tasks.add_task(
            firestore_store.save_optimization,
            req.device_id,
            {
                "timestamps": optimized_df["utc_timestamp"].dt.strftime("%Y-%m-%dT%H:%M:%SZ").tolist(),
                "pv_kw_pred": optimized_df["pv_kw_pred"].astype(float).tolist(),
                "wind_kw_pred": optimized_df["wind_kw_pred"].astype(float).tolist(),
                "renewable_kw_pred": optimized_df["renewable_kw_pred"].astype(float).tolist(),
                "load_kw_pred": optimized_df["load_kw_pred"].astype(float).tolist(),
                "net_load_kw": optimized_df["net_load_kw"].astype(float).tolist(),
                "grid_import_kw_before": optimized_df["grid_import_kw_before"].astype(float).tolist(),
                "grid_import_kw_after": optimized_df["grid_import_kw_after"].astype(float).tolist(),
                "peak_before_kw": float(summary["peak_before_kw"]),
                "peak_after_kw": float(summary["peak_after_kw"]),
                "battery_charge_kw": optimized_df["battery_charge_kw"].astype(float).tolist(),
                "battery_discharge_kw": optimized_df["battery_discharge_kw"].astype(float).tolist(),
                "soc_kwh": optimized_df["soc_kwh"].astype(float).tolist(),
                "objective_summary": summary["objective_summary"],
                "scenario_parameters": summary["scenario_parameters"],
                "load_model_name": load_payload["model_name"],
                "load_model_version": load_payload["model_version"],
                "pv_source": pv_source,
                "source_profile_id": resolved["profile_id"],
                "scale_factor": resolved["scale_factor"],
                "scaling_mode": resolved["scaling_mode"],
                "dispatch_step_minutes": req.dispatch_step_minutes,
                "total_pv_kwh": float(summary["total_pv_kwh"]),
                "total_wind_kwh": float(summary["total_wind_kwh"]),
                "total_renewable_kwh": float(summary["total_renewable_kwh"]),
                "total_load_kwh": float(summary["total_load_kwh"]),
                "total_deficit_kwh": float(summary["total_deficit_kwh"]),
                "total_surplus_kwh": float(summary["total_surplus_kwh"]),
                "total_grid_import_kwh_before": float(summary["total_grid_import_kwh_before"]),
                "total_grid_import_kwh_after": float(summary["total_grid_import_kwh_after"]),
                "grid_import_reduction_kwh": float(summary["grid_import_reduction_kwh"]),
                "grid_import_reduction_pct": float(summary["grid_import_reduction_pct"]),
                "self_sufficiency_ratio_before": float(summary["self_sufficiency_ratio_before"]),
                "self_sufficiency_ratio_after": float(summary["self_sufficiency_ratio_after"]),
                "self_consumption_ratio_before": float(summary["self_consumption_ratio_before"]),
                "self_consumption_ratio_after": float(summary["self_consumption_ratio_after"]),
                "optimization_gain_kwh": float(summary["optimization_gain_kwh"]),
            },
        )
        persisted = True

    return OptimizeResponse(
        n=int(len(optimized_df)),
        step_minutes=req.dispatch_step_minutes,
        timestamps=optimized_df["utc_timestamp"].dt.strftime("%Y-%m-%dT%H:%M:%SZ").tolist(),
        pv_kw_pred=optimized_df["pv_kw_pred"].astype(float).tolist(),
        wind_kw_pred=optimized_df["wind_kw_pred"].astype(float).tolist(),
        renewable_kw_pred=optimized_df["renewable_kw_pred"].astype(float).tolist(),
        load_kw_pred=optimized_df["load_kw_pred"].astype(float).tolist(),
        net_load_kw=optimized_df["net_load_kw"].astype(float).tolist(),
        grid_import_kw_before=optimized_df["grid_import_kw_before"].astype(float).tolist(),
        grid_import_kw_after=optimized_df["grid_import_kw_after"].astype(float).tolist(),
        peak_before_kw=float(summary["peak_before_kw"]),
        peak_after_kw=float(summary["peak_after_kw"]),
        battery_charge_kw=optimized_df["battery_charge_kw"].astype(float).tolist(),
        battery_discharge_kw=optimized_df["battery_discharge_kw"].astype(float).tolist(),
        soc_kwh=optimized_df["soc_kwh"].astype(float).tolist(),
        objective_summary=summary["objective_summary"],
        scenario_parameters=summary["scenario_parameters"],
        load_model_name=load_payload["model_name"],
        load_model_version=load_payload["model_version"],
        pv_source=pv_source,
        source_profile_id=resolved["profile_id"],
        scale_factor=float(resolved["scale_factor"]),
        scaling_mode=resolved["scaling_mode"],
        total_pv_kwh=float(summary["total_pv_kwh"]),
        total_wind_kwh=float(summary["total_wind_kwh"]),
        total_renewable_kwh=float(summary["total_renewable_kwh"]),
        total_load_kwh=float(summary["total_load_kwh"]),
        total_deficit_kwh=float(summary["total_deficit_kwh"]),
        total_surplus_kwh=float(summary["total_surplus_kwh"]),
        total_grid_import_kwh_before=float(summary["total_grid_import_kwh_before"]),
        total_grid_import_kwh_after=float(summary["total_grid_import_kwh_after"]),
        grid_import_reduction_kwh=float(summary["grid_import_reduction_kwh"]),
        grid_import_reduction_pct=float(summary["grid_import_reduction_pct"]),
        self_sufficiency_ratio_before=float(summary["self_sufficiency_ratio_before"]),
        self_sufficiency_ratio_after=float(summary["self_sufficiency_ratio_after"]),
        self_consumption_ratio_before=float(summary["self_consumption_ratio_before"]),
        self_consumption_ratio_after=float(summary["self_consumption_ratio_after"]),
        optimization_gain_kwh=float(summary["optimization_gain_kwh"]),
        firestore_persisted=persisted,
        firestore_error=firestore_error,
    )


def _default_tilt_deg(lat: float) -> float:
    return float(min(max(abs(lat) * 0.76, 10.0), 35.0))


def _target_values_to_step_kwh(
    values: np.ndarray,
    *,
    step_minutes: int,
    target_unit: str,
) -> np.ndarray:
    arr = np.nan_to_num(np.asarray(values, dtype=float), nan=0.0, posinf=0.0, neginf=0.0)
    unit = (target_unit or "Wh_per_step").strip().lower()
    step_h = step_minutes / 60.0
    if "wh" in unit:
        return np.clip(arr, 0.0, None) / 1000.0
    if "kw" in unit:
        return np.clip(arr, 0.0, None) * step_h
    return np.clip(arr, 0.0, None) / 1000.0


def _step_kwh_to_target_values(
    step_kwh: np.ndarray,
    *,
    step_minutes: int,
    target_unit: str,
) -> np.ndarray:
    arr = np.nan_to_num(np.asarray(step_kwh, dtype=float), nan=0.0, posinf=0.0, neginf=0.0)
    unit = (target_unit or "Wh_per_step").strip().lower()
    step_h = step_minutes / 60.0
    if "wh" in unit:
        return arr * 1000.0
    if "kw" in unit:
        return arr / max(step_h, 1e-9)
    return arr * 1000.0


def _physical_baseline_step_kwh(
    *,
    df_h: pd.DataFrame,
    lat: float,
    capacity_kw: float,
    step_minutes: int,
    tilt_deg: float,
    azimuth_deg: float,
) -> np.ndarray:
    ts = pd.to_datetime(df_h["timestamp"], errors="coerce")
    if ts.isna().any():
        raise ValueError("timestamp column contains invalid values")

    ghi = np.clip(pd.to_numeric(df_h.get("GHI"), errors="coerce").to_numpy(dtype=float), 0.0, None)
    air_temp = np.nan_to_num(
        pd.to_numeric(df_h.get("temp"), errors="coerce").to_numpy(dtype=float),
        nan=20.0,
    )
    wind_speed = np.nan_to_num(
        pd.to_numeric(df_h.get("wind_speed"), errors="coerce").to_numpy(dtype=float),
        nan=1.5,
    )
    snow_1h = np.clip(
        np.nan_to_num(pd.to_numeric(df_h.get("snow_1h"), errors="coerce").to_numpy(dtype=float), nan=0.0),
        0.0,
        None,
    )
    is_sun = np.nan_to_num(
        pd.to_numeric(df_h.get("isSun"), errors="coerce").to_numpy(dtype=float),
        nan=0.0,
    )

    lat_r = np.deg2rad(float(lat))
    beta = np.deg2rad(float(np.clip(tilt_deg, 0.0, 90.0)))
    gamma = np.deg2rad(float(((azimuth_deg - 180.0) + 180.0) % 360.0 - 180.0))

    day_of_year = ts.dt.dayofyear.to_numpy(dtype=float)
    hour_decimal = (
        ts.dt.hour.to_numpy(dtype=float)
        + ts.dt.minute.to_numpy(dtype=float) / 60.0
        + ts.dt.second.to_numpy(dtype=float) / 3600.0
    )

    decl = np.deg2rad(23.45) * np.sin(2.0 * np.pi * (284.0 + day_of_year) / 365.0)
    hour_angle = np.deg2rad(15.0 * (hour_decimal - 12.0))

    sin_lat = np.sin(lat_r)
    cos_lat = np.cos(lat_r)
    sin_dec = np.sin(decl)
    cos_dec = np.cos(decl)
    cos_h = np.cos(hour_angle)
    sin_h = np.sin(hour_angle)

    cos_theta_z = sin_lat * sin_dec + cos_lat * cos_dec * cos_h
    cos_theta_z = np.clip(cos_theta_z, 0.0, None)

    cos_theta = (
        sin_dec * sin_lat * np.cos(beta)
        - sin_dec * cos_lat * np.sin(beta) * np.cos(gamma)
        + cos_dec * cos_lat * np.cos(beta) * cos_h
        + cos_dec * sin_lat * np.sin(beta) * np.cos(gamma) * cos_h
        + cos_dec * np.sin(beta) * np.sin(gamma) * sin_h
    )
    cos_theta = np.clip(cos_theta, 0.0, None)

    isotropic = (1.0 + np.cos(beta)) / 2.0
    ground_reflect = 0.2 * (1.0 - np.cos(beta)) / 2.0
    beam_ratio = np.where(cos_theta_z > 1e-4, cos_theta / np.maximum(cos_theta_z, 1e-4), 0.0)
    beam_ratio = np.clip(beam_ratio, 0.0, 1.35)
    poa_ratio = np.where(
        is_sun > 0.0,
        0.72 * beam_ratio + 0.23 * isotropic + ground_reflect,
        0.0,
    )
    poa_ratio = np.clip(poa_ratio, 0.0, 1.28)

    poa_wm2 = np.clip(ghi * poa_ratio, 0.0, 1250.0)
    cell_temp = air_temp + (poa_wm2 / 800.0) * (20.0 - np.clip(wind_speed, 0.0, 10.0) * 0.8)
    temp_factor = np.clip(1.0 - 0.0042 * np.maximum(cell_temp - 25.0, 0.0), 0.72, 1.02)
    snow_factor = np.clip(1.0 - np.clip(snow_1h, 0.0, 8.0) * 0.06, 0.35, 1.0)
    base_pr = 0.82

    step_h = step_minutes / 60.0
    power_kw = capacity_kw * np.clip(poa_wm2 / 1000.0, 0.0, 1.18) * base_pr * temp_factor * snow_factor
    power_kw = np.where(is_sun > 0.0, power_kw, 0.0)
    return np.clip(power_kw * step_h, 0.0, None)


def _wind_power_curve_step_kwh(
    *,
    df_h: pd.DataFrame,
    capacity_kw: float,
    step_minutes: int,
    hub_height_m: float,
    reference_height_m: float,
    cut_in_ms: float,
    rated_ms: float,
    cut_out_ms: float,
) -> np.ndarray:
    if rated_ms <= cut_in_ms:
        raise ValueError("wind_rated_ms must be greater than wind_cut_in_ms")
    if cut_out_ms <= rated_ms:
        raise ValueError("wind_cut_out_ms must be greater than wind_rated_ms")

    wind_10m = np.clip(
        np.nan_to_num(pd.to_numeric(df_h.get("wind_speed_wind"), errors="coerce").to_numpy(dtype=float), nan=0.0),
        0.0,
        None,
    )
    # 1/7 power law is a standard neutral-stability engineering approximation.
    shear_alpha = 1.0 / 7.0
    hub_ratio = max(float(hub_height_m), 1e-6) / max(float(reference_height_m), 1e-6)
    wind_hub = wind_10m * (hub_ratio ** shear_alpha)

    power_fraction = np.zeros_like(wind_hub, dtype=float)
    ramp_mask = (wind_hub >= cut_in_ms) & (wind_hub < rated_ms)
    power_fraction[ramp_mask] = (
        (wind_hub[ramp_mask] ** 3 - cut_in_ms ** 3)
        / max(rated_ms ** 3 - cut_in_ms ** 3, 1e-9)
    )
    rated_mask = (wind_hub >= rated_ms) & (wind_hub <= cut_out_ms)
    power_fraction[rated_mask] = 1.0
    power_kw = float(capacity_kw) * np.clip(power_fraction, 0.0, 1.0)
    return np.clip(power_kw * (step_minutes / 60.0), 0.0, None)


def _apply_wind_capacity_aware_calibration(
    *,
    df_h: pd.DataFrame,
    wind_pred: List[float],
    capacity_kw: float,
    step_minutes: int,
    target_unit: str,
    hub_height_m: float,
    reference_height_m: float,
    cut_in_ms: float,
    rated_ms: float,
    cut_out_ms: float,
) -> List[float]:
    raw_step_kwh = _target_values_to_step_kwh(
        np.asarray(wind_pred, dtype=float),
        step_minutes=step_minutes,
        target_unit=target_unit,
    )
    baseline_step_kwh = _wind_power_curve_step_kwh(
        df_h=df_h,
        capacity_kw=capacity_kw,
        step_minutes=step_minutes,
        hub_height_m=hub_height_m,
        reference_height_m=reference_height_m,
        cut_in_ms=cut_in_ms,
        rated_ms=rated_ms,
        cut_out_ms=cut_out_ms,
    )

    raw_total = float(np.sum(raw_step_kwh))
    baseline_total = float(np.sum(baseline_step_kwh))
    if baseline_total <= 1e-9:
        calibrated = np.zeros_like(raw_step_kwh)
    elif raw_total <= 1e-9:
        calibrated = baseline_step_kwh
    else:
        scaled_raw = raw_step_kwh * (baseline_total / raw_total)
        raw_weights = scaled_raw / max(float(np.sum(scaled_raw)), 1e-9)
        baseline_weights = baseline_step_kwh / max(baseline_total, 1e-9)
        hybrid_weights = np.clip(0.65 * raw_weights + 0.35 * baseline_weights, 0.0, None)
        hybrid_weights = hybrid_weights / max(float(np.sum(hybrid_weights)), 1e-9)
        calibrated = baseline_total * hybrid_weights
        step_cap = float(capacity_kw) * (step_minutes / 60.0)
        calibrated = np.minimum(calibrated, step_cap)

    return _step_kwh_to_target_values(
        calibrated,
        step_minutes=step_minutes,
        target_unit=target_unit,
    ).astype(float).tolist()


def _apply_capacity_aware_calibration(
    *,
    df_h: pd.DataFrame,
    y_pred: List[float],
    lat: float,
    capacity_kw: float,
    step_minutes: int,
    target_unit: str,
    tilt_deg: Optional[float],
    azimuth_deg: Optional[float],
) -> Tuple[List[float], CalibrationResponse]:
    raw_step_kwh = _target_values_to_step_kwh(
        np.asarray(y_pred, dtype=float),
        step_minutes=step_minutes,
        target_unit=target_unit,
    )
    eff_tilt = float(tilt_deg if tilt_deg is not None else _default_tilt_deg(lat))
    eff_azimuth = float(azimuth_deg if azimuth_deg is not None else 180.0)

    baseline_step_kwh = _physical_baseline_step_kwh(
        df_h=df_h,
        lat=lat,
        capacity_kw=float(capacity_kw),
        step_minutes=step_minutes,
        tilt_deg=eff_tilt,
        azimuth_deg=eff_azimuth,
    )

    raw_total_kwh = float(np.sum(raw_step_kwh))
    baseline_total_kwh = float(np.sum(baseline_step_kwh))
    notes: List[str] = []

    if baseline_total_kwh <= 1e-9:
        calibrated_step_kwh = np.zeros_like(raw_step_kwh)
        scale_factor = 0.0
        notes.append("baseline solar resource is effectively zero for this horizon")
    else:
        if raw_total_kwh > 1e-9:
            scale_factor = baseline_total_kwh / raw_total_kwh
            scaled_raw = raw_step_kwh * scale_factor
        else:
            scale_factor = 1.0
            scaled_raw = baseline_step_kwh.copy()
            notes.append("raw model total is near zero, baseline fallback used")

        calibrated_step_kwh = np.zeros_like(scaled_raw)
        dates = pd.to_datetime(df_h["timestamp"], errors="coerce").dt.date
        unique_dates = pd.Index(dates).dropna().unique()
        step_h = step_minutes / 60.0
        is_sun = np.nan_to_num(
            pd.to_numeric(df_h.get("isSun"), errors="coerce").to_numpy(dtype=float),
            nan=0.0,
        )

        for date_value in unique_dates:
            mask = (dates == date_value).to_numpy(dtype=bool)
            sr = scaled_raw[mask]
            bl = baseline_step_kwh[mask]
            sun_mask = is_sun[mask]
            sr_total = float(np.sum(sr))
            bl_total = float(np.sum(bl))

            if sr_total <= 1e-9 and bl_total <= 1e-9:
                continue
            if sr_total <= 1e-9:
                calibrated_step_kwh[mask] = bl
                continue
            if bl_total <= 1e-9:
                calibrated_step_kwh[mask] = sr
                continue

            raw_weights = sr / sr_total
            base_weights = bl / bl_total
            hybrid_weights = 0.74 * raw_weights + 0.26 * base_weights
            hybrid_weights = np.clip(hybrid_weights, 0.0, None)
            weight_sum = float(np.sum(hybrid_weights))
            if weight_sum <= 1e-9:
                hybrid_weights = base_weights
                weight_sum = float(np.sum(hybrid_weights))
            hybrid_weights = hybrid_weights / max(weight_sum, 1e-9)

            target_day_total = 0.58 * sr_total + 0.42 * bl_total
            day_values = target_day_total * hybrid_weights

            envelope = np.maximum(bl * 1.20, float(capacity_kw) * step_h * 0.015 * sun_mask)
            day_values = np.minimum(day_values, envelope)
            feasible_total = float(np.sum(envelope))
            target_day_total = min(target_day_total, feasible_total) if feasible_total > 1e-9 else target_day_total
            current_total = float(np.sum(day_values))
            if current_total > 1e-9 and target_day_total > 1e-9:
                day_values = day_values * (target_day_total / current_total)

            calibrated_step_kwh[mask] = np.clip(day_values, 0.0, None)

    calibrated_total_kwh = float(np.sum(calibrated_step_kwh))
    out_values = _step_kwh_to_target_values(
        calibrated_step_kwh,
        step_minutes=step_minutes,
        target_unit=target_unit,
    ).astype(float)

    meta = CalibrationResponse(
        enabled=True,
        method="capacity-aware-post-calibration",
        version="1.0",
        capacity_kw=float(capacity_kw),
        tilt_deg=eff_tilt,
        azimuth_deg=eff_azimuth,
        raw_model_total_kwh=raw_total_kwh,
        baseline_total_kwh=baseline_total_kwh,
        calibrated_total_kwh=calibrated_total_kwh,
        scale_factor=float(scale_factor),
        notes=notes,
    )
    return out_values.tolist(), meta


@app.get("/meteo", response_model=MeteoResponse)
async def meteo(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    hours: int = Query(48, ge=1, le=384, description="Forecast horizon in hours"),
    start_time: Optional[str] = Query(
        None,
        description="ISO datetime. If omitted -> now. Example: 2026-02-01T10:00:00 or with offset.",
    ),
    timezone: str = Query(DEFAULT_TIMEZONE, description="Open-Meteo timezone param: 'auto' or IANA name"),
    step_minutes: int = Query(60, ge=15, le=60, description="Output step size in minutes: 15/30/60"),
):
    if _http is None:
        raise HTTPException(status_code=503, detail="HTTP client not ready")
    if step_minutes not in (15, 30, 60):
        raise HTTPException(status_code=400, detail="step_minutes must be one of: 15, 30, 60")

    try:
        if start_time:
            st = datetime.fromisoformat(start_time)
        else:
            st = datetime.now(dt_timezone.utc)
        st = _ceil_to_step(st, step_minutes)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid start_time. Use ISO format.")

    end_dt = st + timedelta(hours=hours)

    try:
        df_all, tz_used = await _build_meteo_from_open_meteo(
            client=_http,
            lat=lat,
            lon=lon,
            start_dt=st,
            end_dt=end_dt,
            timezone=timezone,
            step_minutes=step_minutes,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Open-Meteo meteo build failed: {e}")

    df_all = df_all.sort_values("timestamp").reset_index(drop=True)
    ts_all = pd.to_datetime(df_all["timestamp"], errors="coerce", utc=True)
    if ts_all.isna().any():
        raise HTTPException(status_code=502, detail="Open-Meteo meteo timestamps are invalid")

    st_utc = _as_utc_timestamp(st)
    end_utc = _as_utc_timestamp(end_dt)
    mask_h = (ts_all >= st_utc) & (ts_all < end_utc)
    if int(mask_h.sum()) == 0:
        raise HTTPException(status_code=502, detail="No meteo rows returned for requested horizon")

    out = df_all.loc[mask_h.to_numpy()].reset_index(drop=True)

    times = [pd.to_datetime(t, utc=True).isoformat() for t in ts_all[mask_h].tolist()]

    def farr(col: str) -> List[float]:
        return np.nan_to_num(
            pd.to_numeric(out[col], errors="coerce").to_numpy(dtype=float),
            nan=0.0,
            posinf=0.0,
            neginf=0.0,
        ).tolist()

    wcode = np.nan_to_num(
        pd.to_numeric(out["weather_code"], errors="coerce").to_numpy(dtype=float),
        nan=0.0,
        posinf=0.0,
        neginf=0.0,
    )
    wcode = np.rint(wcode).astype(int).tolist()

    return MeteoResponse(
        n=int(len(times)),
        step_minutes=step_minutes,
        timezone=str(tz_used),
        source="open-meteo",
        hourly=MeteoHourlyPayload(
            time=times,
            temperature_2m=farr("temperature_2m"),
            relative_humidity_2m=farr("relative_humidity_2m"),
            pressure_msl=farr("pressure_msl"),
            wind_speed_10m=farr("wind_speed_10m"),
            precipitation=farr("precipitation"),
            cloud_cover=farr("cloud_cover"),
            shortwave_radiation=farr("shortwave_radiation"),
            weather_code=wcode,
        ),
    )


@app.get("/meteo/48h", response_model=MeteoResponse)
async def meteo_48h(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    start_time: Optional[str] = Query(None),
    timezone: str = Query(DEFAULT_TIMEZONE),
    step_minutes: int = Query(60, ge=15, le=60),
):
    return await meteo(
        lat=lat,
        lon=lon,
        hours=48,
        start_time=start_time,
        timezone=timezone,
        step_minutes=step_minutes,
    )


# =========================
# Open-Meteo Feature Builder
# =========================
def _specific_humidity_from_open_meteo(
    temp_c: np.ndarray,
    relative_humidity_pct: np.ndarray,
    pressure_hpa: np.ndarray,
) -> np.ndarray:
    temp = np.asarray(temp_c, dtype=float)
    rh = np.clip(np.asarray(relative_humidity_pct, dtype=float), 0.0, 100.0)
    pressure = np.clip(np.asarray(pressure_hpa, dtype=float), 300.0, 1100.0)

    saturation_vapor_pressure = 6.112 * np.exp((17.67 * temp) / np.maximum(temp + 243.5, 1e-6))
    vapor_pressure = np.clip(rh / 100.0 * saturation_vapor_pressure, 0.0, pressure * 0.95)
    q = 0.622 * vapor_pressure / np.maximum(pressure - 0.378 * vapor_pressure, 1e-6)
    return np.clip(np.nan_to_num(q, nan=0.0, posinf=0.0, neginf=0.0), 0.0, 0.04)


def _air_density_from_open_meteo(
    temp_c: np.ndarray,
    pressure_hpa: np.ndarray,
    specific_humidity: np.ndarray,
) -> np.ndarray:
    temp_k = np.asarray(temp_c, dtype=float) + 273.15
    pressure_pa = np.asarray(pressure_hpa, dtype=float) * 100.0
    q = np.clip(np.asarray(specific_humidity, dtype=float), 0.0, 0.04)
    virtual_temp_k = np.maximum(temp_k * (1.0 + 0.61 * q), 150.0)
    density = pressure_pa / (287.05 * virtual_temp_k)
    return np.clip(np.nan_to_num(density, nan=1.225, posinf=1.225, neginf=1.225), 0.8, 1.6)


def _toa_horizontal_irradiance(timestamp: pd.Series, lat: float) -> np.ndarray:
    ts = pd.to_datetime(timestamp, errors="coerce")
    day_of_year = ts.dt.dayofyear.fillna(1).to_numpy(dtype=float)
    hour_decimal = (
        ts.dt.hour.fillna(0).to_numpy(dtype=float)
        + ts.dt.minute.fillna(0).to_numpy(dtype=float) / 60.0
        + ts.dt.second.fillna(0).to_numpy(dtype=float) / 3600.0
    )

    lat_r = np.deg2rad(float(lat))
    decl = np.deg2rad(23.45) * np.sin(2.0 * np.pi * (284.0 + day_of_year) / 365.0)
    hour_angle = np.deg2rad(15.0 * (hour_decimal - 12.0))
    cos_zenith = (
        np.sin(lat_r) * np.sin(decl)
        + np.cos(lat_r) * np.cos(decl) * np.cos(hour_angle)
    )
    eccentricity = 1.0 + 0.033 * np.cos(2.0 * np.pi * day_of_year / 365.0)
    toa = 1367.0 * eccentricity * np.clip(cos_zenith, 0.0, None)
    return np.clip(np.nan_to_num(toa, nan=0.0, posinf=0.0, neginf=0.0), 0.0, 1400.0)


async def _build_features_from_open_meteo(
    client: httpx.AsyncClient,
    lat: float,
    lon: float,
    start_dt: datetime,
    end_dt: datetime,
    timezone: str,
    step_minutes: int,
    required_cols: List[str],
) -> Tuple[pd.DataFrame, str]:
    """
    Builds DataFrame with columns exactly required by model meta['num_cols'] plus 'timestamp'.
    Client (Flutter) sends: lat, lon, start_time. Everything else is fetched/derived here.
    """

    # --- Request: 15-min grid (preferred). If Open-Meteo ever omits minutely_15, we fallback to hourly. ---
    # Radiation: shortwave_radiation is the closest proxy to GHI.
    min15_vars = [
        "temperature_2m",
        "relative_humidity_2m",
        "pressure_msl",
        "wind_speed_10m",
        "precipitation",
        "rain",
        "snowfall",
        "cloud_cover",
        "shortwave_radiation",
        "weather_code",
    ]

    hourly_vars = [
        "temperature_2m",
        "relative_humidity_2m",
        "pressure_msl",
        "wind_speed_10m",
        "precipitation",
        "rain",
        "snowfall",
        "cloud_cover",
        "shortwave_radiation",
        "weather_code",
    ]

    daily_vars = [
        "sunrise",
        "sunset",
    ]

    # Provider dates are LOCAL calendar days. A UTC date can omit the last
    # hours of the horizon after local midnight (e.g. UTC+05:00).
    if timezone == "auto":
        start_date = (start_dt - timedelta(days=1)).date().isoformat()
        end_date = (end_dt + timedelta(days=1)).date().isoformat()
    else:
        try:
            start_date = _as_utc_timestamp(start_dt).tz_convert(timezone).date().isoformat()
            end_date = _as_utc_timestamp(end_dt).tz_convert(timezone).date().isoformat()
        except Exception as exc:
            raise HTTPException(status_code=422, detail="Invalid IANA timezone") from exc

    params = {
        "latitude": lat,
        "longitude": lon,
        "timezone": timezone,
        "wind_speed_unit": "ms",
        "start_date": start_date,
        "end_date": end_date,
        "daily": ",".join(daily_vars),
        "hourly": ",".join(hourly_vars),
    }

    if step_minutes != 60:
        params["minutely_15"] = ",".join(min15_vars)
    r = await client.get(OPEN_METEO_BASE_URL, params=params)
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Open-Meteo error {r.status_code}: {r.text[:500]}")

    js = r.json()
    tz_used = js.get("timezone", timezone)

    # ---- Daily sunrise/sunset map ----
    daily = js.get("daily") or {}
    sunrise = daily.get("sunrise", [])
    sunset = daily.get("sunset", [])
    dtime = daily.get("time", [])

    if not (len(dtime) == len(sunrise) == len(sunset)) or len(dtime) == 0:
        raise HTTPException(status_code=502, detail="Open-Meteo daily sunrise/sunset missing or invalid")

    daily_df = pd.DataFrame(
        {
            "date": pd.to_datetime(dtime, errors="coerce").date,
            "sunrise": pd.to_datetime(sunrise, errors="coerce"),
            "sunset": pd.to_datetime(sunset, errors="coerce"),
        }
    )
    if daily_df[["sunrise", "sunset"]].isna().any().any():
        raise HTTPException(status_code=502, detail="Open-Meteo daily sunrise/sunset contains invalid datetimes")

    daily_df["dayLength"] = (daily_df["sunset"] - daily_df["sunrise"]).dt.total_seconds() / 60.0  # minutes
    daily_df = daily_df.set_index("date")

    # ---- Build base time grid ----
    # Prefer minutely_15 if present, else use hourly and upsample.
    if js.get("minutely_15") and (js["minutely_15"].get("time") is not None):
        base = js["minutely_15"]
        t = pd.to_datetime(base.get("time", []), errors="coerce")
        t = t.dropna()
        if len(t) == 0:
            raise HTTPException(status_code=502, detail="Open-Meteo minutely_15 time is empty/invalid")

        df = pd.DataFrame({"timestamp": t}).reset_index(drop=True)

        def get_arr(name: str) -> np.ndarray:
            v = base.get(name)
            if v is None:
                return np.full(len(df), np.nan, dtype=float)
            arr = np.asarray(v, dtype=float)
            if arr.shape[0] != len(df):
                return np.full(len(df), np.nan, dtype=float)
            return arr

        # base series (always float arrays)
        df["_temp"] = get_arr("temperature_2m")
        df["_rh"] = get_arr("relative_humidity_2m")
        df["_p"] = get_arr("pressure_msl")
        df["_wind"] = get_arr("wind_speed_10m")
        df["_precip"] = get_arr("precipitation")
        df["_rain"] = get_arr("rain")
        df["_snow"] = get_arr("snowfall")
        df["_cloud"] = get_arr("cloud_cover")
        df["_sw_rad"] = get_arr("shortwave_radiation")
        df["_wcode"] = get_arr("weather_code")

        # If user requested 30/60 min step, resample deterministically:
        # - continuous vars: mean
        # - accumulations (precip/rain/snow): sum
        if step_minutes != 15:
            df = df.set_index("timestamp")

            cont_cols = ["_temp", "_rh", "_p", "_wind", "_cloud", "_sw_rad", "_wcode"]
            sum_cols = ["_precip", "_rain", "_snow"]

            df_cont = df[cont_cols].resample(f"{step_minutes}min").mean()
            df_sum = df[sum_cols].resample(f"{step_minutes}min").sum(min_count=1)

            df = pd.concat([df_cont, df_sum], axis=1).reset_index()

    else:
        # Fallback: hourly only -> upsample to requested step
        hourly = js.get("hourly") or {}
        if not hourly.get("time"):
            raise HTTPException(status_code=502, detail="Open-Meteo hourly missing")

        t = pd.to_datetime(hourly.get("time", []), errors="coerce")
        t = t.dropna()
        if len(t) == 0:
            raise HTTPException(status_code=502, detail="Open-Meteo hourly time is empty/invalid")

        df = pd.DataFrame({"timestamp": t}).reset_index(drop=True)

        def h(name: str) -> np.ndarray:
            v = hourly.get(name)
            if v is None:
                return np.full(len(df), np.nan, dtype=float)
            arr = np.asarray(v, dtype=float)
            if arr.shape[0] != len(df):
                return np.full(len(df), np.nan, dtype=float)
            return arr

        df["_temp"] = h("temperature_2m")
        df["_rh"] = h("relative_humidity_2m")
        df["_p"] = h("pressure_msl")
        df["_wind"] = h("wind_speed_10m")
        df["_precip"] = h("precipitation")
        df["_rain"] = h("rain")
        df["_snow"] = h("snowfall")
        df["_cloud"] = h("cloud_cover")
        df["_sw_rad"] = h("shortwave_radiation")
        df["_wcode"] = h("weather_code")

        df = df.set_index("timestamp").sort_index()

        # Upsample.
        # For continuous vars -> time interpolation; for accumulations -> distribute evenly per sub-step.
        steps_per_hour = int(round(60 / step_minutes))

        cont_cols = ["_temp", "_rh", "_p", "_wind", "_cloud", "_sw_rad", "_wcode"]
        sum_like_cols = ["_precip", "_rain", "_snow"]

        df_up = df[cont_cols].resample(f"{step_minutes}min").interpolate(method="time")

        df_acc = df[sum_like_cols].resample(f"{step_minutes}min").ffill()
        # distribute hourly totals across sub-steps (rough but stable)
        for c in sum_like_cols:
            df_acc[c] = df_acc[c] / float(max(1, steps_per_hour))

        df = pd.concat([df_up, df_acc], axis=1).reset_index()

    required_weather = ["_temp", "_rh", "_p", "_wind", "_sw_rad"]
    if not np.isfinite(df[required_weather].to_numpy(dtype=float)).all():
        raise HTTPException(status_code=502, detail="Open-Meteo hourly weather contains missing required values")

    # ---- Derive day features per timestamp ----
    ts = pd.to_datetime(df["timestamp"], errors="coerce")
    if ts.isna().any():
        raise HTTPException(status_code=502, detail="Open-Meteo timestamps contain invalid values after parsing")

    df["hour"] = ts.dt.hour.astype(int)
    df["month"] = ts.dt.month.astype(int)
    df["weekday"] = ts.dt.dayofweek.astype(int)
    df["dayofyear"] = ts.dt.dayofyear.astype(int)

    df["sin_hour"] = np.sin(2.0 * np.pi * df["hour"].to_numpy(dtype=float) / 24.0)
    df["cos_hour"] = np.cos(2.0 * np.pi * df["hour"].to_numpy(dtype=float) / 24.0)
    df["sin_year"] = np.sin(2.0 * np.pi * df["dayofyear"].to_numpy(dtype=float) / 365.0)
    df["cos_year"] = np.cos(2.0 * np.pi * df["dayofyear"].to_numpy(dtype=float) / 365.0)

    # join sunrise/sunset by date
    dkey = ts.dt.date
    df["_sunrise"] = [daily_df.loc[d, "sunrise"] if d in daily_df.index else pd.NaT for d in dkey]
    df["_sunset"] = [daily_df.loc[d, "sunset"] if d in daily_df.index else pd.NaT for d in dkey]
    df["dayLength"] = [daily_df.loc[d, "dayLength"] if d in daily_df.index else np.nan for d in dkey]

    # isSun
    sr = pd.to_datetime(df["_sunrise"], errors="coerce")
    ss = pd.to_datetime(df["_sunset"], errors="coerce")
    df["isSun"] = ((ts >= sr) & (ts <= ss)).astype(int)

    # sunlightTime (minutes since sunrise, clipped 0..dayLength)
    mins_since_sunrise = (ts - sr).dt.total_seconds() / 60.0
    dl = df["dayLength"].to_numpy(dtype=float)
    dl0 = np.nan_to_num(dl, nan=0.0)
    df["sunlightTime"] = np.clip(mins_since_sunrise.to_numpy(dtype=float), 0.0, dl0)

    # SunlightTime/daylength
    dl_safe = np.where(np.isfinite(dl) & (dl > 1e-6), dl, np.nan)
    df["SunlightTime/daylength"] = df["sunlightTime"].to_numpy(dtype=float) / dl_safe
    df["SunlightTime/daylength"] = np.nan_to_num(
        df["SunlightTime/daylength"].to_numpy(dtype=float),
        nan=0.0, posinf=0.0, neginf=0.0
    )

    # ---- Map Open-Meteo -> your dataset feature names ----
    df["temp"] = df["_temp"]
    df["pressure"] = df["_p"]
    df["humidity"] = df["_rh"]
    df["wind_speed"] = df["_wind"]
    df["clouds_all"] = df["_cloud"]

    # Radiation proxy for GHI
    df["GHI"] = df["_sw_rad"]

    # ---- Map Open-Meteo -> experiments renewable-hybrid feature names ----
    specific_humidity = _specific_humidity_from_open_meteo(
        temp_c=df["_temp"].to_numpy(dtype=float),
        relative_humidity_pct=df["_rh"].to_numpy(dtype=float),
        pressure_hpa=df["_p"].to_numpy(dtype=float),
    )
    df["temperature_solar"] = df["_temp"]
    df["specific_humidity_solar"] = specific_humidity
    df["humidity_solar"] = specific_humidity
    df["relative_humidity_solar"] = np.clip(
        np.nan_to_num(df["_rh"].to_numpy(dtype=float) / 100.0, nan=0.0),
        0.0,
        2.0,
    )
    df["surface_irradiance_solar"] = np.clip(
        np.nan_to_num(df["_sw_rad"].to_numpy(dtype=float), nan=0.0),
        0.0,
        None,
    )
    df["toa_irradiance_solar"] = _toa_horizontal_irradiance(df["timestamp"], lat=lat)
    df["air_density_wind"] = _air_density_from_open_meteo(
        temp_c=df["_temp"].to_numpy(dtype=float),
        pressure_hpa=df["_p"].to_numpy(dtype=float),
        specific_humidity=specific_humidity,
    )
    df["wind_speed_wind"] = np.clip(
        np.nan_to_num(df["_wind"].to_numpy(dtype=float), nan=0.0),
        0.0,
        None,
    )

    # rain_1h, snow_1h:
    # rolling sum over last 60 minutes (steps_per_hour depends on step)
    steps_per_hour = int(round(60 / step_minutes))

    rain_base = df["_rain"].copy()
    if pd.Series(rain_base).isna().all():
        rain_base = df["_precip"].copy()

    df["rain_1h"] = (
        pd.Series(rain_base, dtype="float64")
        .rolling(window=steps_per_hour, min_periods=1)
        .sum()
        .to_numpy(dtype=float)
    )

    snow_base = df["_snow"].copy()
    if pd.Series(snow_base).isna().all():
        snow_base = 0.0

    # Open-Meteo snowfall commonly in cm; convert to mm (rough) -> *10
    df["snow_1h"] = (
        pd.Series(snow_base, dtype="float64")
        .rolling(window=steps_per_hour, min_periods=1)
        .sum()
        .to_numpy(dtype=float)
        * 10.0
    )

    # weather_type: map WMO weather_code -> your 1..5 buckets
    df["weather_type"] = pd.Series(df["_wcode"]).apply(_map_wmo_to_weather_type).astype(int)

    # ---- Keep only model-required columns + timestamp ----
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise HTTPException(status_code=500, detail=f"Server cannot build required features: {missing}")

    support_cols = [
        "GHI",
        "temp",
        "wind_speed",
        "snow_1h",
        "isSun",
    ]
    keep_cols = ["timestamp"] + required_cols + [c for c in support_cols if c in df.columns and c not in required_cols]
    out = df[keep_cols].copy()

    # Ensure numeric types for model features
    for c in required_cols:
        out[c] = pd.to_numeric(out[c], errors="coerce")

    out.replace([np.inf, -np.inf], np.nan, inplace=True)

    # Prefer median fill (more stable than hard 0 for pressure/temp/etc.), fallback to 0.
    med = out[required_cols].median(numeric_only=True)
    out[required_cols] = out[required_cols].fillna(med).fillna(0.0)

    # Open-Meteo time strings are local wall clock; attach the returned timezone
    # before comparing to request UTC instants. Preserve local hours for features.
    localized = pd.to_datetime(out["timestamp"], errors="raise").dt.tz_localize(tz_used, ambiguous="raise", nonexistent="raise")
    out["timestamp"] = localized

    return out, tz_used


async def _build_meteo_from_open_meteo(
    client: httpx.AsyncClient,
    lat: float,
    lon: float,
    start_dt: datetime,
    end_dt: datetime,
    timezone: str,
    step_minutes: int,
) -> Tuple[pd.DataFrame, str]:
    """
    Build meteo table from Open-Meteo with deterministic 15/30/60-minute output.
    """
    vars_all = [
        "temperature_2m",
        "relative_humidity_2m",
        "pressure_msl",
        "wind_speed_10m",
        "precipitation",
        "cloud_cover",
        "shortwave_radiation",
        "weather_code",
    ]
    cont_cols = [
        "temperature_2m",
        "relative_humidity_2m",
        "pressure_msl",
        "wind_speed_10m",
        "cloud_cover",
        "shortwave_radiation",
    ]
    sum_cols = ["precipitation"]

    start_date = start_dt.date().isoformat()
    end_date = end_dt.date().isoformat()

    params = {
        "latitude": lat,
        "longitude": lon,
        "timezone": timezone,
        "wind_speed_unit": "ms",
        "start_date": start_date,
        "end_date": end_date,
        "hourly": ",".join(vars_all),
        "minutely_15": ",".join(vars_all),
    }

    r = await client.get(OPEN_METEO_BASE_URL, params=params)
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Open-Meteo error {r.status_code}: {r.text[:500]}")

    js = r.json()
    tz_used = js.get("timezone", timezone)

    def _from_block(block: Dict[str, Any]) -> pd.DataFrame:
        t = pd.to_datetime(block.get("time", []), errors="coerce")
        t = t.dropna()
        if len(t) == 0:
            raise HTTPException(status_code=502, detail="Open-Meteo meteo time axis is empty/invalid")

        df_local = pd.DataFrame({"timestamp": t}).reset_index(drop=True)

        def _arr(name: str) -> np.ndarray:
            v = block.get(name)
            if v is None:
                return np.full(len(df_local), np.nan, dtype=float)
            arr = np.asarray(v, dtype=float)
            if arr.shape[0] != len(df_local):
                return np.full(len(df_local), np.nan, dtype=float)
            return arr

        for c in vars_all:
            df_local[c] = _arr(c)
        return df_local

    m15 = js.get("minutely_15") or {}
    h1 = js.get("hourly") or {}

    has_m15 = isinstance(m15.get("time"), list) and len(m15.get("time", [])) > 0
    has_h1 = isinstance(h1.get("time"), list) and len(h1.get("time", [])) > 0

    if has_m15:
        df = _from_block(m15)
        if step_minutes != 15:
            df = df.set_index("timestamp").sort_index()
            df_cont = df[cont_cols].resample(f"{step_minutes}min").mean()
            df_sum = df[sum_cols].resample(f"{step_minutes}min").sum(min_count=1)
            df_code = df[["weather_code"]].resample(f"{step_minutes}min").last()
            df = pd.concat([df_cont, df_sum, df_code], axis=1).reset_index()
    elif has_h1:
        df = _from_block(h1)
        if step_minutes != 60:
            df = df.set_index("timestamp").sort_index()
            steps_per_hour = int(round(60 / step_minutes))

            df_cont = df[cont_cols].resample(f"{step_minutes}min").interpolate(method="time")
            df_sum = df[sum_cols].resample(f"{step_minutes}min").ffill()
            for c in sum_cols:
                df_sum[c] = df_sum[c] / float(max(1, steps_per_hour))
            df_code = df[["weather_code"]].resample(f"{step_minutes}min").ffill()
            df = pd.concat([df_cont, df_sum, df_code], axis=1).reset_index()
    else:
        raise HTTPException(status_code=502, detail="Open-Meteo meteo payload missing minutely_15 and hourly")

    for c in vars_all:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    df.replace([np.inf, -np.inf], np.nan, inplace=True)
    med = df[vars_all].median(numeric_only=True)
    df[vars_all] = df[vars_all].fillna(med).fillna(0.0)
    df["weather_code"] = np.rint(df["weather_code"].to_numpy(dtype=float)).astype(int)
    df["timestamp"] = [ts.to_pydatetime() for ts in pd.to_datetime(df["timestamp"], errors="coerce")]

    return df, tz_used


def _map_wmo_to_weather_type(wmo_code: Any) -> int:
    """
    Your dataset uses weather_type 1..5.
    We bucket Open-Meteo WMO codes into 5 coarse classes:

    1 = clear/mostly clear
    2 = partly cloudy
    3 = cloudy/fog
    4 = rain/drizzle
    5 = snow/thunder/heavy
    """
    try:
        c = int(float(wmo_code))
    except Exception:
        return 3

    if c == 0:
        return 1  # clear
    if c in (1, 2):
        return 2  # mainly clear / partly cloudy
    if c == 3:
        return 3  # overcast
    if 45 <= c <= 48:
        return 3  # fog
    if 51 <= c <= 67 or 80 <= c <= 82:
        return 4  # drizzle/rain/showers
    if 71 <= c <= 77 or 85 <= c <= 86:
        return 5  # snow
    if 95 <= c <= 99:
        return 5  # thunderstorm
    return 3

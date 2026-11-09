"""DP-STH++/DualAxis weather-v1 serving, separate from original research routes."""
from __future__ import annotations
import hashlib, json, threading
from pathlib import Path
import numpy as np
import pandas as pd
import torch
from app.weather_features import BASE_COLUMNS, FEATURE_COLUMNS, weather_matrix, hourly_windows
from app.weather_architectures import build_dp_weather, build_dualaxis_weather


class WeatherModelRuntime:
    def __init__(self, model_dir):
        self.path=Path(model_dir); self.model=None; self.qc=None
        self._lock=threading.RLock()

    def load(self):
        manifest_bytes=(self.path/'manifest.json').read_bytes()
        if hashlib.sha256(manifest_bytes).hexdigest() != 'a63dee20fdd23fcc7fe61cc00a9b2757ad7f0dd42367034adfffbe1d65c261ac':
            raise ValueError('Weather manifest checksum mismatch')
        manifest=json.loads(manifest_bytes)
        for name,digest in manifest['files'].items():
            if hashlib.sha256((self.path/name).read_bytes()).hexdigest()!=digest:
                raise ValueError(f'Weather artifact checksum mismatch: {name}')
        for name,digest in manifest['code_sha256'].items():
            if hashlib.sha256((Path(__file__).parent/name).read_bytes()).hexdigest()!=digest:
                raise ValueError(f'Weather inference/training source mismatch: {name}')
        self.manifest=manifest
        self.prep=json.loads((self.path/'preprocessing.json').read_text())
        self.qc_cal=json.loads((self.path/'qc_calibration.json').read_text())
        if self.prep['feature_columns']!=FEATURE_COLUMNS:
            raise ValueError('Weather feature order mismatch')
        import tensorflow as tf
        self.tf=tf
        with tf.device('/CPU:0'):
            self.model=build_dp_weather(tf)
            self.model.load_weights(self.path/'dp_weather.weights.h5')
            self.model.trainable=False
        self.qc=build_dualaxis_weather()
        self.qc.load_state_dict(torch.load(self.path/'dualaxis_weather.pt',map_location='cpu',weights_only=True))
        self.qc.eval()
        self._infer=tf.function(lambda seq,flat,refs:self.model([seq,flat,refs],training=False),
                                input_signature=[tf.TensorSpec([None,24,12],tf.float32),
                                                 tf.TensorSpec([None,12],tf.float32),tf.TensorSpec([None,2],tf.float32)])
        with tf.device('/CPU:0'):
            self._infer(np.zeros((1,24,12),np.float32),np.zeros((1,12),np.float32),np.zeros((1,2),np.float32))
        return self

    @property
    def is_loaded(self): return self.model is not None and self.qc is not None
    @property
    def model_name(self): return 'DP-STH++'
    @property
    def model_version(self): return 'weather-v1-20261029'
    @property
    def n_timesteps(self): return 24
    @property
    def num_cols(self): return list(BASE_COLUMNS)
    @property
    def x_input_mode(self): return 'open_meteo_weather_only_24h'
    @property
    def y_transform(self): return 'fit_reference_normalization_then_physical_site_adapter'
    @property
    def winsor_limits(self): return (0.,0.)
    @property
    def target_name(self): return 'Solar generation estimate'
    @property
    def wind_target_name(self): return 'Wind generation estimate'
    @property
    def target_unit(self): return 'Wh_per_step'
    @property
    def wind_target_unit(self): return 'Wh_per_step'

    def meta(self):
        return dict(model_name=self.model_name,model_version=self.model_version,
                    quality_model='DualAxis',quality_model_version=self.model_version,
                    engineered_feature_count=len(FEATURE_COLUMNS),features=FEATURE_COLUMNS,
                    solar_extreme_threshold=self.prep['extreme_thresholds'][0],
                    wind_extreme_threshold=self.prep['extreme_thresholds'][1],
                    raw_prediction_unit='reference_normalized_source_generation',
                    forecast_strategy='direct weather-conditioned rolling 24h windows; no generation recursion',
                    generation_history_required=False,quality_policy='advisory weather reconstruction diagnostic',
                    original_article_weights=False,
                    training_manifest=self.manifest,
                    operational_horizon_accuracy_validated=False,
                    energy_basis='physical site estimate adjusted by neural weather response; not site-calibrated measurement')

    def predict_weather(self, frame):
        with self._lock:
            if not self.is_loaded: raise RuntimeError('Weather models not loaded')
            matrix,refs=weather_matrix(frame,self.prep['reference_coefficients'])
            scaled=((matrix-np.asarray(self.prep['mean']))/np.asarray(self.prep['scale'])).astype(np.float32)
            windows=hourly_windows(scaled);refs=refs[23:]
            outputs=[[] for _ in range(4)]
            with self.tf.device('/CPU:0'):
                for start in range(0,len(windows),64):
                    batch=windows[start:start+64]
                    pred=self._infer(batch,batch[:,-1],refs[start:start+64])
                    for dest,value in zip(outputs,pred):dest.extend(value.numpy().ravel().tolist())
            generation=np.column_stack(outputs[:2]);scores=np.column_stack(outputs[2:])
            if not np.isfinite(generation).all() or not np.isfinite(scores).all():
                raise RuntimeError('Nonfinite weather-model outputs')
            if (generation<0).any() or ((scores<0)|(scores>1)).any():
                raise RuntimeError('Invalid weather-model outputs')
            # One diagnostic per 24-hour block plus the final available window.
            ids=np.unique(np.r_[np.arange(0,len(windows),24),len(windows)-1]).astype(int)
            qc=self.score_windows(windows[ids])
            return dict(times=frame.timestamp.iloc[23:].tolist(),normalized=generation,
                        reference=refs,extreme_scores=scores,
                        quality=dict(model_name='DualAxis',model_version=self.model_version,
                                     source_kind='weather_forecast_windows',score_is_probability=False,
                                     threshold=self.qc_cal['threshold'],n_windows=len(ids),
                                     times=[str(frame.timestamp.iloc[23+i]) for i in ids],
                                     scores=qc.tolist(),flagged_windows=int(np.sum(qc>self.qc_cal['threshold'])),
                                     status='attention' if (qc>self.qc_cal['threshold']).any() else 'within_reference',
                                     scope='Reconstruction discrepancy relative to source weather; not forecast truth or fault detection'))

    def score_windows(self, windows):
        scores=[]
        with torch.no_grad():
            for start in range(0,len(windows),16):
                x=torch.tensor(windows[start:start+16],dtype=torch.float32)
                rng=torch.Generator().manual_seed(1729);errors=[]
                for _ in range(3):
                    mask=(torch.rand((1,24,12),generator=rng)<.30).expand_as(x)
                    out=self.qc(x.masked_fill(mask,0))
                    errors.append((((out-x)**2)*mask).sum((1,2))/mask.sum((1,2)))
                scores.extend(torch.stack(errors).mean(0).sqrt().numpy().tolist())
        return np.asarray(scores)


def site_energy_adapter(predicted, reference, physical_kwh, capacity_kw):
    """Explicit bounded correction, never a claim about the source plant units.

    P / R compares the neural weather response with the fit-only weather
    reference in the SAME dimensionless scale. Physical site energy provides
    kWh; a 0.25..2 correction bound is an engineering guard, not a confidence
    interval. Near-zero reference receives no inferred correction.
    """
    predicted=np.asarray(predicted);reference=np.asarray(reference)
    correction=np.divide(predicted,reference,out=np.ones_like(predicted),where=reference>.01)
    correction=np.clip(correction,.25,2.)
    return np.clip(np.asarray(physical_kwh)*correction,0,float(capacity_kw)),correction

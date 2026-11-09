"""Reproducible weather-variant experiment. Run stages from the notebook."""
from pathlib import Path
import copy, hashlib, json, os, sys, time
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
os.environ.setdefault("TF_NUM_INTRAOP_THREADS", "4")
os.environ.setdefault("TF_NUM_INTEROP_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "4")
ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "smart-city-renewable-energy-server"
sys.path.insert(0, str(SERVER))
import numpy as np
import pandas as pd
from app.weather_features import BASE_COLUMNS, FEATURE_COLUMNS, TARGET_COLUMNS, weather_matrix, hourly_windows
from app.weather_architectures import build_dp_weather, build_dualaxis_weather

HERE = Path(__file__).resolve().parent
OUT = HERE / "outputs"
OUT.mkdir(exist_ok=True)
SOURCE = ROOT / 'data' / 'renewables_combined_FULL.csv'
DATA_HASH = '2771dd8b57aa43bc79944a9e8b2eb72d1214674056e601b997038fea164f1204'


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def prepare():
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == DATA_HASH
    frame = pd.read_csv(SOURCE)
    frame['timestamp'] = pd.to_datetime(frame['timestamp'])
    frame = frame.sort_values('timestamp', kind='stable').drop_duplicates('timestamp', keep='first').reset_index(drop=True)
    assert (frame.timestamp.diff().iloc[1:] == pd.Timedelta(hours=1)).all()
    n = len(frame); boundaries = [int(n*p) for p in (.60, .75, .80)]
    y = frame[TARGET_COLUMNS].to_numpy(np.float32)
    assert np.isfinite(y).all() and (y >= 0).all()
    scale = np.quantile(y[:boundaries[0]], .99, axis=0)
    _, refs = weather_matrix(frame)
    coefficients = np.sum(refs[:boundaries[0]] * (y[:boundaries[0]]/scale), axis=0) / np.maximum(np.sum(refs[:boundaries[0]]**2,axis=0), 1e-9)
    x, refs = weather_matrix(frame, coefficients)
    mean = x[:boundaries[0]].mean(0); std = x[:boundaries[0]].std(0)
    std = np.where(std > 1e-6, std, 1.0)
    windows = hourly_windows((x-mean)/std)
    ids = np.arange(23, n)
    splits = {'fit': ids < boundaries[0],
              'validation': (ids >= boundaries[0]+23) & (ids < boundaries[1]),
              'calibration': (ids >= boundaries[1]+23) & (ids < boundaries[2]),
              'holdout': ids >= boundaries[2]+23}
    thresholds = np.quantile(y[:boundaries[0]], .90, axis=0)
    prep = dict(feature_columns=FEATURE_COLUMNS, base_columns=BASE_COLUMNS,
                mean=mean.tolist(), scale=std.tolist(), target_reference=scale.tolist(),
                reference_coefficients=coefficients.tolist(), extreme_thresholds=thresholds.tolist(),
                lookback=24, alignment='window ending at target weather hour',
                source_target_units='unverified source units; not kWh',
                excluded_features=['generation history', 'ambiguous source humidity'])
    protocol = dict(seed=42, source_sha256=DATA_HASH, source_rows=n,
                    split_boundaries=boundaries, split_counts={k:int(v.sum()) for k,v in splits.items()},
                    split_gap_hours=23, fit_scope='first 60 percent of chronological rows only',
                    checkpoint_selection='validation only', qc_threshold_scope='separate calibration block',
                    holdout_status='retrospective same source, previously explored by original research',
                    dp_epochs_max=35, qc_epochs_max=16,
                    promotion_gate='finite nonnegative outputs and positive holdout R2 for both generation targets',
                    forecast_validation='weather-conditional reconstruction of 168/336-hour blocks; no archived forecast weather available',
                    limitations=['Source units/capacity/location/timezone not established',
                                 'No measured new-site energy calibration',
                                 'Weather forecasts have additional lead-time error absent from retrospective conditional metrics'])
    save('preprocessing.json',prep); save('protocol_before_training.json',protocol)
    pd.DataFrame({'timestamp':frame.timestamp.iloc[ids].values,
                  'split':np.select(list(splits.values()),list(splits),default='purge')}).to_csv(OUT/'split_manifest.csv',index=False)
    print(json.dumps(protocol,indent=2))
    return dict(frame=frame, x=windows.astype(np.float32), refs=refs[ids], y=(y[ids]/scale).astype(np.float32),
                raw_y=y[ids], labels=(y[ids]>=thresholds).astype(np.float32), ids=ids,
                splits=splits, preprocessing=prep)


def train_dp(data):
    import tensorflow as tf
    tf.config.set_visible_devices([], 'GPU')
    tf.keras.utils.set_random_seed(42)
    tf.config.experimental.enable_op_determinism()
    model = build_dp_weather(tf)
    model.compile(optimizer=tf.keras.optimizers.Adam(6e-4, clipnorm=1.0),
                  loss=['mse','mse','binary_crossentropy','binary_crossentropy'],
                  loss_weights=[1.,1.,.10,.10])
    def inputs(mask): return [data['x'][mask],data['x'][mask,-1],data['refs'][mask]]
    def targets(mask): return [data['y'][mask,j:j+1] for j in range(2)] + [data['labels'][mask,j:j+1] for j in range(2)]
    class Progress(tf.keras.callbacks.Callback):
        def on_epoch_end(self, epoch, logs=None):
            save('progress.json',dict(stage='DP-STH++ weather training',epoch=epoch+1,logs={k:float(v) for k,v in (logs or {}).items()}))
    start=time.monotonic()
    history=model.fit(inputs(data['splits']['fit']),targets(data['splits']['fit']),
                      validation_data=(inputs(data['splits']['validation']),targets(data['splits']['validation'])),
                      batch_size=128,epochs=35,shuffle=False,verbose=2,
                      callbacks=[tf.keras.callbacks.EarlyStopping(monitor='val_loss',patience=7,restore_best_weights=True),
                                 tf.keras.callbacks.CSVLogger(str(OUT/'dp_history.csv')),Progress()])
    model.save_weights(OUT/'dp_weather.weights.h5')
    result=dict(seconds=time.monotonic()-start,epochs=len(history.history['loss']),
                best_epoch=int(np.argmin(history.history['val_loss']))+1,parameter_count=model.count_params(),
                tensorflow=tf.__version__,keras=tf.keras.__version__,device='CPU')
    save('dp_training.json',result);print(result)
    return model


def qc_scores(model, windows, repeats=3):
    import torch
    model.eval(); scores=[]
    with torch.no_grad():
        for start in range(0,len(windows),16):
            x=torch.tensor(windows[start:start+16],dtype=torch.float32)
            rng=torch.Generator().manual_seed(1729)
            errors=[]
            for _ in range(repeats):
                # Same mask pattern for each window: batch/chunk-independent score.
                mask=(torch.rand((1,24,12),generator=rng)<.30).expand_as(x)
                out=model(x.masked_fill(mask,0))
                errors.append((((out-x)**2)*mask).sum((1,2))/mask.sum((1,2)))
            scores.extend(torch.stack(errors).mean(0).sqrt().numpy().tolist())
    return np.asarray(scores)


def train_qc(data):
    import torch
    torch.set_num_threads(4);torch.manual_seed(42)
    model=build_dualaxis_weather()
    opt=torch.optim.AdamW(model.parameters(),lr=3e-4,weight_decay=1e-4)
    # Non-overlapping/subsampled windows reduce nearly duplicate examples.
    fit=data['x'][data['splits']['fit']][::6]
    valid=data['x'][data['splits']['validation']][::24]
    best=float('inf'); best_state=None; stale=0; rows=[]; start=time.monotonic()
    for epoch in range(16):
        model.train(); losses=[]
        for offset in range(0,len(fit),24):
            x=torch.tensor(fit[offset:offset+24]);mask=torch.rand_like(x)<.30
            out=model(x.masked_fill(mask,0));loss=((out-x)[mask]**2).mean()
            opt.zero_grad();loss.backward();torch.nn.utils.clip_grad_norm_(model.parameters(),1.);opt.step()
            losses.append(float(loss.detach()))
        validation=float(np.mean(qc_scores(model,valid)**2))
        rows.append(dict(epoch=epoch+1,train_mse=float(np.mean(losses)),validation_mse=validation))
        pd.DataFrame(rows).to_csv(OUT/'qc_history.csv',index=False)
        save('progress.json',dict(stage='DualAxis weather training',**rows[-1]));print(rows[-1],flush=True)
        if validation < best:
            best=validation;best_state=copy.deepcopy(model.state_dict());stale=0
        else: stale+=1
        if stale>=5: break
    model.load_state_dict(best_state);torch.save(model.state_dict(),OUT/'dualaxis_weather.pt')
    calibration=qc_scores(model,data['x'][data['splits']['calibration']][::24])
    threshold=float(np.quantile(calibration,.99))
    save('qc_calibration.json',dict(threshold=threshold,quantile=.99,n=int(len(calibration)),
                                  mask_rate=.30,repeats=3,seed=1729,score='masked normalized RMSE',
                                  calibration_scores=calibration.tolist(),threshold_scope='disjoint calibration block',
                                  is_fault_probability=False))
    save('qc_training.json',dict(seconds=time.monotonic()-start,epochs=len(rows),best_epoch=int(np.argmin([x['validation_mse'] for x in rows]))+1,
                                 parameter_count=sum(p.numel() for p in model.parameters()),torch=torch.__version__,device='CPU',fit_windows=len(fit)))
    return model


def evaluate(data, dp, qc):
    from sklearn.metrics import mean_absolute_error,mean_squared_error,r2_score,roc_auc_score,brier_score_loss
    mask=data['splits']['holdout']; x=data['x'][mask]; refs=data['refs'][mask]
    pred=dp.predict([x,x[:,-1],refs],batch_size=128,verbose=0)
    scale=np.asarray(data['preprocessing']['target_reference'])
    normalized=np.column_stack([pred[0].ravel(),pred[1].ravel()]); raw=normalized*scale
    truth=data['raw_y'][mask];prob=np.column_stack([pred[2].ravel(),pred[3].ravel()])
    assert np.isfinite(raw).all() and (raw>=0).all()
    def metrics(a,b):return dict(MAE=float(mean_absolute_error(a,b)),RMSE=float(np.sqrt(mean_squared_error(a,b))),R2=float(r2_score(a,b)))
    rows=[]
    for j,target in enumerate(TARGET_COLUMNS):
        rows.append(dict(target=target,model='DP-STH++ weather-v1',**metrics(truth[:,j],raw[:,j])))
        rows.append(dict(target=target,model='weather reference',**metrics(truth[:,j],refs[:,j]*scale[j])))
    pd.DataFrame(rows).to_csv(OUT/'holdout_hourly_metrics.csv',index=False)
    horizon_rows=[]
    for horizon in (168,336):
        # Non-overlapping complete origins; hourly truth is never fed to the network.
        for offset in range(0,len(truth)-horizon+1,horizon):
            for j,target in enumerate(TARGET_COLUMNS):
                a=truth[offset:offset+horizon,j].reshape(-1,24).sum(1)
                b=raw[offset:offset+horizon,j].reshape(-1,24).sum(1)
                horizon_rows.append(dict(horizon_hours=horizon,origin_offset=offset,target=target,
                                         metric_unit='sum of source units per 24 hours',**metrics(a,b)))
    pd.DataFrame(horizon_rows).to_csv(OUT/'conditional_horizon_metrics.csv',index=False)
    dates=data['frame'].timestamp.iloc[data['ids'][mask]].astype(str).to_numpy()
    table=pd.DataFrame(dict(timestamp=dates,solar_actual=truth[:,0],solar_predicted=raw[:,0],
                            wind_actual=truth[:,1],wind_predicted=raw[:,1]))
    table.to_csv(OUT/'holdout_predictions.csv',index=False)
    threshold=json.loads((OUT/'qc_calibration.json').read_text())['threshold']
    score=qc_scores(qc,x[::24]); corrupted=x[::24].copy();corrupted[:,12,0]+=6
    corrupt_score=qc_scores(qc,corrupted)
    save('qc_evaluation.json',dict(n=len(score),threshold=threshold,unmodified_exceedance_fraction=float(np.mean(score>threshold)),
                                   artificial_temperature_spike_exceedance_fraction=float(np.mean(corrupt_score>threshold)),
                                   median_clean_score=float(np.median(score)),median_spike_score=float(np.median(corrupt_score)),
                                   limitation='Artificial perturbation only; no labelled real faults or forecast-error calibration'))
    # Serialization parity uses newly constructed models, not in-memory copies.
    import tensorflow as tf,torch
    dp_reload=build_dp_weather(tf);dp_reload.load_weights(OUT/'dp_weather.weights.h5')
    check=dp_reload([x[:3],x[:3,-1],refs[:3]],training=False)
    for a,b in zip(check,pred):np.testing.assert_allclose(a.numpy(),b[:3],rtol=1e-5,atol=1e-5)
    qc_reload=build_dualaxis_weather();qc_reload.load_state_dict(torch.load(OUT/'dualaxis_weather.pt',map_location='cpu',weights_only=True))
    np.testing.assert_allclose(qc_scores(qc_reload,x[:3]),qc_scores(qc,x[:3]),rtol=1e-6,atol=1e-6)
    gate=all(row['R2']>0 for row in rows if row['model'].startswith('DP'))
    save('evaluation.json',dict(hourly_metrics=rows,conditional_horizon_blocks=horizon_rows,
                               serialization_parity=True,promotion_gate_passed=gate,
                               quality_model='DualAxis / weather-v1',
                               actual_forecast_7_14_day_accuracy_validated=False))
    print(pd.DataFrame(rows).to_string(index=False));print('Promotion gate:',gate)
    return gate


def export(data):
    evaluation=json.loads((OUT/'evaluation.json').read_text())
    if not evaluation['promotion_gate_passed']:raise RuntimeError('Model did not pass the prespecified promotion gate')
    import shutil,datetime
    dest=SERVER/'models/weather_v1';dest.mkdir(exist_ok=True)
    names=['dp_weather.weights.h5','dualaxis_weather.pt','preprocessing.json','protocol_before_training.json',
           'dp_training.json','qc_training.json','qc_calibration.json','evaluation.json','qc_evaluation.json']
    for name in names:shutil.copy2(OUT/name,dest/name)
    manifest=dict(model_name='DP-STH++',model_version='weather-v1-20261029',quality_model='DualAxis',quality_version='weather-v1-20261029',
                  source_dataset_sha256=DATA_HASH,created_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  architecture_changes=['Weather-only 24-hour windows ending at target hour',
                                        'Weather reference residual heads replace measured generation skip connections',
                                        'DualAxis temporal then feature attention with 12 weather features',
                                        'Fixed multi-task MSE/BCE weights; no original uncertainty loss-scale layer'],
                  preserved_architecture=['LSTM','GRU','causal dilated Conv1D','causal Transformer','context gating','residual regression and extreme heads'],
                  source_urls=['https://data.mendeley.com/datasets/gxc6j5btrx/1','https://open-meteo.com/en/docs'],
                  files={name:hashlib.sha256((dest/name).read_bytes()).hexdigest() for name in names},
                  code_sha256={name:hashlib.sha256((SERVER/'app'/name).read_bytes()).hexdigest() for name in ['weather_features.py','weather_architectures.py']})
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    save('completion.json',dict(status='trained_evaluated_exported',export_directory=str(dest),manifest_sha256=hashlib.sha256((dest/'manifest.json').read_bytes()).hexdigest()))
    print('Exported verified artifacts:',dest)

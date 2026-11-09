"""Real weather weights: parity, input contract, hour alignment and site-energy invariants."""
import asyncio
import json
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from fastapi.testclient import TestClient
from app import main
from app.weather_runtime import WeatherModelRuntime, site_energy_adapter
from app.weather_features import BASE_COLUMNS

ROOT = Path(__file__).resolve().parents[1]

class WeatherModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = WeatherModelRuntime(ROOT/'models/weather_v1').load()
        case=json.loads((ROOT/'tests/fixtures/ssl_qc_golden.json').read_text())['cases'][0]
        cls.frame=pd.DataFrame(case['records'])
        cls.frame['timestamp']=pd.date_range('2026-10-29',periods=24,freq='h',tz='Asia/Almaty')

    def test_weather_needs_no_generation_and_is_repeatable(self):
        frame=self.frame[['timestamp']+BASE_COLUMNS]
        a=self.runtime.predict_weather(frame); b=self.runtime.predict_weather(frame)
        np.testing.assert_array_equal(a['normalized'],b['normalized'])
        self.assertEqual(a['normalized'].shape,(1,2))
        self.assertEqual(a['quality'],b['quality'])
        self.assertEqual(a['quality']['model_name'],'DualAxis')
        self.assertFalse(a['quality']['score_is_probability'])
        changed=frame.copy(); changed['surface_irradiance_solar']*=.5
        c=self.runtime.predict_weather(changed)
        self.assertGreater(np.max(np.abs(a['normalized']-c['normalized'])),1e-6)

    def test_rejects_gaps_and_missing_weather(self):
        broken=self.frame.copy();broken.loc[12,'timestamp']=broken.loc[11,'timestamp']
        with self.assertRaises(ValueError):self.runtime.predict_weather(broken)
        broken=self.frame.copy();broken.loc[12,BASE_COLUMNS[0]]=np.nan
        with self.assertRaises(ValueError):self.runtime.predict_weather(broken)

    def test_energy_adapter_is_bounded_and_uses_neural_output(self):
        base=np.array([0.,2.,10.]);ref=np.array([0.,1.,1.])
        energy,_=site_energy_adapter(np.array([10.,1.5,10.]),ref,base,12.)
        np.testing.assert_allclose(energy,[0.,3.,12.])
        zero,_=site_energy_adapter(np.array([1.,1.,1.]),ref,base,0.)
        np.testing.assert_array_equal(zero,0)

    def test_provider_date_bounds_follow_local_timezone(self):
        from datetime import datetime
        from types import SimpleNamespace
        from fastapi import HTTPException
        class Client:
            async def get(self, url, params):
                self.params=params
                return SimpleNamespace(status_code=500,text="stop after recording request")
        for zone,start,end,expected_start,expected_end in [
            ('Asia/Almaty','2026-10-29T20:00:00+00:00','2026-11-12T20:00:00+00:00','2026-10-30','2026-11-13'),
            ('America/Los_Angeles','2026-10-29T02:00:00+00:00','2026-11-12T02:00:00+00:00','2026-10-28','2026-11-11')]:
            client=Client()
            with self.assertRaises(HTTPException):
                asyncio.run(main._build_features_from_open_meteo(client,50.968,71.344,datetime.fromisoformat(start),
                            datetime.fromisoformat(end),zone,60,BASE_COLUMNS))
            self.assertEqual(client.params['start_date'],expected_start)
            self.assertEqual(client.params['end_date'],expected_end)
            self.assertNotIn('minutely_15',client.params)

    def test_actual_api_7_14_days_uses_both_models_and_preserves_energy(self):
        async def weather(**kwargs):
            start=pd.Timestamp(kwargs['start_dt']);end=pd.Timestamp(kwargs['end_dt'])
            idx=pd.date_range(start,end,freq='h',inclusive='left').tz_convert('Asia/Almaty')
            frame=pd.concat([self.frame]*((len(idx)//24)+1),ignore_index=True).iloc[:len(idx)].copy()
            frame['timestamp']=idx
            frame['GHI']=frame.surface_irradiance_solar
            frame['temp']=frame.temperature_solar;frame['wind_speed']=frame.wind_speed_wind
            frame['snow_1h']=0.;frame['isSun']=(frame.GHI>0).astype(int)
            return frame,'Asia/Almaty'
        with patch.object(main,'runtime',self.runtime),patch.object(main,'_http',object()),patch.object(main,'_build_features_from_open_meteo',weather):
            client=TestClient(main.app)
            for days in (7,14):
                params=dict(lat=50.968,lon=71.344,start_time='2026-10-29T12:00:00+05:00',capacity_kw=25,wind_capacity_kw=12,step_minutes=60)
                response=client.get(f'/forecast/{days}d',params=params)
                self.assertEqual(response.status_code,200,response.text[:1000]);raw=response.json()
                self.assertEqual(raw['n'],24*days)
                self.assertEqual(pd.Timestamp(raw['times'][0]),pd.Timestamp(params['start_time']))
                self.assertEqual(raw['model_name'],'DP-STH++');self.assertEqual(raw['quality']['model_name'],'DualAxis')
                self.assertFalse(raw['provenance']['original_article_weights'])
                params['step_minutes']=15
                fine=client.get(f'/forecast/{days}d',params=params).json()
                self.assertEqual(fine['n'],96*days)
                for key,capacity in [('solar_pred',25),('wind_pred',12)]:
                    self.assertAlmostEqual(sum(raw[key]),sum(fine[key]),places=5)
                    self.assertTrue(np.isfinite(raw[key]).all())
                    self.assertTrue(all(0<=v<=capacity*1000 for v in raw[key]))
            response=client.get('/forecast/7d',params={'lat':50.968,'lon':71.344})
            self.assertEqual(response.status_code,422)
            client.close()

if __name__=='__main__':unittest.main()

"""Regression for native-runtime crashes when all four serving models coexist.

A fresh process is required: importing PyTorch/scikit-learn in the test runner
would conceal the production import order and inherited OpenMP configuration.
Only bundled artifacts and real frozen fixture rows are used; no network calls.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import textwrap
import unittest


SERVER_ROOT = Path(__file__).resolve().parents[1]


class ModelCoexistenceTests(unittest.TestCase):
    def test_default_native_threads_support_all_models_in_one_process(self):
        code = textwrap.dedent(
            """
            import asyncio
            import json
            import math
            import os
            from pathlib import Path

            # Import the application before any native ML package, as Uvicorn does.
            from app import main

            async def verify():
                await main._startup()
                try:
                    health = main.health()
                    assert health['model_loaded'], health
                    assert health['load_model_loaded'], health
                    assert health['ssl_qc_model_loaded'], health
                    assert health['dp_sthpp_model_loaded'], health
                    assert not health['firestore_enabled'], health
                    assert os.environ['OMP_NUM_THREADS'] == '1'
                    assert main.torch.get_num_threads() == 1
                    print('All four real models loaded with application thread defaults', flush=True)

                    fixture = json.loads(Path('tests/fixtures/ssl_qc_golden.json').read_text())
                    case = fixture['cases'][0]
                    qc = main.ssl_qc_runtime.score(case['records'], window_id=case['window_id'])
                    expected = case['expected']['qc_score']
                    assert math.isclose(qc['qc_score'], expected, rel_tol=1e-5, abs_tol=1e-6), (qc['qc_score'], expected)
                    print('Initial QC agrees with the frozen golden fixture', flush=True)

                    joint = main.generation_analyze(main.GenerationAnalysisRequest(
                        records=case['records'], window_id=case['window_id']))
                    assert joint['quality']['qc_score'] == qc['qc_score']
                    assert joint['forecast']['model_name'] == 'DP-STH++'
                    assert joint['forecast_modified_by_qc'] is False
                    print('Combined endpoint executes SSL-QC and DP-STH++', flush=True)

                    import pandas as pd
                    renewable = main.runtime.predict_weather(pd.DataFrame(case['records']))
                    assert renewable['normalized'].shape == (1, 2)
                    assert all(math.isfinite(v) and v >= 0 for v in renewable['normalized'].ravel())
                    assert renewable['quality']['model_name'] == 'DualAxis'
                    print('Weather DP-STH++ and DualAxis returned finite results', flush=True)

                    load = main.load_runtime.forecast(days=1)
                    assert load['n'] == 96, load['n']
                    assert len(load['load_kw_pred']) == 96
                    assert all(math.isfinite(v) and v >= 0 for v in load['load_kw_pred'])
                    print('Load model returned 96 finite results', flush=True)

                    again = main.ssl_qc_runtime.score(case['records'], window_id=case['window_id'])
                    assert again['qc_score'] == qc['qc_score'], (again['qc_score'], qc['qc_score'])
                    assert again['components'] == qc['components']
                    print('QC remains identical after both other models perform inference', flush=True)
                finally:
                    await main._shutdown()

            asyncio.run(verify())
            """
        )
        environment = os.environ.copy()
        # Exercise application defaults, not test-runner workarounds. Removing
        # loader overrides also reproduces the native libraries used by each wheel.
        for name in (
            "OMP_NUM_THREADS", "SSL_QC_CPU_THREADS", "KMP_DUPLICATE_LIB_OK",
            "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH",
            "MODEL_DIR", "LOAD_MODEL_DIR", "SSL_QC_MODEL_DIR", "DP_STHPP_MODEL_DIR",
            "TF_NUM_INTRAOP_THREADS", "TF_NUM_INTEROP_THREADS", "CUDA_VISIBLE_DEVICES",
        ):
            environment.pop(name, None)
        environment["FIRESTORE_ENABLED"] = "false"
        environment["PYTHONFAULTHANDLER"] = "1"
        try:
            result = subprocess.run(
                [sys.executable, "-u", "-c", code],
                cwd=SERVER_ROOT,
                env=environment,
                text=True,
                capture_output=True,
                timeout=120,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            self.fail(
                "Model coexistence process exceeded 120 seconds.\n"
                f"stdout: {_bounded_output(exc.stdout)}\n"
                f"stderr: {_bounded_output(exc.stderr)}"
            )
        self.assertEqual(
            result.returncode,
            0,
            "Model coexistence process failed (a negative return code indicates a signal).\n"
            f"return code: {result.returncode}\n"
            f"stdout: {_bounded_output(result.stdout)}\n"
            f"stderr: {_bounded_output(result.stderr)}",
        )


def _bounded_output(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    return value[-8000:]


if __name__ == "__main__":
    unittest.main()

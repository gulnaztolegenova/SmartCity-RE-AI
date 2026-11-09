# DP-STH++ fixed v3 — local CPU server package

These files are byte-identical copies from the genuine, visibly trained run
`Gulnaz_T/Gulnaz_T_N1_DP-STH++/Server_Export/dp-sthpp-v3-csv-cpu-20261013T143156623652Z`.
The raw canonical CSV has SHA-256
`2771dd8b57aa43bc79944a9e8b2eb72d1214674056e601b997038fea164f1204`.
The prior Metal run was rejected after a directly reproduced ReLU backend error;
only the subsequent CPU run supplies these weights.

The package retains the original export manifest and a subset of its files.
The original manifest also lists research plots/tables that remain in the
scientific project. All serving files have hashes pinned in
`app/dp_sthpp_runtime.py`; neither a changed manifest nor a changed weight file
can silently select another model. `architecture_source.txt` is the original
reviewed constructor documentation. The runtime reconstructs that architecture
in Python and loads HDF5 weights without deserializing Lambda bytecode.

Validated dependencies are TensorFlow 2.18.1, Keras 3.12.1 and NumPy 2.0.2.
The runtime imports TensorFlow only during `load()` and explicitly places weights
and inference on CPU. It does not compile a training optimizer. The source
preprocessing is frozen JSON, so DP inference does not depend on sklearn pickle
compatibility. Parent process configuration controls CPU thread limits.

Callers must supply 24 consecutive whole-hour measured records, including past
solar and wind generation, with a common explicit UTC offset. Eight physical
signals are mandatory; four calendar features are derived from local timestamps.
Supplied calendar values must agree. Training used the source numerical feature
scales; weather-service substitutions and source-to-site scaling are not defined.
In particular, `relative_humidity_solar` is an unverified source alias, not an
automatically interchangeable meteorological relative-humidity percentage.

The result is one following hour in **unverified source units**. Negative outputs
are retained. Sigmoid extreme scores refer to a fit-only 90th-percentile target
threshold and are not calibrated alarms. There is no capacity multiplier,
automatic clipping, weather fallback, or validated recursive 7/14-day mode.
Historical holdout metrics are retrospective and must not be described as an
independent prospective test or as validation on an arbitrary installation.

`tests/fixtures/dp_sthpp_golden.json` is copied from the three real inner-validation
reload examples. Their original timestamps are timezone-naive. Tests append an
explicit offset only to exercise the API contract while preserving calendar
values; this does not establish the original source timezone. Regression parity
uses `rtol=1e-5, atol=1e-3` in source units and raw-probability parity uses
`rtol=1e-5, atol=1e-6`, matching the export's CPU validation.

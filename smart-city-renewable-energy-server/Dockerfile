FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 \
    SSL_QC_CPU_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    CUDA_VISIBLE_DEVICES=-1

WORKDIR /app

# Native scientific libraries need OpenMP.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN python -m pip install --no-cache-dir -U pip setuptools wheel
# Cloud Run uses CPUs; avoid installing the much larger CUDA distribution.
# Resolve common Python dependencies from PyPI in the next step. The PyTorch
# index is needed only for the CPU wheel, not its duplicate dependency mirror.
RUN pip install --no-cache-dir --no-deps torch==2.11.0 --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy app + model artifacts
COPY app /app/app
COPY models /app/models

ENV MODEL_DIR=/app/models
ENV SERVICE_NAME=smart-city-renewable-energy-server
ENV API_TITLE="Smart City Renewable Energy Forecast API"

# Build-time check on the target Linux image, including both neural artifacts.
# Network services and billing are not needed for this local model smoke test.
RUN FIRESTORE_ENABLED=false python -c "import asyncio; from app import main; asyncio.run(main._startup()); assert main.health()['dp_sthpp_model_loaded']; assert main.health()['ssl_qc_model_loaded']; asyncio.run(main._shutdown())"

EXPOSE 8080

# Cloud Run listens on $PORT
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]

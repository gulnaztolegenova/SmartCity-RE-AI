#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-smart-city-renewable-energy-server}"
API_TITLE="${API_TITLE:-Smart City Renewable Energy Forecast API}"
ARTIFACT_REPOSITORY="${ARTIFACT_REPOSITORY:-cloud-run-source-deploy}"
IMAGE_TAG="${IMAGE_TAG:-$(date -u '+%Y%m%d%H%M%S')}"
IMAGE_URI="${IMAGE_URI:-${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPOSITORY}/${SERVICE_NAME}:${IMAGE_TAG}}"
MEMORY="${MEMORY:-3Gi}"
CPU="${CPU:-2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
CONCURRENCY="${CONCURRENCY:-2}"
MIN_INSTANCES="${MIN_INSTANCES:-1}"
MAX_INSTANCES="${MAX_INSTANCES:-10}"
FIRESTORE_ENABLED="${FIRESTORE_ENABLED:-true}"
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-smartcity-runtime@${PROJECT_ID}.iam.gserviceaccount.com}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "ERROR: gcloud project is not configured. Run: gcloud config set project <PROJECT_ID>" >&2
  exit 1
fi

echo "Checking billing for project: ${PROJECT_ID}"
BILLING_ENABLED="$(gcloud billing projects describe "${PROJECT_ID}" --format='value(billingEnabled)')"
if [[ "${BILLING_ENABLED}" != "True" && "${BILLING_ENABLED}" != "true" ]]; then
  echo "ERROR: billing is not enabled for project '${PROJECT_ID}'." >&2
  echo "Link a billing account first, then rerun this script." >&2
  exit 1
fi

echo "Enabling required GCP services..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${PROJECT_ID}"

if ! gcloud artifacts repositories describe "${ARTIFACT_REPOSITORY}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" >/dev/null 2>&1; then
  echo "Creating Artifact Registry repository: ${ARTIFACT_REPOSITORY} (${REGION})..."
  gcloud artifacts repositories create "${ARTIFACT_REPOSITORY}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --repository-format=docker \
    --description="Docker images for Cloud Run services"
fi

echo "Building container image with Cloud Build..."
echo "IMAGE_URI=${IMAGE_URI}"
gcloud builds submit "${SCRIPT_DIR}" \
  --project="${PROJECT_ID}" \
  --tag="${IMAGE_URI}"

echo "Deploying ${SERVICE_NAME} image to Cloud Run (${REGION})..."
gcloud run deploy "${SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --image="${IMAGE_URI}" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --memory="${MEMORY}" \
  --cpu="${CPU}" \
  --timeout="${TIMEOUT_SECONDS}" \
  --concurrency="${CONCURRENCY}" \
  --min="${MIN_INSTANCES}" \
  --max-instances="${MAX_INSTANCES}" \
  --service-account="${RUNTIME_SERVICE_ACCOUNT}" \
  --set-env-vars="SERVICE_NAME=${SERVICE_NAME},API_TITLE=${API_TITLE},MODEL_DIR=/app/models,LOAD_MODEL_DIR=/app/models,FIRESTORE_ENABLED=${FIRESTORE_ENABLED},FIRESTORE_PROJECT_ID=${PROJECT_ID}"

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" --project="${PROJECT_ID}" --region="${REGION}" --format='value(status.url)')"

echo
echo "Cloud Run service deployed."
echo "PROJECT_ID=${PROJECT_ID}"
echo "REGION=${REGION}"
echo "SERVICE_NAME=${SERVICE_NAME}"
echo "IMAGE_URI=${IMAGE_URI}"
echo "SERVICE_URL=${SERVICE_URL}"

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="${CLOUD_RUN_SERVICE_NAME:-noongil-backend}"
REPOSITORY="${ARTIFACT_REGISTRY_REPOSITORY:-noongil}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
IMAGE_URI="${IMAGE_URI:-${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${SERVICE_NAME}:${IMAGE_TAG}}"
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-true}"
SERVICE_ACCOUNT="${CLOUD_RUN_SERVICE_ACCOUNT:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $1"
    exit 1
  fi
}

if [ -z "$PROJECT_ID" ]; then
  echo "ERROR: GCP_PROJECT_ID must be set."
  echo "       Example: GCP_PROJECT_ID=noongil-ai ./infra/scripts/deploy-backend.sh"
  exit 1
fi

require_command gcloud

echo "==> Project: $PROJECT_ID"
echo "==> Region: $REGION"
echo "==> Service: $SERVICE_NAME"
echo "==> Image: $IMAGE_URI"

echo "==> Enabling required Google Cloud APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  --project "$PROJECT_ID"

echo "==> Ensuring Artifact Registry repository exists..."
if ! gcloud artifacts repositories describe "$REPOSITORY" \
  --project "$PROJECT_ID" \
  --location "$REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" \
    --project "$PROJECT_ID" \
    --location "$REGION" \
    --repository-format docker \
    --description "Noongil backend images"
fi

DASHBOARD_DIR="$ROOT_DIR/dashboard"

echo "==> Building dashboard..."
if [ -d "$DASHBOARD_DIR" ] && [ -f "$DASHBOARD_DIR/package.json" ]; then
  (cd "$DASHBOARD_DIR" && npm ci && npm run build)
  echo "==> Dashboard built to $BACKEND_DIR/public/dashboard/"
else
  echo "WARN: Dashboard directory not found, skipping dashboard build"
fi

echo "==> Building container with Cloud Build..."
gcloud builds submit "$BACKEND_DIR" \
  --project "$PROJECT_ID" \
  --tag "$IMAGE_URI"

ENV_VARS=(
  "GCP_PROJECT_ID=$PROJECT_ID"
  "GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
  "GCP_REGION=$REGION"
)

OPTIONAL_ENV_KEYS=(
  FIREBASE_PROJECT_ID
  FIREBASE_WEB_API_KEY
  FIREBASE_WEB_APP_ID
  FIREBASE_MESSAGING_SENDER_ID
  FIREBASE_MEASUREMENT_ID
  FIREBASE_STORAGE_BUCKET
  PUBLIC_DASHBOARD_URL
  BACKEND_BASE_URL
  NEO4J_URI
  NEO4J_USER
  NEO4J_PASSWORD
  DD_API_KEY
  DD_SITE
  DD_HOST
  PAGERDUTY_WEBHOOK_SECRET
  MAILERSEND_API_KEY
  MAILERSEND_FROM_EMAIL
  MAILERSEND_FROM_NAME
)

for key in "${OPTIONAL_ENV_KEYS[@]}"; do
  value="${!key:-}"
  if [ -n "$value" ]; then
    ENV_VARS+=("$key=$value")
  fi
done

DEPLOY_ARGS=(
  run deploy "$SERVICE_NAME"
  "--project" "$PROJECT_ID"
  "--image" "$IMAGE_URI"
  "--region" "$REGION"
  "--platform" "managed"
  "--port" "8080"
  "--set-env-vars" "$(IFS=,; echo "${ENV_VARS[*]}")"
)

if [ "$ALLOW_UNAUTHENTICATED" = "true" ]; then
  DEPLOY_ARGS+=("--allow-unauthenticated")
else
  DEPLOY_ARGS+=("--no-allow-unauthenticated")
fi

if [ -n "$SERVICE_ACCOUNT" ]; then
  DEPLOY_ARGS+=("--service-account" "$SERVICE_ACCOUNT")
fi

echo "==> Deploying to Cloud Run..."
gcloud "${DEPLOY_ARGS[@]}"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format='value(status.url)')"

echo "==> Done!"
echo "==> Service URL: $SERVICE_URL"
echo "==> Health check: $SERVICE_URL/health"

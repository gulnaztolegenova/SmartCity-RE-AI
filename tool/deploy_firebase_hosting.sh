#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID to your Firebase project id}"
API_BASE_URL="${API_BASE_URL:?Set API_BASE_URL to the deployed API endpoint}"

"$ROOT_DIR/tool/write_build_metadata.sh"

cd "$ROOT_DIR"
flutter gen-l10n
flutter analyze
flutter build web --release --pwa-strategy=none --dart-define=API_BASE_URL="$API_BASE_URL"
npx -y firebase-tools@latest deploy --only hosting --project "$PROJECT_ID"

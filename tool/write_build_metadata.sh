#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/lib/core/generated/deploy_metadata.g.dart"
TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat > "$OUTPUT_FILE" <<EOF
// Generated deployment metadata. Updated automatically before hosting deploy.
const String kLastDeployAtIso8601 = '$TIMESTAMP_UTC';
EOF

echo "Updated deploy metadata: $TIMESTAMP_UTC"

#!/usr/bin/env bash
set -euo pipefail

# Usage: ./setup_client_space.sh <org_id> <org_name>
# Example: ./setup_client_space.sh org_001 "Acme Corp"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <org_id> <org_name>"
  exit 1
fi

ORG_ID="$1"
ORG_NAME="$2"

# Load env vars if .env exists in parent directory
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

KIBANA_HOST="${KIBANA_HOST:-http://localhost:5601}"
ES_USER="${DESTINATION_ES_USER:-elastic}"
ES_PASS="${DESTINATION_ES_PASSWORD:-changeme}"

# Slugify org_id: lowercase, replace non-alphanumeric with hyphens
SPACE_ID=$(echo "${ORG_ID}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')

kibana_curl() {
  curl -sf -u "${ES_USER}:${ES_PASS}" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    "$@"
}

create_space() {
  echo "Creating Kibana space: ${SPACE_ID} (${ORG_NAME})..."
  kibana_curl -X POST "${KIBANA_HOST}/api/spaces/space" \
    -d "{
      \"id\": \"${SPACE_ID}\",
      \"name\": \"${ORG_NAME}\",
      \"description\": \"Consumption dashboard for ${ORG_NAME} (${ORG_ID})\",
      \"color\": \"#1BA9F5\",
      \"initials\": \"$(echo "${ORG_NAME}" | cut -c1 | tr '[:lower:]' '[:upper:]')\"
    }" || {
    echo "  Note: Space may already exist, continuing..."
  }
  echo ""
  echo "Space created (or already exists)."
}

create_data_view() {
  local space_id="$1"
  local title="$2"
  local name="$3"
  local time_field="$4"

  echo "Creating data view: ${name}..."
  kibana_curl -X POST "${KIBANA_HOST}/s/${space_id}/api/data_views/data_view" \
    -d "{
      \"data_view\": {
        \"title\": \"${title}\",
        \"name\": \"${name}\",
        \"timeFieldName\": \"${time_field}\"
      }
    }" || true
  echo ""
  echo "  Data view '${name}' created (or already exists)."
}

import_ndjson() {
  local ndjson_file="$1"
  if [ ! -f "${ndjson_file}" ]; then
    echo "  WARNING: ${ndjson_file} not found, skipping."
    return
  fi
  echo "Importing $(basename "${ndjson_file}") into space: ${SPACE_ID}..."
  curl -sf -u "${ES_USER}:${ES_PASS}" \
    -H "kbn-xsrf: true" \
    -X POST "${KIBANA_HOST}/s/${SPACE_ID}/api/saved_objects/_import?overwrite=true" \
    --form "file=@${ndjson_file}"
  echo ""
  echo "  Imported."
}

main() {
  create_space

  create_data_view \
    "${SPACE_ID}" \
    "consumption-node-hourly" \
    "Node Usage (Hourly)" \
    "hour"

  create_data_view \
    "${SPACE_ID}" \
    "consumption-index-hourly" \
    "Index Usage (Hourly)" \
    "hour"

  import_ndjson "$(dirname "$0")/consumption_dashboard.ndjson"
  import_ndjson "$(dirname "$0")/monthly_dashboard.ndjson"

  echo ""
  echo "=== Client space setup complete ==="
  echo ""
  echo "Dashboards: ${KIBANA_HOST}/s/${SPACE_ID}/app/dashboards"
}

main

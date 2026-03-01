#!/usr/bin/env bash
set -euo pipefail

# Load env vars if .env exists
if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

ES_HOST="${DESTINATION_ES_HOST:-http://localhost:9200}"
ES_USER="${DESTINATION_ES_USER:-elastic}"
ES_PASS="${DESTINATION_ES_PASSWORD:-changeme}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

es_curl() {
  curl -sf -u "${ES_USER}:${ES_PASS}" "$@"
}

wait_for_es() {
  echo "Waiting for Elasticsearch at ${ES_HOST}..."
  local attempts=0
  until es_curl "${ES_HOST}/_cluster/health" | grep -qv '"status":"red"'; do
    attempts=$((attempts + 1))
    if [ $attempts -ge 30 ]; then
      echo "ERROR: Elasticsearch did not become healthy after 30 attempts."
      exit 1
    fi
    echo "  Not ready yet (attempt ${attempts}/30), retrying in 5s..."
    sleep 5
  done
  echo "Elasticsearch is healthy."
}

apply_ilm_policy() {
  echo "Applying ILM policy..."
  es_curl -X PUT "${ES_HOST}/_ilm/policy/consumption-policy" \
    -H "Content-Type: application/json" \
    -d @"${SCRIPT_DIR}/elasticsearch/ilm_policy.json"
  echo ""
  echo "ILM policy applied."
}

apply_index_template() {
  echo "Applying index template..."
  es_curl -X PUT "${ES_HOST}/_index_template/consumption" \
    -H "Content-Type: application/json" \
    -d @"${SCRIPT_DIR}/elasticsearch/index_template.json"
  echo ""
  echo "Index template applied."
}

apply_transforms() {
  local transforms_dir="${SCRIPT_DIR}/elasticsearch/transforms"
  for transform_file in "${transforms_dir}"/*.json; do
    local transform_id
    transform_id=$(jq -r '.id' "${transform_file}")
    echo "Processing transform: ${transform_id}"

    # Delete existing transform (ignore error if not found)
    es_curl -X DELETE "${ES_HOST}/_transform/${transform_id}?force=true" 2>/dev/null || true
    echo "  Deleted existing transform (if any)."

    # PUT the transform body without the top-level id field
    local body
    body=$(jq 'del(.id)' "${transform_file}")
    es_curl -X PUT "${ES_HOST}/_transform/${transform_id}" \
      -H "Content-Type: application/json" \
      -d "${body}"
    echo ""
    echo "  Created transform: ${transform_id}"

    # Start the transform
    es_curl -X POST "${ES_HOST}/_transform/${transform_id}/_start"
    echo ""
    echo "  Started transform: ${transform_id}"
  done
}

main() {
  wait_for_es
  apply_ilm_policy
  apply_index_template
  apply_transforms
  echo ""
  echo "=== Initialization complete ==="
  echo "Check transform status: GET ${ES_HOST}/_transform/_stats"
  echo "Check node data:        GET ${ES_HOST}/consumption-node-hourly/_count"
  echo "Check index data:       GET ${ES_HOST}/consumption-index-hourly/_count"
}

main

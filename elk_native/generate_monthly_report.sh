#!/usr/bin/env bash
set -euo pipefail

# Usage: ./generate_monthly_report.sh [YYYY-MM]
# Default: previous complete month
# Outputs: node_report_YYYY-MM.csv  and  index_report_YYYY-MM.csv

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load env vars
if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
fi

ES_HOST="${DESTINATION_ES_HOST:-http://localhost:9200}"
ES_USER="${DESTINATION_ES_USER:-elastic}"
ES_PASS="${DESTINATION_ES_PASSWORD:-changeme}"

# ── Date helpers ──────────────────────────────────────────────────────────────

resolve_month() {
  local input="$1"
  # Try GNU date (Linux)
  if date --version >/dev/null 2>&1; then
    echo "$(date -d "${input}-01 -1 month" +%Y-%m 2>/dev/null)" && return
  fi
  # Try BSD date (macOS)
  echo "$(date -v-1m -j -f "%Y-%m-%d" "${input}-01" +%Y-%m 2>/dev/null)" && return
  # Python fallback
  python3 -c "
from datetime import date
d = date.today().replace(day=1)
import calendar; prev = d.replace(month=d.month-1) if d.month>1 else d.replace(year=d.year-1, month=12)
print(prev.strftime('%Y-%m'))
"
}

if [ -n "${1:-}" ]; then
  MONTH="$1"
else
  TODAY=$(date +%Y-%m)
  MONTH=$(resolve_month "${TODAY}")
fi

# Validate format
if ! echo "${MONTH}" | grep -qE '^[0-9]{4}-[0-9]{2}$'; then
  echo "ERROR: Invalid month format '${MONTH}'. Use YYYY-MM."
  exit 1
fi

MONTH_START="${MONTH}-01T00:00:00.000Z"

# Calculate next month start for upper bound
YEAR="${MONTH%-*}"
MON="${MONTH#*-}"
if [ "${MON}" = "12" ]; then
  NEXT_MONTH="$((YEAR + 1))-01-01T00:00:00.000Z"
else
  NEXT_MON=$(printf "%02d" $((10#${MON} + 1)))
  NEXT_MONTH="${YEAR}-${NEXT_MON}-01T00:00:00.000Z"
fi

NODE_OUT="${SCRIPT_DIR}/node_report_${MONTH}.csv"
INDEX_OUT="${SCRIPT_DIR}/index_report_${MONTH}.csv"

es_search() {
  local index="$1"
  local query="$2"
  curl -sf -u "${ES_USER}:${ES_PASS}" \
    -H "Content-Type: application/json" \
    -X GET "${ES_HOST}/${index}/_search" \
    -d "${query}"
}

DATE_FILTER=$(cat <<EOF
{
  "size": 5000,
  "query": {
    "range": {
      "month": {
        "gte": "${MONTH_START}",
        "lt":  "${NEXT_MONTH}"
      }
    }
  },
  "sort": [
    { "organization_id": "asc" },
    { "cluster_name":    "asc" }
  ]
}
EOF
)

# ── Node report ───────────────────────────────────────────────────────────────

echo "Generating node report for ${MONTH}..."

es_search "consumption-node-monthly" "${DATE_FILTER}" | jq -r '
  ["month","organization_id","cluster_name","node_id","node_name",
   "avg_cpu_percent","avg_jvm_heap_percent",
   "max_memory_bytes","min_fs_available_bytes",
   "max_indexing_total","max_search_total"],
  (.hits.hits[] | ._source |
    [ .month, .organization_id, .cluster_name, .node_id, .node_name,
      (.avg_cpu_percent    | if . then (. * 100 | round / 100) else null end),
      (.avg_jvm_heap_percent | if . then (. * 100 | round / 100) else null end),
      .max_memory_bytes, .min_fs_available_bytes,
      .max_indexing_total, .max_search_total
    ])
  | @csv
' > "${NODE_OUT}"

NODE_COUNT=$(tail -n +2 "${NODE_OUT}" | wc -l | tr -d ' ')
echo "  Wrote ${NODE_COUNT} rows → ${NODE_OUT}"

# ── Index report ──────────────────────────────────────────────────────────────

echo "Generating index report for ${MONTH}..."

es_search "consumption-index-monthly" "${DATE_FILTER}" | jq -r '
  ["month","organization_id","cluster_name","index_name",
   "max_total_docs_count","max_store_size_bytes",
   "max_search_query_total","max_indexing_total"],
  (.hits.hits[] | ._source |
    [ .month, .organization_id, .cluster_name, .index_name,
      .max_total_docs_count, .max_store_size_bytes,
      .max_search_query_total, .max_indexing_total
    ])
  | @csv
' > "${INDEX_OUT}"

INDEX_COUNT=$(tail -n +2 "${INDEX_OUT}" | wc -l | tr -d ' ')
echo "  Wrote ${INDEX_COUNT} rows → ${INDEX_OUT}"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Monthly Report: ${MONTH} ==="
echo ""
if [ "${NODE_COUNT}" -gt 0 ]; then
  echo "Node summary:"
  tail -n +2 "${NODE_OUT}" | awk -F',' '
    { gsub(/"/, "", $2); gsub(/"/, "", $3); gsub(/"/, "", $5)
      cpu[$2","$3] += $6+0; jvm[$2","$3] += $7+0; n[$2","$3]++ }
    END {
      for (k in n)
        printf "  %-30s  avg CPU: %5.1f%%  avg JVM: %5.1f%%\n",
               k, cpu[k]/n[k], jvm[k]/n[k]
    }
  '
fi
echo ""
if [ "${INDEX_COUNT}" -gt 0 ]; then
  echo "Top 5 indices by store size:"
  tail -n +2 "${INDEX_OUT}" | sort -t',' -k6 -rn | head -5 | awk -F',' '
    { gsub(/"/, "", $4)
      size=$6+0
      if (size > 1073741824)      printf "  %-40s  %7.2f GB\n", $4, size/1073741824
      else if (size > 1048576)    printf "  %-40s  %7.2f MB\n", $4, size/1048576
      else                        printf "  %-40s  %7.2f KB\n", $4, size/1024
    }
  '
fi
echo ""
echo "Files: ${NODE_OUT}"
echo "       ${INDEX_OUT}"

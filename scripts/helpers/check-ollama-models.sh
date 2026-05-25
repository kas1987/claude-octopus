#!/usr/bin/env bash
# Check installed Ollama models for staleness against OCTO_OLLAMA_STALE_DAYS.
# Sources scripts/lib/provider-versions.sh for the comparator.
#
# Usage:
#   bash scripts/helpers/check-ollama-models.sh             # human-readable per-model lines
#   bash scripts/helpers/check-ollama-models.sh --json      # JSON output
#   bash scripts/helpers/check-ollama-models.sh --exit-code # exit 1 if any model stale
#   bash scripts/helpers/check-ollama-models.sh --count-stale # print integer count only
#
# Env vars:
#   OCTO_OLLAMA_API_URL   override Ollama endpoint (default: http://localhost:11434)
#   OCTO_OLLAMA_STALE_DAYS override staleness threshold (default: 30)

OCTO_ROOT="${OCTO_ROOT:-$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || echo "${HOME}/.claude-octopus/plugin")}"
OCTO_OLLAMA_API_URL="${OCTO_OLLAMA_API_URL:-http://localhost:11434}"

# shellcheck source=scripts/lib/provider-versions.sh
source "${OCTO_ROOT}/scripts/lib/provider-versions.sh" 2>/dev/null || {
  echo "ERROR: provider-versions.sh not found at ${OCTO_ROOT}/scripts/lib/" >&2
  exit 1
}

# Fetch /api/tags. Returns empty string if Ollama unreachable (fail open).
# OCTO_OLLAMA_API_URL may be a base URL (http://...) or a file:// path to a mock JSON.
# For file:// URLs, the file IS the /api/tags response (no path suffix appended).
_octo_fetch_tags() {
  local base="${OCTO_OLLAMA_API_URL}"
  if [[ "$base" == file://* ]]; then
    cat "${base#file://}" 2>/dev/null || echo ""
    return 0
  fi
  curl -sf --max-time 3 "${base}/api/tags" 2>/dev/null || echo ""
}

# Parse models from API JSON into "name|modified_at" lines (one per model).
# Writes JSON to a tempfile and passes as argv to python3 (avoids stdin/heredoc conflict).
_octo_parse_models() {
  local json="$1"
  [[ -z "$json" ]] && return 0
  local tmpf
  tmpf=$(mktemp 2>/dev/null) || tmpf="/tmp/octo-ollama-parse-$$.json"
  printf '%s' "$json" > "$tmpf"
  python3 - "$tmpf" <<'PYEOF' 2>/dev/null
import sys, json
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    for m in data.get("models", []):
        name = m.get("name", "")
        modified_at = m.get("modified_at", "").rstrip()
        if name:
            print(f"{name}|{modified_at}")
except Exception:
    pass
PYEOF
  rm -f "$tmpf" 2>/dev/null
}

declare -a MODEL_LINES
declare -a MODEL_STATUSES
STALE_COUNT=0
TOTAL_COUNT=0

TAGS_JSON=$(_octo_fetch_tags)

if [[ -n "$TAGS_JSON" ]]; then
  while IFS='|' read -r name modified_at; do
    [[ -z "$name" ]] && continue
    # Strip CR (Python on Windows emits CRLF in text-mode stdout).
    modified_at="${modified_at%$'\r'}"
    name="${name%$'\r'}"
    ((TOTAL_COUNT++))
    if octo_ollama_model_age_ok "$modified_at"; then
      MODEL_LINES+=("  ✅ ${name}")
      MODEL_STATUSES+=("fresh")
    else
      MODEL_LINES+=("  ⚠️  ${name} (stale, modified ${modified_at})")
      MODEL_STATUSES+=("stale")
      ((STALE_COUNT++))
    fi
  done < <(_octo_parse_models "$TAGS_JSON")
fi

# --count-stale: print integer count only
if [[ "${1:-}" == "--count-stale" ]]; then
  printf '%d\n' "$STALE_COUNT"
  exit 0
fi

# --exit-code: exit 1 if any stale, else 0
if [[ "${1:-}" == "--exit-code" ]]; then
  [[ "$STALE_COUNT" -gt 0 ]] && exit 1
  exit 0
fi

# --json output
print_json_models() {
  local count="${#MODEL_LINES[@]}"
  echo "{"
  echo "  \"total\": ${TOTAL_COUNT},"
  echo "  \"stale\": ${STALE_COUNT},"
  echo "  \"threshold_days\": ${OCTO_OLLAMA_STALE_DAYS},"
  echo "  \"results\": ["
  for i in "${!MODEL_LINES[@]}"; do
    local comma="," label status
    [[ $((i + 1)) -eq ${count} ]] && comma=""
    label=$(echo "${MODEL_LINES[$i]}" | sed "s/^[[:space:]]*[✅⚠️ ]*//" | xargs)
    status="${MODEL_STATUSES[$i]}"
    echo "    {\"name\": \"${label}\", \"status\": \"${status}\"}${comma}"
  done
  echo "  ]"
  echo "}"
}

if [[ "${1:-}" == "--json" ]]; then
  print_json_models
  exit 0
fi

# Human-readable output
for line in "${MODEL_LINES[@]}"; do
  echo "$line"
done
if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  echo "  (no Ollama models detected — server unreachable or no models installed)"
fi
[[ "$STALE_COUNT" -gt 0 ]] && exit 1
exit 0
#!/usr/bin/env bash
# /octo:preflight — Provider health probe with per-provider timeouts.
# Called by /octo:preflight slash command and setup.md STEP 1.
#
# Usage:
#   bash scripts/helpers/preflight.sh            # interactive dashboard
#   bash scripts/helpers/preflight.sh --exit-code # exits 0 if Claude available (always)
#   bash scripts/helpers/preflight.sh --json      # JSON output for scripting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_VERSIONS="${SCRIPT_DIR}/check-versions.sh"

# Portable timeout: prefer gtimeout (macOS), fallback to timeout, finally no-op.
_octo_timeout_cmd=""
if command -v gtimeout >/dev/null 2>&1; then
  _octo_timeout_cmd="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  _octo_timeout_cmd="timeout"
fi

# json_escape STRING - emit a JSON-safe string body (no surrounding quotes).
# Handles backslash, double quote, and control characters via Python.
json_escape() {
  python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$1" 2>/dev/null || printf "%s" "$1"
}

PROVIDERS_READY=0
PROVIDERS_DEGRADED=0
declare -a RESULT_LINES
declare -a RESULT_STATUSES

check_provider() {
  local name="$1"
  local check_cmd="$2"
  local timeout_s="${3:-2}"
  local icon

  if [[ -n "$_octo_timeout_cmd" ]]; then
    "$_octo_timeout_cmd" "$timeout_s" bash -c "$check_cmd" &>/dev/null 2>&1
  else
    bash -c "$check_cmd" &>/dev/null 2>&1
  fi
  if [[ $? -eq 0 ]]; then
    icon="✅"
    ((PROVIDERS_READY++))
    RESULT_STATUSES+=("available")
  else
    icon="⚠️ "
    ((PROVIDERS_DEGRADED++))
    RESULT_STATUSES+=("unavailable")
  fi

  RESULT_LINES+=("  ${icon} ${name}")
}

# Claude is always available (built-in)
check_provider "Claude (built-in)" "true"
check_provider "Codex CLI"    "command -v codex"
check_provider "Gemini CLI"   "command -v gemini"
check_provider "Copilot"      "command -v gh && gh copilot --version"
check_provider "Qwen CLI"     "command -v qwen"
check_provider "OpenCode"     "command -v opencode"
check_provider "Ollama"       "curl -sf --max-time 2 http://localhost:11434/api/tags" 2
check_provider "Perplexity"   "[ -n \"${PERPLEXITY_API_KEY:-}\" ]"
check_provider "OpenRouter"   "[ -n \"${OPENROUTER_API_KEY:-}\" ]"

if [[ "${1:-}" == "--exit-code" ]]; then
  exit 0
fi

print_json_output() {
  local count="${#RESULT_LINES[@]}"
  local ver_json
  ver_json="{}"
  if [[ -f "$CHECK_VERSIONS" ]]; then
    ver_json=$(bash "$CHECK_VERSIONS" --json 2>/dev/null) || ver_json='{"any_below_floor":false,"results":[]}'
  fi
  echo "{"
  echo "  \"providers_ready\": $PROVIDERS_READY,"
  echo "  \"providers_degraded\": $PROVIDERS_DEGRADED,"
  echo "  \"results\": ["
  for i in "${!RESULT_LINES[@]}"; do
    local comma=","
    [[ $((i + 1)) -eq $count ]] && comma=""
    local label
    label=$(echo "${RESULT_LINES[$i]}" | sed "s/^[[:space:]]*//" | sed "s/^[^A-Za-z]*//" | xargs)
    label=$(json_escape "$label")
    echo "    {\"name\": \"${label}\", \"status\": \"${RESULT_STATUSES[$i]}\"}${comma}"
  done
  echo "  ],"
  echo "  \"versions\": ${ver_json}"
  echo "}"
}

if [[ "${1:-}" == "--json" ]]; then
  print_json_output
  exit 0
fi

echo ""
echo "🐙 Octopus Provider Health"
echo "──────────────────────────"
for line in "${RESULT_LINES[@]}"; do
  echo "$line"
done
echo ""
echo "  Ready: $PROVIDERS_READY  |  Unavailable: $PROVIDERS_DEGRADED"
echo ""
if [[ $PROVIDERS_READY -eq 1 ]]; then
  echo "  ℹ️  Claude-only mode. Run /octo:setup to add providers."
elif [[ $PROVIDERS_READY -ge 3 ]]; then
  echo "  🚀 Multi-provider mode active. Run /octo:embrace for full orchestration."
fi

# Version floor section
if [[ -f "$CHECK_VERSIONS" ]]; then
  bash "$CHECK_VERSIONS" 2>/dev/null || true
fi

echo ""
exit 0

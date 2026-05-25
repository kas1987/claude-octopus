#!/usr/bin/env bash
# /octo:preflight — Provider health probe with per-provider timeouts.
# Called by /octo:preflight slash command and setup.md STEP 1.
#
# Usage:
#   bash scripts/helpers/preflight.sh            # interactive dashboard
#   bash scripts/helpers/preflight.sh --exit-code # exits 0 if Claude available (always)
#   bash scripts/helpers/preflight.sh --json      # JSON output for scripting

PROVIDERS_READY=0
PROVIDERS_DEGRADED=0
declare -a RESULT_LINES
declare -a RESULT_STATUSES

check_provider() {
  local name="$1"
  local check_cmd="$2"
  local timeout_s="${3:-2}"
  local icon

  if timeout "$timeout_s" bash -c "$check_cmd" &>/dev/null 2>&1; then
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
  echo "{"
  echo "  \"providers_ready\": $PROVIDERS_READY,"
  echo "  \"providers_degraded\": $PROVIDERS_DEGRADED,"
  echo "  \"results\": ["
  for i in "${!RESULT_LINES[@]}"; do
    local comma=","
    [[ $((i + 1)) -eq $count ]] && comma=""
    local label
    label=$(echo "${RESULT_LINES[$i]}" | sed "s/^[[:space:]]*[✅⚠️ ]*//" | xargs)
    echo "    {\"name\": \"${label}\", \"status\": \"${RESULT_STATUSES[$i]}\"}${comma}"
  done
  echo "  ]"
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
echo ""
exit 0

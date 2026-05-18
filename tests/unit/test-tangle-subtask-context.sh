#!/usr/bin/env bash
# Regression checks for /octo:develop subtask prompt context preservation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle subtask context preservation"

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

# shellcheck source=/dev/null
source "$WORKFLOWS"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$(mktemp -d)"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
CAPTURE_DIR="$RESULTS_DIR/captured-prompts"
mkdir -p "$WORKSPACE_DIR/.octo/agents" "$CAPTURE_DIR"
trap 'rm -rf "$RESULTS_DIR"' EXIT

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
validate_tangle_results() { :; }

run_agent_sync() {
    cat <<'EOF'
1. [CODING] Template polish
2. [REASONING] Integration review
EOF
}

spawn_agent_capture_pid() {
    local _agent="$1"
    local prompt="$2"
    local task_id="$3"
    printf '%s' "$prompt" > "$CAPTURE_DIR/${task_id}.prompt"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '12345\n'
}

original_prompt="Update src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts. Do not modify src/lib/render/renderEmailTemplate.ts."

tangle_develop "$original_prompt" >/dev/null

captured_prompts="$(cat "$CAPTURE_DIR"/*.prompt)"

test_case "subtask prompts include original task context"
if [[ "$captured_prompts" == *"Original task context:"* ]] && \
   [[ "$captured_prompts" == *"src/lib/templates/NA10_HANDLE_SILENCE.ts"* ]] && \
   [[ "$captured_prompts" == *"src/lib/templates/NA20_REQUEST_MISSING_INFO.ts"* ]]; then
    test_pass
else
    test_fail "spawned subtasks did not receive the original task context and explicit file targets"
fi

test_case "subtask prompts preserve original forbidden changes"
if [[ "$captured_prompts" == *"Do not modify src/lib/render/renderEmailTemplate.ts"* ]]; then
    test_pass
else
    test_fail "spawned subtasks did not receive the original forbidden-change constraint"
fi

test_case "subtask prompts still include the assigned subtask"
if [[ "$captured_prompts" == *"Assigned subtask:"* ]] && \
   [[ "$captured_prompts" == *"Template polish"* ]] && \
   [[ "$captured_prompts" == *"Integration review"* ]]; then
    test_pass
else
    test_fail "spawned prompts lost the assigned subtask text"
fi

test_summary

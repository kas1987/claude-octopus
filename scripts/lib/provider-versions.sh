#!/usr/bin/env bash
# Provider CLI version floors — minimum versions for stable orchestration.
# Source this file to access floor constants and octo_version_ok().

OCTO_CODEX_MIN_VERSION="0.100.0"
OCTO_GEMINI_MIN_VERSION="1.0.0"
OCTO_QWEN_MIN_VERSION="9.10.0"
OCTO_GH_MIN_VERSION="2.0.0"
OCTO_OPENCODE_MIN_VERSION="0.1.0"

# octo_version_ok INSTALLED MIN
# Returns 0 (ok) if INSTALLED >= MIN, 1 if below floor.
# Unknown version always returns 0 (fail open — don't block users on unknown).
octo_version_ok() {
  local installed="$1" min="$2"
  [[ "$installed" == "unknown" ]] && return 0

  # Use inline IFS assignment (not local IFS) for bash 3.x portability.
  local -a iv mv
  IFS='.' read -ra iv <<< "$installed"
  IFS='.' read -ra mv <<< "$min"

  local i
  for i in 0 1 2; do
    local a="${iv[$i]:-0}" b="${mv[$i]:-0}"
    # Force base-10 to prevent octal interpretation of 08/09.
    (( 10#$a > 10#$b )) && return 0
    (( 10#$a < 10#$b )) && return 1
  done
  return 0
}
#!/usr/bin/env bash
# Plugin root helpers for Claude Octopus.
# Source-safe: no main execution block.

octo_is_windows_git_bash() {
    local uname_s="${1:-}"
    if [[ -z "$uname_s" ]]; then
        uname_s="$(uname -s 2>/dev/null || true)"
    fi

    case "$uname_s" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac

    [[ "${OS:-}" == "Windows_NT" ]] && {
        [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] ||
        [[ "${OSTYPE:-}" == msys* ]] || [[ "${OSTYPE:-}" == mingw* ]] ||
        [[ "${OSTYPE:-}" == cygwin* ]]
    }
}

octo_write_stable_script_shim() {
    local plugin_root="$1"
    local stable_root="$2"
    local rel_path="$3"
    local src="${plugin_root}/${rel_path}"
    local dst="${stable_root}/${rel_path}"

    [[ -f "$src" ]] || return 0

    local quoted_src
    printf -v quoted_src '%q' "$src"
    mkdir -p "$(dirname "$dst")"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'exec %s "$@"\n' "$quoted_src"
    } > "$dst"
    chmod +x "$dst" 2>/dev/null || true
}

octo_ensure_stable_plugin_root() {
    local plugin_root="$1"
    local stable_root="${2:-${HOME}/.claude-octopus/plugin}"

    [[ -n "$plugin_root" && -d "$plugin_root" ]] || return 1

    mkdir -p "$(dirname "$stable_root")"

    if [[ -L "$stable_root" || -f "$stable_root" ]]; then
        rm -f "$stable_root" 2>/dev/null || true
    fi

    if [[ ! -e "$stable_root" ]]; then
        ln -s "$plugin_root" "$stable_root" 2>/dev/null || true
    fi

    if [[ -L "$stable_root" && -x "$stable_root/scripts/orchestrate.sh" ]]; then
        return 0
    fi

    if [[ -e "$stable_root" && ! -d "$stable_root" ]]; then
        rm -f "$stable_root" 2>/dev/null || true
    fi

    # Windows Git Bash often cannot create native symlinks without Developer
    # Mode/admin rights. Keep the stable path usable by writing tiny wrappers
    # for script entry points referenced by commands and skills.
    mkdir -p "$stable_root"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/orchestrate.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/install-deps.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/helpers/check-providers.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/scheduler/octopus-scheduler.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/state-manager.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/octo-state.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/agent-registry.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/reactions.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/migrate-todos.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/claude-mem-bridge.sh"

    [[ -x "$stable_root/scripts/orchestrate.sh" ]]
}

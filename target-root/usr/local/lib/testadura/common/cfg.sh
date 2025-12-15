# shellcheck shell=bash
# ============================================================================
# Testadura — cfg.sh
# ---------------------------------------------------------------------------
# Purpose : Configuration file discovery and loading
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Conventions:
#   - Config files are shell-sourceable (.conf)
#   - Variables defined in config are expected to be UPPERCASE
#
# Search order (when CFG_AUTO=1, default):
#   1) Explicit CFG_FILE
#   2) <script_dir>/<script_name>.conf        (dev/local)
#   3) /etc/testadura/<script_name>.conf      (system)
#   4) /etc/testadura/testadura.conf          (global fallback)
#
# A script may optionally define:
#   load_config()   -> fully custom logic (overrides everything)
#
# Public API:
#   td_cfg_load
#   td_cfg_source
#   td_cfg_default_path
#   td_cfg_system_path
# ============================================================================

[[ -n "${TD_CFG_LOADED:-}" ]] && return 0
TD_CFG_LOADED=1

# ----------------------------------------------------------------------------
# Determine default local config path: <script_dir>/<script>.conf
# ----------------------------------------------------------------------------
td_cfg_default_path() {
    local script_dir script_name base

    script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${SCRIPT_FILE:-$0}")" && pwd)}"
    script_name="${SCRIPT_NAME:-$(basename "${SCRIPT_FILE:-$0}")}"
    base="${script_name%.sh}"

    printf '%s/%s.conf\n' "$script_dir" "$base"
}

# ----------------------------------------------------------------------------
# Determine system config path: /etc/testadura/<script>.conf
# ----------------------------------------------------------------------------
td_cfg_system_path() {
    local script_name base

    script_name="${SCRIPT_NAME:-$(basename "${SCRIPT_FILE:-$0}")}"
    base="${script_name%.sh}"

    printf '/etc/testadura/%s.conf\n' "$base"
}

# ----------------------------------------------------------------------------
# Source a config file
#   $1 = path
#   $2 = optional (1 = ignore if missing, 0 = error if missing)
# ----------------------------------------------------------------------------
td_cfg_source() {
    local path="$1"
    local optional="${2:-0}"

    [[ -n "$path" ]] || {
        echo "[FAIL] Config path is empty" >&2
        return 1
    }

    if [[ ! -f "$path" ]]; then
        if [[ "$optional" -eq 1 ]]; then
            return 0
        fi
        echo "[FAIL] Config file not found: $path" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$path"
}

# ----------------------------------------------------------------------------
# Load configuration according to conventions
# ----------------------------------------------------------------------------
td_cfg_load() {
    # 1) Script-defined override
    if declare -f load_config >/dev/null 2>&1; then
        load_config
        return $?
    fi

    local auto="${CFG_AUTO:-1}"

    # 2) Explicit config file (required)
    if [[ -n "${CFG_FILE:-}" ]]; then
        td_cfg_source "$CFG_FILE" 0
        return $?
    fi

    # 3) Automatic discovery
    if [[ "$auto" -eq 1 ]]; then
        local path

        # Local (dev)
        path="$(td_cfg_default_path)"
        td_cfg_source "$path" 1 && return 0

        # System
        path="$(td_cfg_system_path)"
        td_cfg_source "$path" 1 && return 0

        # Global fallback
        td_cfg_source "/etc/testadura/testadura.conf" 1 && return 0
    fi

    return 0
}

#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — Script Template
# ------------------------------------------------------------------------------
# Purpose : Canonical executable template for Testadura scripts
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in by defining ARGS_SPEC and/or CFG_*.
# ==============================================================================

set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    SCRIPT_FILE="${BASH_SOURCE[0]}"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_FILE")" && pwd)"
    SCRIPT_NAME="$(basename "$SCRIPT_FILE")"
    SCRIPT_DESC="Short description of what this script does."
    SCRIPT_VERSION="1.0"
    SCRIPT_VERSION_STATUS="alpha"
    SCRIPT_BUILD="20250110"

# --- Framework roots (explicit) ----------------------------------------------
    # Override from environment if desired:
    #   TD_ROOT=/some/path COMMON_LIB=/some/path/common ./yourscript.sh
    TD_ROOT="${TD_ROOT:-/usr/local/lib/testadura}"
    COMMON_LIB="${COMMON_LIB:-$TD_ROOT/common}"

# --- Using / imports ----------------------------------------------------------
    # Edit this list per script, like a “using” section in C#.
    # Keep it explicit; avoid auto-loading *.sh.
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"    # td_parse_args, td_show_help
    "cfg.sh"    # td_cfg_load, config discovery + source
    "ui.sh"     # user inetractive helpers
    # "fs.sh"   # optional: filesystem helpers
    )

    td_source_libs() {
        local lib path
        for lib in "${TD_USING[@]}"; do
            path="$COMMON_LIB/$lib"
            if [[ ! -f "$path" ]]; then
                echo "[FAIL] Missing library: $path" >&2
                exit 1
            fi
            # shellcheck source=/dev/null
            source "$path"
        done
    }

    td_source_libs

# --- Example: Arguments -------------------------------------------------------
    # Define ARGS_SPEC to enable td_parse_args.
    #
    # Format:
    #   "name|short|type|var|help|choices"
    #
    # Notes:
    # - Keep trailing "|" if choices is empty.
    # - 'flag'  -> default 0, becomes 1 if present
    # - 'value' -> consumes next token
    # - 'enum'  -> consumes next token, must match choices list
    ARGS_SPEC=(
    "config|c|value|CFG_FILE|Config file path (overrides auto-discovery)|"
    "verbose|v|flag|FLAG_VERBOSE|Verbose output|"
    "mode|m|enum|ENUM_MODE|Run mode|dev,prd,auto"
    )

    # Parse args (creates: HELP_REQUESTED, TD_POSITIONAL and initializes option vars)
    td_parse_args "$@" || exit 1

    if [[ "${HELP_REQUESTED:-0}" -eq 1 ]]; then
        td_show_help
        exit 0
    fi

# --- Example: Config loading --------------------------------------------------
    # cfg.sh supports:
    #   CFG_FILE -> explicit path (set via --config above)
    #   CFG_AUTO -> 1/0 (default 1) auto discovery if CFG_FILE not set
    #
    # Auto-discovery order (per cfg.sh):
    #   1) <script_dir>/<script>.conf           (optional)
    #   2) /etc/testadura/<script>.conf         (optional)
    #   3) /etc/testadura/testadura.conf        (optional)
    #
    # If you want to disable auto-discovery:
    #   CFG_AUTO=0
    #
    # You can also define a custom load_config() function in this script;
    # td_cfg_load will call it instead of its own discovery logic.
    td_cfg_load || exit 1

# --- Example: Post-load defaults ---------------------------------------------
# Config can define defaults; CLI can override them. Decide your precedence.
    # Here: if ENUM_MODE not set via CLI, default to "auto".
    if [[ -z "${ENUM_MODE:-}" ]]; then
        ENUM_MODE="auto"
    fi


# --- main --------------------------------------------------------------------
    __td_showarguments() {
        printf "Script              : %s\n" "$SCRIPT_NAME"
        printf "Script dir          : %s\n" "$SCRIPT_DIR"
        printf "[INFO] TD_ROOT      : $TD_ROOT"
        printf "[INFO] COMMON_LIB   : $COMMON_LIB"
        printf "[INFO] CFG_FILE    : ${CFG_FILE:-<auto>}"
        print "[INFO] MODE        : ${ENUM_MODE:-<unset>}"
        printf "[INFO] Positional  : ${TD_POSITIONAL[*]:-<none>}"
        printf -- "Arguments / Flags:\n"

        local entry varname
        for entry in "${ARGS_SPEC[@]:-}"; do
            IFS='|' read -r name short type var help choices <<< "$entry"
            varname="${var}"
            printf "  --%s (-%s) : %s = %s\n" "$name" "$short" "$varname" "${!varname:-<unset>}"
        done

        printf -- "Positional args:\n"
        for arg in "${TD_POSITIONAL[@]:-}"; do
            printf "  %s\n" "$arg"
        done
    }
    main() {
        td_parse_args "$@"
        
        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi

    }

    # Run main with positional args only (not the options)
    main "$@"

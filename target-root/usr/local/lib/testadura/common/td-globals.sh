# =================================================================================
# Testadura — td-globals.sh
# ---------------------------------------------------------------------------------
# Purpose    : Definition of framework-wide global variables and defaults
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Declares the set of global variables used by the Testadura framework,
#   including default values and global variable name lists (system/user).
#
#   This file defines names and defaults only; it does not load configuration
#   files or apply runtime policy.
#
# Non-goals:
#   - Loading or parsing configuration files
#   - Runtime environment detection
#   - UI, logging, or side effects
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_GLOBALS_LOADED:-}" ]] && return 0
    TD_GLOBALS_LOADED=1

# --- Framwork info ---------------------------------------------------------------
    TD_PRODUCT="SolidgroundUX"
    TD_VERSION="1.1-beta"
    TD_VERSION_DATE="2026-01-08"
    TD_COMPANY="Testadura Consultancy"
    TD_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework settings (overridden by scripts when sourced) ---------------------  
    __define_default() {
        local name="$1"
        local value="$2"
        if [[ -z "${!name:-}" ]]; then
            printf -v "$name" '%s' "$value"
        fi
    }
    init_derived_paths() {
        # anchors must exist (even if default)
        __define_default TD_FRAMEWORK_ROOT "/"
        __define_default TD_APPLICATION_ROOT "/"

        # derived locations
        __define_default TD_COMMON_LIB  "$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common"
        __define_default TD_SYSCFG_DIR  "$TD_APPLICATION_ROOT/etc/testadura"
        __define_default TD_USRCFG_DIR  "$HOME/.config/testadura" # Usr config directory path
        __define_default TD_STATE_DIR   "$TD_APPLICATION_ROOT/var/testadura"

        # logs
        __define_default TD_LOG_PATH      "$TD_FRAMEWORK_ROOT/var/log/testadura/solidgroundux.log"
        __define_default TD_ALTLOG_PATH   "$HOME/.state/testadura/solidgroundux.log"
    }
    init_global_defaults() {
        __define_default TD_LOG_MAX_BYTES "$((25 * 1024 * 1024))" # 25 MiB
        __define_default TD_LOG_KEEP "20" # keep N rotated logs
        __define_default TD_LOG_COMPRESS "1" # gzip rotated logs (1/0)

        __define_default TD_LOGFILE_ENABLED "0"  # Enable logging to file (1=yes,0=no)
        __define_default TD_CONSOLE_MSGTYPES "STRT|WARN|FAIL|END"  # Enable logging to file (1=yes,0=no)

        __define_default SAY_DATE_DEFAULT "0" # 0 = no date, 1 = add date
        __define_default SAY_SHOW_DEFAULT "label" # label|icon|symbol|all|label,icon|...
        __define_default SAY_COLORIZE_DEFAULT "label" # none|label|msg|both|all|date
        __define_default SAY_DATE_FORMAT "%Y-%m-%d %H:%M:%S" # date format for --date
    }
    init_script_paths() {
        [[ -n "${TD_SCRIPT_NAME:-}" ]] || return 0
        __define_default TD_SYSCFG_FILE "$TD_SYSCFG_DIR/$TD_SCRIPT_NAME.cfg" # System config file path
        __define_default TD_USRCFG_FILE "$TD_USRCFG_DIR/$TD_SCRIPT_NAME.cfg" # User config file path
        __define_default TD_STATE_FILE  "$TD_STATE_DIR/$TD_SCRIPT_NAME.state" # State file path
    }

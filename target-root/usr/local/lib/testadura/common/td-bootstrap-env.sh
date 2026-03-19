# =================================================================================
# Testadura Consultancy — Bootstrap Environment Setup module
# ---------------------------------------------------------------------------------
# Module     : td-bootstrap-env.sh
# Purpose    : Bootstrap environment primitives (defaults, roots, derived paths)
#
# Scope:
#   - Defines framework identity metadata
#   - Defines framework-global configuration specifications (TD_FRAMEWORK_GLOBALS)
#   - Defines core library load order (TD_CORE_LIBS)
#   - Applies default values (td_apply_defaults / td_defaults_reset)
#   - Derives standard directory and file paths from root settings
#   - Prepares framework-level cfg path resolution
#
# Design:
#   - Pure bootstrap layer (no argument parsing, no UI, no logging policy)
#   - Idempotent and safe for repeated sourcing
#   - No side effects beyond variable initialization and path derivation
#
# Assumptions:
#   - Minimal shell environment; safe to source early in bootstrap
#   - Caller may run under sudo; TD_USER_HOME is derived accordingly
#
# Non-goals:
#   - Argument parsing (args layer)
#   - Configuration application (cfg/state layer)
#   - UI/logging behavior (ui modules)
#
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================
set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # __td_lib_guard
        # Purpose:
        #   Ensure the file is sourced as a library and only initialized once.
        #
        # Behavior:
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution if the file is executed instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Skips initialization if the library was already loaded.
        #
        # Inputs:
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals):
        #   TD_<MODULE>_LOADED
        #
        # Returns:
        #   0 if already loaded or successfully initialized.
        #   Exits with code 2 if executed instead of sourced.
        #
        # Usage:
        #   __td_lib_guard
        #
        # Examples:
        #   # Typical usage at top of library file
        #   __td_lib_guard
        #   unset -f __td_lib_guard
        #
        # Notes:
        #   - Guard variable is derived dynamically (e.g. ui-glyphs.sh → TD_UI_GLYPHS_LOADED).
        #   - Safe under `set -u` due to indirect expansion with default.
    __lib_base="$(basename "${BASH_SOURCE[0]}")"
    __lib_base="${__lib_base%.sh}"
    __lib_base="${__lib_base//-/_}"
    __lib_guard="TD_${__lib_base^^}_LOADED"

    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
        echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
        exit 2
    }

    # Load guard (safe under set -u)
    [[ -n "${!__lib_guard-}" ]] && return 0
    printf -v "$__lib_guard" '1'

# --- Framework identity ----------------------------------------------------------
    # Product/branding metadata used by framework-info, logging headers, and about text.
    TD_PRODUCT="SolidgroundUX"
    TD_VERSION="1.0-R2-beta"
    TD_VERSION_DATE="2026-01-08"
    TD_COMPANY="Testadura Consultancy"
    TD_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"
    TD_LICENSE_FILE="LICENSE"
    TD_LICENSE_ACCEPTED=0
    TD_README_FILE="README.md"

# --- Framework metadata ----------------------------------------------------------
    # TD_FRAMEWORK_GLOBALS spec format:
        #   audience|VARNAME|Human-readable description|extra
        #   - audience: system | user | both
        #   - extra: reserved for future metadata (currently unused)
    TD_FRAMEWORK_GLOBALS=(
        "system|TD_SYSCFG_DIR|Framework-wide system configuration directory|"
        "system|TD_DOCS_DIR|Framework-wide documentation directory|"
        "system|TD_LOGFILE_ENABLED|Enable or disable logfile output|"
        "both|TD_CONSOLE_MSGTYPES|Console message types to display|"          # <- both
        "system|TD_LOG_PATH|Primary log file or directory path|"
        "both|TD_ALTLOG_PATH|Alternate log path override|"                    # <- both
        "system|TD_LOG_MAX_BYTES|Maximum log file size before rotation|"
        "system|TD_LOG_KEEP|Number of rotated log files to retain|"
        "system|TD_LOG_COMPRESS|Compress rotated log files|"

        "user|TD_STATE_DIR|User-specific persistent state directory|"
        "user|TD_USRCFG_DIR|User-specific configuration directory|"

        "both|TD_UI_STYLE|Default UI style file (basename or path)|"          # <- both
        "both|TD_UI_PALETTE|Default UI palette file (basename or path)|"      # <- both

        "user|SAY_COLORIZE_DEFAULT|Default colorized console output setting|"
        "user|SAY_DATE_DEFAULT|Default timestamp visibility|"
        "user|SAY_SHOW_DEFAULT|Default console message visibility|"
        "user|SAY_DATE_FORMAT|Default date/time format for console output|"
    )

    # TD_CORE_LIBS:
        #   Core libraries sourced by td-bootstrap in this exact order.
        #   Ordering is part of the bootstrap contract.
    TD_CORE_LIBS=(
        args.sh
        framework-info.sh
        cfg.sh
        core.sh
        ui.sh
        ui-say.sh
        ui-ask.sh
        ui-dlg.sh
        ui-glyphs.sh
    )

    TD_FRAMEWORK_DIRS=(
    )
# --- Helpers ---------------------------------------------------------------------
    __build_framework_dirs(){
        TD_FRAMEWORK_DIRS=(
            "s|$TD_COMMON_LIB"
            "s|$TD_SYSCFG_DIR"
            "u|$TD_USRCFG_DIR"
            "u|$TD_STATE_DIR"
            "s|$TD_STYLE_DIR"
            "s|$TD_DOCS_DIR"
            "s|$(dirname "$TD_LOG_PATH")"
            "u|$(dirname "$TD_ALTLOG_PATH")"
        )
    }
# --- Public API ------------------------------------------------------------------
    # td_apply_defaults
        # Purpose:
        #   Apply default values for bootstrap globals if currently unset.
        #
        # Behavior:
        #   - Initializes root variables (TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT).
        #   - Sets logging and UI defaults.
        #   - Resolves TD_USER_HOME (prefers SUDO_USER when present).
        #   - Establishes framework cfg basename.
        #
        # Outputs (globals):
        #   TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT
        #   TD_USER_HOME
        #   TD_LOG_*, TD_LOGFILE_ENABLED, TD_LOG_TO_CONSOLE, TD_CONSOLE_MSGTYPES
        #   TD_UI_STYLE, TD_UI_PALETTE
        #   SAY_* defaults
        #   TD_FRAMEWORK_CFG_BASENAME
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_apply_defaults
        #
        # Examples:
        #   td_apply_defaults
        #
        #   # Override before applying defaults
        #   TD_LOGFILE_ENABLED=1
        #   td_apply_defaults
    td_apply_defaults() {
        : "${TD_FRAMEWORK_ROOT:=/}"
        : "${TD_APPLICATION_ROOT:=$TD_FRAMEWORK_ROOT}"

        : "${TD_LOG_MAX_BYTES:=$((25 * 1024 * 1024))}"
        : "${TD_LOG_KEEP:=20}"
        : "${TD_LOG_COMPRESS:=1}"

        : "${TD_LOGFILE_ENABLED:=0}"
        : "${TD_LOG_TO_CONSOLE:=1}"
        : "${TD_CONSOLE_MSGTYPES:=STRT|WARN|FAIL|INFO|END}"

        if [[ -n "${SUDO_USER:-}" ]]; then
            TD_USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        else
            TD_USER_HOME="$HOME"
        fi

        : "${TD_UI_STYLE:=default-ui-style.sh}"
        : "${TD_UI_PALETTE:=default-ui-palette.sh}"

        : "${SAY_DATE_DEFAULT:=0}"
        : "${SAY_SHOW_DEFAULT:=label}"
        : "${SAY_COLORIZE_DEFAULT:=label}"
        : "${SAY_DATE_FORMAT:=%Y-%m-%d %H:%M:%S}"

        : "${TD_FRAMEWORK_CFG_BASENAME:=td_framework_globals.cfg}"

    }

    # td_defaults_reset
        # Purpose:
        #   Reset all framework-global configuration variables to their default state.
        #
        # Behavior:
        #   - Iterates over TD_FRAMEWORK_GLOBALS specifications.
        #   - Extracts each declared variable name.
        #   - Unsets those variables (ignores unset failures).
        #   - Re-applies defaults via td_defaults_apply().
        #
        # Inputs (globals):
        #   TD_FRAMEWORK_GLOBALS
        #
        # Side effects:
        #   - Unsets variables declared in TD_FRAMEWORK_GLOBALS.
        #   - Reinitializes them according to td_defaults_apply().
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_defaults_reset
        #
        # Examples:
        #   td_defaults_reset
        #
        # Notes:
        #   - Intended for development/testing and controlled reinitialization.
        #   - TD_FRAMEWORK_GLOBALS is the authoritative list of resettable globals.
    td_defaults_reset() {
        local spec audience var desc extra
        for spec in "${TD_FRAMEWORK_GLOBALS[@]}"; do
            IFS='|' read -r audience var desc extra <<< "$spec"
            [[ -n "$var" ]] || continue
            unset "$var" || true
        done


        td_defaults_apply
    }

    # td_rebase_directories
        # Purpose:
        #   Derive standard framework directory and file paths from current root settings.
        #
        # Behavior:
        #   - Computes framework-scoped directories from:
        #       TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT, TD_USER_HOME
        #   - Derives logging paths.
        #   - Optionally derives script-scoped cfg/state paths when TD_SCRIPT_NAME is set.
        #   - Rebuilds TD_FRAMEWORK_DIRS via __build_framework_dirs.
        #
        # Inputs (globals):
        #   TD_FRAMEWORK_ROOT
        #   TD_APPLICATION_ROOT
        #   TD_USER_HOME
        #   TD_SCRIPT_NAME (optional)
        #
        # Outputs (globals):
        #   TD_COMMON_LIB, TD_SYSCFG_DIR, TD_USRCFG_DIR, TD_STATE_DIR
        #   TD_STYLE_DIR, TD_DOCS_DIR
        #   TD_LOG_PATH, TD_ALTLOG_PATH
        #   TD_SYSCFG_FILE, TD_USRCFG_FILE, TD_STATE_FILE (optional)
        #   TD_FRAMEWORK_DIRS
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_rebase_directories
        #
        # Examples:
        #   td_apply_defaults
        #   td_rebase_directories
        #
        #   TD_SCRIPT_NAME="install"
        #   td_rebase_directories
    td_rebase_directories() {
        saydebug "Rebasing directories"
        TD_COMMON_LIB="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common"
        TD_SYSCFG_DIR="$TD_APPLICATION_ROOT/etc/testadura"
        TD_USRCFG_DIR="$TD_USER_HOME/.config/testadura"
        TD_STATE_DIR="$TD_USER_HOME/.state/testadura"
        TD_STYLE_DIR="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/styles"
        TD_DOCS_DIR="$TD_FRAMEWORK_ROOT/usr/local/share/doc/solidgroundux"   # May be absent in dev/minimal installs

        # logs (paths only)
        TD_LOG_PATH="$TD_FRAMEWORK_ROOT/var/log/testadura/solidgroundux.log"
        TD_ALTLOG_PATH="$TD_USER_HOME/.log/testadura/solidgroundux.log"

        # script-scoped paths
        if [[ -n "${TD_SCRIPT_NAME:-}" ]]; then
            TD_SYSCFG_FILE="$TD_SYSCFG_DIR/$TD_SCRIPT_NAME.cfg"
            TD_USRCFG_FILE="$TD_USRCFG_DIR/$TD_SCRIPT_NAME.cfg"
            TD_STATE_FILE="$TD_STATE_DIR/$TD_SCRIPT_NAME.state"
        fi

        __build_framework_dirs
    }

    # td_rebase_framework_cfg_paths
        # Purpose:
        #   Derive framework-global cfg file paths from current cfg directories.
        #
        # Behavior:
        #   - Uses TD_FRAMEWORK_CFG_BASENAME as the filename.
        #   - Produces system and user cfg paths.
        #
        # Inputs (globals):
        #   TD_SYSCFG_DIR
        #   TD_USRCFG_DIR
        #   TD_FRAMEWORK_CFG_BASENAME
        #
        # Outputs (globals):
        #   TD_FRAMEWORK_SYSCFG_FILE
        #   TD_FRAMEWORK_USRCFG_FILE
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_rebase_framework_cfg_paths
        #
        # Examples:
        #   td_rebase_directories
        #   td_rebase_framework_cfg_paths
    td_rebase_framework_cfg_paths() {
        TD_FRAMEWORK_SYSCFG_FILE="$TD_SYSCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
        TD_FRAMEWORK_USRCFG_FILE="$TD_USRCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
    }

    # td_ensure_dirs
        # Purpose:
        #   Ensure that framework directories exist and have appropriate ownership.
        #
        # Arguments:
        #   One or more directory specifications:
        #       "s|/path"  system directory
        #       "u|/path"  user directory
        #
        # Behavior:
        #   - Creates directories using mkdir -p.
        #   - For user directories:
        #       - Assigns ownership to SUDO_USER when running under sudo.
        #       - Ensures user has read/write/execute permissions.
        #   - Ignores malformed entries.
        #
        # Inputs (globals):
        #   SUDO_USER
        #   EUID
        #
        # Returns:
        #   0   success
        #   1   failure creating one or more directories
        #
        # Usage:
        #   td_ensure_dirs "s|/path" "u|/path"
        #
        # Examples:
        #   td_ensure_dirs \
        #       "s|$TD_COMMON_LIB" \
        #       "s|$TD_SYSCFG_DIR" \
        #       "u|$TD_USRCFG_DIR" \
        #       "u|$TD_STATE_DIR"
    td_ensure_dirs() {
        local spec
        local kind
        local dir
        local owner=""

        if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            owner="$SUDO_USER"
        fi
        
        if [[ -n "$owner" ]]; then
            sayinfo "Creating directories for user-owned paths as $owner"
        else
            sayinfo "Creating framework directories"
        fi
        
        for spec in "$@"; do
            IFS='|' read -r kind dir <<< "$spec"
            [[ -z "$dir" ]] && continue

            sayinfo "Trying $dir"
            if [[ ! -d "$dir" ]]; then
                mkdir -p -- "$dir" || {
                    sayfail "Cannot create directory: $dir"
                    return 1
                }
            fi

            if [[ "$kind" == "u" ]]; then
                if [[ -n "$owner" ]]; then
                    sayinfo "Set owner"
                    chown "$owner:$owner" "$dir" 2>/dev/null || true
                fi
                sayinfo "Set user rights"

                chmod u+rwx "$dir" 2>/dev/null || true
            fi
        done
    }


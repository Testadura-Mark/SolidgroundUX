# =================================================================================
# Testadura Consultancy — lib-template.sh
# ---------------------------------------------------------------------------------
# Purpose    : Template for Testadura Bash libraries (header + guards + structure)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides a standard skeleton for Testadura framework libraries, including:
#   - Canonical header sections (purpose/description/contracts)
#   - "library only" execution guard (must be sourced, never executed)
#   - Load guard for idempotent sourcing
#   - Suggested naming conventions for internal/public functions
#
# Assumptions:
#   - None by default. Each library should explicitly document:
#       - Whether it is a CORE lib (no framework deps), or
#       - A FRAMEWORK lib (may assume framework/theme primitives exist).
#
# Design rules:
#   - Libraries define functions and constants only.
#   - No auto-execution (must be sourced).
#   - No `set -euo pipefail` or persistent shell-option changes.
#   - No path detection or root resolution (bootstrap owns path resolution).
#   - No global behavior changes (UI routing, logging policy, shell options).
#   - Safe to source multiple times (idempotent load guard).
#
# Non-goals:
#   - Executable scripts (use /bin tools or applets for entry points)
#   - User interaction unless explicitly part of a UI module
#   - Policy decisions (libraries provide mechanisms; callers decide policy)
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_BOOTSTRAP_ENV_LOADED:-}" ]] && return 0
    TD_BOOTSTRAP_ENV_LOADED=1

# --- Framework info ---------------------------------------------------------------
    TD_PRODUCT="SolidgroundUX"
    TD_VERSION="1.0-R2-beta"
    TD_VERSION_DATE="2026-01-08"
    TD_COMPANY="Testadura Consultancy"
    TD_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework metadata ------------------------------------------------------
   TD_FRAMEWORK_GLOBALS=(
        "system|TD_SYSCFG_DIR|Framework-wide system configuration directory|"

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


    TD_CORE_LIBS=(
        args.sh
        cfg.sh
        core.sh
        ui.sh
        ui-say.sh
        ui-ask.sh
        ui-dlg.sh
    )

# --- Public API ------------------------------------------------------------------
    # --- Defaults ---------------------------------------------------------------------
    td_defaults_apply() {
        : "${TD_FRAMEWORK_ROOT:=/}"
        : "${TD_APPLICATION_ROOT:=/}"

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

    td_defaults_reset() {
        local spec audience var desc extra
        for spec in "${TD_FRAMEWORK_GLOBALS[@]}"; do
            IFS='|' read -r audience var desc extra <<< "$spec"
            [[ -n "$var" ]] || continue
            unset "$var" || true
        done


        td_defaults_apply
    }

    # --- Rebase directories ----------------------------------------------------------
        # Compute all directory and file path globals from the current root settings.
        # Call this after TD_FRAMEWORK_ROOT / TD_APPLICATION_ROOT / TD_USER_HOME are set.
    td_rebase_directories() {
        TD_COMMON_LIB="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common"
        TD_SYSCFG_DIR="$TD_APPLICATION_ROOT/etc/testadura"
        TD_USRCFG_DIR="$TD_USER_HOME/.config/testadura"
        TD_STATE_DIR="$TD_APPLICATION_ROOT/var/lib/testadura"
        TD_STYLE_DIR="$TD_COMMON_LIB/styles"

        # logs (paths only)
        TD_LOG_PATH="$TD_FRAMEWORK_ROOT/var/log/testadura/solidgroundux.log"
        TD_ALTLOG_PATH="$TD_USER_HOME/.log/testadura/solidgroundux.log"

        # script-scoped paths
        if [[ -n "${TD_SCRIPT_NAME:-}" ]]; then
            TD_SYSCFG_FILE="$TD_SYSCFG_DIR/$TD_SCRIPT_NAME.cfg"
            TD_USRCFG_FILE="$TD_USRCFG_DIR/$TD_SCRIPT_NAME.cfg"
            TD_STATE_FILE="$TD_STATE_DIR/$TD_SCRIPT_NAME.state"
        fi
    }
    # td_rebase_framework_cfg_paths
        #   Derive the framework-global cfg file paths from the already rebased cfg dirs.
        #   These cfg files are framework-scoped (not script-scoped) and always use the
        #   fixed basename $TD_FRAMEWORK_CFG_BASENAME.
        #
        # Outputs (globals):
        #   TD_FRAMEWORK_SYSCFG_FILE
        #   TD_FRAMEWORK_USRCFG_FILE
    td_rebase_framework_cfg_paths() {
        TD_FRAMEWORK_SYSCFG_FILE="$TD_SYSCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
        TD_FRAMEWORK_USRCFG_FILE="$TD_USRCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
    }

    # td_load_bootstrap_cfg
    # Locate, optionally create, and source the bootstrap configuration file.
    #
    # Purpose:
    #   - Establish TD_FRAMEWORK_ROOT and TD_APPLICATION_ROOT early
    #   - Support dev-tree (target-root) execution without installer
    #
    td_load_bootstrap_cfg() {
        local self_path
        local target_root
        local cfg

        self_path="$(readlink -f "${BASH_SOURCE[1]}")"

        # --- Dev-tree detection (target-root) -------------------------------
        if [[ "$self_path" == */target-root/* ]]; then
            target_root="${self_path%%/target-root/*}/target-root"
        elif [[ "$self_path" == */target-root ]]; then
            target_root="$self_path"
        fi

        if [[ -n "${target_root:-}" ]]; then
            cfg="$target_root/usr/local/lib/testadura/solidgroundux.cfg"

            if [[ ! -r "$cfg" ]]; then
                if [[ $EUID -eq 0 ]]; then
                    mkdir -p "$(dirname "$cfg")" || return 127
                    printf '%s\n' \
                        "# SolidgroundUX bootstrap configuration" \
                        "# Auto-created for dev target-root" \
                        "TD_FRAMEWORK_ROOT=/" \
                        "TD_APPLICATION_ROOT=$target_root" \
                        >"$cfg"
                else
                    printf "ERR: Missing bootstrap cfg: %s\n" "$cfg" >&2
                    return 126
                fi
            fi
        else
            # Installed system default
            cfg="/usr/local/lib/testadura/solidgroundux.cfg"
        fi

        if [[ -r "$cfg" ]]; then
            # shellcheck source=/dev/null
            source "$cfg"
        else
            printf "ERR: Cannot read bootstrap cfg: %s\n" "$cfg" >&2
            return 126
        fi
    }



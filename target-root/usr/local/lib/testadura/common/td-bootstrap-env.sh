# =================================================================================
# Testadura — td-bootstrap-env.sh
# ---------------------------------------------------------------------------------
# Purpose    : Bootstrap environment primitives (defaults, roots, derived paths)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides the earliest bootstrap environment layer used by td-bootstrap.sh.
#   Responsibilities:
#   - Defines framework identity metadata (product/version/license filenames)
#   - Defines the framework-global cfg metadata specs (TD_FRAMEWORK_GLOBALS)
#   - Defines core library load order (TD_CORE_LIBS)
#   - Establishes default values (td_defaults_apply / td_defaults_reset)
#   - Derives standard directory and file paths from root settings
#   - Locates and sources the bootstrap cfg (solidgroundux.cfg), supporting dev-tree
#
# Assumptions:
#   - Minimal shell environment; safe to source early in bootstrap.
#   - Caller may be running under sudo; TD_USER_HOME is derived accordingly.
#
# Design rules / Contract:
#   - No user interaction (no prompts/dialogs).
#   - No persistent shell-option changes (no set -euo pipefail; no shopt).
#   - Safe to source multiple times (idempotent load guard).
#   - Path derivation is purely from current globals (roots/user home/script name).
#
# Non-goals:
#   - Argument parsing (handled by bootstrap + args layer)
#   - Configuration domain application (handled by cfg/state layer)
#   - Logging/UI policy decisions (handled by ui-say/ui modules)
# =================================================================================

# --- Library guard ---------------------------------------------------------------
    # Derive a unique per-library guard variable from the filename:
    #   ui.sh        -> TD_UI_LOADED
    #   ui-sgr.sh    -> TD_UI_SGR_LOADED
    #   foo-bar.sh   -> TD_FOO_BAR_LOADED
    # Note:
    #   Guard variables (__lib_*) are internal globals by convention; they are not part
    #   of the public API and may change without notice.
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
        # audience|VARNAME|Human-readable description|extra
        # Where audience is one of: system | user | both
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
    TD_CORE_LIBS=(
        args.sh
        framework-info.sh
        cfg.sh
        core.sh
        ui.sh
        ui-say.sh
        ui-ask.sh
        ui-dlg.sh
    )

# --- Public API ------------------------------------------------------------------
    # td_defaults_apply
        # Apply default values for bootstrap globals if they are currently unset.
        #
        # Notes:
        #   - Does not overwrite values already set by the caller or bootstrap cfg.
        #   - Derives TD_USER_HOME from SUDO_USER when available.
        #
        # Outputs (globals):
        #   Sets default values for logging, UI style/palette, and framework cfg basename.
        #
        # Returns:
        #   Always 0.
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

    # td_defaults_reset
        # Clear all variables declared in TD_FRAMEWORK_GLOBALS, then re-apply defaults.
        #
        # Notes:
        #   - Uses TD_FRAMEWORK_GLOBALS as the authoritative list of resettable globals.
        #   - Intended for development/testing and controlled reinitialization.
        #
        # Returns:
        #   Always 0.

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
        # Derive standard directory and file paths from current root settings.
        #
        # Call after:
        #   - TD_FRAMEWORK_ROOT / TD_APPLICATION_ROOT are set (bootstrap cfg)
        #   - TD_USER_HOME is set (td_defaults_apply)
        #   - TD_SCRIPT_NAME is set (entry script), if script-scoped files are desired
        #
        # Outputs (globals):
        #   Directories:
        #     TD_COMMON_LIB, TD_SYSCFG_DIR, TD_USRCFG_DIR, TD_STATE_DIR,
        #     TD_STYLE_DIR, TD_DOCS_DIR
        #   Logging paths:
        #     TD_LOG_PATH, TD_ALTLOG_PATH
        #   Script-scoped paths (only if TD_SCRIPT_NAME is set):
        #     TD_SYSCFG_FILE, TD_USRCFG_FILE, TD_STATE_FILE
    td_rebase_directories() {
        TD_COMMON_LIB="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common"
        TD_SYSCFG_DIR="$TD_APPLICATION_ROOT/etc/testadura"
        TD_USRCFG_DIR="$TD_USER_HOME/.config/testadura"
        TD_STATE_DIR="$TD_USER_HOME/.state/testadura"
        TD_STYLE_DIR="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/styles"
        TD_DOCS_DIR="$TD_FRAMEWORK_ROOT/usr/local/share/solidgroundux"   # May be absent in dev/minimal installs

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
        #   Derive the framework-global cfg file paths from the current cfg dirs.
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
        local target_root="/"
        local cfg

        # BASH_SOURCE[1] is the caller (typically td-bootstrap.sh), not this library.
        self_path="$(readlink -f "${BASH_SOURCE[1]}")"

        # Dev-tree detection (target-root) -------------------------------
        if [[ "$self_path" == */target-root/* ]]; then
            target_root="${self_path%%/target-root/*}/target-root"
        elif [[ "$self_path" == */target-root ]]; then
            target_root="$self_path"
        fi
        sayinfo "$target_root $self_path"
        if [[ -n "${target_root:-}" ]]; then
            cfg="$target_root/usr/local/lib/testadura/solidgroundux.cfg"
            sayinfo "$cfg"
            if [[ ! -r "$cfg" ]]; then
                sayinfo "doesn't exists $cfg, should create one $EUID" 
                if [[ $EUID -eq 0 ]]; then
                    sayinfo "creating one $EUID"
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



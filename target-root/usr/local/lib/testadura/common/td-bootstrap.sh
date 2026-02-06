# =================================================================================
# Testadura — td-bootstrap.sh
# ---------------------------------------------------------------------------------
# Purpose    : Framework bootstrap and library load orchestration
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Initializes the Testadura framework environment by:
#   - Resolving base paths (framework root / application root)
#   - Establishing core framework invariants (env vars, directories, defaults)
#   - Sourcing required libraries in a defined, layered order
#
#   This file defines what it means to run inside a "framework context".
#
# Assumptions:
#   - None. Bootstrap is the starting point and must tolerate a minimal shell.
#
# Design rules / Contract:
#   - Owns all path resolution and library load order.
#   - Sources libraries in layers (core → theme → ui → say/ask/dlg → args → etc.).
#   - Performs environment sanity checks only (existence, permissions, commands).
#   - Must remain thin: no reusable helpers live here (libraries own helpers).
#   - No application logic or policy decisions.
#   - No user interaction (no ask/confirm/dialogs); output should be minimal.
#
# Non-goals:
#   - Argument parsing (handled by args layer)
#   - Configuration loading (handled by cfg/state layer)
#   - Script execution or control flow (entry scripts/applications own this)
# =================================================================================

# --- Validate use ----------------------------------------------------------------
# Refuse to execute (library only)
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
  exit 2
}

# Load guard
[[ -n "${TD_BOOTSTRAP_LOADED:-}" ]] && return 0
TD_BOOTSTRAP_LOADED=1

# Framwork root
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-}"
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-}" # Application root (where this script is deployed)    
    
    TD_FRAMEWORK_CFG_BASENAME="td_framework_globals.cfg"

# Minimal colors
    MSG_CLR_INFO=$'\e[38;5;250m'
    MSG_CLR_STRT=$'\e[38;5;82m'
    MSG_CLR_OK=$'\e[38;5;82m'
    MSG_CLR_WARN=$'\e[1;38;5;208m'
    MSG_CLR_FAIL=$'\e[38;5;196m' 
    MSG_CLR_CNCL=$'\e[0;33m'
    MSG_CLR_END=$'\e[38;5;82m'
    MSG_CLR_EMPTY=$'\e[2;38;5;250m'
    MSG_CLR_DEBUG=$'\e[1;35m'

    TUI_COMMIT=$'\e[2;37m'
    RESET=$'\e[0m'
# --- Minimal fallback UI (overridden by ui.sh when sourced) -----------------
    saystart()   { printf '%sSTART%s\t%s\n' "${MSG_CLR_STRT-}" "${RESET-}" "$*" >&2; }
    sayinfo()    { printf '%sINFO%s \t%s\n' "${MSG_CLR_INFO-}" "${RESET-}" "$*" >&2; }
    sayok()      { printf '%sOK%s   \t%s\n' "${MSG_CLR_OK-}"   "${RESET-}" "$*" >&2; }
    saywarning() { printf '%sWARN%s \t%s\n' "${MSG_CLR_WARN-}" "${RESET-}" "$*" >&2; }
    sayfail()    { printf '%sFAIL%s \t%s\n' "${MSG_CLR_FAIL-}" "${RESET-}" "$*" >&2; }
    saydebug() {
        if (( ${FLAG_DEBUG:-0} )); then
            printf '%sDEBUG%s \t%s\n' "${MSG_CLR_DBG-}" "${RESET-}" "$*" >&2;
        fi
    }
    saycancel() { printf '%sCANCEL%s\t%s\n' "${MSG_CLR_CAN-}" "${RESET-}" "$*" >&2; }
    sayend() { printf '%sEND%s   \t%s\n' "${MSG_CLR_END-}" "${RESET-}" "$*" >&2; }
    sayerror() { printf '%sERR%s   \t%s\n' "${MSG_CLR_ERR-}" "${RESET-}" "$*" >&2; }

# --- Framework metadata ------------------------------------------------------


# --- Helper functions -------------------------------------------------------
    # --- Rebase directories ----------------------------------------------------------
        # Compute all directory and file path globals from the current root settings.
        # Call this after TD_FRAMEWORK_ROOT / TD_APPLICATION_ROOT / TD_USER_HOME are set.
    __rebase_directories() {
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
    __rebase_framework_cfg_paths() {
        TD_FRAMEWORK_SYSCFG_FILE="$TD_SYSCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
        TD_FRAMEWORK_USRCFG_FILE="$TD_USRCFG_DIR/$TD_FRAMEWORK_CFG_BASENAME"
    }

    # --- Default settings ------------------------------------------------------------
        # Define default non-path settings (logging, output behaviour, etc.)
        # These values may be overridden by configuration.
    __default_settings() {
        # --- User context ---------------------------------------------------------------
            # Home directory of the invoking (non-sudo) user.
            # When running under sudo, prefer the original user's HOME.
        if [[ -n "${SUDO_USER:-}" ]]; then
            TD_USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        else
            TD_USER_HOME="$HOME"
        fi

        # logging behaviour
        TD_LOG_MAX_BYTES="$((25 * 1024 * 1024))"   # 25 MiB
        TD_LOG_KEEP="20"                           # keep N rotated logs
        TD_LOG_COMPRESS="1"                        # gzip rotated logs (1/0)

        TD_LOGFILE_ENABLED="0"                     # log to file (1=yes,0=no)
        TD_LOG_TO_CONSOLE="1"                      # log to console (1=yes,0=no)
        TD_CONSOLE_MSGTYPES="STRT|WARN|FAIL|INFO|END"
        
        TD_UI_STYLE="${TD_UI_STYLE:-default-ui-style.sh}"
        TD_UI_PALETTE="${TD_UI_PALETTE:-default-ui-palette.sh}"

        # SAY defaults
        SAY_DATE_DEFAULT="0"                       # add date (1=yes,0=no)
        SAY_SHOW_DEFAULT="label"                   # label|icon|symbol|all|...
        SAY_COLORIZE_DEFAULT="label"               # none|label|msg|both|all|date
        SAY_DATE_FORMAT="%Y-%m-%d %H:%M:%S"
    }


# --- Main sequence functions ------------------------------------------------        
    # __parse_bootstrap_args
        # Parse framework-level (bootstrap) command-line switches.
        #
        # This function scans the command line for bootstrap options that control
        # framework initialization and execution constraints. Parsing stops at the
        # first non-bootstrap argument or at the explicit "--" separator.
        #
        # Behavior:
            #   - Recognized bootstrap switches set internal execution selectors (exe_*),
            #     framework flags, or logging options.
            #   - All remaining arguments (after "--" or after the first unknown option)
            #     are collected verbatim into TD_BOOTSTRAP_REST and left untouched.
            #   - Script-specific arguments are *not* validated or interpreted here.
            #
        # Parsing rules:
            #   - Bootstrap options must appear before script arguments.
            #   - Encountering "--" explicitly ends bootstrap parsing.
            #   - Encountering any unknown option implicitly ends bootstrap parsing.
            #
        # Recognized bootstrap switches:
            #   --ui
            #       Enable UI initialization (sets exe_ui=1).
            #
            #   --state
            #       Enable loading of persistent state (sets exe_state=1).
            #
            #   --cfg
            #       Enable loading of configuration files (sets exe_cfg=1).
            #
            #   --needroot
            #       Enforce execution as root (sets exe_root=1).
            #
            #   --cannotroot
            #       Enforce execution as non-root (sets exe_root=2).
            #
            #   --args
            #       Enable parsing of script arguments (sets exe_args=1).
            #       Included for symmetry; script arg parsing is enabled by default.
            #
            #   --log
            #       Enable logging to file (sets TD_LOGFILE_ENABLED=1).
            #
            #   --console
            #       Enable logging to console output (sets TD_LOG_TO_CONSOLE=1).
            #
            #   --
            #       Explicit end of bootstrap options. All remaining arguments are treated
            #       as script arguments and copied into TD_BOOTSTRAP_REST.
        #
        # Outputs (globals):
            #   exe_ui, exe_libs, exe_state, exe_cfg, exe_args, exe_root
            #       Execution selectors used by td_bootstrap to control initialization.
            #
            #   TD_BOOTSTRAP_REST
            #       Array containing all script arguments (post-bootstrap), preserved
            #       exactly as received.
            #
            # Return value:
            #   Always returns 0. Errors are not raised here; validation is deferred to
            #   later bootstrap stages.
            #
        # Notes:
            #   - This function does not enforce ordering or validity of script arguments.
            #   - Bootstrap parsing is intentionally permissive to allow scripts to define
            #     their own argument syntax without interference.
    __parse_bootstrap_args() {
        exe_ui=0
        exe_libs=1
        exe_state=0
        exe_cfg=0
        exe_args=1
        exe_root=0

        TD_BOOTSTRAP_REST=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --ui)        exe_ui=1; shift ;;
                --state)     exe_state=1; shift ;;
                --needroot)  exe_root=1; shift ;;
                --cannotroot)exe_root=2; shift ;;
                --log)       TD_LOGFILE_ENABLED=1; shift ;;
                --console)   TD_LOG_TO_CONSOLE=1; shift ;; 
                --) shift; TD_BOOTSTRAP_REST=("$@"); return 0 ;;
                *) TD_BOOTSTRAP_REST=("$@"); return 0 ;;
            esac
        done
    }

    # __init_bootstrap
        # Initialize the SolidgroundUX bootstrap environment.
        #
        # Responsibilities:
            #   - Resolve the absolute path of td-bootstrap.sh (this file).
            #   - Locate the bootstrap configuration file that lives beside it.
            #   - Create a minimal bootstrap configuration if none exists.
            #   - Establish the initial framework/application roots used for further setup.
        #
        # Bootstrap configuration:
            #   - The file "solidgroundux.cfg" is expected to reside in the same directory
            #     as td-bootstrap.sh.
            #   - This file is the *earliest* configuration source and is loaded before
            #     any framework libraries or domain-specific configuration.
        #
        # Auto-creation behavior:
            #   - If the bootstrap configuration file does not exist, a minimal template
            #     is created in-place.
            #   - Auto-created defaults set:
            #       TD_FRAMEWORK_ROOT=/
            #       TD_APPLICATION_ROOT=/
            #   - Creation failures are considered fatal.
        #
        # Execution model:
            #   - This function may be executed more than once across process boundaries
            #     when root escalation is required (e.g. via need_root + exec sudo).
            #   - Each execution is isolated to its process; no state is shared between
            #     pre- and post-escalation runs.
        #
        # Design notes:
            #   - No directory probing or upward traversal is performed.
            #   - No user interaction or policy decisions occur here.
            #   - This function must be safe to call multiple times per process
            #     (idempotent by construction).
        #
        # Failure handling:
            #   - Failure to create or source the bootstrap configuration is fatal and
            #     aborts bootstrap immediately.
            #
    __init_bootstrap() {
       
        : "${TD_FRAMEWORK_ROOT:=/}"
        : "${TD_APPLICATION_ROOT:=/}"

        __load_bootstrap_cfg

        __rebase_directories
        __rebase_framework_cfg_paths
        
        saydebug "Sourcing $TD_COMMON_LIB/td-globals.sh"
        source "$TD_COMMON_LIB/td-globals.sh"

    }

    # __load_bootstrap_cfg
    # Locate, optionally create, and source the bootstrap configuration file.
    #
    # Purpose:
    #   - Establish TD_FRAMEWORK_ROOT and TD_APPLICATION_ROOT early
    #   - Support dev-tree (target-root) execution without installer
    #
    __load_bootstrap_cfg() {
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


    td_load_ui_style() {
        local style_path palette_path

        style_path="$TD_UI_STYLE"
        palette_path="$TD_UI_PALETTE"

        # If values are basenames, resolve from TD_STYLE_DIR
        [[ "$style_path" == */* ]] || style_path="$TD_STYLE_DIR/$style_path"
        [[ "$palette_path" == */* ]] || palette_path="$TD_STYLE_DIR/$palette_path"

        [[ -r "$palette_path" ]] || { saywarning "Palette not found: $palette_path"; return 1; }
        [[ -r "$style_path"   ]] || { saywarning "Style not found: $style_path";   return 1; }

        # shellcheck source=/dev/null
        source "$palette_path"
        # shellcheck source=/dev/null
        source "$style_path"
    }

    # __source_corelibs
        # Source all core framework libraries required for normal operation.
        #
        # This function iterates over the list of core library filenames defined in
        # TD_CORE_LIBS and sources each one from TD_COMMON_LIB.
        #
        # Behavior:
        #   - Libraries are sourced in the order specified by TD_CORE_LIBS.
        #   - Each library is expected to define functions, globals, or defaults used
        #     throughout the framework.
        #   - No validation or dependency resolution is performed here; ordering and
        #     completeness are assumed to be correct.
        #
        # Assumptions:
        #   - TD_COMMON_LIB is already set and points to the framework library directory.
        #   - TD_CORE_LIBS contains relative filenames (not absolute paths).
        #   - Missing or failing libraries will cause the script to terminate via
        #     standard shell error handling unless caught by the caller.
        #
        # Notes:
        #   - shellcheck warnings for dynamic sourcing are intentionally suppressed.
        #   - This function is typically called from td_bootstrap after globals have
        #     been initialized and before any framework functionality is used.
    __source_corelibs(){
        saydebug "Loading core libraries..."  
        __rebase_directories

        local lib path
        for lib in "${TD_CORE_LIBS[@]}"; do
            path="$TD_COMMON_LIB/$lib"
            # shellcheck source=/dev/null
            source "$path"
        done
    }


    
# --- Public API -------------------------------------------------------------
    # td_bootstrap
        # Initialize the Testadura runtime context for the current script.
        #
        # What it does:
        #   - Parse bootstrap selectors (UI/state/root constraints)
        #   - Load bootstrap cfg (roots), rebase derived paths
        #   - Source globals (td-globals.sh), then core libraries (TD_CORE_LIBS)
        #   - Apply framework cfg domain, then parse builtins/script args as configured
        #
        # Contract:
        #   - Must not call framework helpers before corelibs are sourced.
        #   - Bootstrap cfg establishes TD_FRAMEWORK_ROOT / TD_APPLICATION_ROOT.
        #   - Builtin flags are detected here but executed by the caller script.
        #
        # Returns: 0 on success; non-zero on fatal initialization failure.
    td_bootstrap() {

        # Definitions
            : "${TUI_COMMIT:=$(printf '\e[38;5;130m')}"
            : "${TUI_DRYRUN:=$(printf '\e[38;5;245m')}"
            : "${RESET:=$(printf '\e[0m')}"
            : "${RUN_MODE:="${TUI_COMMIT}COMMIT${RESET}"}"
            : "${FLAG_DEBUG:=0}"
            : "${FLAG_DRYRUN:=0}"
            : "${FLAG_VERBOSE:=0}"
            : "${FLAG_STATERESET:=0}"
            : "${FLAG_INIT_CONFIG:=0}"
            : "${FLAG_SHOWARGS:=0}"
            : "${FLAG_HELP:=0}"

            __boot_fail() {
                local msg="${1:-Bootstrap step failed}"
                local rc="${2:-1}"

                sayerror "$msg"
                return "$rc"
            }

        # Basic initialization - Defaults 
            __default_settings  
            
            saydebug "Parsing bootstrap arguments..."
            __parse_bootstrap_args "$@" || __boot_fail "Failed parsing bootstrap arguments" 

            saydebug "Initializing bootstrap..."
            __init_bootstrap || __boot_fail "Failed to initialize bootstrapper" $?   

            saydebug "Loading core libraries"
            __source_corelibs || __boot_fail "Failed to load core libraries" $?
            
            td_load_ui_style

        # Load Framework globals
            td_cfg_domain_apply "Framework" "$TD_FRAMEWORK_SYSCFG_FILE" "$TD_FRAMEWORK_USRCFG_FILE" "TD_FRAMEWORK_GLOBALS" "framework"
       
        # Parse builtin arguments early
            td_parse_args builtins "${TD_BOOTSTRAP_REST[@]}" || __boot_fail "Error parsing builtins" $?
            TD_BOOTSTRAP_REST=( "${TD_POSITIONAL[@]}" )

        # Final basic settings       
            td_update_runmode || __boot_fail "Error setting RUN_MODE" $?  
     
        saydebug "Applying options"
        # Options
            # If you want ui, init after libs (unless ui_init is dependency-free)
            if (( exe_ui )); then
                ui_init || __boot_fail "ui_init failed" $?
            fi

            # Root checks (after libs so need_root exists)
            if (( exe_root == 1 )); then
                need_root "${TD_BOOTSTRAP_REST[@]}" || __boot_fail "Failed to enable need_root" $?
            fi

            if (( exe_root == 2 )); then
                cannot_root "${TD_BOOTSTRAP_REST[@]}" || __boot_fail "Failed to enable cannot_root" $?
            fi

            # Reset statefile before it;s loaded if requested
            if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
                td_state_reset
                sayinfo "State file reset as requested."
            fi    

            # Load state and parse *script* args
            if (( exe_state )); then
                td_state_load || __boot_fail "State load failed" $?
            fi

        if (( ${#TD_SCRIPT_GLOBALS[@]} > 0 )); then
            td_cfg_domain_apply "Script" "$TD_SYSCFG_FILE" "$TD_USRCFG_FILE" "TD_SCRIPT_GLOBALS" || __boot_fail "CFG load failed" $?
        fi

        # Always parse script args if the script defines any arg specs
        if (( ${#TD_ARGS_SPEC[@]} > 0 )); then
            td_parse_args script "${TD_BOOTSTRAP_REST[@]}" || __boot_fail "Error parsing script args" $?
            TD_BOOTSTRAP_REST=( "${TD_POSITIONAL[@]}" )
        fi

        td_update_runmode

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            saydebug "Running in $RUN_MODE mode (no changes will be made)."
        else
            saydebug "Running in $RUN_MODE mode (changes will be applied)."
        fi
        return 0
    }





         
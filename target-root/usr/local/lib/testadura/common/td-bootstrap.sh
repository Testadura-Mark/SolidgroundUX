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
        if (( ${FLAG_VERBOSE:-0} )); then
            printf '%sDEBUG%s \t%s\n' "${MSG_CLR_DBG-}" "${RESET-}" "$*" >&2;
        fi
    }
    saycancel() { printf '%sCANCEL%s\t%s\n' "${MSG_CLR_CAN-}" "${RESET-}" "$*" >&2; }
    sayend() { printf '%sEND%s   \t%s\n' "${MSG_CLR_END-}" "${RESET-}" "$*" >&2; }
    sayok() { printf '%sOK%s    \t%s\n' "${MSG_CLR_OK-}" "${RESET-}" "$*" >&2; }
    sayinfo() { printf '%sINFO%s  \t%s\n' "${MSG_CLR_INFO-}" "${RESET-}" "$*" >&2; }
    sayerror() { printf '%sERR%s   \t%s\n' "${MSG_CLR_ERR-}" "${RESET-}" "$*" >&2; }

# --- Loading libraries from TD_COMMON_LIB -----------------------------------
    td_source_libs() {
        local lib path
        saystart "Sourcing libraries from: $TD_COMMON_LIB" 

        for lib in "${TD_USING[@]}"; do
            path="$TD_COMMON_LIB/$lib"

            if [[ -f "$path" ]]; then
                #sayinfo "Using library: $path" >&2
                # shellcheck source=/dev/null
                source "$path"
                continue
            fi

            # core.sh is required
            if [[ "$lib" == "core.sh" ]]; then
                sayfail "Required library not found: $path" 
                echo "Cannot continue without core library." >&2
                exit 2
            fi

            saywarning "Library not found (optional): $path" 
        done

        sayend "All libraries sourced." 
    }

# --- Framework metadata ------------------------------------------------------
        TD_SYS_GLOBALS=(
            TD_SYSCFG_DIR
            TD_SYSCFG_FILE
            TD_LOGFILE_ENABLED
            TD_CONSOLE_MSGTYPES
            TD_LOG_PATH
            TD_ALTLOG_PATH
            TD_LOG_MAX_BYTES
            TD_LOG_KEEP
            TD_LOG_COMPRESS
        )
        TD_USR_GLOBALS=(
            TD_STATE_DIR
            TD_USRCFG_DIR
            TD_USRCFG_FILE
            TD_CONSOLE_MSGTYPES
            SAY_COLORIZE_DEFAULT
            SAY_DATE_DEFAULT
            SAY_SHOW_DEFAULT
            SAY_DATE_FORMAT
        )
        TD_CORE_LIBS=(
            args.sh
            cfg.sh
            core.sh
            ui.sh
            ui-say.sh
            ui-ask.sh
            ui-dlg.sh
            default-colors.sh
            default-styles.sh
        )
        TD_SCRIPT_SETTINGS=(
        )
# --- Helper functions -------------------------------------------------------
    __create_cfg_template() {
        if [[ "${FLAG_INIT_CONFIG:-0}" -ne 1 ]]; then
            saydebug "Init config flag is off"
            return 0
        fi

        local dir="$1"
        local filename="$2"
        local template_fn="$3"
        local dirmode="${4:-0755}"
        local filemode="${5:-0644}"

        if [[ -z "$dir" || -z "$filename" || -z "$template_fn" ]]; then
            sayerror "__create_cfg_template: missing arguments" >&2
            return 1
        fi

        if ! declare -F "$template_fn" >/dev/null; then
            sayerror "__create_cfg_template: template not found: $template_fn" >&2
            return 2
        fi

        install -d -m "$dirmode" "$dir" || return 3

        local path="$dir/$filename"

        "$template_fn" > "$path" || return 4
        chmod "$filemode" "$path" || return 5

        sayok "Wrote config: $path"
        return 0
    }

    __source_systemoruser() {
        local cfg_file="$1"          # e.g. solidgroundux.cfg
        local cfg_create="${2:-0}"   # 0/1
        local template_fn="${3:-}"   # e.g. __create_cfg_template
        local sysdir="${TD_SYSCFG_DIR:-$TD_APPLICATION_ROOT/etc/testadura}"
        local usrdir="${TD_USRCFG_DIR:-$HOME/.config/testadura}"
        local cfg_source=0
        local user_cfg=""

        # --- system cfg ---
        if [[ -r "$sysdir/$cfg_file" ]]; then
            # shellcheck disable=SC1090
            source "$sysdir/$cfg_file"
            cfg_source=1
        fi

        # --- optional user cfg (dev override) ---
        if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
            user_cfg="$usrdir/$cfg_file"
            if [[ -r "$user_cfg" ]]; then
                # shellcheck disable=SC1090
                source "$user_cfg"
                cfg_source=2
            fi
        fi

        # --- create if requested and none found ---
        if (( cfg_create == 1 )) && (( cfg_source == 0 )); then
            if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "Would have created system config $sysdir/$cfg_file"
                else
                    __create_cfg_template \
                        "$sysdir" \
                        "$cfg_file" \
                        "$template_fn"
                    saydebug "created system config $sysdir/$cfg_file"
                fi
            else
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "Would have created user config $usrdir/$cfg_file"
                else
                    __create_cfg_template \
                        "$usrdir" \
                        "$cfg_file" \
                        "$template_fn"
                        saydebug "created user config $usrdir/$cfg_file"
                fi
            fi
        fi

        return 0
    }

 # -- Template cfg files   
    __print_sysglobals_cfg(){
        local var
        printf '%s\n' "# Framework globals system only globals and settings"
        
        # Build lookup table for user globals
        local -A _usr
        for var in "${TD_USR_GLOBALS[@]}"; do
            _usr["$var"]=1
        done

        # Emit only SYS globals not present in USR globals
        for var in "${TD_SYS_GLOBALS[@]}"; do
            [[ -n "${_usr[$var]:-}" ]] && continue

            if [[ -v "$var" ]]; then
                printf '%s=%q\n' "$var" "${!var}"
            else
                printf '# %s is unset\n' "$var"
            fi
        done
        printf "\n"
        __print_usrglobals_cfg
    }
    __print_usrglobals_cfg(){
        local var
        printf '%s\n' "# User overridable globals and settings"
        for var in "${TD_USR_GLOBALS[@]}"; do
            if [[ -v "$var" ]]; then
                printf '%s=%q\n' "$var" "${!var}"
            else
                printf '# %s is unset\n' "$var"
            fi
        done
    }
    __print_bootstrap_cfg() {
        printf "%s\n" "# SolidgroundUX bootstrap configuration"
        printf "%s\n" "# Purpose: allow locating the framework + application roots."
        printf "%s\n" "# Values below mirror derived defaults at source-time."
        printf "%s\n" "# Override by editing this file if needed."
        printf "%s\n" ""

        printf 'TD_FRAMEWORK_ROOT=%q\n' "$TD_FRAMEWORK_ROOT"
        printf 'TD_APPLICATION_ROOT=%q\n' "$TD_APPLICATION_ROOT"
        printf "%s\n" ""

        printf "%s\n" "# Initially derived, but overridable here"

        printf 'TD_COMMON_LIB=%q\n' "${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}" 
        printf 'TD_SYSCFG_DIR=%q\n' "${TD_SYSCFG_DIR:-$TD_APPLICATION_ROOT/etc/testadura}"
        printf 'TD_USRCFG_DIR=%q\n' "${TD_USRCFG_DIR:-$HOME/.config/testadura}"
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
            #   --initcfg
            #       Allow creation of missing config templates during bootstrap
            #       (sets FLAG_INIT_CONFIG=1).
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
                --cfg)       exe_cfg=1; shift ;;
                --needroot)  exe_root=1; shift ;;
                --cannotroot)exe_root=2; shift ;;
                --args)      exe_args=1; shift ;;
                --log)       TD_LOGFILE_ENABLED=1; shift ;;
                --console)   TD_LOG_TO_CONSOLE=1; shift ;; 
                --initcfg)
                    FLAG_INIT_CONFIG=1; shift ;;
                --) shift; TD_BOOTSTRAP_REST=("$@"); return 0 ;;
                *) TD_BOOTSTRAP_REST=("$@"); return 0 ;;
            esac
        done

        TD_BOOTSTRAP_REST=()
    }
   
    __init_bootstrap() {
        cfg_source=0  # 0 defaults, 1 system, 2 user
        cfg_file="solidgroundux.cfg"
        __source_systemoruser "$cfg_file" 1 "__print_bootstrap_cfg"           
    }

    __source_globals(){
        # load td-globals and register define globals
        TD_COMMON_LIB="${TD_COMMON_LIB:-"${TD_FRAMEWORK_ROOT}/usr/local/lib/testadura/common"}"
        if [[ ! -r "$TD_COMMON_LIB/td-globals.sh" ]]; then
            sayfail "Cannot source globals: $TD_COMMON_LIB/td-globals.sh not found"
            exit 2
        fi
        saydebug "Sourcing $TD_COMMON_LIB/td-globals.sh"
        source "$TD_COMMON_LIB/td-globals.sh"
        init_derived_paths
        init_global_defaults

        cfg_source=0  # 0 defaults, 1 system, 2 user
        cfg_file="td-globals.cfg"

        if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
            __source_systemoruser "$cfg_file" 1 "__print_sysglobals_cfg"
        else
            __source_systemoruser "$cfg_file" 1 "__print_usrglobals_cfg"
        fi

        # re-derive anything still unset based on possibly-updated anchors
        init_derived_paths
        init_script_paths
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
        local lib path
        for lib in "${TD_CORE_LIBS[@]}"; do
            path="$TD_COMMON_LIB/$lib"
            # shellcheck source=/dev/null
            source "$path"
        done
    }

    __finalize_bootstrap() {       
        FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   
        FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
        FLAG_STATERESET="${FLAG_STATERESET:-0}"
        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi

        td_update_runmode

        TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)" # User home directory
        
        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            saydebug "Running in $RUN_MODE mode (no changes will be made)."
        else
            saydebug "Running in $RUN_MODE mode (changes will be applied)."
        fi

    }    
# --- Public API -------------------------------------------------------------
    # td_bootstrap
        # Initialize (or re-enter) a Testadura framework context for the current script.
        #
        # Summary:
        #   td_bootstrap is the single entry point that:
        #   - Parses bootstrap-only switches (what to initialize, root constraints, etc.)
        #   - Normalizes common framework flags (dry-run, verbose, state reset, etc.)
        #   - Loads framework globals (td-globals.sh + optional td-globals.cfg)
        #   - Loads core framework libraries (core/ui/say/ask/dlg/args/cfg/state, styles)
        #   - Extracts framework builtin arguments (e.g. --help, --showargs) from the
        #     remaining argument list and records them as flags
        #   - Optionally initializes the UI layer
        #   - Optionally enforces root / non-root execution constraints
        #   - Optionally loads cfg and state files
        #   - Parses the *script's* arguments (via TD_ARGS_SPEC) after bootstrap switches
        #   - Finalizes runtime flags and derived values (e.g. RUN_MODE)
        #
        # Important distinction:
        #   - Bootstrap arguments control framework initialization and invariants.
        #   - Builtin arguments (e.g. --help, --showargs) are detected here but enacted
        #     later by the executable script.
        #   - Script arguments are parsed *after* bootstrap and are passed through in
        #     TD_BOOTSTRAP_REST, then parsed by td_parse_args().
        #
        # Usage:
            #   td_bootstrap [bootstrap options] [--] [script args...]
            #
        # Bootstrap options:
            #   --ui
            #       Initialize the UI layer (calls ui_init after libraries are sourced).
            #
            #   --state
            #       Load persistent state (calls td_state_load).
            #
            #   --cfg
            #       Load configuration (calls td_cfg_load).
            #
            #   --needroot
            #       Enforce execution as root (calls need_root with remaining script args).
            #       Typical use: scripts that must write to /etc, manage services, etc.
            #
            #   --cannotroot
            #       Enforce execution as non-root (calls cannot_root with remaining script args).
            #       Typical use: user-scoped scripts where root would be unsafe or unwanted.
            #
            #   --args
            #       Enable parsing of script arguments (default: on). Included for symmetry
            #       with other selectors; usually unnecessary unless supporting libs-only modes.
            #
            #   --initcfg
            #       Allow creation of missing config templates during bootstrap (framework-level
            #       switch used by config initialization helpers).
            #
            #   --
            #       End bootstrap option parsing. Everything after "--" is treated as script
            #       arguments and passed to td_parse_args().
        #
        # Inputs (environment, optional):
        #   TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT
        #       Anchor roots used to derive TD_COMMON_LIB and config/state paths. May be
        #       pre-set by the caller (e.g. dev workspace) or provided via bootstrap cfg.
        #
        #   FLAG_DRYRUN, FLAG_VERBOSE, FLAG_STATERESET, FLAG_INIT_CONFIG
        #       May be pre-set by the environment; bootstrap normalizes and uses them.
        #
        # Outputs (side effects / globals):
            #   TD_BOOTSTRAP_REST   : array of script arguments (post-bootstrap, post-builtin)
            #   FLAG_HELP           : 0|1 set when -h/--help is present
            #   FLAG_SHOWARGS       : 0|1 set when --showargs is present
            #   TD_POSITIONAL       : array (set by td_parse_args)
            #   Option variables from TD_ARGS_SPEC (created/initialized by td_parse_args)
            #   Derived framework globals (paths/defaults via init_* functions)
            #   RUN_MODE            : display string (DRYRUN / COMMIT) used for UI messaging
        #
        # Return codes:
            #   0  Success
            #   >0 Fatal bootstrap failure (library load, cfg/state load, arg parsing, etc.)
        #
        # Examples:
            #   # Typical script entry: UI + cfg + state + parse script args
            #   td_bootstrap --ui --cfg --state -- "$@"
            #
            #   # Force root (e.g. provisioning script). Script args start after "--".
            #   td_bootstrap --ui --cfg --needroot -- "$@"
            #
            #   # User-only tool; refuse sudo/root execution
            #   td_bootstrap --ui --cannotroot -- "$@"
            #
            #   # Debug bootstrap and parsed values
            #   FLAG_VERBOSE=1 td_bootstrap --ui --cfg --state -- "$@"
            #
        # Notes:
            #   - td_bootstrap performs initialization and validation only; it does not
            #     execute builtin actions such as help or showargs.
            #   - Builtin flags are enacted by the executable script (e.g. via
            #     td_builtinarg_handler) after bootstrap completes.
            #   - Keep td_bootstrap thin: it orchestrates load order and invariants but does
            #     not implement application logic.
            #   - RUN_MODE is intended for display only; it must not contain newlines.


    td_bootstrap() {

        # --- Normalize common flags (safe under set -u) ---------------------
        : "${TUI_COMMIT:=$(printf '\e[38;5;130m')}"
        : "${TUI_DRYRUN:=$(printf '\e[38;5;245m')}"
        : "${RESET:=$(printf '\e[0m')}"
        : "${RUN_MODE:="${TUI_COMMIT}COMMIT${RESET}"}"

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

        __parse_bootstrap_args "$@" || __boot_fail "Failed parsing bootstrap arguments" $?

        __init_bootstrap || __boot_fail "Failed to initialize bootstrapper" $?
        __source_globals || __boot_fail "Failed to source global variables" $?
        __source_corelibs || __boot_fail "Failed to load core libraries" $?

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

        # Load state/cfg and parse *script* args (not bootstrap args)
        if (( exe_state )); then
            td_state_load || __boot_fail "State load failed" $?
        fi

        if (( exe_cfg )); then
            td_cfg_load || __boot_fail "CFG load failed" $?
        fi

        if (( exe_args )); then
            # Parse args so flags/vals are populated (but don't enforce root)
            td_parse_args "${TD_BOOTSTRAP_REST[@]}" || __boot_fail "Error parsing arguments" $?

            td_update_runmode || __boot_fail "Error setting RUN_MODE" $?
        fi
        return 0
    }





         
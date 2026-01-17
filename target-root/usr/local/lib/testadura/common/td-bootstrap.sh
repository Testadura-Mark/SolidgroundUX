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

# --- Minimal fallback UI (overridden by ui.sh when sourced) -----------------
    saystart()   { printf 'START   \t%s\n' "$*" >&2; }
    saywarning() { printf 'WARNING \t%s\n' "$*" >&2; }
    sayfail()    { printf 'FAIL    \t%s\n' "$*" >&2; }
    saydebug()   { printf 'DEBUG   \t%s\n' "$*" >&2; }
    saycancel()  { printf 'CANCEL  \t%s\n' "$*" >&2; }
    sayend()     { printf 'END     \t%s\n' "$*" >&2; }
    sayok()      { printf 'OK      \t%s\n' "$*" >&2; }
    sayinfo()    { printf 'INFO    \t%s\n' "$*" >&2; }
    sayerror()   { printf 'ERR     \t%s\n' "$*" >&2; }

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

# --- Framwork metadata ------------------------------------------------------
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


# --- Main sequence functions        
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
        #FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
        FLAG_STATERESET="${FLAG_STATERESET:-0}"
        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi

        RUN_MODE=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_ORANGE}DRYRUN${RESET}" || echo "${BOLD_GREEN}COMMIT${RESET}")

        TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)" # User home directory
        
        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            sayinfo "Running in $RUN_MODE mode (no changes will be made)."
        else
            saywarning "Running in $RUN_MODE mode (changes will be applied)."
        fi

    }    
# --- Public API -------------------------------------------------------------
    # -- td_bootstrap ---------------------------------------------------------------
        # Initialize (or re-enter) a Testadura "framework context" for the current script.
        #
        # Summary:
        #   td_bootstrap is the single entry point that:
        #   - Parses bootstrap-only switches (what to initialize, root constraints, etc.)
        #   - Loads framework globals (td-globals.sh + optional td-globals.cfg)
        #   - Loads core framework libraries (core/ui/say/ask/dlg/args/cfg/state, styles)
        #   - Optionally initializes the UI layer
        #   - Optionally loads cfg/state files
        #   - Parses the *script's* arguments (via TD_ARGS_SPEC) after bootstrap switches
        #   - Finalizes runtime flags and derived values (RUN_MODE, TD_USER_HOME, etc.)
        #
        # Important distinction:
        #   - Bootstrap arguments control framework initialization.
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
            #       Load state (calls td_state_load).
            #
            #   --cfg
            #       Load config (calls td_cfg_load).
            #
            #   --needroot
            #       Enforce running as root (calls need_root with remaining script args).
            #       Typical use: scripts that must write /etc, manage services, etc.
            #
            #   --cannotroot
            #       Enforce NOT running as root (calls cannot_root with remaining script args).
            #       Typical use: user-scoped scripts where root would be unsafe/unwanted.
            #
            #   --args
            #       Enable parsing of script arguments (default: on). Included for symmetry
            #       with other selectors; usually not needed unless you add "libs-only" modes.
            #
            #   --initcfg
            #       Allow creating missing config templates during bootstrap (framework-level
            #       switch used by __create_cfg_template / __source_systemoruser).
            #
            #   --
            #       End bootstrap option parsing. Everything after "--" is treated as script
            #       arguments and passed to td_parse_args().
        #
        # Inputs (environment, optional):
            #   TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT
            #       Anchor roots used to derive TD_COMMON_LIB and config/state paths. May be
            #       pre-set by the caller (e.g., dev workspace) or provided via bootstrap cfg.
            #
            #   FLAG_DRYRUN, FLAG_VERBOSE, FLAG_STATERESET, FLAG_INIT_CONFIG
            #       May be pre-set by environment; bootstrap normalizes/uses them.
            #
        # Outputs (side effects / globals):
            #   TD_BOOTSTRAP_REST   : array of script args (post-bootstrap) passed to td_parse_args()
            #   HELP_REQUESTED      : 0|1 (set by td_parse_args)
            #   TD_POSITIONAL       : array (set by td_parse_args)
            #   Option vars from TD_ARGS_SPEC (created/initialized by td_parse_args)
            #   Derived framework globals (paths/defaults via init_* functions)
            #   RUN_MODE            : display string (DRYRUN/COMMIT) used for UI messaging
            #
        # Return codes:
            #   0  Success
            #   1  Script arg parsing / validation failure (from td_parse_args) or cfg/state load failure
            #   2  Fatal framework failure (e.g., missing required libraries/globals)
        #
        # Examples:
            #   # Typical script entry: UI + cfg + state + parse script args
            #   td_bootstrap --ui --cfg --state -- "$@"
            #
            #   # Force root (e.g., provisioning script). Script args start after "--".
            #   td_bootstrap --ui --cfg --needroot -- "$@"
            #
            #   # User-only tool; refuse sudo/root execution
            #   td_bootstrap --ui --cannotroot -- "$@"
            #
            #   # Debug bootstrap and parsed values (assuming you show td_showarguments on verbose)
            #   FLAG_VERBOSE=1 td_bootstrap --ui --cfg --state -- "$@"
            #
        # Notes:
        #   - Keep td_bootstrap thin: it orchestrates load order and invariants but does
        #     not implement application logic.
        #   - If RUN_MODE is used in headers, ensure it does not contain newlines.
    # ------------------------------------------------------------------------------
    td_bootstrap() {
        FLAG_INIT_CONFIG="${FLAG_INIT_CONFIG:-0}"
        FLAG_DRYRUN="${FLAG_DRYRUN:-0}"

        __parse_bootstrap_args "$@"

        __init_bootstrap
        __source_globals
        __source_corelibs

        # If you want ui, init after libs (unless ui_init is dependency-free)
        (( exe_ui )) && ui_init

        # Root checks (after libs so need_root exists)
        if (( exe_root == 1 )); then
            need_root "${TD_BOOTSTRAP_REST[@]}"
        fi
        if (( exe_root == 2 )); then
            cannot_root "${TD_BOOTSTRAP_REST[@]}"
        fi

        # Load state/cfg and parse *script* args (not bootstrap args)
            
        (( exe_state )) && td_state_load
        (( exe_cfg ))   && td_cfg_load

        td_parse_args "${TD_BOOTSTRAP_REST[@]}"     
   
        __finalize_bootstrap

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            td_showarguments
        fi
        return 0
    }




         
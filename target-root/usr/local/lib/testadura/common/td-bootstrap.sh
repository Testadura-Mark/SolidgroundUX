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
# --- Library guard ----------------------------------------------------------------
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
            printf '%sDEBUG%s \t%s\n' "${MSG_CLR_DEBUG-}" "${RESET-}" "$*" >&2;
        fi
    }
    saycancel() { printf '%sCANCEL%s\t%s\n' "${MSG_CLR_CNCL-}" "${RESET-}" "$*" >&2; }
    sayend() { printf '%sEND%s   \t%s\n' "${MSG_CLR_END-}" "${RESET-}" "$*" >&2; }
    sayerror() { printf '%sERROR%s   \t%s\n' "${MSG_CLR_FAIL-}" "${RESET-}" "$*" >&2; }

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
        exe_libs=1
        exe_state=0
        exe_cfg=0
        exe_args=1
        exe_root=0

        TD_BOOTSTRAP_REST=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
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

    td_check_license() {
        local license_file="$TD_DOCS_DIR/$TD_LICENSE_FILE"
        local accepted_file="$TD_STATE_DIR/$TD_LICENSE_FILE.accepted"
        local isaccepted=0
        local wasaccepted=0
        local current_hash

        if ! current_hash="$(td_hash_sha256_file "$license_file")"; then
            saywarning "td_check_license: could not compute hash"
            current_hash=""
        fi

        if [[ -r "$accepted_file" ]]; then

            local stored_hash
            stored_hash="$(cat "$accepted_file" 2>/dev/null)"

            if [[ "$stored_hash" == "$current_hash" ]]; then
                sayinfo "td_check_license: accepted state matches current license hash"
                isaccepted=1
            else
                sayinfo "td_check_license: accepted state hash does NOT match current license hash"
            fi
        else
            sayinfo "td_check_license: no accepted state file found at: $accepted_file"
        fi

        if (( isaccepted == 0 )); then
            local question_text
            if (( ${wasaccepted:-0} == 1 )); then
                question_text="The license has been updated since you last accepted it. Do you accept the new license terms?"
            else
                question_text="Do you accept these license terms? \n (You must accept to use this software.)"
            fi

            td_print_license 

            if ask_yesno "$question_text"; then
                echo "$current_hash" > "$accepted_file"
            else
                saywarning "Cancelled by user."
                exit 0
            fi
                       
            sayinfo "td_check_license: license not accepted; prompting user"
        fi

        sayinfo "License acceptance status: $(
            [[ $isaccepted -eq 1 ]] \
            && echo "${TUI_VALID}ACCEPTED${RESET}" \
            || echo "${TUI_INVALID}NOT ACCEPTED${RESET}"
        )"

        TD_LICENSE_ACCEPTED=$isaccepted
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
        TD_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # shellcheck source=/dev/null
        source "$TD_BOOTSTRAP_DIR/td-bootstrap-env.sh"

        td_defaults_apply

        td_load_bootstrap_cfg
        td_rebase_directories
        td_rebase_framework_cfg_paths   
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
        td_rebase_directories

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
            saydebug "Initializing bootstrap..."
            __init_bootstrap || __boot_fail "Failed to initialize bootstrapper" $?   

            saydebug "Parsing bootstrap arguments..."
            __parse_bootstrap_args "$@" || __boot_fail "Failed parsing bootstrap arguments" 

            saydebug "Loading core libraries"
            __source_corelibs || __boot_fail "Failed to load core libraries" $?
            
            td_load_ui_style

        # Load Framework globals
            td_cfg_domain_apply "Framework" "$TD_FRAMEWORK_SYSCFG_FILE" "$TD_FRAMEWORK_USRCFG_FILE" "TD_FRAMEWORK_GLOBALS" "framework"
       
        # Parse builtin arguments early
            local -a __td_script_args
            local -a __td_after_builtins
            __td_script_args=( "${TD_BOOTSTRAP_REST[@]}" )
            
            td_parse_args builtins "${__td_script_args[@]}" || __boot_fail "Error parsing builtins" $?
            __td_after_builtins=( "${TD_POSITIONAL[@]}" )

        # Final basic settings       
            td_update_runmode || __boot_fail "Error setting RUN_MODE" $?  
     
        saydebug "Applying options"
        # Options

            # Root checks (after libs so need_root exists)
            if (( exe_root == 1 )); then
                need_root "${__td_script_args[@]}" || __boot_fail "Failed to enable need_root" $?
            fi

            if (( exe_root == 2 )); then
                cannot_root "${__td_script_args[@]}" || __boot_fail "Failed to enable cannot_root" $?
            fi
            
            # Now the root/non-root debate has been settled, check license acceptance.
            td_check_license || __boot_fail "License acceptance check failed" $?
            
            # Now that we know we won't re-exec, continue with the remainder
            TD_BOOTSTRAP_REST=( "${__td_after_builtins[@]}" )

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





         
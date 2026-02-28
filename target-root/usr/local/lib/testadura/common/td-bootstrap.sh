# =================================================================================
# Testadura Consultancy — td-bootstrap.sh
# ---------------------------------------------------------------------------------
# Purpose    : Framework bootstrap and library load orchestration
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Overview
#   td-bootstrap.sh is the entry bootstrap for any script that runs inside the
#   SolidgroundUX framework context. It must be sourced (never executed) and is
#   responsible for:
#
#   1) Path resolution
#      - Determine bootstrap directory
#      - Load bootstrap environment (td-bootstrap-env.sh)
#      - Apply defaults and derive key directories/files ("rebase")
#
#   2) Library load orchestration
#      - Source core libraries in a fixed order (TD_CORE_LIBS from TD_COMMON_LIB)
#      - Load UI palette and style after core libraries are available
#
#   3) Minimal early error reporting
#      - Provide fallback say* functions before ui.sh is loaded
#
#   4) Framework initialization sequence
#      - Apply Framework configuration domain
#      - Parse builtin arguments (commit/dryrun/debug/help/etc.)
#      - Optionally load persistent state and register EXIT handlers
#      - Apply Script configuration domain (if TD_SCRIPT_GLOBALS defined)
#      - Parse script arguments (if TD_ARGS_SPEC and remaining args exist)
#
# Contract
#   - Owns all path resolution and core library load order.
#   - Performs sanity checks only (existence, permissions, required commands).
#   - No reusable helpers live here (helpers belong in libraries).
#   - No application logic or policy decisions here.
#   - No user interaction until after core libraries are loaded and root constraints
#     are resolved (license acceptance may prompt after that point).
#
# Non-goals
#   - Full argument parsing/validation (args layer)
#   - Configuration semantics beyond loading/applying domains (cfg layer)
#   - Script execution/control flow (entry script owns it)
# =================================================================================
set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # Library-only: must be sourced, never executed.
    # Uses a per-file guard variable derived from the filename, e.g.:
    #   ui.sh      -> TD_UI_LOADED
    #   foo-bar.sh -> TD_FOO_BAR_LOADED
    __td_lib_guard() {
        local lib_base
        local guard

        lib_base="$(basename "${BASH_SOURCE[0]}")"
        lib_base="${lib_base%.sh}"
        lib_base="${lib_base//-/_}"
        guard="TD_${lib_base^^}_LOADED"

        # Refuse to execute (library only)
        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
            exit 2
        }

        # Load guard (safe under set -u)
        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    __td_lib_guard
    unset -f __td_lib_guard

# --- Minimal fallback UI (will be overridden by ui.sh when sourced) --------------
    #   Bootstrap must be able to report failures before core libraries (ui/say/log)
    #   are available. These definitions are intentionally minimal and will be
    #   overridden once ui.sh (or equivalent) is sourced.

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

    # Minimal say functions
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

    # __boot_fail
        # Emit a bootstrap failure message with caller context and return a code.
        #
        # Usage:
        #   cmd || { local rc=$?; __boot_fail "Message" "$rc"; return "$rc"; }
        #
        # Arguments:
        #   $1  Message to display
        #   $2  Return code to propagate (defaults to 1)
        #
        # Output:
        #   Writes one FAIL line to stderr (via sayfail), including:
        #     - calling file, line number, and function.
        #
        # Returns:
        #   The provided return code ($2).
    __boot_fail() {
        local msg="${1:-Bootstrap step failed}"
        local rc="${2:-1}"

        # Caller context
        local caller_file="${BASH_SOURCE[1]}"
        local caller_func="${FUNCNAME[1]}"
        local caller_line="${BASH_LINENO[0]}"

        local fnlmsg="${msg} (at ${caller_file}:${caller_line} in function ${caller_func})"

        sayfail "$fnlmsg"
        return "$rc"
    }

# --- Main sequence helpers + EXIT dispatch ---------------------------------------
    # __parse_bootstrap_args
        # Purpose:
        #   Parse framework-level bootstrap switches before script/builtin parsing.
        #
        # Arguments:
        #   $@  Full command line as received by td_bootstrap().
        #
        # Outputs (globals):
        #   exe_state
        #     0 = no state, 1 = load state, 2 = load + autosave state on EXIT.
        #   exe_root
        #     0 = no constraint, 1 = must be root, 2 = must be non-root.
        #   TD_BOOTSTRAP_REST
        #     Array of remaining arguments after bootstrap parsing (preserved verbatim).
        #
        # Behavior:
        #   - Consumes recognized bootstrap switches from the start of the argument list.
        #   - Stops parsing at "--" or at the first unknown option.
        #   - Copies the remaining arguments into TD_BOOTSTRAP_REST unchanged.
        #
        # Returns:
        #   0 always (validation is deferred to later stages).
        #
        # Notes:
        #   Recognized switches:
        #     --state      -> exe_state=1
        #     --autostate  -> exe_state=2
        #     --needroot   -> exe_root=1
        #     --cannotroot -> exe_root=2
        #     --log        -> TD_LOGFILE_ENABLED=1
        #     --console    -> TD_LOG_TO_CONSOLE=1
        #     --           -> explicit end of bootstrap switches
        #     <unknown>    -> implicit end of bootstrap switches

    __parse_bootstrap_args() {
        exe_state=0
        exe_root=0

        TD_BOOTSTRAP_REST=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --state)
                    exe_state=1; shift ;;
                --autostate)
                     exe_state=2; shift ;;
                --needroot)
                    exe_root=1; shift ;;
                --cannotroot)
                    exe_root=2; shift ;;
                --log)
                    TD_LOGFILE_ENABLED=1; shift ;;
                --console)
                    TD_LOG_TO_CONSOLE=1; shift ;; 
                --) 
                    shift; TD_BOOTSTRAP_REST=("$@"); return 0 ;;
                *) 
                    TD_BOOTSTRAP_REST=("$@"); return 0 ;;
            esac
        done
    }
    # __init_bootstrap
        # Purpose:
        #   Initialize the SolidgroundUX bootstrap environment (env, defaults, roots, derived paths).
        #
        # Outputs (globals):
        #   TD_BOOTSTRAP_DIR
        #     Absolute directory of this file.
        #
        # Behavior:
        #   - Resolves TD_BOOTSTRAP_DIR.
        #   - Sources td-bootstrap-env.sh from TD_BOOTSTRAP_DIR.
        #   - Applies defaults, loads bootstrap cfg, and rebases derived directories/paths.
        #
        # Side effects:
        #   - Sources td-bootstrap-env.sh (may define variables/functions).
        #   - Loads bootstrap cfg via td_load_bootstrap_cfg.
        #
        # Returns:
        #   Propagates failures from sourced/bootstrap routines.
        #
        # Notes:
        #   May run multiple times across process boundaries when root re-exec occurs.
    __init_bootstrap() {
        TD_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        # shellcheck source=/dev/null
        source "$TD_BOOTSTRAP_DIR/td-bootstrap-env.sh"

        td_defaults_apply

        td_load_bootstrap_cfg
        td_rebase_directories
        td_rebase_framework_cfg_paths   
    }

    # __source_corelibs
        # Purpose:
        #   Source core framework libraries in the defined order (TD_CORE_LIBS).
        #
        # Inputs (globals):
        #   TD_COMMON_LIB
        #   TD_CORE_LIBS
        #
        # Behavior:
        #   - Rebase directories.
        #   - Sources each library from: $TD_COMMON_LIB/<lib>.
        #
        # Side effects:
        #   - Defines functions/variables provided by core libraries.
        #
        # Returns:
        #   Propagates any sourcing failures to the caller.
    __source_corelibs(){
        sayinfo "Loading core libraries..."  
        td_rebase_directories

        local lib path
        for lib in "${TD_CORE_LIBS[@]}"; do
            path="$TD_COMMON_LIB/$lib"
            # shellcheck source=/dev/null
            source "$path"
        done
    }

    # __td_on_exit_run
        # Purpose:
        #   Execute registered EXIT handlers (LIFO) while preserving the original exit code.
        #
        # Inputs (globals):
        #   TD_ON_EXIT_HANDLERS
        #
        # Behavior:
        #   - Captures the current exit code ($?) immediately.
        #   - Executes handlers in reverse registration order.
        #   - Evaluates each handler via eval.
        #   - Ignores handler failures to ensure all handlers run.
        #
        # Returns:
        #   The original exit code.
        #
        # Notes:
        #   Installed once via td_on_exit_install().
    __td_on_exit_run() {
        local rc=$?
        local i cmd
        saydebug "Entering on exit"
        declare -p TD_ON_EXIT_HANDLERS >/dev/null 2>&1 || { return "$rc"; }

        for (( i=${#TD_ON_EXIT_HANDLERS[@]}-1; i>=0; i-- )); do
            
            cmd="${TD_ON_EXIT_HANDLERS[i]}"
            saydebug "On exit executing: $cmd"
            eval "$cmd" || true
        done

        return "$rc"
    }

    # __td_save_state_dispatch
        # Purpose:
        #   Save state on EXIT only for clean exits.
        #
        # Behavior:
        #   - Captures the current exit code ($?).
        #   - Calls td_save_state only when rc == 0.
        #   - Skips save on rc == 130 (Ctrl+C) and other non-zero exits.
        #
        # Returns:
        #   The original exit code.
        #
        # Notes:
        #   Registered only when --autostate is active.
    __td_save_state_dispatch() {
        local rc=$?   # capture immediately!

        # Only run state save on clean exit
        if (( rc == 0 )); then
            td_save_state
        elif (( rc == 130 )); then
            saydebug "Interrupted (Ctrl+C), not saving state"
        else
            saydebug "Error exit ($rc), not saving state"
        fi

        return "$rc"
    }

# --- Public API ------------------------------------------------------------------
    # td_on_exit_install
        # Purpose:
        #   Install the framework EXIT dispatcher (trap) exactly once per process.
        #
        # Behavior:
        #   - If not yet installed, registers __td_on_exit_run as the EXIT trap.
        #   - Subsequent calls are no-ops (idempotent).
        #
        # Side effects:
        #   - Sets __TD_ON_EXIT_INSTALLED=1 on first install.
        #   - Installs an EXIT trap handler.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - This does not register handlers; it only installs the dispatcher.
        #   - Add handlers via td_on_exit_add().
    td_on_exit_install() {
        # Install once
        [[ "${__TD_ON_EXIT_INSTALLED-0}" -eq 1 ]] && return 0
        __TD_ON_EXIT_INSTALLED=1
        trap '__td_on_exit_run' EXIT
    }

    # td_parse_statespec
        # Purpose:
        #   Parse a pipe-delimited state specification into component fields.
        #
        # Arguments:
        #   $1  State specification string in the format:
        #       key|label|default|validator|colorize
        #
        # Outputs (globals):
        #   __statekey       Variable name to persist (expected identifier).
        #   __statelabel     Optional human-readable label (UI/prompt usage).
        #   __statedefault   Optional default value when no persisted value exists.
        #   __statevalidate  Optional validator function name.
        #   __statecolorize  Optional UI color token.
        #
        # Behavior:
        #   - Splits the spec on '|' using IFS.
        #   - Assigns missing fields as empty strings.
        #
        # Returns:
        #   0 always (parsing only; no validation performed here).
        #
        # Notes:
        #   - Callers must validate __statekey and interpret semantics of other fields.
        #   - Scratch variables are intentionally global to avoid array/echo returns.
    td_parse_statespec() {
        local spec="${1-}"
        __statekey="" __statelabel="" __statedefault="" __statevalidate="" __statecolorize=""
        IFS='|' read -r __statekey __statelabel __statedefault __statevalidate __statecolorize <<< "$spec"
    }
    
    # td_enable_save_state
        # Purpose:
        #   Enable automatic state persistence.
        #
        # Behavior:
        #   - Sets TD_STATE_SAVE=1.
        #   - Allows td_save_state to execute when invoked.
    td_enable_save_state(){
        TD_STATE_SAVE=1
    }

    # td_disable_save_state
        # Purpose:
        #   Disable automatic state persistence.
        #
        # Behavior:
        #   - Sets TD_STATE_SAVE=0.
        #   - Causes td_save_state to become a no-op.
    td_disable_save_state(){
        TD_STATE_SAVE=0
    }

    # td_save_state
        # Purpose:
        #   Persist selected state variables to storage (as configured by TD_STATE_VARIABLES).
        #
        # Inputs (globals):
        #   TD_STATE_SAVE       Gate flag (0 disables saving; non-zero enables saving).
        #   TD_STATE_VARIABLES  Array of state specs (pipe-delimited).
        #
        # Behavior:
        #   - No-op if TD_STATE_SAVE is disabled.
        #   - Parses each TD_STATE_VARIABLES entry via td_parse_statespec().
        #   - Collects valid state keys (identifiers) into a local list.
        #   - Delegates persistence to td_state_save_keys <keys...>.
        #
        # Side effects:
        #   - Writes state via td_state_save_keys() (implementation-owned).
        #
        # Returns:
        #   0 on success or when no-op (disabled or nothing to save).
        #   Non-zero if td_state_save_keys fails.
        #
        # Notes:
        #   - Intended to be called from EXIT dispatch (e.g., __td_save_state_dispatch).
        #   - Validation is limited to identifier checks; semantics belong to state layer.
    td_save_state(){

        (( ! TD_STATE_SAVE )) && return 0

        saydebug "Assembling list out of TD_STATE_VARIABLES"
        local line key label def validator colorize
        local keys=()

        [[ ${#TD_STATE_VARIABLES[@]} -gt 0 ]] || return 0
        saystart "Saving state variables"
        for line in "${TD_STATE_VARIABLES[@]}"; do
            td_parse_statespec "$line"
            key="$(td_trim "$__statekey")"
            __td_is_ident "$key" || continue
            keys+=( "$key" )
        done

        saydebug "Saving state variables from array"
        # Only save if the array exists and has elements
         [[ ${#keys[@]} -gt 0 ]] || return 0
        td_state_save_keys "${keys[@]}"
        sayend "Done saving state variables."
    }    

    # td_on_exit_add
        # Purpose:
        #   Register a new EXIT handler to be executed by the EXIT dispatcher.
        #
        # Arguments:
        #   $*  Command string to execute on process EXIT (stored as a single string).
        #
        # Inputs (globals):
        #   TD_ON_EXIT_HANDLERS
        #
        # Behavior:
        #   - Appends the handler command string to TD_ON_EXIT_HANDLERS.
        #   - Handlers execute in reverse registration order (LIFO).
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Handlers are evaluated via eval in __td_on_exit_run.
        #   - Call td_on_exit_install() before relying on handlers running.
    td_on_exit_add() {
        # store as one string per handler: "fn arg1 arg2 ..."
        TD_ON_EXIT_HANDLERS+=( "$*" )
    }

    # td_check_license
        # Ensure the current license has been accepted (hash-based acceptance).
        #
        # Behavior:
            #   - Computes SHA-256 of the current license file (TD_DOCS_DIR/TD_LICENSE_FILE).
            #   - If an acceptance file exists (TD_STATE_DIR/<license>.accepted) and its
            #     hash matches the current license hash, license is considered accepted.
            #   - Otherwise, prints the license and prompts the user to accept.
            #   - On acceptance, writes the current hash to the acceptance file.
        #
        # Side effects:
            #   - May prompt the user (ask_yesno) and print the license text.
            #   - Writes acceptance state to: TD_STATE_DIR/<license>.accepted
            #   - Sets TD_LICENSE_ACCEPTED (1 accepted, 0 not accepted)
        #
        # Returns:
            #   0  License accepted (already accepted or accepted now)
            #   2  User declined/cancelled acceptance
            #   1  Error (e.g., cannot hash license file or cannot write acceptance state)
        #
        # Notes:
            #   - Called only after root constraints are resolved to avoid double prompting
            #     across sudo re-exec.
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
            wasaccepted=1

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
                return 2
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

    # td_load_ui_style
        # Load the active UI palette and style definitions.
        #
        # Behavior:
            #   - Resolves TD_UI_PALETTE and TD_UI_STYLE; if a value is a basename,
            #     it is resolved relative to TD_STYLE_DIR.
            #   - Sources palette first, then style.
        #
        # Returns:
            #   0 on success
            #   1 if palette/style file is missing or unreadable
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

    # td_bootstrap
        # Purpose:
        #   Establish the SolidgroundUX runtime context for the current script.
        #
        # Arguments:
        #   $@  Full command line (bootstrap switches + builtins + script args).
        #
        # Inputs (globals):
        #   TD_CORE_LIBS, TD_COMMON_LIB
        #   TD_FRAMEWORK_SYSCFG_FILE, TD_FRAMEWORK_USRCFG_FILE
        #   TD_SYSCFG_FILE, TD_USRCFG_FILE
        #
        # Outputs (globals):
        #   TD_BOOTSTRAP_REST
        #     Remaining script arguments after bootstrap + builtins (+ script args if parsed).
        #   RUN_MODE, FLAG_* and other builtin-derived selectors.
        #
        # Behavior:
        #   - Initializes bootstrap environment (roots, derived paths).
        #   - Parses bootstrap switches into exe_state/exe_root and TD_BOOTSTRAP_REST.
        #   - Sources core libraries, then loads UI palette/style.
        #   - Applies Framework cfg domain.
        #   - Parses builtin args early (stop-at-unknown).
        #   - Enforces root/non-root constraints when requested.
        #   - Checks license acceptance (after root constraints are resolved).
        #   - Optionally loads state and registers EXIT handlers (state/autostate).
        #   - Applies Script cfg domain (if TD_SCRIPT_GLOBALS defined).
        #   - Parses script args (if TD_ARGS_SPEC defined and args remain).
        #
        # Side effects:
        #   - Sources multiple libraries and cfg files.
        #   - May prompt for license acceptance.
        #   - May register EXIT trap and handlers.
        #
        # Returns:
        #   0 on success.
        #   2 if license acceptance is declined/cancelled.
        #   Non-zero on fatal initialization failure.
        #
        # Notes:
        #   Callers own application control flow; td_bootstrap only prepares the context.
    td_bootstrap() {
        saystart "Initializing framework"
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

            if ! declare -p TD_SCRIPT_GLOBALS >/dev/null 2>&1; then
                declare -ag TD_SCRIPT_GLOBALS=()
            fi
            
            if ! declare -p TD_STATE_VARIABLES >/dev/null 2>&1; then
                declare -ag TD_STATE_VARIABLES=()
            fi

            if ! declare -p TD_ON_EXIT_HANDLERS >/dev/null 2>&1; then
                declare -ag TD_ON_EXIT_HANDLERS=()
            fi

        # Basic initialization - Defaults
            saydebug "Initializing bootstrap..."
            __init_bootstrap || { local rc=$?; __boot_fail "Failed to initialize bootstrapper" "$rc"; return "$rc"; }

            sayinfo "Parsing bootstrap arguments..."
            __parse_bootstrap_args "$@" || { local rc=$?; __boot_fail "Failed parsing bootstrap arguments" "$rc"; return "$rc"; }

            saydebug "Loading core libraries"
            __source_corelibs || { local rc=$?; __boot_fail "Failed to load core libraries" "$rc"; return "$rc"; }

            saydebug "Loading UI style"
            td_load_ui_style || { local rc=$?; __boot_fail "Failed to load UI style" "$rc"; return "$rc"; }

        # Load Framework globals
            saydebug "Loading framework globals"
            td_cfg_domain_apply "Framework" "$TD_FRAMEWORK_SYSCFG_FILE" "$TD_FRAMEWORK_USRCFG_FILE" "TD_FRAMEWORK_GLOBALS" "framework" \
                || { local rc=$?; __boot_fail "Framework cfg load failed" "$rc"; return "$rc"; }

        # Parse builtin arguments early
            saydebug "Processing builtin arguments."
            local -a __td_script_args
            local -a __td_after_builtins
                __td_script_args=( "${TD_BOOTSTRAP_REST[@]}" )

            saydebug "Parsing arguments $TD_BUILTIN_ARGS ${__td_script_args[@]}"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             
            td_parse_args --stop-at-unknown "${__td_script_args[@]}" \
                || { local rc=$?; __boot_fail "Error parsing builtins" "$rc"; return "$rc"; }
            __td_after_builtins=( "${TD_POSITIONAL[@]}" )

        # Final basic settings
            saydebug "Finalizing initial settings"
            td_update_runmode || { local rc=$?; __boot_fail "Error setting RUN_MODE" "$rc"; return "$rc"; }

        sayinfo "Applying bootstrap options"

        # Root checks (after libs so need_root exists)
            if (( exe_root == 1 )); then
                td_need_root "${__td_script_args[@]}" \
                    || { local rc=$?; __boot_fail "Failed to enable need_root" "$rc"; return "$rc"; }
            fi

            if (( exe_root == 2 )); then
                td_cannot_root "${__td_script_args[@]}" \
                    || { local rc=$?; __boot_fail "Failed to enable cannot_root" "$rc"; return "$rc"; }
            fi

        # Now the root/non-root debate has been settled, check license acceptance.
            td_check_license
            case $? in
                0) : ;;
                2) return 2 ;;
                *) { __boot_fail "License acceptance check failed" 1; return 1; } ;;
            esac
        
        # Now that we know we won't re-exec, continue with the remainder of the arguments
        TD_BOOTSTRAP_REST=( "${__td_after_builtins[@]}" )

        # Reset statefile before it's loaded if requested
        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi

        # Load state and parse *script* args
        if (( exe_state > 0 )); then
            saydebug "Installing on exit handler"
            td_on_exit_install

            saydebug "Loading state file."
            td_state_load || { local rc=$?; __boot_fail "Failed to load state" "$rc"; return "$rc"; }
        fi

        if (( exe_state == 2 )); then
            saydebug "Registering save state"
            td_on_exit_add "__td_save_state_dispatch"
        fi
        
        if (( ${#TD_SCRIPT_GLOBALS[@]} > 0 )); then
            saydebug "Processing CFG."
            td_cfg_domain_apply "Script" "$TD_SYSCFG_FILE" "$TD_USRCFG_FILE" "TD_SCRIPT_GLOBALS" \
                || { local rc=$?; __boot_fail "Script cfg load failed" "$rc"; return "$rc"; }
        fi

        # Always parse script args if the script defines any arg specs
        if (( ${#TD_ARGS_SPEC[@]} > 0 && ${#TD_BOOTSTRAP_REST[@]} > 0 )); then
            saydebug "Parsing script arguments $TD_BOOTSTRAP_REST"
            td_parse_args "${TD_BOOTSTRAP_REST[@]}" \
                || { local rc=$?; __boot_fail "Error parsing script args" "$rc"; return "$rc"; }
            TD_BOOTSTRAP_REST=( "${TD_POSITIONAL[@]}" )
            saydebug "Parsed script arguments $TD_BOOTSTRAP_REST remaining"
        fi

        saydebug "Update loadmode"
        td_update_runmode || { local rc=$?; __boot_fail "Error updating RUN_MODE" "$rc"; return "$rc"; }

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            sayinfo "Running in $RUN_MODE mode (no changes will be made)."
        else
            sayinfo "Running in $RUN_MODE mode (changes will be applied)."
        fi
        sayend "Finished bootstrap"
        return 0
    }






         
#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — Script Template
# ----------------------------------------------------------------------------------
# Purpose : Canonical executable template for Testadura scripts
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in by defining ARGS_SPEC and/or CFG_*.
# ==================================================================================

set -euo pipefail
# --- Load bootstrapper ---------------------------------------------------------
    _bootstrap_default="/usr/local/lib/testadura/common/td-bootstrap.sh"

    # Optional non-interactive overrides (recommended)
    # - TD_BOOTSTRAP: full path to td-bootstrap.sh
    # - TD_FRAMEWORK_PREFIX: prefix that contains usr/local/lib/testadura/common/td-bootstrap.sh
    if [[ -n "${TD_BOOTSTRAP:-}" ]]; then
        BOOTSTRAP="$TD_BOOTSTRAP"
    elif [[ -n "${TD_FRAMEWORK_PREFIX:-}" ]]; then
        BOOTSTRAP="$TD_FRAMEWORK_PREFIX/usr/local/lib/testadura/common/td-bootstrap.sh"
    else
        BOOTSTRAP="$_bootstrap_default"
    fi

    if [[ -r "$BOOTSTRAP" ]]; then
        # shellcheck disable=SC1091
        source "$BOOTSTRAP"
    else
        # Only prompt if interactive
        if [[ -t 0 ]]; then
            printf "\nFramework not installed at: %s\n" "$BOOTSTRAP"
            printf "Are you developing the framework or using a custom install path?\n\n"
            printf "Enter one of:\n"
            printf "  - prefix (contains usr/local/...), e.g. /home/me/dev/solidgroundux/target-root\n"
            printf "  - common dir, e.g. /home/me/dev/solidgroundux/target-root/usr/local/lib/testadura/common\n"
            printf "  - full path to td-bootstrap.sh\n\n"

            read -r -p "Path (empty to abort): " _root
            [[ -n "$_root" ]] || exit 127

            if [[ "$_root" == */td-bootstrap.sh ]]; then
                BOOTSTRAP="$_root"
            elif [[ -r "$_root/td-bootstrap.sh" ]]; then
                BOOTSTRAP="$_root/td-bootstrap.sh"
            else
                BOOTSTRAP="$_root/usr/local/lib/testadura/common/td-bootstrap.sh"
            fi

            if [[ ! -r "$BOOTSTRAP" ]]; then
                printf "FATAL: No td-bootstrap.sh found at: %s\n" "$BOOTSTRAP" >&2
                exit 127
            fi

            # shellcheck disable=SC1091
            source "$BOOTSTRAP"
        else
            printf "FATAL: Testadura framework not installed (missing: %s)\n" "$BOOTSTRAP" >&2
            exit 127
        fi
    fi


# --- Script metadata (identity) ------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Script metadata (framework integration) ----------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )

    # TD_ARGS_SPEC
        # --- Example: Arguments ----------------------------------------------
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        #   var     = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    TD_ARGS_SPEC=(
        "load|l|flag|FLAG_LOAD|Random argument for testing|"
        "unload|u|flag|FLAG_UNLOAD|Random argument for testing|"
        "exit|x|flag|FLAG_EXIT|Random argument for testing|"
    )

    TD_SCRIPT_EXAMPLES=(
        "$TD_SCRIPT_NAME --load --verbose  #Some example usage"
    ) 
    
    TD_SCRIPT_GLOBALS=(
        "system|TD_SYS_STRING|System CFG string|"
        "system|TD_SYS_INT|System CFG int|"
        "system|TD_SYS_DATE|System CFG date|"

        "user|TD_USR_STRING|User CFG string|"
        "user|TD_USR_INT|User CFG int|"
        "user|TD_USR_DATE|User  CFG date|"

        "both|TD_COMMON_STRING|Common CFG string|"
        "both|TD_COMMON_INT|Common CFG int|"
        "both|TD_COMMON_DATE|Common  CFG date|"
    )
# --- local script functions ---------------------------------------------------
    # Declarations
        : "${TD_SYS_STRING:=system-default}"
        : "${TD_SYS_INT:=0}"
        : "${TD_SYS_DATE:=1970-01-01}"

        : "${TD_USR_STRING:=user-default}"
        : "${TD_USR_INT:=0}"
        : "${TD_USR_DATE:=1970-01-01}"

        : "${TD_COMMON_STRING:=common-default}"
        : "${TD_COMMON_INT:=0}"
        : "${TD_COMMON_DATE:=1970-01-01}"

        : "${STATE_VAR1:=State VAR1}"
        : "${STATE_VAR2:=4}"
        : "${STATE_VAR3:=2025-01-01}"

 # --- main --------------------------------------------------------------------
    # main MUST BE LAST function in script
        # Main entry point for the executable script.
        #
        # Execution flow:
        #   1) Invoke td_bootstrap to initialize the framework environment, parse
        #      framework-level arguments, and optionally load UI, state, and config.
        #   2) Abort immediately if bootstrap reports an error condition.
        #   3) Enact framework builtin arguments (help, showargs, state reset, etc.).
        #      Info-only builtins terminate execution; mutating builtins may continue.
        #   4) Continue with script-specific logic.
        #
        # Bootstrap options:
        #   The script author explicitly selects which framework features to enable.
        #   None are required; include only what this script needs.
        #
        #   --state        Enable persistent state loading/saving.
        #   --needroot     Require execution as root.
        #   --cannotroot   Require execution as non-root.
        #   --log          Enable logging to file.
        #   --console      Enable logging to console output.
        #   --             End of bootstrap options; remaining args are script arguments.
        # Notes:
        #   - Builtin argument handling is centralized in td_builtinarg_handler.
        #   - Scripts may override builtin handling, but doing so transfers
        #     responsibility for correct behavior to the script author.
    main() {
        # -- Bootstrap
            local rc = 0
            td_bootstrap --state --needroot -- "$@"
            rc=$?
            (( rc != 0 )) && exit "$rc"
                        
            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_update_runmode
                td_print_titlebar

        # -- Main script logic
        saydebug "Setting state vars"
        td_state_set "STATE_VAR1" "$STATE_VAR1"
        td_state_set "STATE_VAR2" "$STATE_VAR2"
        td_state_set "STATE_VAR3" "$STATE_VAR3"
        printf '%s\n' "$RUN_MODE $TD_STATE_FILE"
    }

    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"

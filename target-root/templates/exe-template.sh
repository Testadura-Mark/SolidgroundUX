#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — Script Template
# ------------------------------------------------------------------------------
# Purpose : Canonical executable template for Testadura scripts
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in by defining ARGS_SPEC and/or CFG_*.
# ==============================================================================

set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_VERSION_STATUS="beta"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework roots (explicit) ----------------------------------------------
    # Override from environment if desired:
    # Directory where Testadura framework is installed
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-/}"
    # Application root (where this script is deployed)
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-/}"
    # Common libraries path
    TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}"
    # State and config files
    TD_STATE_FILE="${TD_STATE_FILE:-"$TD_APPLICATION_ROOT/var/testadura/$TD_SCRIPT_NAME.state"}"
    TD_CFG_FILE="${TD_CFG_FILE:-"$TD_APPLICATION_ROOT/etc/testadura/$TD_SCRIPT_NAME.cfg"}"
    # User home directory
    TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"

# --- Minimal fallback UI (overridden by ui.sh when sourced) -------------------
    saystart()   { printf '[STRT] %s\n' "$*" >&2; }
    saywarning() { printf '[WARN] %s\n' "$*" >&2; }
    sayfail()    { printf '[FAIL] %s\n' "$*" >&2; }
    saycancel()  { printf '[CNCL] %s\n' "$*" >&2; }
    sayend()     { printf '[END ] %s\n' "$*" >&2; }
    sayok()      { printf '[OK  ] %s\n' "$*" >&2; }
    sayinfo()    { printf '[INFO] %s\n' "$*" >&2; }
    sayerror()   { printf '[ERR ] %s\n' "$*" >&2; }

# --- Using / imports ----------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"   # td_parse_args, td_show_help
    "default-colors.sh" # color definitions for terminal output
    "default-styles.sh" # text styles for terminal output
    "ui.sh"     # user inetractive helpers
    "cfg.sh"    # td_cfg_load, config discovery + source, td_state_set/load
    )

    td_source_libs() {
        local lib path
        saystart "Sourcing libraries from: $TD_COMMON_LIB" >&2

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
                sayfail "Required library not found: $path" >&2
                td_die "Cannot continue without core library."
            fi

            saywarning "Library not found (optional): $path" >&2``
        done

        sayend "All libraries sourced." >&2
    }


# --- Example: Arguments -------------------------------------------------------
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
    # ------------------------------------------------------------------------
    TD_ARGS_SPEC=(
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output, show arguments|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        "  $TD_SCRIPT_NAME -d"
        ""
        "Show arguments:"
        "  $TD_SCRIPT_NAME --verbose"
        "  $TD_SCRIPT_NAME -v"
    ) 


# --- local script functions -------------------------------------------------

# --- main() must be the last function in the script -------------------------
    __td_showarguments() {
        printf "File                : %s\n" "$TD_SCRIPT_FILE"
        printf "Script              : %s\n" "$TD_SCRIPT_NAME"
        printf "Script description  : %s\n" "$TD_SCRIPT_DESC"
        printf "Script dir          : %s\n" "$TD_SCRIPT_DIR"
        printf "Script version      : %s (build %s)\n" "$TD_SCRIPT_VERSION" "$TD_SCRIPT_BUILD"
        printf "TD_APPLICATION_ROOT : %s\n" "${TD_APPLICATION_ROOT:-<none>}"
        printf "TD_FRAMEWORK_ROOT   : %s\n" "${TD_FRAMEWORK_ROOT:-<none>}"
        printf "TD_COMMON_LIB       : %s\n" "${TD_COMMON_LIB:-<none>}"

        printf "TD_STATE_FILE       : %s\n" "${TD_STATE_FILE:-<none>}"
        printf "TD_CFG_FILE         : %s\n" "${TD_CFG_FILE:-<none>}"

        printf -- "Arguments / Flags:\n"

        local entry varname
        for entry in "${TD_ARGS_SPEC[@]:-}"; do
            IFS='|' read -r name short type var help choices <<< "$entry"
            varname="${var}"
            printf "  --%s (-%s) : %s = %s\n" "$name" "$short" "$varname" "${!varname:-<unset>}"
        done

        printf -- "Positional args:\n"
        for arg in "${TD_POSITIONAL[@]:-}"; do
            printf "  %s\n" "$arg"
        done
    }

    main() {
        # --- Source libraries ------------------------------------------------------
        td_source_libs
        
        # --- Ensure sudo or non-sudo as desired ---------------------------
            #need_root "$@"
            #cannot_root "$@"

        # --- Load previous state and config
            # enable if desired:
            #td_state_load
            #td_cfg_load

        # --- Parse arguments
            td_parse_args "$@"
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   

            if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
                __td_showarguments
            fi
    }

    # Run main with positional args only (not the options)
    main "$@"

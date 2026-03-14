#!/usr/bin/env bash
# =====================================================================================
# Testadura Consultancy — Script Template
# ------------------------------------------------------------------------------------
# Purpose : Canonical executable template for Testadura scripts
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ------------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in via TD_ARGS_SPEC and TD_SCRIPT_GLOBALS.
# -----------------------------------------------------------------------------------
# How to use this template (Edit Map)
# 1) Set identity fields in "Script metadata (identity)" (DESC, VERSION, etc.)
# 2) Add required libraries to TD_USING (optional)
# 3) Define TD_ARGS_SPEC if your script has CLI options (optional)
# 4) Add TD_SCRIPT_EXAMPLES for --help (recommended)
# 5) List intentional global variables in TD_SCRIPT_GLOBALS (recommended)
# 6) Implement your logic inside main() under "-- Main script logic"
#
# IMPORTANT:
#   - Never read prompts from stdin in executables. Use /dev/tty (or ask/td_dlg_*).
#   - Never print UI to stdout if stdout may be piped; prefer say*/td_print_* which can route.
#   - Do NOT modify the bootstrap loader unless you are developing the framework.
# ===================================================================================
set -uo pipefail

# --- Bootstrap --------------------------------------------------------------------
    # __framework_locator
        # Resolve, create, and load the SolidGroundUX bootstrap configuration.
        #
        # Purpose:
        #   Establish the two root variables that define the framework layout:
        #
        #       TD_FRAMEWORK_ROOT
        #       TD_APPLICATION_ROOT
        #
        #   Once these are known, all other framework paths can be derived from
        #   them by td-bootstrap.sh and the common libraries.
        #
        # Search order:
        #   1. User configuration
        #        ~/.config/testadura/solidgroundux.cfg
        #
        #   2. System configuration
        #        /etc/testadura/solidgroundux.cfg
        #
        #   User configuration overrides system configuration.
        #
        # Sudo behavior:
        #   When running under sudo, the lookup still prefers the invoking user's
        #   home configuration (derived from SUDO_USER) rather than /root, so a
        #   developer's user override remains active under elevation.
        #
        # Creation behavior:
        #   If no configuration file exists:
        #
        #     - non-root user → create in ~/.config/testadura
        #     - root user     → create in /etc/testadura
        #
        #   When created interactively, prompt for:
        #
        #       TD_FRAMEWORK_ROOT     [default: /]
        #       TD_APPLICATION_ROOT   [default: TD_FRAMEWORK_ROOT]
        #
        #   In non-interactive mode, defaults are used automatically.
        #
        # Result:
        #   Sources the selected configuration file and ensures:
        #
        #       TD_FRAMEWORK_ROOT defaults to /
        #       TD_APPLICATION_ROOT defaults to TD_FRAMEWORK_ROOT
        #
        # Returns:
        #   0   success
        #   126 configuration unreadable / invalid
        #   127 configuration directory or file could not be created
    __framework_locator (){
        local cfg_home="$HOME"

        if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            cfg_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        fi

        local cfg_user="$cfg_home/.config/testadura/solidgroundux.cfg"
        local cfg_sys="/etc/testadura/solidgroundux.cfg"
        local cfg=""
        local fw_root="/"
        local app_root="$fw_root"
        local reply

        # Determine existing configuration
        if [[ -r "$cfg_user" ]]; then
            cfg="$cfg_user"

        elif [[ -r "$cfg_sys" ]]; then
            cfg="$cfg_sys"

        else
            # Determine creation location
            if [[ $EUID -eq 0 ]]; then
                cfg="$cfg_sys"
            else
                cfg="$cfg_user"
            fi

            # Interactive prompts (first run only)
            if [[ -t 0 && -t 1 ]]; then

                sayinfo "SolidGroundUX bootstrap configuration"
                sayinfo "No configuration file found."
                sayinfo "Creating: $cfg"

                printf "TD_FRAMEWORK_ROOT [/] : " > /dev/tty
                read -r reply < /dev/tty
                fw_root="${reply:-/}"

                printf "TD_APPLICATION_ROOT [/] : " > /dev/tty
                read -r reply < /dev/tty
                app_root="${reply:-$fw_root}"
            fi

            # Validate paths (must be absolute)
            case "$fw_root" in
                /*) ;;
                *) sayfail "ERR: TD_FRAMEWORK_ROOT must be an absolute path"; return 126 ;;
            esac

            case "$app_root" in
                /*) ;;
                *) sayfail "ERR: TD_APPLICATION_ROOT must be an absolute path"; return 126 ;;
            esac

            # Create configuration file
            mkdir -p "$(dirname "$cfg")" || return 127

            # write cfg file 
            {
                printf '%s\n' "# SolidGroundUX bootstrap configuration"
                printf '%s\n' "# Auto-generated on first run"
                printf '\n'
                printf 'TD_FRAMEWORK_ROOT=%q\n' "$fw_root"
                printf 'TD_APPLICATION_ROOT=%q\n' "$app_root"
            } > "$cfg" || return 127

            saydebug "Created bootstrap cfg: $cfg"
        fi

        # Load configuration
        if [[ -r "$cfg" ]]; then
            # shellcheck source=/dev/null
            source "$cfg"

            : "${TD_FRAMEWORK_ROOT:=/}"
            : "${TD_APPLICATION_ROOT:=$TD_FRAMEWORK_ROOT}"
        else
            sayfail "Cannot read bootstrap cfg: $cfg"
            return 126
        fi

        saydebug "Bootstrap cfg loaded: $cfg, TD_FRAMEWORK_ROOT=$TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT=$TD_APPLICATION_ROOT"

    }

    # __load_bootstrapper
        # Resolve and source the framework bootstrap library.
        #
        # Purpose:
        #   Load the canonical td-bootstrap.sh entry library after the framework
        #   roots have been established by __framework_locator.
        #
        # Behavior:
        #   1. Calls __framework_locator to load or create the bootstrap cfg.
        #   2. Derives the bootstrap path from TD_FRAMEWORK_ROOT.
        #   3. Verifies that td-bootstrap.sh is readable.
        #   4. Sources td-bootstrap.sh into the current shell.
        #
        # Path rule:
        #   If TD_FRAMEWORK_ROOT is "/":
        #
        #       /usr/local/lib/testadura/common/td-bootstrap.sh
        #
        #   Otherwise:
        #
        #       $TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common/td-bootstrap.sh
        #
        # Notes:
        #   - This function performs executable-level startup resolution.
        #   - td-bootstrap.sh is expected to derive secondary paths from the
        #     already-established root variables, not rediscover them.
        #
        # Returns:
        #   0   success
        #   126 bootstrap library unreadable
    __load_bootstrapper(){
        local bootstrap=""

        __framework_locator || return $?

        if [[ "$TD_FRAMEWORK_ROOT" == "/" ]]; then
            bootstrap="/usr/local/lib/testadura/common/td-bootstrap.sh"
        else
            bootstrap="${TD_FRAMEWORK_ROOT%/}/usr/local/lib/testadura/common/td-bootstrap.sh"
        fi

        [[ -r "$bootstrap" ]] || {
            printf "FATAL: Cannot read bootstrap: %s\n" "$bootstrap" >&2
            return 126
        }
        
        saydebug "Loading $bootstrap"
            
        # shellcheck source=/dev/null
        source "$bootstrap"
    }

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

    # Minimal UI
    saystart()   { printf '%sSTART%s\t%s\n' "${MSG_CLR_STRT-}" "${RESET-}" "$*" >&2; }
    sayinfo()    { 
        if (( ${FLAG_VERBOSE:-0} )); then
            printf '%sINFO%s \t%s\n' "${MSG_CLR_INFO-}" "${RESET-}" "$*" >&2; 
        fi
    }
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

# --- Script metadata (identity) ---------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="${TD_SCRIPT_NAME}"
    : "${TD_SCRIPT_DESC:=Canonical executable template for Testadura scripts}"
    : "${TD_SCRIPT_VERSION:=1.0}"
    : "${TD_SCRIPT_BUILD:=20250110}"
    : "${TD_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${TD_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${TD_SCRIPT_COPYRIGHT:=© 2025 Mark Fieten — Testadura Consultancy}"
    : "${TD_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.0}"

# --- Script metadata (framework integration) --------------------------------------
    # TD_USING
        # Libraries to source from TD_COMMON_LIB.
        # These are loaded automatically by td_bootstrap AFTER core libraries.
        #
        # Example:
        #   TD_USING=( net.sh fs.sh )
        #
        # Leave empty if no extra libs are needed.
    TD_USING=(
    )

    # TD_ARGS_SPEC 
        # Optional: script-specific arguments
        # --- Example: Arguments
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
    )

    # TD_SCRIPT_EXAMPLES
        # Optional: examples for --help output.
        # Each entry is a string that will be printed verbatim.
        #
        # Example:
        #   TD_SCRIPT_EXAMPLES=(
        #       "Example usage:"
        #       "  script.sh --verbose --mode fast"
        #       "  script.sh -v -m slow"
        #   )
        #
        # Leave empty if no examples are needed.
    TD_SCRIPT_EXAMPLES=(
    ) 

    # TD_SCRIPT_GLOBALS
        # Explicit declaration of global variables intentionally used by this script.
        #
        # Purpose:
        #   - Declares which globals are part of the script’s public/config contract.
        #   - Enables optional configuration loading when non-empty.
        #
        # Behavior:
        #   - If this array is non-empty, td_bootstrap enables config integration.
        #   - Variables listed here may be populated from configuration files.
        #   - Unlisted globals will NOT be auto-populated.
        #
        # Use this to:
        #   - Document intentional globals
        #   - Prevent accidental namespace leakage
        #   - Make configuration behavior explicit and predictable
        #
        # Only list:
        #   - Variables that must be globally accessible
        #   - Variables that may be defined in config files
        #
        # Leave empty if:
        #   - The script does not use configuration-driven globals
    TD_SCRIPT_GLOBALS=(
    )

    # TD_STATE_VARIABLES
        # List of variables participating in persistent state.
        #
        # Purpose:
        #   - Declares which variables should be saved/restored when state is enabled.
        #
        # Behavior:
        #   - Only used when td_bootstrap is invoked with --state.
        #   - Variables listed here are serialized on exit (if TD_STATE_SAVE=1).
        #   - On startup, previously saved values are restored before main logic runs.
        #
        # Contract:
        #   - Variables must be simple scalars (no arrays/associatives unless explicitly supported).
        #   - Script remains fully functional when state is disabled.
        #
        # Leave empty if:
        #   - The script does not use persistent state.
    TD_STATE_VARIABLES=(
    )

    # TD_ON_EXIT_HANDLERS
        # List of functions to be invoked on script termination.
        #
        # Purpose:
        #   - Allows scripts to register cleanup or finalization hooks.
        #
        # Behavior:
        #   - Functions listed here are executed during framework exit handling.
        #   - Execution order follows array order.
        #   - Handlers run regardless of normal exit or controlled termination.
        #
        # Contract:
        #   - Functions must exist before exit occurs.
        #   - Handlers must not call exit directly.
        #   - Handlers should be idempotent (safe if executed once).
        #
        # Typical uses:
        #   - Cleanup temporary files
        #   - Persist additional state
        #   - Release locks
        #
        # Leave empty if:
        #   - No custom exit behavior is required.
    TD_ON_EXIT_HANDLERS=(
    )
    
    # State persistence is opt-in.
        # Scripts that want persistent state must:
        #   1) set TD_STATE_SAVE=1
        #   2) call td_bootstrap --state
    TD_STATE_SAVE=0

# --- Local script Declarations ----------------------------------------------------
    # Put script-local constants and defaults here (NOT framework config).
    # Prefer local variables inside functions unless a value must be shared.

# --- Local script functions -------------------------------------------------------

# --- Main -------------------------------------------------------------------------
    # main
        # Purpose:
        #   Canonical script entry point.
        #
        # Behavior:
        #   - Resolves and loads the framework bootstrap library.
        #   - Initializes framework runtime via td_bootstrap.
        #   - Executes builtin framework arguments.
        #   - Prints the standard title bar.
        #   - Runs script-specific logic.
        #
        # Arguments:
        #   $@  Framework and script-specific command-line arguments.
        #
        # Returns:
        #   Exits with the status produced by bootstrap or script logic.
    main() {
        # -- Bootstrap
            local rc=0

            __load_bootstrapper || exit $?            

            # Recognized switches:
            #     --state      -> enable saving state variables 
            #     --autostate  -> enable state support and auto-save TD_STATE_VARIABLES on exit
            #     --needroot   -> restart script if not root
            #     --cannotroot -> exit script if root
            #     --log        -> enable file logging
            #     --console    -> enable console logging
            # Example:
            #   td_bootstrap --state --needroot -- "$@"
            td_bootstrap -- "$@"
            rc=$?

            saydebug "After bootstrap: $rc"
            (( rc != 0 )) && exit "$rc"
                        
        # -- Handle builtin arguments
            saydebug "Calling builtinarg handler"
            td_builtinarg_handler
            saydebug "Exited builtinarg handler"

        # -- UI
            td_update_runmode
            td_print_titlebar

        # -- Main script logic

    }

    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"
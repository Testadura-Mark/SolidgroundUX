#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — bootstrap-test
# ----------------------------------------------------------------------------------
# Purpose : Testscript testing some basic framework functions
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in by defining ARGS_SPEC and/or CFG_*.
# ==================================================================================
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

                read -r -p "TD_FRAMEWORK_ROOT [/] : " reply
                fw_root="${reply:-/}"

                read -r -p "TD_APPLICATION_ROOT [/] : " reply
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
    
    # - Minimal fallback UI (will be overridden by ui.sh when sourced)
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
    TD_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    : "${TD_SCRIPT_DESC:=Canonical executable template for Testadura scripts}"
    : "${TD_SCRIPT_VERSION:=1.0}"
    : "${TD_SCRIPT_BUILD:=20250110}"
    : "${TD_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${TD_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${TD_SCRIPT_COPYRIGHT:=© 2025 Mark Fieten — Testadura Consultancy}"
    : "${TD_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.0}"

# --- Script metadata (framework integration) --------------------------------------
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

    : "${INP_NAME=}"
    : "${INP_STREET=}"
    : "${INP_ZIPCODE=}"
    : "${INP_CITY=}"
    : "${INP_COUNTRY=}"
    : "${INP_AGE=}"
     
    TD_STATE_VARIABLES=(
        "INP_NAME|Name|Petrus Puk|"
        "INP_STREET|Address|Nowhere straat|"
        "INP_ZIPCODE|Postcode|5544 QU|"
        "INP_CITY|Stad||"
        "INP_COUNTRY|||"
        "INP_AGE|Leeftijd|102|td_is_number"
    )

    TD_ON_EXIT_HANDLERS=(
    )

    TD_STATE_SAVE=1

# --- Local script Declarations ----------------------------------------------------
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
    
# --- Local script functions -------------------------------------------------------
    input_test() {
        td_prompt_fromlist --autoalign "${TD_STATE_VARIABLES[@]}" 
    }

    ask_test(){
        echo "stdin tty?  $([[ -t 0 ]] && echo yes || echo no)"
        echo "stdout tty? $([[ -t 1 ]] && echo yes || echo no)"
        echo "/dev/tty rw? $([[ -r /dev/tty && -w /dev/tty ]] && echo yes || echo no)"

        echo
        echo "---------------------------------------------"
        echo "ask_yesno (default YES)"
        ask_yesno "Continue?" 10
        echo "rc=$?"

        echo
        echo "---------------------------------------------"
        echo "ask_noyes (default NO)"
        ask_noyes "Continue?" 12
        echo "rc=$?"

        echo
        echo "---------------------------------------------"
        echo "ask_okcancel (default OK)"
        ask_okcancel "Apply changes?" 15
        echo "rc=$?"

        echo
        echo "---------------------------------------------"
        echo "ask_ok_redo_quit"
        ask_ok_redo_quit "Run job?" 10
        echo "rc=$?"

        echo
        echo "---------------------------------------------"
        echo "ask_continue" 12
        ask_continue "Press enter to continue..." 
        echo "rc=$?"

        echo
        echo "---------------------------------------------"
        echo "ask_continue"
        ask_continue "Press enter to continue..." 
        echo "rc=$?"
    }
# --- Main -------------------------------------------------------------------------
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
            local rc=0

            __load_bootstrapper || exit $?            

            td_bootstrap --state --needroot -- "$@"
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
        

        # -- Debug ask_redo_quit
        while true; do
            input_test

            ask_ok_redo_quit "Continue anyway?"
            local rc=$?
            saydebug "Return received: $rc"
            case $rc in
                0) saydebug "0 detected"; TD_STATE_SAVE=1; td_save_state; break ;;
                1) sayinfo "Redoing selection..."; saydebug "Redo detected"; continue ;;
                2) saywarning "User quit."; TD_STATE_SAVE=0; saydebug "Quit"; break ;;
                3) saywarning "Invalid response."; saydebug "Invalid Response"; continue ;;
            esac
        done

        ask_test
    }

    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"

#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — prepare-release.sh
# ----------------------------------------------------------------------------------
# Purpose : Creates a clean tar.gz release archive of the application
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------

# ==================================================================================

set -euo pipefail

# --- Script metadata -------------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_LOG_PATH="/var/log/testadura/${SGND_PRODUCT:-$TD_SCRIPT_NAME}.log"
    TD_SCRIPT_DESC=" Creates a clean tar.gz release archive of a workspace"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework roots (explicit) --------------------------------------------------
    # Override from environment if desired:
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-/}" # Directory where Testadura framework is installed
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-/}" # Application root (where this script is deployed)
    TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}" # Common libraries path
    TD_STATE_FILE="${TD_STATE_FILE:-"$TD_APPLICATION_ROOT/var/testadura/$TD_SCRIPT_NAME.state"}" # State file path
    TD_CFG_FILE="${TD_CFG_FILE:-"$TD_APPLICATION_ROOT/etc/testadura/$TD_SCRIPT_NAME.cfg"}" # Config file path
    TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)" # User home directory

    TD_LOGFILE_ENABLED="${TD_LOGFILE_ENABLED:-0}"  # Enable logging to file (1=yes,0=no)
    TD_CONSOLE_MSGTYPES="${TD_CONSOLE_MSGTYPES:-STRT|WARN|FAIL|END}"  # Enable logging to file (1=yes,0=no)
    TD_LOG_PATH="${TD_LOG_PATH:-/var/log/testadura/solidgroundux.log}" # Log file path
    TD_ALTLOG_PATH="${TD_ALTLOG_PATH:-~/.state/testadura/solidgroundux.log}" # Alternate Log file path
    TD_LOG_MAX_BYTES="${TD_LOG_MAX_BYTES:-$((25 * 1024 * 1024))}" # 25 MiB
    TD_LOG_KEEP="${TD_LOG_KEEP:-20}" # keep N rotated logs
    TD_LOG_COMPRESS="${TD_LOG_COMPRESS:-1}" # gzip rotated logs (1/0)
    # User home directory
    TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"

# --- Minimal fallback UI (overridden by ui.sh when sourced) ----------------------
    saystart()   { printf 'START  \t%s\n' "$*" >&2; }
    saywarning() { printf 'WARNING \t%s\n' "$*" >&2; }
    sayfail()    { printf 'FAIL    \t%s\n' "$*" >&2; }
    saycancel()  { printf 'CANCEL  \t%s\n' "$*" >&2; }
    sayend()     { printf 'END     \t%s\n' "$*" >&2; }
    sayok()      { printf 'OK      \t%s\n' "$*" >&2; }
    sayinfo()    { printf 'INFO    \t%s\n' "$*" >&2; }
    sayerror()   { printf 'ERR     \t%s\n' "$*" >&2; }

# --- UI Control --------------------------------------------------------------------
    ui_init() {
        UI_ACTIVE=0
        if ! exec 3<>/dev/tty; then
            UIFD=""
            return 1
        fi
        UIFD=3
        trap ui_leave EXIT INT TERM
    }

    ui_enter() { 
        UI_ACTIVE=1
        tput smcup >&"$UIFD"; tput clear >&"$UIFD"; 
    }
    
    ui_leave() {
        if [[ "$UI_ACTIVE" -eq 0 ]]; then
            return 0
        fi
        UI_ACTIVE=0  
        tput rmcup >&"$UIFD"
        tput cud1  >&"$UIFD"   # cursor down 1
    }
    
    ui_print() { printf '%s' "$*" >&$UIFD; }

    ui_printf() { printf "$@" >&$UIFD ; }

# --- Using / imports -------------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"   # td_parse_args, td_show_help
    "default-colors.sh" # color definitions for terminal output
    "default-styles.sh" # text styles for terminal output
    "ui.sh"     # user inetractive helpers
    "cfg.sh"    # td_cfg_load, config discovery + source, td_state_set/load
    "version.sh" # version comparison helpers
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


# --- Argument specification and processing ---------------------------------------
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
        "auto|a|flag|FLAG_AUTO|Repeat with last settings|"
        "cleanup|c|flag|FLAG_CLEANUP|Cleanup staging files after run|"
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "useexisting|u|flag|FLAG_USEEXISTING|Use existing staging files|"
        "statereset|r|flag|FLAG_STATERESET|Reset the state file|"
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

        printf "TD_LOGFILE_ENABLED : %s\n" "${TD_LOGFILE_ENABLED:-<none>}"
        printf "TD_LOG_PATH        : %s\n" "${TD_LOG_PATH:-<none>}"
        printf "TD_ALTLOG_PATH     : %s\n" "${TD_ALTLOG_PATH:-<none>}"
        
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

    __set_runmodes()
    {
        RUN_MODE=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_ORANGE}DRYRUN${RESET}" || echo "${BOLD_GREEN}COMMIT${RESET}")

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            sayinfo "Running in Dry-Run mode (no changes will be made)."
        else
            saywarning "Running in Normal mode (changes will be applied)."
        fi

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi

        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi
    }


# --- local script functions ------------------------------------------------------
    __save_parameters(){
        td_state_set "RELEASE" "$RELEASE"
        td_state_set "SOURCE_DIR" "$SOURCE_DIR"
        td_state_set "STAGING_ROOT" "$STAGING_ROOT"
        td_state_set "TAR_FILE" "$TAR_FILE"
        td_state_set "FLAG_CLEANUP" "$FLAG_CLEANUP"
        td_state_set "FLAG_USEEXISTING" "$FLAG_USEEXISTING"
    }
    __get_parameters(){
        RELEASE="${RELEASE:-"$SGND_PRODUCT-$SGND_VERSION"}"
        SOURCE_DIR="${SOURCE_DIR:-"$TD_APPLICATION_ROOT"}"
        TD_APPLICATION_PARENT="$(dirname "$TD_APPLICATION_ROOT")"
        STAGING_ROOT="${STAGING_ROOT:-"$TD_APPLICATION_PARENT/releases"}"
        TAR_FILE="${TAR_FILE:-"$RELEASE.tar.gz"}"
        FLAG_AUTO="${FLAG_AUTO:-0}"
        FLAG_CLEANUP="${FLAG_CLEANUP:-0}"

        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
             sayinfo "Auto mode: using last deployment or default settings."
             return 0
        fi

        while true; do
            printf "\n${CLI_BORDER}================================================================\n"
            printf "${CLI_TEXT}   Prepare Release                                        ${RUN_MODE}\n"                        
            printf "${CLI_BORDER}================================================================\n"
            ask --label "Release" --var RELEASE --default "$RELEASE" --colorize both 
            ask --label "Source directory" --var SOURCE_DIR --default "$SOURCE_DIR" --validate_fn validate_dir_exists --colorize both
            ask --label "Staging directory" --var STAGING_ROOT --default "$STAGING_ROOT" --validate_fn validate_dir_exists--colorize both
            ask --label "Tar file" --var TAR_FILE --default "$TAR_FILE" --colorize both
            if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
                cleanup="Y"
            else
                cleanup="N"
            fi
            ask --label "Cleanup staging files after run (Y/N)" --var cleanup --default "$cleanup" --choices "Y,N" --colorize both
            if [[ "$cleanup" == "Y" || "$cleanup" == "y" ]]; then
                FLAG_CLEANUP=1
            else
                FLAG_CLEANUP=0
            fi
            
             if [[ "$FLAG_USEEXISTING" -eq 1 ]]; then
                useexisting="Y"
            else
                useexisting="N"
            fi
            ask --label "Use existing staging files (Y/N)" --var useexisting --default "$useexisting" --choices "Y,N" --colorize both
            if [[ "$useexisting" == "Y" || "$useexisting" == "y" ]]; then
                FLAG_USEEXISTING=1
            else
                FLAG_USEEXISTING=0
            fi
            printf "${CLI_BORDER}===============================================================\n"
            printf "\n"
            
            if dlg_autocontinue 10 "Create a release using these settings?" "APRC"; then
                rc=0
            else
                rc=$?
            fi
            case "$rc" in
                0) 
                    saydebug "Proceeding with release creation..."
                    __save_parameters
                    return 0
                    ;;
                1) 
                    saydebug "Auto proceeding with release creation..."
                    __save_parameters
                    return 0
                    ;;
                2)
                    saycancel "Operation cancelled by user."
                    exit 1
                    ;;
                3)
                    saydebug "Redoing input..."
                    continue
                    ;;
                *)
                    continue
                    ;;
            esac
        done
    }

   __create_tar() {

    saystart "Creating release: $RELEASE"

    STAGE_PATH="${STAGING_ROOT%/}/$RELEASE"

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have check/created directory: $STAGE_PATH"
    else
        saydebug "Ensuring staging dir exists: $STAGE_PATH"
        mkdir -p "$STAGE_PATH"
    fi

    # -- Stage clean copy ---------------------------------------------------------
    if [[ "$FLAG_USEEXISTING" -eq 1 && -n "$(ls -A "$STAGE_PATH" 2>/dev/null)" ]]; then
        sayinfo "Using existing staging files as requested."
    else
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have staged files from $SOURCE_DIR to $STAGE_PATH"
        else
            saydebug "Staging files from $SOURCE_DIR to $STAGE_PATH"
            rsync -a --delete \
                --exclude '.*' \
                --exclude '*.state' \
                --exclude '*.code-workspace' \
                "${SOURCE_DIR%/}/" "$STAGE_PATH/" || { sayfail "rsync failed."; return 1; }
        fi
    fi

    # --- Create tar.gz -----------------------------------------------------------
    TAR_PATH="${STAGING_ROOT%/}/$TAR_FILE"
    saydebug "Creating tar.gz archive $TAR_PATH from staged files in $STAGE_PATH"

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have created tar.gz archive at: $TAR_PATH"
    else
        tar -C "$STAGE_PATH" -czpf "$TAR_PATH" . || { sayfail "tar failed."; return 1; }
        sayinfo "Created $TAR_PATH"

        # --- Inspect archive (first few entries) --------------------------------
        tar -tf "$TAR_PATH" | head -n 30
    fi

    # --- Cleanup staged dir ------------------------------------------------------
    if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have cleaned up staged files at: $STAGE_PATH"
        else
            saydebug "Cleaning up staged files as requested."
            rm -rf "$STAGE_PATH"
        fi
    fi

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have listed available releases in: ${STAGING_ROOT%/}"
    else
        sayinfo "Release created successfully. Available releases:"
        ls -ltr "${STAGING_ROOT%/}"/*.tar.gz 2>/dev/null || true
    fi

    sayend "Release created."

    dlg_autocontinue 15 "Press any key to continue..." "A"
    }
    

# === main() must be the last function in the script ==============================
    main() {
    # --- Bootstrap ---------------------------------------------------------------
        # -- Initialize  UI 
            ui_init

        # -- Source libraries 
            td_source_libs

        # -- Ensure sudo or non-sudo as desired 
            #need_root "$@"
            #cannot_root "$@"

        # -- Load previous state and config
            # enable if desired:
            td_state_load
            #td_cfg_load

        # ---Parse arguments
            td_parse_args "$@"
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   
            FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
            FLAG_STATERESET="${FLAG_STATERESET:-0}"
            FLAG_USEEXISTING="${FLAG_USEEXISTING:-0}"
            __set_runmodes

    # --- Main script logic here --------------------------------------------------

        __get_parameters
        __create_tar
    }

    # Run main with positional args only (not the options)
    main "$@"

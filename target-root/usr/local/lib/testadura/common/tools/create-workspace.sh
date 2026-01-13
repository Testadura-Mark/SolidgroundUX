#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — create-workspace.sh
# -------------------------------------------------------------------------------
# Purpose : Generic script template
# Author  : Mark Fieten
# Version : 1.0 (2025-11-20)
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description :
#   Script to create a workspace from a source root to a target root.
#   - Sets up directory structure
#   - Creates a VS Code workspace file
#   - Copies template files
# Usage examples:
#   ./create-workspace.sh --project MyProject --folder /path/to/project
#   ./create-workspace.sh -p MyProject -f /path/to/project --dryrun
# ==============================================================================
set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_LOG_PATH="/var/log/testadura/${SGND_PRODUCT:-$TD_SCRIPT_NAME}.log"
    TD_SCRIPT_DESC="Create a new project workspace from templates"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework roots (explicit) -----------------------------------------------
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

# --- Minimal fallback UI (overridden by ui.sh when sourced) -------------------
    saystart()   { printf '[STRT] %s\n' "$*" >&2; }
    saywarning() { printf '[WARN] %s\n' "$*" >&2; }
    sayfail()    { printf '[FAIL] %s\n' "$*" >&2; }
    saycancel()  { printf '[CNCL] %s\n' "$*" >&2; }
    sayend()     { printf '[END ] %s\n' "$*" >&2; }
    sayok()      { printf '[OK  ] %s\n' "$*" >&2; }
    sayinfo()    { printf '[INFO] %s\n' "$*" >&2; }
    sayerror()   { printf '[ERR ] %s\n' "$*" >&2; }
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

            saywarning "Library not found (optional): $path" >&2
        done

        sayend "All libraries sourced." >&2
    }


# --- Argument specification and processing ------------------------------------
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
        "project|p|value|PROJECT_NAME|Project name|"
        "folder|f|value|PROJECT_FOLDER|Set project folder|"
        "dryrun|d|flag|FLAG_DRYRUN| Emulate only don't do any work|"
        "statereset|r|flag|FLAG_STATERESET|Reset the state file|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Show help"
        "  $TD_SCRIPT_NAME --help"
        ""
        "Perform a dry run:"
        "  $TD_SCRIPT_NAME --dryrun"
        "  $TD_SCRIPT_NAME -d"
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

# --- local script functions ---------------------------------------------------
    __resolve_project_settings()
    {
        local template_dir slug default_name default_folder default_template base

        default_name="Script1.sh"
        default_projectname="Project"
        sample_scriptname="Script.sh"
           
        # --- Non-interactive AUTO mode:
        
        # --- Interactive mode OR missing arguments:
            while true; do
             
                #  Get user input
                ask --label "Project name " --var PROJECT_NAME --default "$default_projectname"
                slug="${PROJECT_NAME// /-}"

                if [[ -n "${PROJECT_FOLDER:-}" ]]; then
                    default_folder="$PROJECT_FOLDER"
                else
                    default_folder="$HOME/dev/${slug}"
                fi
                
                ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder"

                # Normalize folder to absolute path
                if [[ "$PROJECT_FOLDER" != /* ]]; then
                   PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi

                sayinfo "Project name   : $PROJECT_NAME"
                sayinfo "Project folder : $PROJECT_FOLDER"

                if ask_ok_redo_quit "Proceed with these settings?"; then
                    # OK (0)
                    return 0
                else
                    ret=$?     # <- capture the 1 or 2
                    case $ret in
                        1) continue ;;             # REDO
                        2) saywarning "Aborted." ; return 1 ;;
                        *)  sayfail "Unexpected code: $ret" ; return 1 ;;
                    esac
                fi
            done
        # -- Summary

    }
    
    __create_repository()
    {
        mkdir -p "$PROJECT_FOLDER"
        
        DIRS=(
        "target-root"
        "target-root/etc/systemd/system"
        "target-root/usr/local/bin"
        "target-root/usr/local/lib"
        "target-root/usr/local/sbin"
        "docs"
        "templates"
        )
        
        for d in "${DIRS[@]}"; do
            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                mkdir -p "${PROJECT_FOLDER}/${d}"
                sayinfo "Created folder ${PROJECT_FOLDER}/${d}"
            else
                sayinfo "Would have created folder ${PROJECT_FOLDER}/${d}" 
            fi
            
        done

        # Copy template files
        template_dir="${TD_COMMON_LIB}/templates"
        if [[ -d "$template_dir" ]]; then
            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                cp -r "${template_dir}/." "$PROJECT_FOLDER/templates/"
                sayinfo "Copied templates to ${PROJECT_FOLDER}/templates/"
            else
                sayinfo "Would have copied templates to ${PROJECT_FOLDER}/templates/" 
            fi
        else
            saywarning "Template directory $template_dir does not exist; skipping template copy."
        fi
    }

    __create_workspace_file(){
        local workspace_file="${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace"

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created workspace file ${workspace_file}" 
            return 0
        fi

cat > "$workspace_file" <<EOF
    {
    "folders": [
        { "name": "${PROJECT_NAME}", "path": "." }
    ],
    "settings": {
        "files.exclude": {
        "**/.git": true,
        "**/.DS_Store": true
        },
        "terminal.integrated.cwd": "\${workspaceFolder}"
    }
    }
EOF

        sayinfo "Created VS Code workspace file ${workspace_file}"
    }


# === main() must be the last function in the script ===========================
   main() {
    # --- Bootstrap ------------------------------------------------------------
        # -- Initialize  UI 
            ui_init
        # -- Source libraries 
            td_source_libs
            
        # -- Ensure sudo or non-sudo as desired 
            #need_root "$@"
            cannot_root "$@"

        # -- Load previous state and config
            # enable if desired:
            #td_state_load
            #td_cfg_load

        # -- Parse arguments
            td_parse_args "$@"
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   
            FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
            FLAG_STATERESET="${FLAG_STATERESET:-0}"
            __set_runmodes

    # --- Main script logic here ---------------------------------------------
        # -- Resolve settings (0=OK, 1=abort, 2=skip template)
        if __resolve_project_settings; then
            proceed=0
        else
            proceed=$?
        fi    

        # User aborted
        if [[ "$proceed" -eq 1 ]]; then
            exit 0
        fi

        # For 0 (OK) and 2 (skip template) we still create repo + workspace
        __create_repository
        __create_workspace_file

    }

    main "$@"


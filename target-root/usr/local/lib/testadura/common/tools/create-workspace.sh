#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — create-workspace.sh
# -------------------------------------------------------------------------------
# Purpose    : Create a new development workspace from templates
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description:
#   Developer utility that scaffolds a new project workspace from a source
#   template into a target directory.
#
#   - Creates the required directory structure
#   - Copies framework or project template files
#   - Optionally generates a VS Code workspace file
#
# Assumptions:
#   - Target directory does not already contain a conflicting workspace
#   - Intended for development use (not deployment)
#
# Effects:
#   - Creates directories and files under the specified target path
#   - May overwrite existing files if explicitly allowed
#
# Usage examples:
#   ./create-workspace.sh --project MyProject --folder /path/to/project
#   ./create-workspace.sh -p MyProject -f /path/to/project --dryrun
# ===============================================================================
set -euo pipefail
source /home/sysadmin/dev/solidgroundux/target-root/usr/local/lib/testadura/common/td-bootstrap.sh

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_DESC="Create a new project workspace from templates"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"
   
# --- Using / imports ----------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )

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
        {
            printf '{\n'
            printf '  "folders": [\n'
            printf '    { "name": "%s", "path": "." }\n' "$PROJECT_NAME"
            printf '  ],\n'
            printf '  "settings": {\n'
            printf '    "files.exclude": {\n'
            printf '      "**/.git": true,\n'
            printf '      "**/.DS_Store": true\n'
            printf '    },\n'
            printf '    "terminal.integrated.cwd": "\\${workspaceFolder}"\n'
            printf '  }\n'
            printf '}\n'
        } > "$workspace_file"

        sayinfo "Created VS Code workspace file ${workspace_file}"
    }


# === main() must be the last function in the script ===========================
   main() {
    # --- Bootstrap ---------------------------------------------------------------
            
            td_bootstrap --state -- "$@"
            if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
                td_state_reset
                sayinfo "State file reset as requested."
            fi

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


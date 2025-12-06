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
#   Creates a repository and a VS Code workspace file
# Options :
#   
# ==============================================================================
set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    SCRIPT_FILE="${BASH_SOURCE[0]}"
    SCRIPT_NAME=""
    SCRIPT_DESC="Short description of what this script does."
    SCRIPT_VERSION="1.0"
    SCRIPT_VERSION_STATUS="alpha"
    SCRIPT_BUILD="20250110"

    # Determine the directory where this script lives
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Derive default SCRIPT_NAME from SCRIPT_FILE if not explicitly set
    if [[ -z "${SCRIPT_NAME:-}" ]]; then
        base="$(basename "$SCRIPT_FILE")"
        SCRIPT_NAME="${base%.sh}"
    fi

    # Determine the testadura root:
        # If "target-root" is part of the script path, use that as TD_ROOT
        # Otherwise fall back to the real root "/"
        TD_ROOT="$SCRIPT_DIR"
        RUN_MODE="production"
        while [[ "$TD_ROOT" != "/" ]]; do
        if [[ "$(basename "$TD_ROOT")" == "target-root" ]]; then
            RUN_MODE="development"
            break
        fi
            TD_ROOT="$(dirname "$TD_ROOT")"
        done

        # If we reached "/" without finding target-root, assume production
        if [[ "$TD_ROOT" == "/" ]]; then
            TD_ROOT=""
        fi

    # Find framework libraries
    DEV_COMMON_LIB="${TD_ROOT}/usr/local/lib/testadura/common"
    SYS_COMMON_LIB="/usr/local/lib/testadura/common"

    if [[ -d "$DEV_COMMON_LIB" ]]; then
        COMMON_LIB="$DEV_COMMON_LIB"
    elif [[ -d "$SYS_COMMON_LIB" ]]; then
        COMMON_LIB="$SYS_COMMON_LIB"
    else
        say FAIL "SoluxGround framework not found in either %s or %s" "$DEV_COMMON_LIB" "$SYS_COMMON_LIB"
    fi

    DEBUGMODE=0
    
# --- Argument specification ---------------------------------------------------
    # --------------------------------------------------------------------------
    # Each entry:
    #   "name|short|type|var|help|choices"
    #
    #   name    = long option name WITHOUT leading --
    #   short   = short option name WITHOUT leading -
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
    ARGS_SPEC=(
        "project|p|value|PROJECT_NAME|Project name|"
        "folder|f|value|PROJECT_FOLDER|Set project folder|"
        "dryrun|d|flag|FLAG_DRYRUN| Emulate only don't do any work|"
        "mode|m|enum|ENUM_MODE|Execution mode: Interactive or Auto|Interactive,Auto"
        "version|v|action|show_version|Show version information"
    )

    SCRIPT_EXAMPLES=(
    "Show help"
    "  $SCRIPT_NAME --help"
    ""
    "Perform a dry run:"
    "  $SCRIPT_NAME --dryrun"
    "  $SCRIPT_NAME -d"
    )

# --- Optional: custom config loading ----------------------------------------
    # ------------------------------------------------------------------------
    # If you define this function, bootstrap will call it before parsing args.
    # If you DON'T define it, bootstrap will automatically try:
    #   $SCRIPT_DIR/${SCRIPT_NAME}.conf
    #
    # Example:
    #
    # load_config() {
    #   local cfg="$SCRIPT_DIR/${SCRIPT_NAME}.conf"
    #   [[ -f "$cfg" ]] && . "$cfg"
    # }
    # -----------------------------------------------------------------------


# --- local script functions -------------------------------------------------
    __resolve_project_settings()
    {
        local mode template_dir slug default_name default_folder default_template base

        mode="${ENUM_MODE:-Interactive}"
        template_dir="/usr/local/dev/soluxground/target-root/usr/local/lib/testadura/templates"
        default_name="Script1.sh"
        default_projectname="Project"
        sample_scriptname="Script.sh"

        skip_template=0

        # Ensure a sane default template if not provided
        if [[ -d "$template_dir" ]]; then
            TEMPLATE_SCRIPT="$(find "$template_dir" -maxdepth 1 -type f | sort | head -n 1 || true)"
        fi

        # --- Non-interactive AUTO mode:
            #   Only if project AND folder are both provided.  

            if [[ "$mode" == "Auto" && -n "${PROJECT_NAME:-}" && -n "${PROJECT_FOLDER:-}" ]]; then
                if [[ -z "${TEMPLATE_SCRIPT:-}" || ! -f "$TEMPLATE_SCRIPT" ]]; then
                    sayfail "No valid template script found in $template_dir and none provided explicitly."
                    sayinfo "Skipping scriptfile creation, create one manually."
                    return 2
                fi

                # Normalize folder to absolute path
                if [[ "$PROJECT_FOLDER" != /* ]]; then
                    PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi

                sayinfo "Mode Auto: using project $PROJECT_NAME in folder $PROJECT_FOLDER" 
                sayinfo "Mode Auto: using template script $TEMPLATE_SCRIPT" 
                return 0
            fi

        # --- Interactive mode OR missing arguments:
            while true; do
             
                #  Get user input
                ask --label "Project name " --var PROJECT_NAME --default "$default_projectname"
                slug="${PROJECT_NAME// /-}"

                if [[ -n "${PROJECT_FOLDER:-}" ]]; then
                    default_folder="$PROJECT_FOLDER"
                else
                    default_folder="/usr/local/dev/${slug}"
                fi
                
                ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder"

                ask --label "Script template " --var TEMPLATE_SCRIPT --default "$TEMPLATE_SCRIPT" --validate validate_file_exists

                if [[ -z "${TEMPLATE_SCRIPT:-}" || ! -f "$TEMPLATE_SCRIPT" ]]; then
                    sayfail "Template script ${TEMPLATE_SCRIPT:-<empty>} is not a valid file." "${TEMPLATE_SCRIPT:-<empty>}"
                    return 2
                fi

                # Normalize folder to absolute path
                if [[ "$PROJECT_FOLDER" != /* ]]; then
                    PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi
                
                __display_summary
                if ask_ok_redo_quit "Proceed with these settings?"; then
                    # OK (0)
                    return 0
                else
                    ret=$?     # <- capture the 10 or 20
                    case $ret in
                        10) continue ;;             # REDO
                        20) saywarning "Aborted." ; return 1 ;;
                        *)  sayfail "Unexpected code: $ret" ; return 1 ;;
                    esac
                fi
            done
        # -- Summary

    }
    
    __display_summary(){
        justsay "${CLR_LABEL}--- Summary"
        justsay "${CLR_LABEL}Using project name     ${CLR_INPUT}$PROJECT_NAME" 
        justsay "${CLR_LABEL}Using project folder   ${CLR_INPUT}$PROJECT_FOLDER" 
        justsay "${CLR_LABEL}Using template script  ${CLR_INPUT}$TEMPLATE_SCRIPT" 
     }
    
    __create_repository()
    {
        mkdir -p "$PROJECT_FOLDER"
        
        DIRS=(
        "target-root"
        "target-root/etc"
        "target-root/usr/local/bin"
        "target-root/usr/local/lib"
        "target-root/usr/local/sbin"
        "docs"
        )

        for d in "${DIRS[@]}"; do
            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                mkdir -p "${PROJECT_FOLDER}/${d}"
                sayinfo "Created folder ${PROJECT_FOLDER}/${d}"
            else
                sayinfo "Would have created folder ${PROJECT_FOLDER}/${d}" 
            fi
            
        done
    }

    __create_workspace_file()
{
    local workspace_file="${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace"

     if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have created workspace file ${workspace_file}" 
        return 0
     fi

    cat > "$workspace_file" <<EOF
{
    "folders": [
        {
            "name": "${PROJECT_NAME}",
            "path": "."
        },
        {
            "name": "target-root",
            "path": "target-root"
        }
    ],
    "filesToOpen": [
        {
            "path": "target-root/usr/local/lib/${SCRIPT_NAME}.sh"
        }
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

    __copy_samplescript()
    {
        local src="$TEMPLATE_SCRIPT"
        local tmpl_dir="${PROJECT_FOLDER}/templates"
        local target_dir="${PROJECT_FOLDER}/target-root/usr/local/lib"
        local target_script="${target_dir}/${sample_scriptname}"

        # Safety checks
        if [[ -z "$src" || ! -f "$src" ]]; then
            sayfail "Cannot copy sample script: TEMPLATE_SCRIPT '${src:-<empty>}' is not a valid file."
            return 1
        fi

        #
        # Create templates directory
        #
        if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
            mkdir -p "$tmpl_dir"
            say info "Created templates directory ${tmpl_dir}"
        else
            say info "Would have created templates directory ${tmpl_dir}"
        fi

        #
        # Create library directory
        #
        if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
            mkdir -p "$target_dir"
            sayinfo "Created library directory ${target_dir}"
        else
            sayinfo "Would have created library directory ${target_dir}" 
        fi

        #
        # Copy original template into templates/
        #
        if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
            cp "$src" "$tmpl_dir/"
            sayinfo "Copied template script into ${tmpl_dir}" 
        else
            sayinfo "Would have copied template script into ${tmpl_dir}" 
        fi

        #
        # Install renamed script into target-root/usr/local/lib/
        #
        if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
            cp "$src" "$target_script"
            sayinfo "Installed script as ${target_script}" 
        else
            sayinfo "Would have installed script as ${target_script}" 
        fi

        return 0
    }


# --- main() must be the last function in the script -------------------------
    showarguments() {
        printf "Script          : %s\n" "$SCRIPT_NAME"
        printf "Script dir      : %s\n" "$SCRIPT_DIR"

        printf -- "Arguments / Flags:\n"

        local entry varname
        for entry in "${ARGS_SPEC[@]}"; do
            # Split the spec into fields
            IFS='|' read -r name short type varname help choices <<< "$entry"

            # Skip empty or malformed entries
            [[ -z "$varname" ]] && continue

            # Use indirect expansion to get the variable value
            local value="${!varname:-<unset>}"

            printf "  %-15s = %s\n" "$varname" "$value"
        done

        # Optional: print other environment metadata
        printf "Run mode        : %s\n" "$RUN_MODE"
        printf "COMMON_LIB      : %s\n" "$COMMON_LIB"
        printf "TD_ROOT         : %s\n" "$TD_ROOT"
    }

    main() {

        showarguments

        # Resolve settings (0=OK, 1=abort, 2=skip template)
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

        # Only when proceed==0 do we also create/copy the sample script
        if [[ "$proceed" -eq 0 ]]; then
            __copy_samplescript
        fi

    }

# --- Hand off to the bootstrapper (framework) ----------------------------
    AUTOLOAD_FRAMEWORK=true
    # shellcheck source=/dev/null
    . "${COMMON_LIB}/bootstrap.sh"

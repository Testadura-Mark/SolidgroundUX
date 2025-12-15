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
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_FILE")" && pwd)"
    SCRIPT_NAME="$(basename "$SCRIPT_FILE")"
    SCRIPT_DESC="Create a VSCode repository."
    SCRIPT_VERSION="1.0"
    SCRIPT_VERSION_STATUS="alpha"
    SCRIPT_BUILD="20250110"

# --- Framework roots (explicit) ----------------------------------------------
    # Override from environment if desired:
    #   TD_ROOT=/some/path COMMON_LIB=/some/path/common ./yourscript.sh
    TD_ROOT="${TD_ROOT:-/usr/local/lib/testadura}"
    COMMON_LIB="${COMMON_LIB:-$TD_ROOT/common}"
    COMMON_LIB_DEV="$( getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/dev/soluxground/target-root/usr/local/lib/testadura/common"

# --- Using / imports ----------------------------------------------------------
    # Edit this list per script, like a “using” section in C#.
    # Keep it explicit; avoid auto-loading *.sh.
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"    # td_parse_args, td_show_help
    "cfg.sh"    # td_cfg_load, config discovery + source
    "ui.sh"     # user inetractive helpers
    "default-colors.sh" # color definitions for terminal output
    "default-styles.sh" # text styles for terminal output
    )

    td_source_libs() {
        local lib path path_dev

        for lib in "${TD_USING[@]}"; do
            path="$COMMON_LIB/$lib"

            if [[ -f "$path" ]]; then
                # shellcheck source=/dev/null
                source "$path"
                continue
            fi

            # Fallback to dev location if configured
            if [[ -n "${COMMON_LIB_DEV:-}" ]]; then
                path_dev="$COMMON_LIB_DEV/$lib"
                if [[ -f "$path_dev" ]]; then
                    echo "[INFO] Using dev library: $path_dev" >&2
                    # shellcheck source=/dev/null
                    source "$path_dev"
                    continue
                fi
            fi

            echo "[FAIL] Missing library: $path" >&2
            [[ -n "${path_dev:-}" ]] && echo "[FAIL] Also not found in: $path_dev" >&2
            exit 1
        done
    }

    td_source_libs

# --- Example: Arguments -------------------------------------------------------
    # Define ARGS_SPEC to enable td_parse_args.
    #
    # Format:
    #   "name|short|type|var|help|choices"
    #
    # Notes:
    # - Keep trailing "|" if choices is empty.
    # - 'flag'  -> default 0, becomes 1 if present
    # - 'value' -> consumes next token
    # - 'enum'  -> consumes next token, must match choices list
    ARGS_SPEC=(
        "project|p|value|PROJECT_NAME|Project name|"
        "folder|f|value|PROJECT_FOLDER|Set project folder|"
        "dryrun|d|flag|FLAG_DRYRUN| Emulate only don't do any work|"
        "mode|m|enum|ENUM_MODE|Execution mode: Interactive or Auto|Interactive,Auto"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output|"
    )

    SCRIPT_EXAMPLES=(
        "Show help"
        "  $SCRIPT_NAME --help"
        ""
        "Perform a dry run:"
        "  $SCRIPT_NAME --dryrun"
        "  $SCRIPT_NAME -d"
    )

    # Parse args (creates: HELP_REQUESTED, TD_POSITIONAL and initializes option vars)
    td_parse_args "$@" || exit 1

    if [[ "${HELP_REQUESTED:-0}" -eq 1 ]]; then
        td_show_help
        exit 0
    fi

# --- Example: Config loading --------------------------------------------------
    # cfg.sh supports:
    #   CFG_FILE -> explicit path (set via --config above)
    #   CFG_AUTO -> 1/0 (default 1) auto discovery if CFG_FILE not set
    #
    # Auto-discovery order (per cfg.sh):
    #   1) <script_dir>/<script>.conf           (optional)
    #   2) /etc/testadura/<script>.conf         (optional)
    #   3) /etc/testadura/testadura.conf        (optional)
    #
    # If you want to disable auto-discovery:
    #   CFG_AUTO=0
    #
    # You can also define a custom load_config() function in this script;
    # td_cfg_load will call it instead of its own discovery logic.
    td_cfg_load || exit 1

# --- Example: Post-load defaults ---------------------------------------------
# Config can define defaults; CLI can override them. Decide your precedence.
    # Here: if ENUM_MODE not set via CLI, default to "auto".
    if [[ -z "${ENUM_MODE:-}" ]]; then
        ENUM_MODE="auto"
    fi
    


# --- local script functions -------------------------------------------------
    __resolve_project_settings()
    {
        local mode template_dir slug default_name default_folder default_template base

        mode="${ENUM_MODE:-Interactive}"
        template_dir="${TD_ROOT}/usr/local/lib/testadura/templates"
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
                    default_folder="$HOME/dev/${slug}"
                fi
                
                ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder"

                ask --label "Script template " --var TEMPLATE_SCRIPT --default "$TEMPLATE_SCRIPT" --validate validate_file_exists

                if [[ -z "${TEMPLATE_SCRIPT:-}" || ! -f "$TEMPLATE_SCRIPT" ]]; then
                    sayfail "Template script ${TEMPLATE_SCRIPT:-<empty>} is not a valid file." "${TEMPLATE_SCRIPT:-<empty>}"
                    return 2
                fi

                 justsay "$PROJECT_FOLDER"
                # Normalize folder to absolute path
                if [[ "$PROJECT_FOLDER" != /* ]]; then
                   PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi
                justsay "$PROJECT_FOLDER"

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
        "target-root/etc/systemd/system"
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
     __td_showarguments() {
        printf "Script              : %s\n" "$SCRIPT_NAME"
        printf "Script dir          : %s\n" "$SCRIPT_DIR"
        printf "[INFO] TD_ROOT      : $TD_ROOT"
        printf "[INFO] COMMON_LIB   : $COMMON_LIB"
        printf "[INFO] CFG_FILE    : ${CFG_FILE:-<auto>}"
        print "[INFO] MODE        : ${ENUM_MODE:-<unset>}"
        printf "[INFO] Positional  : ${TD_POSITIONAL[*]:-<none>}"
        printf -- "Arguments / Flags:\n"

        local entry varname
        for entry in "${ARGS_SPEC[@]:-}"; do
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

        td_parse_args "$@"

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi
        
        cannot_root

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

    main "${TD_POSITIONAL[@]}"


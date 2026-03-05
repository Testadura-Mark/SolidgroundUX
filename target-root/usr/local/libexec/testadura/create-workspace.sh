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
set -uo pipefail
# --- Load bootstrapper ------------------------------------------------------------
    _bootstrap_default="/usr/local/lib/testadura/common/td-bootstrap.sh"

    # Optional non-interactive overrides (useful for CI/dev installs)
    # - TD_BOOTSTRAP: full path to td-bootstrap.sh
    # - TD_FRAMEWORK_PREFIX: sysroot/prefix that contains usr/local/lib/testadura/common/td-bootstrap.sh

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
            printf "  - common dir (the folder that contains td-bootstrap.sh), e.g. /home/me/dev/solidgroundux/target-root/usr/local/lib/testadura/common\n"
            printf "  - full path to td-bootstrap.sh\n\n"

            read -r -p "Path (empty to abort): " _root </dev/tty
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

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Create workspace"
    : "${TD_SCRIPT_DESC:=Create a new project workspace from templates}"
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
        "Show help"
        "  $TD_SCRIPT_NAME --help"
        ""
        "Perform a dry run:"
        "  $TD_SCRIPT_NAME --dryrun"
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


# --- local script functions ---------------------------------------------------
    # __resolve_project_settings
        #   Resolve project name and target folder for a new workspace.
        #
        # Description:
        #   Prompts the user for project settings and confirms the resulting values.
        #   The function resolves:
        #
        #     PROJECT_NAME   Name of the project
        #     PROJECT_FOLDER Absolute path to the project directory
        #
        #   The project name is converted to a filesystem-safe slug (spaces replaced
        #   with '-') which is used to derive the default project folder if none is
        #   provided.
        #
        #   The function loops until the user confirms the settings or aborts.
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Sets the following variables in the caller scope:
        #
        #     PROJECT_NAME
        #     PROJECT_FOLDER
        #
        # Returns:
        #   0  Settings confirmed
        #   1  User aborted or an unexpected response occurred
        #
        # Notes:
        #   - Relative project folder paths are normalized to absolute paths.
        #   - Uses ask() and ask_ok_redo_quit() for interactive input.
        #   - Confirmation includes a short auto-continue timeout.
    __resolve_project_settings()
    {
        local template_dir slug default_name default_folder default_template base default_projectname

        default_projectname="Project"j
           
        # --- Non-interactive AUTO mode:
        
        # --- Interactive mode OR missing arguments:
            while true; do
             
                #  Get user input
                ask --label "Project name " --var PROJECT_NAME --default "$default_projectname"
                slug="${PROJECT_NAME// /-}"


                if [[ -n "${PROJECT_FOLDER:-}" ]]; then
                    default_folder="$PROJECT_FOLDER"
                else
                    default_folder="$TD_USER_HOME/dev/${slug}"
                fi

                ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder"

                # Normalize folder to absolute path
                if [[ "$PROJECT_FOLDER" != /* ]]; then
                   PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi

                sayinfo "Project name   : $PROJECT_NAME"
                sayinfo "Project folder : $PROJECT_FOLDER"

                ask_ok_redo_quit "Continue with these settings?" 15
                case $? in
                    0) break ;;   # OK
                    1) PROJECT_NAME=""; PROJECT_FOLDER=""; continue ;;  # REDO
                    2) saycancel "Aborting as per user request."; return 1 ;;
                    *) sayfail "Aborting (unexpected response)."; return 1 ;;
                esac
            done
        # -- Summary

    }
    
    # __create_repository
        #   Create the project repository structure and copy template files.
        #
        # Description:
        #   Creates the directory layout required for a Testadura-style project
        #   workspace under PROJECT_FOLDER. The structure includes a staging
        #   "target-root" tree that mirrors the eventual filesystem deployment
        #   layout.
        #
        #   After creating the directory structure, template files are copied
        #   from the framework templates directory into the project repository.
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Creates directories and copies template files under PROJECT_FOLDER.
        #
        # Returns:
        #   0 on success
        #   Non-zero if filesystem operations fail.
        #
        # Notes:
        #   - Honors FLAG_DRYRUN and reports intended actions without modifying
        #     the filesystem when enabled.
        #   - Template files are copied from:
        #
        #       ${TD_COMMON_LIB}/../templates
        #
        #   - Missing template directories are reported but do not cause failure.
    __create_repository()
    {
        local d template_dir
        local -a DIRS
        
        mkdir -p "$PROJECT_FOLDER"
        
        DIRS=(
        "target-root"
        "target-root/etc/systemd/system"
        "target-root/usr/local/bin"
        "target-root/usr/local/lib"
        "target-root/usr/local/sbin"
        "target-root/usr/local/libexec"
        "target-root/usr/local/lib/testadura/templates"
        "target-root/usr/local/share/doc"
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
        template_dir="${TD_COMMON_LIB}/../templates"
        if [[ -d "$template_dir" ]]; then
            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                cp -r -v "${template_dir}/." "$PROJECT_FOLDER/target-root/usr/local/lib/testadura/templates/"
                sayinfo "Copied templates to ${PROJECT_FOLDER}/target-root/usr/local/lib/testadura/templates/"
            else
                sayinfo "Would have copied templates to ${PROJECT_FOLDER}/target-root/usr/local/lib/testadura/templates/" 
            fi
        else
            saywarning "Template directory $template_dir does not exist; skipping template copy."
        fi

    }

    # __create_workspace_file
        #   Generate a VS Code workspace configuration for the project.
        #
        # Description:
        #   Creates a .code-workspace file in the project root that defines
        #   the project folder and a minimal set of editor settings.
        #
        #   The workspace configuration includes:
        #
        #     - The project root folder
        #     - File exclusion patterns (.git, .DS_Store)
        #     - Default terminal working directory
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Creates:
        #
        #     ${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace
        #
        # Returns:
        #   0 on success
        #   Non-zero if file creation fails.
        #
        # Notes:
        #   - Honors FLAG_DRYRUN and reports the intended action without creating
        #     the workspace file when enabled.
        #   - The generated workspace assumes the project root as the workspace
        #     folder.
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

# --- main -----------------------------------------------------------------------
    # main MUST BE LAST function in script
    main() {
        # -- Bootstrap
            local rc proceed
            td_bootstrap -- "$@"
            rc=$?
            if (( rc != 0 )); then
                exit "$rc"
            fi
           
            saydebug "bootstrap returns: $rc"
            saydebug "FLAG HELP : $FLAG_HELP FLAG_SHOWARGS : $FLAG_SHOWARGS"
            
            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_print_titlebar

        # -- Main script logic
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
            
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have fixed ownership and permissions"
            else 
                saydebug "Fixing ownership and permissions $PROJECT_FOLDER"
                td_fix_ownership "${PROJECT_FOLDER}"
                td_fix_permissions "${PROJECT_FOLDER}"
            fi
    }

    main "$@"


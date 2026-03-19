#!/usr/bin/env bash
# ===================================================================================
# Testadura Consultancy — Create Workspace
# -----------------------------------------------------------------------------------
# Module     : create-workspace.sh
# Purpose    : Create a new development workspace from templates
#
# Description:
#   Developer utility that scaffolds a new project workspace into a target
#   directory using the framework's standard template layout.
#
#   The script can:
#     - resolve project name and target folder
#     - create the required repository and target-root structure
#     - copy framework template files
#     - generate a VS Code workspace file
#     - generate a standard .gitignore
#
# Design principles:
#   - Uses the canonical executable bootstrap flow
#   - Keeps workspace creation deterministic and repeatable
#   - Honors dry-run mode for all filesystem changes
#   - Follows Testadura / SolidGround project conventions
#
# Intended use:
#   - Development and project scaffolding
#   - Not intended for deployment or runtime installation
#
# Author     : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ===================================================================================
set -uo pipefail
# --- Bootstrap --------------------------------------------------------------------
    # __framework_locator
        # Purpose:
        #   Locate, create, and load the SolidGroundUX bootstrap configuration.
        #
        # Behavior:
        #   - Searches user and system bootstrap configuration locations.
        #   - Prefers the invoking user's config over the system config.
        #   - Creates a new bootstrap config when none exists.
        #   - Prompts for framework/application roots in interactive mode.
        #   - Applies default values when running non-interactively.
        #   - Sources the selected configuration file.
        #
        # Outputs (globals):
        #   TD_FRAMEWORK_ROOT
        #   TD_APPLICATION_ROOT
        #
        # Returns:
        #   0   success
        #   126 configuration unreadable or invalid
        #   127 configuration directory or file could not be created
        #
        # Usage:
        #   __framework_locator || return $?
        #
        # Examples:
        #   __framework_locator
        #
        # Notes:
        #   - Under sudo, configuration is resolved relative to SUDO_USER instead of /root.
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
        # Purpose:
        #   Resolve and source the framework bootstrap library.
        #
        # Behavior:
        #   - Calls __framework_locator to establish framework roots.
        #   - Derives the td-bootstrap.sh path from TD_FRAMEWORK_ROOT.
        #   - Verifies that the bootstrap library is readable.
        #   - Sources td-bootstrap.sh into the current shell.
        #
        # Inputs (globals):
        #   TD_FRAMEWORK_ROOT
        #
        # Returns:
        #   0   success
        #   126 bootstrap library unreadable
        #
        # Usage:
        #   __load_bootstrapper || return $?
        #
        # Examples:
        #   __load_bootstrapper
        #
        # Notes:
        #   - This is executable-level startup logic, not reusable framework behavior.
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

# --- Script metadata --------------------------------------------------------------
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
        # Optional: script-specific argument definitions.
        #
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        # Fields:
        #   name    Long option name without leading --
        #   short   Short option name without leading -
        #   type    flag | value | enum
        #   var     Shell variable to receive the parsed value
        #   help    Help text for auto-generated --help output
        #   choices Comma-separated values for enum; empty otherwise
        #
        # Notes:
        #   - -h / --help is built in and does not need to be defined here.
        #   - Parsed values become available in the configured target variables.
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


# --- local script functions -------------------------------------------------------
    # __resolve_project_settings
        # Purpose:
        #   Resolve and confirm the project name and target folder for a new workspace.
        #
        # Behavior:
        #   - Prompts for the project name.
        #   - Derives a filesystem-safe slug from the project name.
        #   - Uses the slug to build a default project folder when none is already set.
        #   - Prompts for the project folder.
        #   - Normalizes relative folder paths to absolute paths.
        #   - Displays a summary and asks the user to confirm, redo, or abort.
        #   - Repeats until the settings are confirmed or the user cancels.
        #
        # Outputs (globals):
        #   PROJECT_NAME
        #   PROJECT_FOLDER
        #
        # Returns:
        #   0  settings confirmed
        #   1  user aborted or an unexpected response occurred
        #
        # Usage:
        #   __resolve_project_settings || return $?
        #
        # Examples:
        #   if __resolve_project_settings; then
        #       sayinfo "Creating workspace at $PROJECT_FOLDER"
        #   fi
        #
        # Notes:
        #   - Uses ask() and ask_ok_redo_quit() for interactive input.
        #   - Confirmation includes a short auto-continue timeout.
    __resolve_project_settings(){
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
        # Purpose:
        #   Create the project repository structure and copy template files.
        #
        # Behavior:
        #   - Creates the project root folder when needed.
        #   - Creates the standard target-root directory layout under PROJECT_FOLDER.
        #   - Copies framework template files into the repository template location.
        #   - Honors dry-run mode by reporting intended actions without modifying the filesystem.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   TD_COMMON_LIB
        #   FLAG_DRYRUN
        #
        # Side effects:
        #   - Creates directories under PROJECT_FOLDER.
        #   - Copies template files into the new repository.
        #
        # Returns:
        #   0 on success
        #   Non-zero if required filesystem operations fail
        #
        # Usage:
        #   __create_repository
        #
        # Examples:
        #   __create_repository || return 1
        #
        # Notes:
        #   - Template files are copied from:
        #       ${TD_COMMON_LIB}/../templates
        #   - Missing template directories are reported but do not currently cause failure.
    __create_repository(){
        local d template_dir
        local -a DIRS
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created folder ${PROJECT_FOLDER}"
        else
            saydebug "Creating folder ${PROJECT_FOLDER}"
            mkdir -p "$PROJECT_FOLDER"
        fi
        
        DIRS=(
        "target-root"
        "target-root/etc/systemd/system"
        "target-root/usr/local/bin"
        "target-root/usr/local/lib"
        "target-root/usr/local/sbin"
        "target-root/usr/local/libexec"
        "target-root/usr/local/lib/testadura/templates"
        "target-root/usr/local/share/doc/$PROJECT_NAME/"
        "target-root/var/lib/testadura/releases"
        "target-root/var/state"
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
        # Purpose:
        #   Generate a VS Code workspace file for the new project.
        #
        # Behavior:
        #   - Creates a .code-workspace file in the project root.
        #   - Configures the project root as the workspace folder.
        #   - Adds a minimal set of editor settings and file exclusions.
        #   - Honors dry-run mode by reporting the intended action without writing the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   FLAG_DRYRUN
        #
        # Side effects:
        #   - Creates or overwrites:
        #       ${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace
        #
        # Returns:
        #   0 on success
        #   Non-zero if file creation fails
        #
        # Usage:
        #   __create_workspace_file
        #
        # Examples:
        #   __create_workspace_file || return 1
        #
        # Notes:
        #   - The generated workspace assumes the project root as the workspace folder.
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
            printf '    "terminal.integrated.cwd": "${workspaceFolder}"\n'
            printf '  }\n'
            printf '}\n'
        } > "$workspace_file"

        sayinfo "Created VS Code workspace file ${workspace_file}"
    }

    # __create_gitignore_file
        # Purpose:
        #   Create a standard .gitignore file in the project workspace root.
        #
        # Behavior:
        #   - Writes a predefined .gitignore containing common exclusions for
        #     Testadura / SolidGround development environments.
        #   - Covers OS artifacts, IDE metadata, logs, runtime state, build output,
        #     archives, environment files, and common backup/swap files.
        #   - Honors dry-run mode by reporting the intended action without creating the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   FLAG_DRYRUN
        #
        # Side effects:
        #   - Creates or overwrites:
        #       ${PROJECT_FOLDER}/.gitignore
        #
        # Returns:
        #   0 on success
        #
        # Usage:
        #   __create_gitignore_file
        #
        # Examples:
        #   __create_gitignore_file
        #
        # Notes:
        #   - The ignore rules are intentionally generic and safe for most script-based projects.
    __create_gitignore_file(){
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created .gitignore" 
            return 0
        fi

        sayinfo "Creating .gitignore"
        saydebug "${PROJECT_FOLDER}/.gitignore"

        printf '%s\n' \
        '# --------------------------------------------------' \
        '# OS junk' \
        '# --------------------------------------------------' \
        '.DS_Store' \
        'Thumbs.db' \
        '*~' \
        '' \
        '# --------------------------------------------------' \
        '# Editors / IDE' \
        '# --------------------------------------------------' \
        '.vscode/*' \
        '!.vscode/settings.json' \
        '!.vscode/extensions.json' \
        '.idea/' \
        '' \
        '# --------------------------------------------------' \
        '# Logs' \
        '# --------------------------------------------------' \
        '*.log' \
        'logs/' \
        '' \
        '# --------------------------------------------------' \
        '# Runtime / state' \
        '# --------------------------------------------------' \
        '*.state' \
        '*.pid' \
        '*.lock' \
        'tmp/' \
        'temp/' \
        '' \
        '# --------------------------------------------------' \
        '# Build / packaging' \
        '# --------------------------------------------------' \
        'build/' \
        'dist/' \
        'release/' \
        '' \
        '# --------------------------------------------------' \
        '# Archives' \
        '# --------------------------------------------------' \
        '*.zip' \
        '*.tar' \
        '*.tar.gz' \
        '*.tgz' \
        '' \
        '# --------------------------------------------------' \
        '# Environment / secrets' \
        '# --------------------------------------------------' \
        '.env' \
        '.env.*' \
        '' \
        '# --------------------------------------------------' \
        '# Misc' \
        '# --------------------------------------------------' \
        '*.bak' \
        '*.swp' \
        '*.swo' \
        > "${PROJECT_FOLDER}/.gitignore"
    }

# --- main -------------------------------------------------------------------------
    # main
        # Purpose:
        #   Execute the workspace creation workflow.
        #
        # Behavior:
        #   - Loads the framework bootstrapper.
        #   - Initializes the framework runtime via td_bootstrap.
        #   - Executes builtin framework argument handling.
        #   - Prepares the standard UI state and title bar.
        #   - Resolves project settings interactively.
        #   - Creates the repository structure, workspace file, and .gitignore.
        #   - Applies final ownership and permission fixes when not in dry-run mode.
        #
        # Arguments:
        #   $@  Framework and script-specific command-line arguments
        #
        # Returns:
        #   Exits with the resulting status produced by bootstrap or script logic
        #
        # Usage:
        #   main "$@"
        #
        # Examples:
        #   main "$@"
        #
        # Notes:
        #   - td_bootstrap splits framework arguments from script arguments automatically.
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
            __create_gitignore_file
            
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have fixed ownership and permissions"
            else 
                saydebug "Fixing ownership and permissions $PROJECT_FOLDER"
                td_fix_ownership "${PROJECT_FOLDER}"
                td_fix_permissions "${PROJECT_FOLDER}"
            fi
    }

    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"


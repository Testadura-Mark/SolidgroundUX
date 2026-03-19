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
#     - generate a workspace creation manifest
#     - optionally generate a console-module app config
#     - remove previously created workspace items through --uncreate
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
        "exe|e|flag|FLAG_EXE|Create executable template and folders|"
        "lib|l|flag|FLAG_LIB|Create library template and folders|"
        "mod|m|flag|FLAG_MOD|Create console module template and folders|"
        "modfolder|M|value|MOD_FOLDER|Location of console module (optional)|"
        "project|p|value|PROJECT_NAME|Project name|"
        "folder|f|value|PROJECT_FOLDER|Set project folder|"
        "uncreate|u|flag|FLAG_UNCREATE|Remove items listed in workspace manifest|"
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
 # -- General helpers
    # __normalize_project_flags
        # Purpose:
        #   Normalize project selection flags into a coherent default state.
        #
        # Behavior:
        #   - If no project flags are given, defaults to executable and library.
        #
        # Inputs (globals):
        #   FLAG_EXE
        #   FLAG_LIB
        #   FLAG_MOD
        #
        # Outputs (globals):
        #   FLAG_EXE
        #   FLAG_LIB
        #   FLAG_MOD
        #
        # Returns:
        #   0 on success
    __normalize_project_flags() {
        if (( ! ${FLAG_EXE:-0} )) && (( ! ${FLAG_LIB:-0} )) && (( ! ${FLAG_MOD:-0} )); then
            FLAG_EXE=1
            FLAG_LIB=1
            FLAG_MOD=0
        fi

        return 0
    }

    # __copy_template_file
        # Purpose:
        #   Copy a single template file to a target location.
        #
        # Behavior:
        #   - Verifies the source template exists.
        #   - Creates the destination parent directory when needed.
        #   - Honors dry-run mode by reporting the intended action only.
        #   - Records the destination file in the manifest only when it did not exist before.
        #
        # Arguments:
        #   $1  Source template file
        #   $2  Destination file
        #
        # Returns:
        #   0 on success
        #   1 on failure
    __copy_template_file() {
        local src="$1"
        local dst="$2"
        local existed=0

        [[ -f "$src" ]] || {
            sayfail "Template file not found: $src"
            return 1
        }

        [[ -e "$dst" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have copied template $src -> $dst"
            return 0
        fi

        mkdir -p "$(dirname "$dst")" || return 1
        cp "$src" "$dst" || return 1

        if (( ! existed )); then
            __manifest_record_file "$dst"
        fi

        sayinfo "Copied template $src -> $dst"
    }

    # __get_template_filenames
        # Purpose:
        #   Determine output filenames for selected template types.
        #
        # Arguments:
        #   $1  Name reference for exe filename
        #   $2  Name reference for lib filename
        #   $3  Name reference for mod filename
    __get_template_filenames() {
        local -n exe_ref=$1
        local -n lib_ref=$2
        local -n mod_ref=$3
        local project_slug=""

        project_slug="${PROJECT_NAME// /-}"
        project_slug="${project_slug,,}"

        exe_ref="${project_slug}.sh"

        if (( ${FLAG_EXE:-0} )) && (( ${FLAG_LIB:-0} )); then
            lib_ref="${project_slug}-lib.sh"
        else
            lib_ref="${project_slug}.sh"
        fi

        mod_ref="mod-${project_slug}.sh"
    }

    # __copy_project_templates
        # Purpose:
        #   Copy the appropriate template file(s) for the selected project components.
        #
        # Behavior:
        #   - Copies exe-template when FLAG_EXE=1
        #   - Copies lib-template when FLAG_LIB=1
        #   - Copies mod-template when FLAG_MOD=1
        #   - Uses component-specific output filenames
        #
        # Inputs (globals):
        #   PROJECT_NAME
        #   PROJECT_FOLDER
        #   FLAG_EXE
        #   FLAG_LIB
        #   FLAG_MOD
        #   TD_COMMON_LIB
        #
        # Returns:
        #   0 on success
        #   1 on failure
    __copy_project_templates() {
        local template_dir=""
        local exe_file=""
        local lib_file=""
        local mod_file=""
        local project_slug=""

        project_slug="${PROJECT_NAME// /-}"
        project_slug="${project_slug,,}"

        template_dir="${TD_COMMON_LIB}/../templates"

        [[ -d "$template_dir" ]] || {
            saywarning "Template directory $template_dir does not exist; skipping template copy."
            return 0
        }

        __get_template_filenames exe_file lib_file mod_file

        if (( ${FLAG_EXE:-0} )); then
            __copy_template_file \
                "${template_dir}/exe-template.sh" \
                "${PROJECT_FOLDER}/target-root/usr/local/libexec/${exe_file}" \
                || return 1
        fi

        if (( ${FLAG_LIB:-0} )); then
            __copy_template_file \
                "${template_dir}/lib-template.sh" \
                "${PROJECT_FOLDER}/target-root/usr/local/lib/${lib_file}" \
                || return 1
        fi

        if (( ${FLAG_MOD:-0} )); then
            __copy_template_file \
                "${template_dir}/mod-template.sh" \
                "${PROJECT_FOLDER}/target-root/usr/local/libexec/${project_slug}/${mod_file}" \
                || return 1
        fi
    }

    # __get_project_directories
        # Purpose:
        #   Build the directory list required for the selected project components.
        #
        # Behavior:
        #   - Adds shared target-root folders when any component is selected
        #   - Adds executable folders when FLAG_EXE=1
        #   - Adds library folders when FLAG_LIB=1
        #   - Adds module folders when FLAG_MOD=1
        #
        # Arguments:
        #   $1  Name reference to output array
        #
        # Inputs (globals):
        #   PROJECT_NAME
        #   FLAG_EXE
        #   FLAG_LIB
        #   FLAG_MOD
        #
        # Returns:
        #   0 on success
    __get_project_directories() {
        local -n out_ref=$1
        local project_slug=""

        project_slug="${PROJECT_NAME// /-}"
        project_slug="${project_slug,,}"

        out_ref=()

        if (( ${FLAG_EXE:-0} )) || (( ${FLAG_LIB:-0} )) || (( ${FLAG_MOD:-0} )); then
            out_ref+=(
                "target-root"
                "target-root/usr/local/share/doc/$PROJECT_NAME"
                "target-root/var/state"
            )
        fi

        if (( ${FLAG_EXE:-0} )); then
            out_ref+=(
                "target-root/etc/systemd/system"
                "target-root/usr/local/bin"
                "target-root/usr/local/sbin"
                "target-root/usr/local/libexec"
                "target-root/var/lib/testadura/releases"
            )
        fi

        if (( ${FLAG_LIB:-0} )); then
            out_ref+=(
                "target-root/usr/local/lib"
                "target-root/usr/local/lib/testadura/templates"
            )
        fi

        if (( ${FLAG_MOD:-0} )); then
            out_ref+=(
                "target-root/usr/local/libexec"
                "target-root/usr/local/libexec/${project_slug}"
            )
        fi
    }

 # -- Manifest helpers
    # __manifest_init
        # Purpose:
        #   Initialize the workspace creation manifest.
        #
        # Behavior:
        #   - Sets WORKSPACE_MANIFEST under the project root.
        #   - Writes a small manifest header with project name and timestamp.
        #   - Honors dry-run mode by reporting the intended action without writing the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   FLAG_DRYRUN
        #
        # Outputs (globals):
        #   WORKSPACE_MANIFEST
        #
        # Returns:
        #   0 on success
        #   Non-zero on failure
    __manifest_init() {
        WORKSPACE_MANIFEST="${PROJECT_FOLDER}/.create-workspace.manifest"

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have initialized manifest ${WORKSPACE_MANIFEST}"
            return 0
        fi

        mkdir -p "$PROJECT_FOLDER" || return 1

        {
            printf '%s\n' "# create-workspace manifest"
            printf '# project: %s\n' "$PROJECT_NAME"
            printf '# created: %(%F %T)T\n' -1
        } > "$WORKSPACE_MANIFEST" || return 1
    }

    # __manifest_record_file
        # Purpose:
        #   Append a file entry to the workspace manifest.
        #
        # Arguments:
        #   $1  Absolute file path
        #
        # Behavior:
        #   - Does nothing when WORKSPACE_MANIFEST is unset.
        #   - Does nothing in dry-run mode.
        #   - Appends a FILE record to the manifest.
        #
        # Returns:
        #   0 always
    __manifest_record_file() {
        local path="$1"

        [[ -n "${WORKSPACE_MANIFEST:-}" ]] || return 0
        [[ "$FLAG_DRYRUN" -eq 1 ]] && return 0

        printf 'FILE|%s\n' "$path" >> "$WORKSPACE_MANIFEST"
    }

    # __manifest_record_dir
        # Purpose:
        #   Append a directory entry to the workspace manifest.
        #
        # Arguments:
        #   $1  Absolute directory path
        #
        # Behavior:
        #   - Does nothing when WORKSPACE_MANIFEST is unset.
        #   - Does nothing in dry-run mode.
        #   - Appends a DIR record to the manifest.
        #
        # Returns:
        #   0 always
    __manifest_record_dir() {
        local path="$1"

        [[ -n "${WORKSPACE_MANIFEST:-}" ]] || return 0
        [[ "$FLAG_DRYRUN" -eq 1 ]] && return 0

        printf 'DIR|%s\n' "$path" >> "$WORKSPACE_MANIFEST"
    }

    # __uncreate_from_manifest
        # Purpose:
        #   Remove files and directories listed in a workspace manifest.
        #
        # Behavior:
        #   - Validates that the manifest exists.
        #   - Reads FILE and DIR entries from the manifest.
        #   - Removes files first.
        #   - Removes directories afterwards in reverse order.
        #   - Removes only empty directories by using rmdir.
        #   - Removes the manifest itself last.
        #   - Honors dry-run mode by reporting intended actions without modifying the filesystem.
        #
        # Arguments:
        #   $1  Manifest file path
        #
        # Returns:
        #   0 on success
        #   1 when the manifest does not exist
    __uncreate_from_manifest() {
        local manifest="$1"
        local line=""
        local kind=""
        local path=""
        local -a files=()
        local -a dirs=()
        local i=0

        [[ -f "$manifest" ]] || {
            sayfail "Manifest not found: $manifest"
            return 1
        }

        # Read manifest entries
        while IFS= read -r line; do
            [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

            kind="${line%%|*}"
            path="${line#*|}"

            case "$kind" in
                FILE) files+=( "$path" ) ;;
                DIR)  dirs+=( "$path" ) ;;
            esac
        done < "$manifest"

        # Remove files first
        for path in "${files[@]}"; do
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have removed file $path"
            else
                if [[ -f "$path" ]]; then
                    rm -f "$path" || return 1
                    sayinfo "Removed file $path"
                fi
            fi
        done

        # Remove directories last, deepest first
        for (( i=${#dirs[@]}-1; i>=0; i-- )); do
            path="${dirs[i]}"

            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have removed directory $path"
            else
                if [[ -d "$path" ]]; then
                    rmdir "$path" 2>/dev/null || true
                    sayinfo "Removed directory (if empty) $path"
                fi
            fi
        done

        # Remove manifest itself last
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have removed manifest $manifest"
        else
            rm -f "$manifest" || return 1
            sayinfo "Removed manifest $manifest"
        fi
    }

 # -- Main sequence
    # __resolve_project_settings
        # Purpose:
        #   Resolve and confirm the project name and target folder for a new workspace.
        #
        # Behavior:
        #   - Prompts for the project name.
        #   - Prompts whether to include executable, library, and console-module components.
        #   - Prompts for the console module app folder when module support is enabled.
        #   - Derives a filesystem-safe slug from the project name.
        #   - Uses the selected components to determine a default project folder.
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
        local slug=""
        local default_folder=""
        local default_projectname="Project"
        local lw=25
        local mxw=60

        while true; do
            td_print
            td_print_sectionheader "Project name and location" --maxwidth "$mxw"
            ask --label "Project name " --var PROJECT_NAME --default "$default_projectname" --labelwidth "$lw"

            slug="${PROJECT_NAME// /-}"
            slug="${slug,,}"

            local resp
            local default

            # Get Project folder
            if [[ -n "${PROJECT_FOLDER:-}" ]]; then
                default_folder="$PROJECT_FOLDER"
            else
                default_folder="$TD_USER_HOME/dev/${slug}"
            fi
            ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder" --labelwidth "$lw"
            if [[ "$PROJECT_FOLDER" != /* ]]; then
               PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
            fi

            td_print
            td_print_sectionheader "Script templates to include" --maxwidth "$mxw"
            lw=35
            # Include exe script
            if [[ "${FLAG_EXE:-0}" -eq 1 ]]; then
                default="Y"
            else
                default="N"
            fi
            ask --label "Include executable script (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw" 
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_EXE=1 || FLAG_EXE=0

            # Include library script
            if [[ "${FLAG_LIB:-0}" -eq 1 ]]; then
                default="Y"
            else
                default="N"
            fi
            ask --label "Include library script (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw"
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_LIB=1 || FLAG_LIB=0
            
            # Include console module
            if [[ "${FLAG_MOD:-0}" -eq 1 ]]; then
                default="Y"
            else
                default="N"
            fi
            
            ask --label "Include console module (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw"
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_MOD=1 || FLAG_MOD=0
            saydebug "${slug}"
            if (( ${FLAG_MOD:-0} )); then
                lw=25
                if [[ -n "${MOD_FOLDER:-}" ]]; then
                    ask --label "Console module app folder " --var MOD_FOLDER --default "$MOD_FOLDER" --labelwidth "$lw"
                else
                    ask --label "Console module app folder " --var MOD_FOLDER --default "$PROJECT_FOLDER/target-root/usr/local/libexec/${slug}" --labelwidth "$lw"
                fi

                if [[ "$MOD_FOLDER" != /* ]]; then
                    MOD_FOLDER="$(pwd)/$MOD_FOLDER"
                fi
            else
                MOD_FOLDER=""
            fi


            if (( ! FLAG_EXE )) && (( ! FLAG_LIB )) && (( ! FLAG_MOD )); then
                saywarning "Nothing selected; defaulting to executable and library."
                FLAG_EXE=1
                FLAG_LIB=1
                FLAG_MOD=0
            fi

            td_print 
            td_print_sectionheader "Summary" --maxwidth "$mxw"

            local exe_text="no"
            local lib_text="no"
            local mod_text="no"

            (( ${FLAG_EXE:-0} )) && exe_text="yes"
            (( ${FLAG_LIB:-0} )) && lib_text="yes"
            (( ${FLAG_MOD:-0} )) && mod_text="yes"

            td_print_labeledvalue --label "Project name"   --value "$PROJECT_NAME"
            td_print_labeledvalue --label "Project folder" --value "$PROJECT_FOLDER"
            td_print_labeledvalue --label "Executable"     --value "$exe_text"
            td_print_labeledvalue --label "Library"        --value "$lib_text"
            td_print_labeledvalue --label "Console module" --value "$mod_text"
            if (( ${FLAG_MOD:-0} )); then
                 td_print_labeledvalue --label "Module app dir" --value "${MOD_FOLDER:-<none>}"
            fi

            td_print 
            td_print_sectionheader --maxwidth "$mxw"

            ask_ok_redo_quit "Continue with these settings?" 15
            case $? in
                0) break ;;
                1) PROJECT_NAME=""; PROJECT_FOLDER=""; continue ;;
                2) saycancel "Aborting as per user request."; return 1 ;;
                *) sayfail "Aborting (unexpected response)."; return 1 ;;
            esac
        done
    }
    
    # __create_repository
        # Purpose:
        #   Create the project repository structure and copy template files.
        #
        # Behavior:
        #   - Creates the project root folder when needed.
        #   - Builds the directory structure based on selected project components.
        #   - Copies only the applicable template file(s).
        #   - Honors dry-run mode by reporting intended actions without modifying the filesystem.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   FLAG_EXE
        #   FLAG_LIB
        #   FLAG_MOD
        #   TD_COMMON_LIB
        #   FLAG_DRYRUN
        #
        # Returns:
        #   0 on success
        #   Non-zero if required filesystem operations fail
    __create_repository(){
        local d=""
        local -a dirs=()

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created folder ${PROJECT_FOLDER}"
        else
            if [[ ! -d "$PROJECT_FOLDER" ]]; then
                saydebug "Creating folder ${PROJECT_FOLDER}"
                mkdir -p "$PROJECT_FOLDER" || return 1
                __manifest_record_dir "${PROJECT_FOLDER}"
            fi
        fi

        __get_project_directories dirs || return 1

        for d in "${dirs[@]}"; do
            if [[ "$d" == "." ]]; then
                continue
            fi

            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                if [[ ! -d "${PROJECT_FOLDER}/${d}" ]]; then
                    mkdir -p "${PROJECT_FOLDER}/${d}" || return 1
                    sayinfo "Created folder ${PROJECT_FOLDER}/${d}"
                    __manifest_record_dir "${PROJECT_FOLDER}/${d}"
                fi
            else
                sayinfo "Would have created folder ${PROJECT_FOLDER}/${d}"
            fi
        done

        __copy_project_templates || return 1
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
        local existed=0

        [[ -e "$workspace_file" ]] && existed=1

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
        } > "$workspace_file" || return 1

        if (( ! existed )); then
            __manifest_record_file "$workspace_file"
        fi

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
        local gitignore_file="${PROJECT_FOLDER}/.gitignore"
        local existed=0

        [[ -e "$gitignore_file" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created .gitignore" 
            return 0
        fi

        sayinfo "Creating .gitignore"
        saydebug "$gitignore_file"

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
        > "$gitignore_file" || return 1

        if (( ! existed )); then
            __manifest_record_file "$gitignore_file"
        fi
    }

    # __create_mod_appcfg
        # Purpose:
        #   Create a console-module application configuration file.
        #
        # Behavior:
        #   - Does nothing when MOD_FOLDER is empty.
        #   - Creates the MOD_FOLDER directory when needed.
        #   - Writes a <project>.app.cfg file pointing to the generated module script.
        #   - Honors dry-run mode by reporting the intended action without writing the file.
        #
        # Inputs (globals):
        #   PROJECT_NAME
        #   PROJECT_FOLDER
        #   MOD_FOLDER
        #   FLAG_DRYRUN
        #
        # Returns:
        #   0 on success
        #   Non-zero on failure
    __create_mod_appcfg() {
        local project_slug=""
        local appcfg_file=""
        local existed=0
        local mod_folder_existed=0

        [[ -n "${MOD_FOLDER:-}" ]] || return 0

        project_slug="${PROJECT_NAME// /-}"
        project_slug="${project_slug,,}"
        appcfg_file="${MOD_FOLDER%/}/${project_slug}.app.cfg"

        [[ -e "$appcfg_file" ]] && existed=1
        [[ -d "$MOD_FOLDER" ]] && mod_folder_existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created module app config ${appcfg_file}"
            return 0
        fi

        mkdir -p "$MOD_FOLDER" || return 1

        if (( ! mod_folder_existed )); then
            __manifest_record_dir "$MOD_FOLDER"
        fi

        {
            printf '%s\n' "# ----------------------------------------------------------------------"
            printf '%s\n' "# Console module app config"
            printf '%s\n' "# Auto-generated by create-workspace"
            printf '%s\n' "# ----------------------------------------------------------------------"
            printf '\n'
            printf 'APP_TITLE=%q\n' "$PROJECT_NAME"
            printf 'MODULE_DIR=%q\n' "${PROJECT_FOLDER}/target-root/usr/local/libexec/${project_slug}"
            printf 'MODULE_FILE=%q\n' "mod-${project_slug}.sh"
        } > "$appcfg_file" || return 1

        if (( ! existed )); then
            __manifest_record_file "$appcfg_file"
        fi

        sayinfo "Created module app config ${appcfg_file}"
    }

# --- main -------------------------------------------------------------------------
    # main
        # Purpose:
        #   Execute the workspace creation or uncreation workflow.
        #
        # Behavior:
        #   - Loads the framework bootstrapper.
        #   - Initializes the framework runtime via td_bootstrap.
        #   - Executes builtin framework argument handling.
        #   - Normalizes project selection flags.
        #   - Prepares the standard UI state and title bar.
        #   - In uncreate mode:
        #       - validates the workspace manifest
        #       - confirms removal with the user
        #       - removes files and directories listed in the manifest
        #   - In normal mode:
        #       - resolves project settings interactively
        #       - initializes the workspace manifest
        #       - creates the repository structure, workspace file, and .gitignore
        #       - optionally creates a console-module app config
        #       - applies final ownership and permission fixes when not in dry-run mode.
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
            local proceed=0
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

            __normalize_project_flags || exit 1

        # -- UI
            td_update_runmode
            td_print_titlebar

        # -- Main script logic
          # -- Uncreate mode
            if (( ${FLAG_UNCREATE:-0} )); then
                if [[ -z "${PROJECT_FOLDER:-}" ]]; then
                    sayfail "Uncreate requires --folder <workspace>"
                    exit 1
                fi

                if [[ "$PROJECT_FOLDER" != /* ]]; then
                    PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi

                local manifest="${PROJECT_FOLDER}/.create-workspace.manifest"

                [[ -f "$manifest" ]] || {
                    sayfail "Manifest not found: $manifest"
                    exit 1
                }

                saywarning "About to remove workspace items listed in manifest:"
                saywarning "$manifest"

                ask_ok_redo_quit "Proceed with uncreate?" 10
                case $? in
                    0) ;;
                    1) exit 0 ;;
                    2) saycancel "Aborted."; exit 0 ;;
                esac

                __uncreate_from_manifest "$manifest" || exit $?

                sayok "Uncreate completed"
                exit 0
            fi
          # -- 'Normal' operation
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
            __manifest_init || exit $?
            __create_repository || exit $?
            __create_workspace_file || exit $?
            __create_gitignore_file || exit $?
            
            if (( ${FLAG_MOD:-0} )); then
                __create_mod_appcfg || exit $?
            fi

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


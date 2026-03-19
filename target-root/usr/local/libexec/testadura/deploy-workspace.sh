#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — Deploy Workspace
# ----------------------------------------------------------------------------------
# Purpose:
#   Deploy or remove a development workspace to/from a target root.
#
# Description:
#   Synchronizes a structured workspace into a target filesystem root.
#
#   The script:
#     - Copies files from source to target while preserving structure
#     - Creates destination directories as required
#     - Applies permission policy based on PERMISSION_RULES
#     - Skips private, hidden, and non-deployable files by convention
#     - Supports undeploy (removal) operations
#
# Deployment model:
#   - Source is treated as a workspace root
#   - Target is treated as a filesystem root (/, chroot, image root, etc.)
#   - Files are installed if missing or newer than target
#   - Undeploy removes only files originating from the workspace
#
# Notes:
#   - May require root privileges depending on target
#   - Honors FLAG_DRYRUN, FLAG_VERBOSE, and FLAG_DEBUG
#
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================
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

# --- Script metadata (identity) ---------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Deploy workspace"
    : "${TD_SCRIPT_DESC:=Deploy a development workspace to a target root filesystem.}"
    : "${TD_SCRIPT_VERSION:=1.0}"
    : "${TD_SCRIPT_BUILD:=20250110}"
    : "${TD_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${TD_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${TD_SCRIPT_COPYRIGHT:=© 2025 Mark Fieten — Testadura Consultancy}"
    : "${TD_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.0}"

    readonly BOOTSTRAP
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
        "auto|a|flag|FLAG_AUTO|Repeat with last settings|"
        "undeploy|u|flag|FLAG_UNDEPLOY|Remove files from main root|"
        "source|s|value|SRC_ROOT|Set Source directory|"
        "target|t|value|DEST_ROOT|Set Target directory|"
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
        "Deploy using defaults:"
        "  $TD_SCRIPT_NAME"
        ""
        "Undeploy everything:"
        "  $TD_SCRIPT_NAME --undeploy"
        "  $TD_SCRIPT_NAME -u"
    ) 

    # TD_SCRIPT_GLOBALS
        # Explicit declaration of global variables intentionally used by this script.
        #
        # IMPORTANT:
        #   - If this array is non-empty, td_bootstrap will enable config loading.
        #   - Variables listed here may be populated from configuration files.
        #   - This makes TD_SCRIPT_GLOBALS part of the script’s configuration contract.
        #
        # Use this to:
        #   - Document intentional globals
        #   - Prevent accidental namespace leakage
        #   - Enable cfg integration in a predictable way
        #
        # Only list:
        #   - Variables that are meant to be globally accessible
        #   - Variables that may be set via config files
        #
        # Leave empty if:
        #   - The script does not use config-driven globals
        #
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

    # PERMISSION_RULES
    #   Declarative permission policy for installed paths.
    #
    # Format (pipe-delimited):
    #   "<prefix>|<file_mode>|<dir_mode>|<description>"
    #
    # Matching:
    #   - Longest prefix match wins.
    #   - A rule applies if abs path equals the prefix or is within the prefix folder.
    #
    # Modes:
    #   - file_mode is used for regular files (install -m).
    #   - dir_mode  is used for directories (install -d -m).
    #
    # Notes:
    #   - This is a policy table: keep it stable and predictable.
    #   - Description is informational only; not used in logic.
    PERMISSION_RULES=(
        "/usr/local/bin|755|755|User entry points"
        "/usr/local/sbin|755|755|Admin entry points"
        "/etc/update-motd.d|755|755|Executed by system"
        "/usr/local/lib/testadura|644|755|Implementation only"
        "/usr/local/lib/testadura/common/tools|755|755|Implementation only"
        "/etc/testadura|640|750|Configuration"
        "/var/lib/testadura|600|700|Application state"
    )

# --- local script functions -------------------------------------------------------
    # __perm_resolve
        # Purpose:
        #   Resolve the effective permission mode for a given path based on PERMISSION_RULES.
        #
        # Arguments:
        #   $1  abs_rel   Absolute path relative to root (e.g. "/usr/local/bin/foo")
        #   $2  kind      "file" or "dir"
        #
        # Behavior:
        #   - Applies longest-prefix match against PERMISSION_RULES
        #   - Returns file_mode or dir_mode depending on kind
        #   - Falls back to defaults when no rule matches
        #
        # Output:
        #   Prints the resolved mode to stdout (no newline)
        #
        # Returns:
        #   0 always
        #
        # Defaults:
        #   file → 644
        #   dir  → 755
        #
        # Usage:
        #   mode="$(__perm_resolve "/usr/local/bin/foo" "file")"
        #
        # Examples:
        #   dir_mode="$(__perm_resolve "/usr/local/bin" "dir")"
    __perm_resolve() {
        local abs_rel="$1"   # e.g. "/usr/local/sbin/td-foo"
        local kind="$2"      # "file" or "dir"

        local best_prefix=""
        local best_file="644"
        local best_dir="755"

        local entry prefix file_mode dir_mode desc

        for entry in "${PERMISSION_RULES[@]}"; do
            IFS='|' read -r prefix file_mode dir_mode desc <<< "$entry"

            if [[ "$abs_rel" == "$prefix" || "$abs_rel" == "$prefix/"* ]]; then
                if [[ ${#prefix} -gt ${#best_prefix} ]]; then
                    best_prefix="$prefix"
                    best_file="$file_mode"
                    best_dir="$dir_mode"
                fi
            fi
        done

        if [[ "$kind" == "dir" ]]; then
            echo "$best_dir"
        else
            echo "$best_file"
        fi
    }

    # __update_lastdeployinfo
        # Purpose:
        #   Persist metadata of the last deployment run for reuse (e.g. auto mode).
        #
        # Behavior:
        #   - Stores timestamp, source, and target in state
        #   - Skips writes when FLAG_DRYRUN is enabled
        #
        # Writes:
        #   last_deploy_run
        #   last_deploy_source
        #   last_deploy_target
        #
        # Inputs (globals):
        #   SRC_ROOT
        #   DEST_ROOT
        #   FLAG_DRYRUN
        #
        # Returns:
        #   0 on success
        #
        # Usage:
        #   __update_lastdeployinfo
    __update_lastdeployinfo() {
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have saved lastdeployinfo"
        else
            saydebug "Saving last deploymentinfo"
            td_state_set "last_deploy_run" "$(date --iso-8601=seconds)"
            td_state_set "last_deploy_source" "$SRC_ROOT"
            td_state_set "last_deploy_target" "${DEST_ROOT:-/}"
        fi
    }

    # __getparameters
        # Purpose:
        #   Collect deployment parameters (source and target roots).
        #
        # Behavior:
        #   - Auto mode:
        #       Uses last deployment settings when available
        #   - Interactive mode:
        #       Prompts for SRC_ROOT and DEST_ROOT
        #       Validates SRC_ROOT structure (advisory only)
        #       Asks for confirmation (OK/Redo/Quit)
        #
        # Validation:
        #   - SRC_ROOT is considered valid if it contains "etc/" or "usr/"
        #   - Validation is advisory only (does not block execution)
        #
        # Outputs (globals):
        #   SRC_ROOT
        #   DEST_ROOT
        #
        # Returns:
        #   0 → confirmed
        #   1 → aborted
        #
        # Usage:
        #   __getparameters || return $?
        #
        # Notes:
        #   - Uses ask and ask_ok_redo_quit
    __getparameters() {
        local default_src default_dst
        default_src="${last_deploy_source:-$HOME/dev}"
        default_dst="${last_deploy_target:-/}"

        # --- Auto mode --------------------------------------------------------------
        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
            if [[ -n "${last_deploy_source:-}" && -n "${last_deploy_target:-}" ]]; then
                sayinfo "Auto mode: using last deployment settings."
                SRC_ROOT="$last_deploy_source"
                DEST_ROOT="$last_deploy_target"
                td_print_titlebar
                return 0
            fi
            saywarning "Auto mode requested, but no previous deployment settings found."
        fi

        # --- Interactive mode -------------------------------------------------------
        while true; do
            # --- Source root --------------------------------------------------------
            if [[ -z "${SRC_ROOT:-}" ]]; then
                ask --label "Workspace source root" \
                    --var SRC_ROOT \
                    --default "$default_src" \
                    --colorize both
            fi

            # Advisory validation
            if [[ -d "$SRC_ROOT/etc" || -d "$SRC_ROOT/usr" ]]; then
                sayinfo "Source root '$SRC_ROOT' looks valid."
            else
                saywarning "Source root '$SRC_ROOT' doesn't look valid; should contain 'etc/' and/or 'usr/'."
            fi

            # --- Target root --------------------------------------------------------
            if [[ -z "${DEST_ROOT:-}" ]]; then
                ask --label "Target root folder" \
                    --var DEST_ROOT \
                    --default "$default_dst" \
                    --colorize both
            fi
            DEST_ROOT="${DEST_ROOT:-/}"

            ask_ok_redo_quit "Continue with deployment?" 15
            case $? in
                0) break ;;   # OK
                1) SRC_ROOT=""; DEST_ROOT=""; continue ;;  # REDO
                2) saycancel "Aborting as per user request."; return 1 ;;
                *) sayfail "Aborting (unexpected response)."; return 1 ;;
            esac
        done

        td_print_titlebar
        return 0
    }

    # __deploy
        # Purpose:
        #   Deploy workspace files from SRC_ROOT into DEST_ROOT.
        #
        # Behavior:
        #   - Recursively processes files under SRC_ROOT
        #   - Computes relative path and destination path
        #   - Skips:
        #       - top-level files
        #       - "_" prefixed files
        #       - ".old" files
        #       - hidden or "_" directories
        #
        # Update logic:
        #   - Installs when destination is missing or source is newer
        #
        # Permissions:
        #   - File mode via __perm_resolve(abs_rel,"file")
        #   - Directory mode via __perm_resolve(rel_dir,"dir")
        #
        # Dry run:
        #   - When FLAG_DRYRUN=1, only reports actions
        #
        # Inputs (globals):
        #   SRC_ROOT
        #   DEST_ROOT
        #   FLAG_DRYRUN
        #   PERMISSION_RULES
        #
        # Returns:
        #   0 always (logs and continues on errors)
        #
        # Usage:
        #   __deploy
        #
        # Notes:
        #   - Uses install for atomic writes and permission control
    __deploy(){
        SRC_ROOT="${SRC_ROOT%/}"
        DEST_ROOT="${DEST_ROOT%/}"

        local file rel name abs_rel perms dst dst_dir dir_mode

        saystart "Starting deployment from $SRC_ROOT to ${DEST_ROOT:-/}"

        find "$SRC_ROOT" -type f |
        while IFS= read -r file; do

            rel="${file#"$SRC_ROOT"/}"

            if [[ "$rel" == "$file" || "$rel" == /* ]]; then
                sayerror "Bad rel path: file='$file' SRC_ROOT='$SRC_ROOT' rel='$rel'"
                continue
            fi

            name="$(basename "$file")"
            abs_rel="/$rel"

            perms="$(__perm_resolve "$abs_rel" "file")"
            dst="${DEST_ROOT:-}/$rel"

            # Skip top-level files, hidden dirs, private dirs
            if [[ "$rel" != */* || "$name" == _* || "$name" == *.old || \
                "$rel" == .*/* || "$rel" == _*/* || \
                "$rel" == */.*/* || "$rel" == */_*/* ]]; then
                continue
            fi

            if [[ ! -e "$dst" || "$file" -nt "$dst" ]]; then
                dst_dir="$(dirname "$dst")"
                dir_mode="$(__perm_resolve "/${rel%/*}" "dir")"

                if [[ $FLAG_DRYRUN == 0 ]]; then
                    sayinfo "Installing $SRC_ROOT/$rel --> $dst, with $perms permissions"
                    install -d -m "$dir_mode" "$dst_dir"
                    install -m "$perms" "$SRC_ROOT/$rel" "$dst"
                else
                    sayinfo "Would have installed $SRC_ROOT/$rel --> $dst, with $perms permissions"
                fi
            else
                saydebug "Skipping $rel; destination is up-to-date."
            fi

        done

        sayend "End deployment complete."
    }

    # __undeploy
        # Purpose:
        #   Remove deployed files from DEST_ROOT that originate from SRC_ROOT.
        #
        # Behavior:
        #   - Enumerates files in SRC_ROOT to determine targets
        #   - Applies same skip rules as __deploy
        #   - Removes matching files from DEST_ROOT
        #
        # Dry run:
        #   - When FLAG_DRYRUN=1, only reports actions
        #
        # Inputs (globals):
        #   SRC_ROOT
        #   DEST_ROOT
        #   FLAG_DRYRUN
        #
        # Returns:
        #   0 always
        #
        # Usage:
        #   __undeploy
        #
        # Notes:
        #   - Only removes files known to the workspace (safe inverse deployment)
    __undeploy(){

        saystart "Starting UNINSTALL from $SRC_ROOT to $DEST_ROOT" --show=symbol

        find "$SRC_ROOT" -type f |
        while IFS= read -r file; do
        
        local file rel name dst
        rel="${file#$SRC_ROOT/}"
        name="$(basename "$file")"
        dst="${DEST_ROOT%/}/$rel"

        if [[ "$rel" != */* || "$name" == _* || "$name" == *.old || \
                "$rel" == .*/* || "$rel" == _*/* || \
                "$rel" == */.*/* || "$rel" == */_*/* ]]; then
            continue
        fi

        if [[ -e "$dst" ]]; then
            saywarning "Removing $dst"
            if [[ $FLAG_DRYRUN == 0 ]]; then
                rm -f "$dst"
            else
                sayinfo "Would have removed $dst"
            fi
        else
            saywarning "Skipping $rel; does not exist."
        fi

        done
    }

# --- Main -------------------------------------------------------------------------
    # main
        # Purpose:
        #   Execute the workspace deployment workflow.
        #
        # Behavior:
        #   - Loads and initializes the framework bootstrap
        #   - Handles builtin arguments
        #   - Displays title bar
        #   - Collects parameters
        #   - Executes deploy or undeploy
        #   - Persists deployment metadata
        #
        # Arguments:
        #   $@  Framework and script-specific arguments
        #
        # Returns:
        #   Exit status from executed operations
        #
        # Usage:
        #   main "$@"
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
            td_bootstrap --state --needroot -- "$@"
            rc=$?

            saydebug "After bootstrap: $rc"
            (( rc != 0 )) && exit "$rc"
                        
        # -- Handle builtin arguments
            saydebug "Calling builtinarg handler"
            td_builtinarg_handler
            saydebug "Exited builtinarg handler"

        # -- UI
            td_bootstrap --state --needroot -- "$@"
            local rc=$?
            (( rc != 0 )) && exit "$rc"

            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_print_titlebar

        # -- Main script logic
            __getparameters || return $?

            # -- Deploy or undeploy                    
            if [[ "${FLAG_UNDEPLOY:-0}" -eq 0 ]]; then
                __deploy || return $?
                __update_lastdeployinfo
            else
                __undeploy
            fi
    }
    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"
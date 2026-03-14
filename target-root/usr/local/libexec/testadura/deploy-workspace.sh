#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — deploy-workspace.sh
# ----------------------------------------------------------------------------------
# Purpose    : Deploy or remove a development workspace to/from a target root
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   Deployment utility for synchronizing a development workspace into a target
#   root filesystem.
#
#   - Copies files from source to target, preserving directory structure.
#   - Creates destination directories as needed.
#   - Sets file and directory permissions based on predefined rules.
#   - Skips private/hidden and top-level files by convention.
#   - Supports undeploy (removal) operations.
#   - Supports dry-run mode.
#
# Deployment Model:
#   - Source is treated as a structured workspace root.
#   - Target is treated as a filesystem root (/, chroot, image root, etc.).
#   - Files are installed only if missing or if the source is newer.
#   - Undeploy removes only files that correspond to workspace files.
#
# Assumptions:
#   - Target root is a prepared filesystem (e.g. /, chroot, container root).
#   - May require root privileges depending on target location.
#   - Permission policy is defined by PERMISSION_RULES within this script.
#
# Effects:
#   - Creates, updates, or removes files under the target root.
#   - Creates directories as required.
#   - Modifies file and directory permissions (mode only; no ownership changes).
#
# Usage examples:
#   ./deploy-workspace.sh --source /home/user/dev/myworkspace --target / --dryrun
#   ./deploy-workspace.sh -s /home/user/dev/myworkspace -t /
#   ./deploy-workspace.sh --undeploy -s /home/user/dev/myworkspace -t /
#   ./deploy-workspace.sh   # interactive mode
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
        #   Resolve the effective permission mode (octal string) for a given path,
        #   based on PERMISSION_RULES.
        #
        # Input:
        #   $1  abs_rel : absolute path rooted at "/", e.g. "/usr/local/sbin/td-foo"
        #   $2  kind    : "file" or "dir"
        #
        # Matching:
        #   - Uses longest-prefix match in PERMISSION_RULES.
        #   - A rule matches if abs_rel equals prefix or is under prefix (prefix/*).
        #
        # Output:
        #   Prints the resolved mode to stdout (no newline).
        #
        # Returns:
        #   0 always (pure resolver; no validation beyond rule matching).
        #
        # Defaults:
        #   - If no rule matches: file=644, dir=755.
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

     #__update_lastdeployinfo
        # Purpose:
        #   Persist "last deployment" metadata into the framework state store
        #   for later reuse (e.g. auto mode defaults).
        #
        # Writes:
        #   last_deploy_run       : ISO-8601 timestamp (seconds)
        #   last_deploy_source    : SRC_ROOT used
        #   last_deploy_target    : DEST_ROOT used (defaults to "/")
        #
        # Notes:
        #   - This function assumes td_state_set is available and state is enabled.
        #
        # Returns:
        #   0 on success; propagates td_state_set failures (if any).
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
        #   Collect deployment parameters (source root and target root) either
        #   automatically (auto mode) or interactively.
        #
        # Behavior:
        #   - Auto mode (FLAG_AUTO=1):
        #       Reuses last_deploy_source/last_deploy_target if available.
        #   - Interactive mode:
        #       Prompts for SRC_ROOT and DEST_ROOT (only if not already set).
        #       Prints an advisory message if SRC_ROOT does not look like a workspace
        #       root (missing 'etc/' and 'usr/' folders).
        #       Asks for final confirmation (OK/Redo/Quit) before returning.
        #
        # Validation Rules (advisory only):
        #   - SRC_ROOT is considered "valid-looking" if:
        #         $SRC_ROOT/etc  OR  $SRC_ROOT/usr exists
        #   - Invalid-looking SRC_ROOT does not block continuation; it only warns.
        #
        # Side Effects:
        #   Sets global variables:
        #       SRC_ROOT
        #       DEST_ROOT
        #
        # Returns:
        #   0  → parameters collected / confirmed
        #   1  → user aborted
        #
        # Exit Policy:
        #   This function never exits the script.
        #   It returns control to the caller.
        #
        # Assumptions:
        #   - ask and ask_ok_redo_quit exist
        #   - sayinfo/saywarning/saycancel/sayfail exist
        #   - last_deploy_source/last_deploy_target may exist
        #   - td_print_titlebar is available
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
        #   Deploy (install/update) workspace files from SRC_ROOT into DEST_ROOT
        #   using deterministic permission policy (PERMISSION_RULES).
        #
        # Behavior:
        #   - Walks SRC_ROOT recursively (files only).
        #   - Converts each file path to a relative workspace path (rel).
        #   - Computes destination path as:  DEST_ROOT + "/" + rel
        #   - Skips:
        #       - top-level files (must be in a subfolder)
        #       - files starting with "_" (private)
        #       - files ending with ".old"
        #       - any file under hidden or "_" directories at any depth
        #
        # Update logic:
        #   - Installs if destination does not exist OR source is newer (-nt).
        #
        # Permissions:
        #   - File mode resolved via __perm_resolve(abs_rel,"file")
        #   - Directory mode resolved via __perm_resolve("/<rel_dir>","dir")
        #   - Directories are created with install -d; files with install -m.
        #
        # Dry run:
        #   - If FLAG_DRYRUN=1, prints intended actions without changing filesystem.
        #
        # Inputs (globals):
        #   SRC_ROOT, DEST_ROOT, FLAG_DRYRUN, PERMISSION_RULES
        #
        # Returns:
        #   0 always (current implementation logs and continues on per-file issues).
        #
        # Notes:
        #   - Paths are normalized by stripping trailing "/" from SRC_ROOT/DEST_ROOT.
        #   - Uses a pipeline into while-read; function-level variables should be local
        #     if you ever rely on their values after the loop.
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
        #   Undeploy (remove) previously deployed files from DEST_ROOT that correspond
        #   to workspace files under SRC_ROOT.
        #
        # Behavior:
        #   - Walks SRC_ROOT recursively (files only) to determine expected targets.
        #   - Computes destination file path as: DEST_ROOT + rel
        #   - Applies the same skip rules as __deploy:
        #       - top-level files
        #       - "_" prefixed files
        #       - ".old" files
        #       - hidden or "_" directories at any depth
        #
        # Dry run:
        #   - If FLAG_DRYRUN=1, prints intended removals without deleting.
        #
        # Inputs (globals):
        #   SRC_ROOT, DEST_ROOT, FLAG_DRYRUN
        #
        # Returns:
        #   0 always (current implementation logs and continues).
        #
        # Notes:
        #   - This is an "inverse by enumeration" uninstall: it removes only files
        #     that exist in the workspace tree (not arbitrary leftovers).
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
        #   Canonical script entry point.
        #
        # Behavior:
        #   - Resolves and loads the framework bootstrap library.
        #   - Initializes framework runtime via td_bootstrap.
        #   - Executes builtin framework arguments.
        #   - Prints the standard title bar.
        #   - Runs script-specific logic.
        #
        # Arguments:
        #   $@  Framework and script-specific command-line arguments.
        #
        # Returns:
        #   Exits with the status produced by bootstrap or script logic.
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
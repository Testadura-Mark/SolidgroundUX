#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — deploy-workspace.sh
# -------------------------------------------------------------------------------
# Purpose : Generic script template
# Author  : Mark Fieten
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description :
#   Deploy a development workspace to a target root filesystem.
#   - Copies files from source to target, preserving structure.
#   - Sets permissions based on predefined rules.
#   - Optionally creates/removes symlinks for executables in /usr/local/bin.
# Usage examples:
#   ./deploy-workspace.sh --source /home/user/dev/myworkspace --target / --dryrun
#   ./deploy-workspace.sh -s /home/user/dev/myworkspace -t / --verbose
#   ./deploy-workspace.sh --undeploy -s /home/user/dev/myworkspace -t 
#  or simply:
#   ./deploy-workspace.sh and follow prompts.
# ==============================================================================
set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_DESC="Deploy a development workspace to a target root filesystem."
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_VERSION_STATUS="beta"
    TD_SCRIPT_BUILD="20250110"
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework roots (explicit) ----------------------------------------------
    # Override from environment if desired:
    # Directory where Testadura framework is installed
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-/}"
    # Application root (where this script is deployed)
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-/}"
    # Common libraries path
    TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}"
    # State and config files
    TD_STATE_FILE="${TD_STATE_FILE:-"$TD_APPLICATION_ROOT/var/testadura/$TD_SCRIPT_NAME.state"}"
    TD_CFG_FILE="${TD_CFG_FILE:-"$TD_APPLICATION_ROOT/etc/testadura/$TD_SCRIPT_NAME.cfg"}"
    # User home directory
    TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"

# --- Minimal fallback UI (overridden by ui.sh when sourced) -------------------
    saystart()   { printf '[STRT] %s\n' "$*" >&2; }
    saywarning() { printf '[WARN] %s\n' "$*" >&2; }
    sayfail()    { printf '[FAIL] %s\n' "$*" >&2; }
    saycancel()  { printf '[CNCL] %s\n' "$*" >&2; }
    sayend()     { printf '[END ] %s\n' "$*" >&2; }
    sayok()      { printf '[OK  ] %s\n' "$*" >&2; }
    sayinfo()    { printf '[INFO] %s\n' "$*" >&2; }
    sayerror()   { printf '[ERR ] %s\n' "$*" >&2; }

# --- Using / imports ----------------------------------------------------------
    # Edit this list per script, like a “using” section in C#.
    # Keep it explicit; avoid auto-loading *.sh.
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"   # td_parse_args, td_show_help
    "default-colors.sh" # color definitions for terminal output
    "default-styles.sh" # text styles for terminal output
    "ui.sh"     # user inetractive helpers
    "cfg.sh"    # td_cfg_load, config discovery + source, td_state_set
    
    
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

# --- Argument specification ---------------------------------------------------
    # --------------------------------------------------------------------------
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
        "undeploy|u|flag|FLAG_UNDEPLOY|Remove files from main root|"
        "source|s|value|SRC_ROOT|Set Source directory|"
        "target|t|value|DEST_ROOT|Set Target directory|"
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Deploy using defaults:"
        "  $TD_SCRIPT_NAME"
        ""
        "Undeploy everything:"
        "  $TD_SCRIPT_NAME --undeploy"
        "  $TD_SCRIPT_NAME -u"
    ) 

# --- local script functions -------------------------------------------------
    # Default permission rules
    PERMISSION_RULES=(
    "/usr/local/bin|755|755|User entry points"
    "/usr/local/sbin|755|755|Admin entry points"
    "/etc/update-motd.d|755|755|Executed by system"
    "/usr/local/lib/testadura|644|755|Implementation only"
    "/usr/local/lib/testadura/common/tools|755|755|Implementation only"
    "/etc/testadura|640|750|Configuration"
    "/var/lib/testadura|600|700|Application state"
    )
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

    __getparameters() {

        local default_src default_dst
        default_src="${last_deploy_source:-$USER_HOME/dev}"
        default_dst="${last_deploy_target:-/}"

        while true; do
            # --- Source root -----------------------------------------------------
            if [[ -z "${SRC_ROOT:-}" ]]; then
                ask --label "Workspace source root" --var SRC_ROOT --default "$default_src" --colorize both
            fi

            # --- Source root validation ------------------------------------------
            while true; do
                if [[ -d "$SRC_ROOT/etc" || -d "$SRC_ROOT/usr" ]]; then
                    sayinfo "Source root '$SRC_ROOT' looks valid."
                    break
                fi

                saywarning "Source root '$SRC_ROOT' doesn't look valid; should contain 'etc/' and/or 'usr/'."

                if ask_ok_redo_quit "Continue anyway?"; then
                    break
                fi

                case $? in
                    1) SRC_ROOT="" ;;  # REDO
                    2) saycancel "Aborting as per user request."; exit 1 ;;
                    *) sayfail "Aborting (unexpected response)."; exit 1 ;;
                esac

                ask --label "Workspace source root" --var SRC_ROOT --default "$default_src" --colorize both
            done

            # --- Target root -----------------------------------------------------
            if [[ -z "${DEST_ROOT:-}" ]]; then
                ask --label "Target root folder" --var DEST_ROOT --default "$default_dst" --colorize both
            fi
            DEST_ROOT="${DEST_ROOT:-/}"

            # --- Create exe symlinks ---------------------------------------------
            FLAG_LINK_EXES="${FLAG_LINK_EXES:-0}"

            if [[ "${last_deploy_link_exes:-0}" -eq 0 ]]; then
                if ask_noyes "Create executable symlinks in ${DEST_ROOT%/}/usr/local/bin?"; then
                    FLAG_LINK_EXES=1
                else
                    FLAG_LINK_EXES=0
                fi
            else
                if ask_yesno "Create executable symlinks in ${DEST_ROOT%/}/usr/local/bin?"; then
                    FLAG_LINK_EXES=1
                else
                    FLAG_LINK_EXES=0
                fi
            fi

            printf "%sDeployment parameter summary\n" "${BOLD_SILVER}"
            printf "  Source root         : %s\n" "$SRC_ROOT"
            printf "  Target root         : %s\n" "${DEST_ROOT:-/}"
            printf "  Create exe symlinks : %s\n" "$([[ "$FLAG_LINK_EXES" -eq 1 ]] && echo Yes || echo No)"

            if ask_ok_redo_quit "Continue with deployment?"; then
                sayinfo "Proceeding with deployment."
                td_state_set "last_deploy_run" "$(date --iso-8601=seconds)"
                td_state_set "last_deploy_source" "$SRC_ROOT"
                td_state_set "last_deploy_target" "${DEST_ROOT:-/}"
                td_state_set "last_deploy_link_exes" "$FLAG_LINK_EXES"
                return 0
            fi

            case $? in
                1)
                    # REDO: keep previous answers as defaults, or clear some fields if you prefer
                    # DEST_ROOT=""   # optionally force re-ask
                    # FLAG_LINK_EXES=0
                    continue
                    ;;
                2)
                    saycancel "Aborting as per user request."
                    exit 1
                    ;;
                *)
                    sayfail "Aborting (unexpected response)."
                    exit 1
                    ;;
            esac
        done
    }

    __deploy(){
        SRC_ROOT="${SRC_ROOT%/}"
        DEST_ROOT="${DEST_ROOT%/}"

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
                    sayinfo "$name --> $dst $perms"
                    install -d -m "$dir_mode" "$dst_dir"
                    install -m "$perms" "$SRC_ROOT/$rel" "$dst"
                else
                    sayinfo "Would have installed $SRC_ROOT/$rel --> $dst, with $perms permissions"
                fi
            else
                saywarning "Skipping $rel; destination is up-to-date."
            fi

        done

        sayend "End deployment complete."
    }
    __undeploy(){

        saystart "Starting UNINSTALL from $SRC_ROOT to $DEST_ROOT" --show=symbol

        find "$SRC_ROOT" -type f |
        while IFS= read -r file; do

        rel="${file#$SRC_ROOT/}"
        name="$(basename "$file")"
        dst="$DEST_ROOT$rel"

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

    __link_executables(){
        local root_dir="$DEST_ROOT/usr/local/lib/testadura"
        local bin_dir="$DEST_ROOT/usr/local/bin"

        [[ -d "$root_dir" ]] || return 0

        saystart "Creating symlinks in $bin_dir for executables under $root_dir" --show=symbol

        # Ensure bin directory exists
        if [[ $FLAG_DRYRUN == 0 ]]; then
            install -d "$bin_dir"
        else
            sayinfo "Would have ensured directory exists: $bin_dir"
        fi

        # Recursively find executable files, but EXCLUDE templates/
        find "$root_dir" \
            -path "$root_dir/templates" -prune -o \
            -type f -perm -111 -print |
        while IFS= read -r f; do

            # f example:
            #   /usr/local/lib/testadura/common/tools/create-workspace.sh

            local rel_target base_src base_noext base link_path

            # Produce a relative path for the symlink target
            rel_target="$(realpath --relative-to="$bin_dir" "$f")"

            base_src="$(basename "$f")"        # e.g., create-workspace.sh
            base_noext="${base_src%.sh}"       # e.g., create-workspace
            base="td-$base_noext"              # e.g., td-create-workspace

            link_path="$bin_dir/$base"

            # Optional: skip private/internal files
            case "$base" in
                td-_*) continue ;;
                td.*)  continue ;;
            esac

            if [[ $FLAG_DRYRUN == 0 ]]; then
                sayinfo "Linking $link_path -> $rel_target"
                ln -sfn "$rel_target" "$link_path"
            else
                sayinfo "Would have linked $link_path -> $rel_target"
            fi

        done

        sayend "Symlink creation complete."
    }

   __unlink_executables(){
        local bin_dir="$DEST_ROOT/usr/local/bin"
        local root_dir="$DEST_ROOT/usr/local/lib/testadura"

        [[ -d "$bin_dir" ]] || return 0

        saystart "Removing symlinks in $bin_dir pointing into Testadura" --show=symbol

        local link target resolved

        for link in "$bin_dir"/td-*; do
            [[ -L "$link" ]] || continue

            target="$(readlink "$link")"

            # Resolve to absolute path
            if [[ "$target" == /* ]]; then
                resolved="$target"
            else
                resolved="$(realpath "$bin_dir/$target")"
            fi

            # Does this link belong to Testadura?
            case "$resolved" in
                "$root_dir"/*)
                    saywarning "Removing symlink $link -> $resolved"
                    if [[ $FLAG_DRYRUN == 0 ]]; then
                        rm -f "$link"
                    else
                        sayinfo "Would remove $link"
                    fi
                    ;;
                *)
                    continue
                    ;;
            esac
        done

        sayend "Symlink cleanup complete."
    }

# --- main() must be the last function in the script -------------------------
    __td_showarguments() 
    {
        
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

    main() {
        # --- Source libraries ------------------------------------------------------
        td_source_libs

        # --- Ensure running as root -----------------------------------------------
        need_root "$@"

        # --- Load previous state and config
            # enable if desired:
            td_state_load
            #td_cfg_load

        # --- Parse arguments
            td_parse_args "$@"
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   

            if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
                __td_showarguments
            fi

            __getparameters

        # --- Deploy or undeploy                    
            if [[ "${FLAG_UNDEPLOY:-0}" -eq 0 ]]; then
                __deploy
                if [[ "$FLAG_LINK_EXES" -eq 1 ]]; then
                    __link_executables
                fi
            else
                __undeploy
                if [[ "$FLAG_LINK_EXES" -eq 1 ]]; then
                    __unlink_executables
                fi
            fi
    }

    main "$@"
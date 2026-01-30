#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — deploy-workspace.sh
# -------------------------------------------------------------------------------
# Purpose    : Deploy or remove a development workspace to/from a target root
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description:
#   Deployment utility for synchronizing a development workspace into a target
#   root filesystem.
#
#   - Copies files from source to target, preserving directory structure.
#   - Sets ownership and permissions based on predefined rules.
#   - Optionally creates or removes executable symlinks in /usr/local/bin.
#   - Supports undeploy (removal) operations.
#
# Assumptions:
#   - Target root is a prepared filesystem (e.g. /, chroot, image root).
#   - May require root privileges depending on target.
#
# Effects:
#   - Creates, overwrites, or removes files under the target root.
#   - May modify /usr/local/bin within the target root.
#
# Usage examples:
#   ./deploy-workspace.sh --source /home/user/dev/myworkspace --target / --dryrun
#   ./deploy-workspace.sh -s /home/user/dev/myworkspace -t / --verbose
#   ./deploy-workspace.sh --undeploy -s /home/user/dev/myworkspace -t /
#   Or simply:
#   ./deploy-workspace.sh   # interactive mode
# ===============================================================================
set -euo pipefail
# -- Find bootstrapper
    BOOTSTRAP="/usr/local/lib/testadura/common/td-bootstrap.sh"

    if [[ -r "$BOOTSTRAP" ]]; then
        # shellcheck disable=SC1091
        source "$BOOTSTRAP"
    else
        # Only prompt if interactive
        if [[ -t 0 ]]; then
            printf "\n"
            printf "Framework not installed in the default location."
            printf "Are you developing the framework or using a custom install path?\n\n"

            read -r -p "Enter framework root path (or leave empty to abort): " _root
            [[ -n "$_root" ]] || exit 127

            BOOTSTRAP="$_root/usr/local/lib/testadura/common/td-bootstrap.sh"
            if [[ ! -r "$BOOTSTRAP" ]]; then
                printf "FATAL: No td-bootstrap.sh found at provided location: $BOOTSTRAP"
                exit 127
            fi

            # Persist for next runs
            CFG="$HOME/.config/testadura/bootstrap.conf"
            mkdir -p "$(dirname "$CFG")"
            printf 'TD_FRAMEWORK_ROOT=%q\n' "$_root" > "$CFG"

            # shellcheck disable=SC1091
            source "$CFG"
            # shellcheck disable=SC1091
            source "$BOOTSTRAP"
        else
            printf "FATAL: Testadura framework not installed ($BOOTSTRAP missing)" >&2
            exit 127
        fi
    fi

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Deploy workspace"
    TD_SCRIPT_DESC="Deploy a development workspace to a target root filesystem."
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Using / imports ----------------------------------------------------------
    # Edit this list per script, like a “using” section in C#.
    # Keep it explicit; avoid auto-loading *.sh.
    TD_USING=(
    
    )

# --- Argument specification and processing ------------------------------------
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
        "auto|a|flag|FLAG_AUTO|Repeat with last settings|"
        "undeploy|u|flag|FLAG_UNDEPLOY|Remove files from main root|"
        "source|s|value|SRC_ROOT|Set Source directory|"
        "target|t|value|DEST_ROOT|Set Target directory|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Deploy using defaults:"
        "  $TD_SCRIPT_NAME"
        ""
        "Undeploy everything:"
        "  $TD_SCRIPT_NAME --undeploy"
        "  $TD_SCRIPT_NAME -u"
    ) 

# --- local script functions ---------------------------------------------------
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

    __update_lastdeployinfo(){
        td_state_set "last_deploy_run" "$(date --iso-8601=seconds)"
        td_state_set "last_deploy_source" "$SRC_ROOT"
        td_state_set "last_deploy_target" "${DEST_ROOT:-/}"
        td_state_set "last_deploy_link_exes" "$FLAG_LINK_EXES"
    }

    __getparameters() {

        local default_src default_dst
        default_src="${last_deploy_source:-$HOME/dev}"
        default_dst="${last_deploy_target:-/}"

        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
            if [[ -n "${last_deploy_source:-}" && -n "${last_deploy_target:-}" ]]; then
                sayinfo "Auto mode: using last deployment settings."
                SRC_ROOT="$last_deploy_source"
                DEST_ROOT="$last_deploy_target"
                FLAG_LINK_EXES="${last_deploy_link_exes:-0}"
                return 0
            else
                saywarning "Auto mode requested, but no previous deployment settings found."
            fi
        fi
        
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
        
        td_print_titlebar 
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
# --- Main Sequence ---------------------------------------------------------------
    # td_builtinarg_handler
        # Handle framework builtin arguments after bootstrap and script setup.
        #
        # This function enacts standard, framework-defined command-line flags that are
        # parsed during bootstrap and exposed as FLAG_* variables.
        #
        # Behavior:
        #   - Info-only builtins (e.g. --help, --showargs) are executed and cause an
        #     immediate exit.
        #   - Mutating builtins (e.g. --resetstate) are executed and execution continues.
        #   - Dry-run mode is respected where applicable.
        #
        # Intended usage:
        #   Call once from the executable script, after td_bootstrap and after the script
        #   has defined its argument specification and config/state context.
        #
        # Customization:
        #   Scripts may override this function to alter or extend builtin argument
        #   handling. If overridden, the script author is responsible for the resulting
        #   behavior.
    td_builtinarg_handler(){
        # Info-only builtins: perform action and EXIT.
        if (( FLAG_HELP )); then
            td_showhelp
            exit 0
        fi

        if (( FLAG_SHOWARGS )); then
            td_showarguments
            exit 0
        fi

        # Mutating builtins: perform action and CONTINUE.
        if (( FLAG_STATERESET )); then
            if (( FLAG_DRYRUN )); then
                sayinfo "Would have reset state file."
            else
                td_state_reset
                sayinfo "State file reset as requested."
            fi
        fi
    }
# --- main -----------------------------------------------------------------------
    # main MUST BE LAST function in script
        # Main entry point for the executable script.
        #
        # Execution flow:
        #   1) Invoke td_bootstrap to initialize the framework environment, parse
        #      framework-level arguments, and optionally load UI, state, and config.
        #   2) Abort immediately if bootstrap reports an error condition.
        #   3) Enact framework builtin arguments (help, showargs, state reset, etc.).
        #      Info-only builtins terminate execution; mutating builtins may continue.
        #   4) Continue with script-specific logic.
        #
        # Bootstrap options used here:
        #   --state         Load persistent state via td_state_load
        #   --needroot     Enforce execution as root
        #   --             End of bootstrap options; remaining args are script arguments
        #
        # Notes:
        #   - Builtin argument handling is centralized in td_builtinarg_handler.
        #   - Scripts may override builtin handling, but doing so transfers
        #     responsibility for correct behavior to the script author.
    main() {
        # -- Bootstrap
            td_bootstrap --state --needroot -- "$@"
            rc=$?
            if (( rc != 0 )); then
                exit "$rc"
            fi

            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_print_titlebar

        # -- Main script logic
            __getparameters

            # -- Deploy or undeploy                    
            if [[ "${FLAG_UNDEPLOY:-0}" -eq 0 ]]; then
                __deploy
                if [[ "$FLAG_LINK_EXES" -eq 1 ]]; then
                    __link_executables
                fi
                __update_lastdeployinfo
            else
                __undeploy
                if [[ "$FLAG_LINK_EXES" -eq 1 ]]; then
                    __unlink_executables
                fi
            fi
    }

    main "$@"
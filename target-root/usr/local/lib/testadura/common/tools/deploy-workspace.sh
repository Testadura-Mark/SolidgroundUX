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
#   Includes boilerplate  for a generic Testadura script.
#   Sources bootstrap.sh at the end of this file.
#   Copy this template to create a new script.
#   Replace <NAME> with the actual script name.
#   Sets global variables:
#     SCRIPT_FILE   - absolute path to this script file
#     SCRIPT_NAME   - script name without path and .sh extension
#     SCRIPT_DESC   - short description of the script
#     SCRIPT_DIR    - directory where this script lives
#     TD_ROOT       - Testadura root ("" for production, or path to target-root)
#     COMMON_LIB    - path to common library    
#     RUN_MODE      - "development" or "production"
# ==============================================================================
set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    SCRIPT_FILE="${BASH_SOURCE[0]}"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_FILE")" && pwd)"
    SCRIPT_NAME="$(basename "$SCRIPT_FILE")"
    SCRIPT_DESC="Short description of what this script does."
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

# --- Argument specification ---------------------------------------------------
    # --------------------------------------------------------------------------
    # Each entry:
    #   "name|type|var|help|choices"
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
    ARGS_SPEC=(
        "undeploy|u|flag|FLAG_UNDEPLOY|Remove files from main root|"
        "source|s|value|SRC_ROOT|Set Source directory|"
        "target|t|value|DEST_ROOT|Set Target directory|"
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "config|c|value|CFG_FILE|Config file path (overrides auto-discovery)|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output|"
        "mode|m|enum|ENUM_MODE|Run mode|dev,prd,auto"
    )

    SCRIPT_EXAMPLES=(
    "Deploy using defaults:"
    "  $SCRIPT_NAME"
    ""
    "Undeploy everything:"
    "  $SCRIPT_NAME --undeploy"
    "  $SCRIPT_NAME -u"
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
    __deploy()
    {
        say STRT "Starting deployment from $SRC_ROOT to $DEST_ROOT" --show=symbol

        find "$SRC_ROOT" -type f |
        while IFS= read -r file; do

        rel="${file#$SRC_ROOT/}"
        name="$(basename "$file")"
        perms=$(stat -c "%a" "$file")
        dst="$DEST_ROOT$rel"

        say "$rel  $name $perms $dst"
        # Skip top-level files, hidden dirs, private dirs
        if [[ "$rel" != */* || "$name" == _* || "$name" == *.old || \
                "$rel" == .*/* || "$rel" == _*/* || \
                "$rel" == */.*/* || "$rel" == */_*/* ]]; then
            continue
        fi

        if [[ ! -e "$dst" || "$file" -nt "$dst" ]]; then
            say "Deploying $SRC_ROOT/$rel to $dst with permissions $perms"
            if [[ $FLAG_DRYRUN == 0 ]]; then
                install -D -m "$perms" "$SRC_ROOT/$rel" "$dst"
            else
                sayinfo "Would have installed $SRC_ROOT/$rel --> $dst, with $perms permissions"
            fi
        else
            say "Skipping $rel; destination is up-to-date."
        fi

        done
        say END "End deployment complete." 
    }

    __undeploy()
    {

        say STRT "Starting UNINSTALL from $SRC_ROOT to $DEST_ROOT" --show=symbol

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
            say WARN "Removing $dst"
            if [[ $FLAG_DRYRUN == 0 ]]; then
                rm -f "$dst"
            else
                sayinfo "Would have removed $dst"
            fi
        else
            say "Skipping $rel; does not exist."
        fi

        done
    }

    __link_executables()
    {
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

   __unlink_executables()
    {
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
        printf "Script              : %s\n" "$SCRIPT_NAME"
        printf "Script dir          : %s\n" "$SCRIPT_DIR"
        printf "[INFO] TD_ROOT      : $TD_ROOT\n"
        printf "[INFO] COMMON_LIB   : $COMMON_LIB\n"
        printf "[INFO] CFG_FILE    : ${CFG_FILE:-<auto>}\n"
        printf "[INFO] MODE        : ${ENUM_MODE:-<unset>}\n"
        printf "[INFO] Positional  : ${TD_POSITIONAL[*]:-<none>}\n"
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

        SRC_ROOT="${SRC_ROOT:-""}"
        DEST_ROOT="${DEST_ROOT:-"/"}"
        FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi

        need_root "$@"
        
        if [[ "${FLAG_UNDEPLOY:-0}" -eq 0 ]]; then
            __deploy
            __link_executables
        else
            __undeploy
            __unlink_executables
        fi
    }

    main "$@"
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
        "version|v|action|show_version|Show version information"
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

# --- main() must be the last function in the script -------------------------
    __sample(){
        printf "Script          : %s\n" "$SCRIPT_NAME"
        printf "Script dir      : %s\n" "$SCRIPT_DIR"
        printf "Verbose         : %s\n" "${FLAG_VERBOSE:-0}"
        printf "Config file     : %s\n" "${VAL_CONFIG:-<none>}"
        printf "Mode            : %s\n" "${ENUM_MODE:-<not set>}"
        printf "Run mode        : %s\n" "$RUN_MODE"
        printf "COMMON_LIB      : %s\n" "$COMMON_LIB"
        printf "TD_ROOT         : %s\n" "$TD_ROOT"
        printf "FLAG_UNDEPLOY   : %s\n" "${FLAG_UNDEPLOY:-0}"
        printf "FLAG_DRYRUN     : %s\n" "${FLAG_DRYRUN:-0}"
        printf "SRC_ROOT        : %s\n" "${SRC_ROOT:-<not set>}"
        printf "DEST_ROOT       : %s\n" "${DEST_ROOT:-<not set>}"
    }

    main() {
        need_root
        SRC_ROOT="${SRC_ROOT:-$TD_ROOT}"
        DEST_ROOT="${DEST_ROOT:-"/"}"
        FLAG_DRYRUN="${FLAG_DRYRUN:-0}"

        __sample

        if [[ "${FLAG_UNDEPLOY:-0}" -eq 0 ]]; then
            __deploy
        else
            __undeploy
        fi
    }

# --- Hand off to the bootstrapper (framework) ----------------------------
    AUTOLOAD_FRAMEWORK=true
    # shellcheck source=/dev/null
    . "${COMMON_LIB}/bootstrap.sh"

#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — prepare-release.sh
# ----------------------------------------------------------------------------------
# Purpose    : Create a clean tar.gz release archive of the current application
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   Developer utility that assembles a reproducible release archive from the
#   current workspace, excluding build artifacts and non-distributable files.
#
# Assumptions:
#   - Run from within an application workspace or repository
#   - Testadura framework is available and bootstrapped
#
# Effects:
#   - Creates a tar.gz archive in the release/output directory
#   - May create or remove temporary staging directories
# ==================================================================================

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

# --- Script metadata -------------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Prepare release"
    TD_SCRIPT_DESC=" Creates a clean tar.gz release archive of a workspace"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Using / imports -------------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )
# --- Argument specification and processing ---------------------------------------
    # --- Example: Arguments -------------------------------------------------------
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
        "cleanup|c|flag|FLAG_CLEANUP|Cleanup staging files after run|"
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "useexisting|u|flag|FLAG_USEEXISTING|Use existing staging files|"
        "statereset|r|flag|FLAG_STATERESET|Reset the state file|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output, show arguments|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        "  $TD_SCRIPT_NAME -d"
        ""
        "Show arguments:"
        "  $TD_SCRIPT_NAME --verbose"
        "  $TD_SCRIPT_NAME -v"
    ) 

# --- local script functions ------------------------------------------------------
    __save_parameters(){
        td_state_set "RELEASE" "$RELEASE"
        td_state_set "SOURCE_DIR" "$SOURCE_DIR"
        td_state_set "STAGING_ROOT" "$STAGING_ROOT"
        td_state_set "TAR_FILE" "$TAR_FILE"
        td_state_set "FLAG_CLEANUP" "$FLAG_CLEANUP"
        td_state_set "FLAG_USEEXISTING" "$FLAG_USEEXISTING"
    }
    __get_parameters(){
        RELEASE="${RELEASE:-"$TD_PRODUCT-$TD_VERSION"}"
        SOURCE_DIR="${SOURCE_DIR:-"$TD_APPLICATION_ROOT"}"
        TD_APPLICATION_PARENT="$(dirname "$TD_APPLICATION_ROOT")"
        STAGING_ROOT="${STAGING_ROOT:-"$TD_APPLICATION_PARENT/releases"}"
        TAR_FILE="${TAR_FILE:-"$RELEASE.tar.gz"}"
        FLAG_AUTO="${FLAG_AUTO:-0}"
        FLAG_CLEANUP="${FLAG_CLEANUP:-0}"

        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
             sayinfo "Auto mode: using last deployment or default settings."
             return 0
        fi

        while true; do
            td_print_titlebar "Prepare Release"
            ask --label "Release" --var RELEASE --default "$RELEASE" --colorize both 
            ask --label "Source directory" --var SOURCE_DIR --default "$SOURCE_DIR" --validate_fn validate_dir_exists --colorize both
            ask --label "Staging directory" --var STAGING_ROOT --default "$STAGING_ROOT" --validate_fn validate_dir_exists--colorize both
            ask --label "Tar file" --var TAR_FILE --default "$TAR_FILE" --colorize both
            if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
                cleanup="Y"
            else
                cleanup="N"
            fi
            ask --label "Cleanup staging files after run (Y/N)" --var cleanup --default "$cleanup" --choices "Y,N" --colorize both
            if [[ "$cleanup" == "Y" || "$cleanup" == "y" ]]; then
                FLAG_CLEANUP=1
            else
                FLAG_CLEANUP=0
            fi
            
             if [[ "$FLAG_USEEXISTING" -eq 1 ]]; then
                useexisting="Y"
            else
                useexisting="N"
            fi
            ask --label "Use existing staging files (Y/N)" --var useexisting --default "$useexisting" --choices "Y,N" --colorize both
            if [[ "$useexisting" == "Y" || "$useexisting" == "y" ]]; then
                FLAG_USEEXISTING=1
            else
                FLAG_USEEXISTING=0
            fi
            td_print_sectionheader --border "="
            printf "\n"
            
            if td_dlg_autocontinue 10 "Create a release using these settings?" "APRC"; then
                rc=0
            else
                rc=$?
            fi
            case "$rc" in
                0) 
                    saydebug "Proceeding with release creation..."
                    __save_parameters
                    return 0
                    ;;
                1) 
                    saydebug "Auto proceeding with release creation..."
                    __save_parameters
                    return 0
                    ;;
                2)
                    saycancel "Operation cancelled by user."
                    exit 1
                    ;;
                3)
                    saydebug "Redoing input..."
                    continue
                    ;;
                *)
                    continue
                    ;;
            esac
        done
    }

   __create_tar() {

    saystart "Creating release: $RELEASE"

    STAGE_PATH="${STAGING_ROOT%/}/$RELEASE"

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have check/created directory: $STAGE_PATH"
    else
        saydebug "Ensuring staging dir exists: $STAGE_PATH"
        mkdir -p "$STAGE_PATH"
    fi

    # -- Stage clean copy ---------------------------------------------------------
    if [[ "$FLAG_USEEXISTING" -eq 1 && -n "$(ls -A "$STAGE_PATH" 2>/dev/null)" ]]; then
        sayinfo "Using existing staging files as requested."
    else
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have staged files from $SOURCE_DIR to $STAGE_PATH"
        else
            saydebug "Staging files from $SOURCE_DIR to $STAGE_PATH"
            rsync -a --delete \
                --exclude '.*' \
                --exclude '*.state' \
                --exclude '*.code-workspace' \
                "${SOURCE_DIR%/}/" "$STAGE_PATH/" || { sayfail "rsync failed."; return 1; }
        fi
    fi

    # --- Create tar.gz -----------------------------------------------------------
    TAR_PATH="${STAGING_ROOT%/}/$TAR_FILE"
    saydebug "Creating tar.gz archive $TAR_PATH from staged files in $STAGE_PATH"

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have created tar.gz archive at: $TAR_PATH"
    else
        tar -C "$STAGE_PATH" -czpf "$TAR_PATH" . || { sayfail "tar failed."; return 1; }

        sha256sum "$TAR_PATH" >> SHA256SUMS

        sayinfo "Created $TAR_PATH"

        # --- Inspect archive (first few entries) --------------------------------
        tar -tf "$TAR_PATH" | head -n 30
    fi

    # --- Cleanup staged dir ------------------------------------------------------
    if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have cleaned up staged files at: $STAGE_PATH"
        else
            saydebug "Cleaning up staged files as requested."
            rm -rf "$STAGE_PATH"
        fi
    fi

    if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
        sayinfo "Would have listed available releases in: ${STAGING_ROOT%/}"
    else
        sayinfo "Release created successfully. Available releases:"
        ls -ltr "${STAGING_ROOT%/}"/*.tar.gz 2>/dev/null || true
    fi

    sayend "Release created."

    }
    

# === main() must be the last function in the script ==============================
    main() {
    # --- Bootstrap ---------------------------------------------------------------
            
            td_bootstrap --state -- "$@"
            if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
                td_state_reset
                sayinfo "State file reset as requested."
            fi

    # --- Main script logic here --------------------------------------------------

        __get_parameters
        __create_tar
    }

    # Run main with positional args only (not the options)
    main "$@"

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

            read -r -p "Path (empty to abort): " _root
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

# --- Script metadata (identity) ---------------------------------------------------
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

# --- Script metadata (framework integration) --------------------------------------
    # Libraries to source from TD_COMMON_LIB
    # Leave empty if no extra libs are needed.
    TD_USING=(
    )
# --- Argument specification and processing ---------------------------------------
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
        "cleanup|c|flag|FLAG_CLEANUP|Cleanup staging files after run|"
        "useexisting|u|flag|FLAG_USEEXISTING|Use existing staging files|"
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
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        ""
        "Show verbose logging"
        "  $TD_SCRIPT_NAME --verbose"
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

# --- Local script functions ------------------------------------------------------
    # __save_parameters
        # Persist the current release parameters to the state store.
        #
        # Stores all user-selected and derived values required to reproduce
        # the same prepare-release run later (e.g. for auto mode or reruns).
        #
        # This function does not perform validation; it assumes parameters
        # have already been resolved and confirmed by the user.
        #
        # Used by:
        #   - __get_parameters (after user confirmation)
    __save_parameters(){
        td_state_set "RELEASE" "$RELEASE"
        td_state_set "SOURCE_DIR" "$SOURCE_DIR"
        td_state_set "STAGING_ROOT" "$STAGING_ROOT"
        td_state_set "TAR_FILE" "$TAR_FILE"
        td_state_set "FLAG_CLEANUP" "$FLAG_CLEANUP"
        td_state_set "FLAG_USEEXISTING" "$FLAG_USEEXISTING"
    }

    # __get_parameters 
        # Resolve and collect all parameters required for prepare-release.
        #
        # Behavior:
        #   - Initializes defaults based on application metadata and paths
        #   - Supports non-interactive "auto" mode using stored or default values
        #   - In interactive mode, prompts the user to review and adjust parameters
        #   - Persists confirmed parameters via __save_parameters
        #
        # Parameters handled:
        #   - RELEASE        : release identifier (used for tar and manifest naming)
        #   - SOURCE_DIR     : source directory to stage from
        #   - STAGING_ROOT   : root directory where releases are created
        #   - TAR_FILE       : final tar.gz filename
        #   - FLAG_CLEANUP   : whether to remove staging files after completion
        #   - FLAG_USEEXISTING : reuse existing staging files if present
        #
        # Exit behavior:
        #   - Returns 0 on successful parameter confirmation
        #   - Exits script on explicit user cancel
    __get_parameters(){
        RELEASE="${RELEASE:-"$TD_PRODUCT-$TD_VERSION"}"
        SOURCE_DIR="${SOURCE_DIR:-"$TD_APPLICATION_ROOT"}"
        TD_APPLICATION_PARENT="$(dirname "$TD_APPLICATION_ROOT")"
        STAGING_ROOT="${STAGING_ROOT:-"$TD_APPLICATION_PARENT/releases"}"
        TAR_FILE="${TAR_FILE:-"$RELEASE.tar.gz"}"
        FLAG_AUTO="${FLAG_AUTO:-0}"
        FLAG_CLEANUP="${FLAG_CLEANUP:-0}"
        FLAG_USEEXISTING="${FLAG_USEEXISTING:-0}"

        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
             sayinfo "Auto mode: using last deployment or default settings."
             return 0
        fi

        while true; do
            ask --label "Release" --var RELEASE --default "$RELEASE" --colorize both 
            ask --label "Source directory" --var SOURCE_DIR --default "$SOURCE_DIR" --validate_fn validate_dir_exists --colorize both
            ask --label "Staging directory" --var STAGING_ROOT --default "$STAGING_ROOT" --validate_fn validate_dir_exists --colorize both
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
            
            local rc=0
            if td_dlg_autocontinue 5 "Create a release using these settings?" "APRC"; then
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
                    td_print_sectionheader --text "Redo input" --border "="
                    continue
                    ;;
                *)
                    continue
                    ;;
            esac
            

        done
    }

    # td_release_write_checksum
        # Add/update a SHA256SUMS entry for a tarball in the staging root.
        # Ensures the SHA256SUMS line contains only the tar filename (not an absolute path).
        #
        # Usage:
        #   td_release_write_checksum "$TAR_PATH" "$TAR_FILE" "$STAGING_ROOT"
    td_release_write_checksum() {
        local tar_path="${1:-}"
        local tar_file="${2:-}"
        local staging_root="${3:-}"

        [[ -n "$tar_path" ]] || return 1
        [[ -n "$tar_file" ]] || return 1
        [[ -n "$staging_root" ]] || return 1

        local sums_file
        sums_file="${staging_root%/}/SHA256SUMS"

        touch "$sums_file" || return 1

        # Remove any existing entry for this filename (idempotent).
        # Match: two spaces + filename at end of line.
        sed -i "\|  $tar_file$|d" "$sums_file" || return 1

        local hash
        hash="$(sha256sum "$tar_path" | awk '{print $1}')" || return 1
        [[ -n "$hash" ]] || return 1

        printf '%s  %s\n' "$hash" "$tar_file" >> "$sums_file" || return 1
    }

    # __create_tar
        # Stage a clean release tree and produce a versioned tar.gz archive.
        #
        # Responsibilities:
        #   - Create/ensure staging directory: $STAGING_ROOT/$RELEASE
        #   - Populate it from SOURCE_DIR (rsync), unless --use-existing is set
        #   - Create an uncompressed tar archive from staged files
        #   - Generate an uninstall manifest from the tar contents
        #   - Embed the manifest into the tar archive
        #   - Compress the tar to tar.gz
        #   - Update $STAGING_ROOT/SHA256SUMS (one entry per tarball)
        #
        # Output artifacts:
        #   - $STAGING_ROOT/$TAR_FILE            (final tar.gz)
        #   - $STAGING_ROOT/$RELEASE.manifest    (external uninstall manifest)
        #   - $STAGING_ROOT/SHA256SUMS
        #
        # Notes:
        #   - Manifest is generated BEFORE embedding, so it does not list itself.
        #   - Append (-r) is only used on uncompressed tar archives.
        #   - DRYRUN prints actions without changing the filesystem.
    __create_tar() {

        saystart "Creating release: $RELEASE"

        STAGE_PATH="${STAGING_ROOT%/}/$RELEASE"

        # --- Ensure staging directory ----------------------------------------------
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have check/created directory: $STAGE_PATH"
        else
            saydebug "Ensuring staging dir exists: $STAGE_PATH"
            mkdir -p "$STAGE_PATH" || { sayfail "mkdir failed."; return 1; }
        fi

        # --- Stage clean copy -------------------------------------------------------
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
                    "${SOURCE_DIR%/}/" "$STAGE_PATH/" || {
                        sayfail "rsync failed."
                        return 1
                    }
            fi
        fi

        # Build uncompressed tar
            TAR_PATH_TAR="${STAGING_ROOT%/}/${TAR_FILE%.gz}"
            TAR_PATH_GZ="${STAGING_ROOT%/}/$TAR_FILE"
            MANIFEST_PATH="${STAGING_ROOT%/}/${RELEASE}.manifest"
            SUMS_PATH="${STAGING_ROOT%/}/SHA256SUMS"

            saydebug "Creating tar archive $TAR_PATH_TAR from staged files in $STAGE_PATH"

            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have created tar archive at: $TAR_PATH_TAR"
                sayinfo "Would have written manifest to: $MANIFEST_PATH"
                sayinfo "Would have updated checksums file: $SUMS_PATH"
                sayinfo "Would have generated manifest and compressed to: $TAR_PATH_GZ"
                sayinfo "Would have written checksum to: ${TAR_PATH_GZ}.sha256"
                sayinfo "Would have written checksum to: ${MANIFEST_PATH}.sha256"
                return 0
            fi

            tar -C "$STAGE_PATH" -cpf "$TAR_PATH_TAR" . || {
                sayfail "tar failed."
                return 1
            }
    }   

        # Write uninstall manifest (external)


            tar -tf "$TAR_PATH_TAR" \
                | sed 's|^\./||' \
                | sed '/^[[:space:]]*$/d' \
                > "$MANIFEST_PATH" || {
                    sayfail "Failed to write manifest."
                    return 1
                }

        # Embed manifest into tar
            tar -C "$STAGING_ROOT" -rf "$TAR_PATH_TAR" "${RELEASE}.manifest" || {
                sayfail "Failed to embed manifest into tar."
                return 1
            }

        # Compress to tar.gz
            gzip -f "$TAR_PATH_TAR" || {
                sayfail "gzip failed."
                return 1
            }

        # Update SHA256SUMS
        td_release_write_checksum "$TAR_PATH_GZ" "$TAR_FILE" "$STAGING_ROOT" || {
                sayfail "Failed to update SHA256SUMS."
                return 1
            }

            # Also add manifest to SHA256SUMS (idempotent)
            sed -i "\|  $(basename "$MANIFEST_PATH")$|d" "$SUMS_PATH" || {
                sayfail "Failed to update SHA256SUMS (manifest)."
                return 1
            }

            # Compute manifest hash once
            manifest_base="$(basename "$MANIFEST_PATH")"
            manifest_hash="$(sha256sum "$MANIFEST_PATH" | awk '{print $1}')"

            printf '%s  %s\n' "$manifest_hash" "$manifest_base" >> "$SUMS_PATH" || {
                sayfail "Failed to append manifest checksum to SHA256SUMS."
                return 1
            }

            printf '%s  %s\n' "$(sha256sum "$TAR_PATH_GZ" | awk '{print $1}')" "$TAR_FILE" > "${TAR_PATH_GZ}.sha256"
            printf '%s  %s\n' "$manifest_hash" "$manifest_base" > "${MANIFEST_PATH}.sha256"

            sayinfo "Created $TAR_PATH_GZ"

            # Inspect archive (first few entries)
            tar -tf "$TAR_PATH_GZ" | head -n 30
        }

# --- Main Sequence ---------------------------------------------------------------

# --- Main -----------------------------------------------------------------------
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
           td_bootstrap --state --needroot -- "$@" || { rc=$?; exit "$rc"; }

            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_print_titlebar

        # -- Main script logic

        __get_parameters
        __create_tar
    }

    # Run main with positional args only (not the options)
    main "$@"

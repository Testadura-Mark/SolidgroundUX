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

            read -r -p "Path (empty to abort): " _root </dev/tty
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
    : "${TD_SCRIPT_DESC:=Creates a clean tar.gz release archive of a workspace}"
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

# --- Local script Declarations ----------------------------------------------------
    # Put script-local constants and defaults here (NOT framework config).
    # Prefer local variables inside functions unless a value must be shared.

# --- Local script functions -------------------------------------------------------
    # __save_parameters
        #   Persist the current release parameters to the state store.
        #
        # Description:
        #   Writes all resolved and user-confirmed parameters required to reproduce
        #   a prepare-release run later. This supports:
        #     - --auto mode reruns
        #     - consistent, repeatable release generation
        #
        #   This function does not validate input; it assumes parameters are already
        #   resolved and confirmed.
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Stores the following keys via td_state_set:
        #     RELEASE
        #     SOURCE_DIR
        #     STAGING_ROOT
        #     TAR_FILE
        #     FLAG_CLEANUP
        #     FLAG_USEEXISTING
        #
        # Returns:
        #   0 on success
        #   Non-zero if state storage fails.
        #
        # Notes:
        #   Requires td_bootstrap --state so the state backend is available.
    __save_parameters(){
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have saved state variables (manual)"
        else
            saydebug "Saving state variables (manual)"
            td_state_set "RELEASE" "$RELEASE"
            td_state_set "SOURCE_DIR" "$SOURCE_DIR"
            td_state_set "STAGING_ROOT" "$STAGING_ROOT"
            td_state_set "TAR_FILE" "$TAR_FILE"
            td_state_set "FLAG_CLEANUP" "$FLAG_CLEANUP"
            td_state_set "FLAG_USEEXISTING" "$FLAG_USEEXISTING"
        fi
    }

    # __get_parameters
        #   Resolve and collect all parameters required to prepare a release archive.
        #
        # Description:
        #   Establishes defaults using application metadata and workspace paths, then
        #   resolves user-adjustable parameters either interactively or via auto mode.
        #
        #   Behavior:
        #     - Computes defaults:
        #         RELEASE      : "$TD_PRODUCT-$TD_VERSION"
        #         SOURCE_DIR   : "$TD_APPLICATION_ROOT"
        #         STAGING_ROOT : "<parent_of_application_root>/releases"
        #         TAR_FILE     : "$RELEASE.tar.gz"
        #     - If FLAG_AUTO=1:
        #         Uses previously stored or default values without prompting and returns.
        #     - Otherwise:
        #         Prompts the user to review and modify parameters and confirms via a
        #         dialog with optional auto-continue.
        #     - On confirmation, persists parameters using __save_parameters().
        #
        # Parameters handled:
        #   RELEASE          Release identifier used for staging and filenames
        #   SOURCE_DIR       Source directory to stage from (rsync root)
        #   STAGING_ROOT     Root directory that will contain staged tree and outputs
        #   TAR_FILE         Final tar.gz filename (stored under STAGING_ROOT)
        #   FLAG_CLEANUP     Remove staging files after run (optional; not enacted here)
        #   FLAG_USEEXISTING Reuse non-empty staging tree if present
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Sets (or updates) the following variables in caller scope:
        #     RELEASE, SOURCE_DIR, STAGING_ROOT, TAR_FILE, FLAG_AUTO,
        #     FLAG_CLEANUP, FLAG_USEEXISTING
        #
        # Returns:
        #   0 on successful resolution/confirmation
        #   Exits the script with status 1 if the user cancels.
        #
        # Notes:
        #   - Directory validation uses validate_dir_exists.
        #   - Confirmation uses td_dlg_autocontinue, distinguishing:
        #       rc=0 explicit OK
        #       rc=1 OK by timeout
        #       rc=2 cancel
        #       rc=3 redo
        #   - Auto mode assumes state was loaded during bootstrap (--state).
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
            
            ask_ok_redo_quit "Create a release using these settings?" 5
            rc=$?

            case "$rc" in
                0)
                    saydebug "Proceeding with release creation..."
                    __save_parameters
                    return 0
                    ;;
                1)
                    saydebug "Redoing input..."
                    td_print_sectionheader --text "Redo input" --border "="
                    continue
                    ;;
                2)
                    saycancel "Operation cancelled by user."
                    exit 1
                    ;;
                *)
                    # Unrecognized / drop to typed prompt behavior depending on your UX choice
                    continue
                    ;;
            esac          

        done
    }

    # td_release_write_checksum
        #   Add or update a SHA256SUMS entry for a release tarball.
        #
        # Description:
        #   Ensures that STAGING_ROOT/SHA256SUMS contains exactly one entry for the
        #   specified tar filename. Any existing line matching the filename is removed,
        #   then a new line is appended using the tarball's SHA256 hash.
        #
        #   The entry format matches the conventional output of sha256sum:
        #     <hash><two spaces><filename>
        #
        #   The stored filename is the basename only (no absolute path).
        #
        # Arguments:
        #   $1  tar_path      Absolute or relative path to the tarball file to hash.
        #   $2  tar_file      Tarball filename to write into SHA256SUMS (basename).
        #   $3  staging_root  Directory containing SHA256SUMS.
        #
        # Output:
        #   Creates or updates:
        #     <staging_root>/SHA256SUMS
        #
        # Returns:
        #   0 on success
        #   1 if required arguments are missing or any operation fails
        #
        # Notes:
        #   - Idempotent: removes any existing entry for the same filename before append.
        #   - Uses sed -i to edit SHA256SUMS in-place.
        #   - Requires sha256sum, sed, awk, and write permission to staging_root.
        #
        # Example:
        #   td_release_write_checksum "$tar_path_gz" "$TAR_FILE" "$STAGING_ROOT"
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
        #   Stage a clean release tree and produce a versioned tar.gz archive.
        #
        # Description:
        #   Builds a reproducible release artifact by staging a filtered copy of the
        #   source workspace into a release-specific staging directory, then packaging
        #   it as a tar.gz archive.
        #
        #   High-level flow:
        #     1) Ensure staging directory exists:  $STAGING_ROOT/$RELEASE
        #     2) Populate staging directory from SOURCE_DIR via rsync (unless
        #        FLAG_USEEXISTING=1 and staging dir is non-empty)
        #     3) Create an uncompressed tar archive from the staged files
        #     4) Generate an uninstall manifest by listing tar contents
        #     5) Embed the manifest into the tar archive (append)
        #     6) Compress to tar.gz
        #     7) Update SHA256SUMS with hashes for:
        #          - the tar.gz
        #          - the manifest
        #        and also write sidecar .sha256 files for both
        #
        # Staging behavior:
        #   - Uses rsync --delete to keep staging clean and reproducible
        #   - Excludes:
        #       .*                 (dotfiles)
        #       *.state            (state files)
        #       *.code-workspace   (workspace files)
        #
        # Output artifacts:
        #   - $STAGING_ROOT/$TAR_FILE              Final tar.gz archive
        #   - $STAGING_ROOT/$RELEASE.manifest      External uninstall manifest
        #   - $STAGING_ROOT/SHA256SUMS             Rolling checksum index
        #   - $STAGING_ROOT/$TAR_FILE.sha256       Sidecar checksum for tarball
        #   - $STAGING_ROOT/$RELEASE.manifest.sha256 Sidecar checksum for manifest
        #
        # Arguments:
        #   None.
        #
        # Output:
        #   Creates and/or updates files under STAGING_ROOT as described above.
        #
        # Returns:
        #   0 on success
        #   1 on failure to stage, package, hash, or write artifacts
        #
        # Notes:
        #   - DRYRUN prints intended actions without modifying the filesystem.
        #   - Manifest is generated BEFORE embedding, so it does not list itself.
        #   - Tar append (-r/-f) is only performed on the uncompressed tar archive.
        #   - Assumes gzip, tar, rsync, sha256sum, sed, awk are available.
    __create_tar() {
        saystart "Creating release: $RELEASE"

        local stage_path tar_path_tar tar_path_gz manifest_path sums_path
        local manifest_base manifest_hash

        stage_path="${STAGING_ROOT%/}/$RELEASE"

        # --- Ensure staging directory ----------------------------------------------
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have check/created directory: $stage_path"
        else
            saydebug "Ensuring staging dir exists: $stage_path"
            mkdir -p "$stage_path" || { sayfail "mkdir failed."; return 1; }
        fi

        # --- Stage clean copy -------------------------------------------------------
        if [[ "$FLAG_USEEXISTING" -eq 1 && -n "$(ls -A "$stage_path" 2>/dev/null)" ]]; then
            sayinfo "Using existing staging files as requested."
        else
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have staged files from $SOURCE_DIR to $stage_path"
            else
                saydebug "Staging files from $SOURCE_DIR to $stage_path"
                rsync -a --delete \
                    --exclude '.*' \
                    --exclude '*.state' \
                    --exclude '*.code-workspace' \
                    "${SOURCE_DIR%/}/" "$stage_path/" || {
                        sayfail "rsync failed."
                        return 1
                    }
            fi
        fi

        # --- Build paths ------------------------------------------------------------
        tar_path_tar="${STAGING_ROOT%/}/${TAR_FILE%.gz}"
        tar_path_gz="${STAGING_ROOT%/}/$TAR_FILE"
        manifest_path="${STAGING_ROOT%/}/${RELEASE}.manifest"
        sums_path="${STAGING_ROOT%/}/SHA256SUMS"

        saydebug "Creating tar archive $tar_path_tar from staged files in $stage_path"

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created tar archive at: $tar_path_tar"
            sayinfo "Would have written manifest to: $manifest_path"
            sayinfo "Would have updated checksums file: $sums_path"
            sayinfo "Would have generated manifest and compressed to: $tar_path_gz"
            sayinfo "Would have written checksum to: ${tar_path_gz}.sha256"
            sayinfo "Would have written checksum to: ${manifest_path}.sha256"
            return 0
        fi

        # --- Create uncompressed tar -----------------------------------------------
        tar -C "$stage_path" -cpf "$tar_path_tar" . || { sayfail "tar failed."; return 1; }

        # --- Write uninstall manifest (external) ------------------------------------
        tar -tf "$tar_path_tar" \
            | sed 's|^\./||' \
            | sed '/^[[:space:]]*$/d' \
            > "$manifest_path" || { sayfail "Failed to write manifest."; return 1; }

        # --- Embed manifest into tar ------------------------------------------------
        tar -C "$STAGING_ROOT" -rf "$tar_path_tar" "${RELEASE}.manifest" \
            || { sayfail "Failed to embed manifest into tar."; return 1; }

        # --- Compress to tar.gz -----------------------------------------------------
        gzip -f "$tar_path_tar" || { sayfail "gzip failed."; return 1; }

        # --- Update SHA256SUMS ------------------------------------------------------
        td_release_write_checksum "$tar_path_gz" "$TAR_FILE" "$STAGING_ROOT" \
            || { sayfail "Failed to update SHA256SUMS."; return 1; }

        # Remove existing manifest entry (idempotent)
        sed -i "\|  $(basename "$manifest_path")$|d" "$sums_path" \
            || { sayfail "Failed to update SHA256SUMS (manifest)."; return 1; }

        manifest_base="$(basename "$manifest_path")"
        manifest_hash="$(sha256sum "$manifest_path" | awk '{print $1}')" \
            || { sayfail "Failed to hash manifest."; return 1; }

        printf '%s  %s\n' "$manifest_hash" "$manifest_base" >> "$sums_path" \
            || { sayfail "Failed to append manifest checksum to SHA256SUMS."; return 1; }

        # Write sidecar .sha256 files
        printf '%s  %s\n' "$(sha256sum "$tar_path_gz" | awk '{print $1}')" "$TAR_FILE" > "${tar_path_gz}.sha256"
        printf '%s  %s\n' "$manifest_hash" "$manifest_base" > "${manifest_path}.sha256"

        sayinfo "Created $tar_path_gz"

        # Inspect archive (first few entries)
        tar -tf "$tar_path_gz" | head -n 30

        return 0
    }

# --- Main Sequence ----------------------------------------------------------------
    # main
        #   Script entry point for preparing a release archive.
        #
        # Description:
        #   Initializes the Testadura framework via td_bootstrap, handles builtin
        #   framework arguments, then resolves parameters and builds the release.
        #
        # Execution flow:
        #   1) td_bootstrap --state --needroot -- "$@"
        #      - Initializes framework runtime, UI, logging, and argument parsing
        #      - Loads persistent state (required for --auto reuse)
        #      - Enforces root privileges (required for consistent staging/output paths)
        #   2) td_builtinarg_handler
        #      - Executes builtin flags (help/showargs/resetstate/etc.)
        #      - Info-only builtins exit immediately
        #   3) td_print_titlebar
        #      - Prints standard script header UI
        #   4) __get_parameters
        #      - Resolve and confirm parameter set (or reuse in auto mode)
        #   5) __create_tar
        #      - Stage workspace and generate tarball + manifest + checksums
        #
        # Arguments:
        #   $@  Script command-line arguments (framework + script-specific).
        #
        # Output:
        #   Produces release artifacts under STAGING_ROOT.
        #
        # Returns:
        #   Exits with the status returned by the release creation steps.
        #
        # Notes:
        #   This script requires --state to support reproducible "auto" runs and
        #   parameter persistence between executions.
    main() {
        # -- Bootstrap
           td_bootstrap --state -- "$@" || { rc=$?; exit "$rc"; }

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

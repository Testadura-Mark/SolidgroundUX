#!/usr/bin/env bash
#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — Prepare Release
# ----------------------------------------------------------------------------------
# Purpose:
#   Create a clean tar.gz release archive from the current workspace.
#
# Description:
#   Developer utility that assembles a reproducible release package from a
#   workspace by staging a filtered copy, generating a manifest, and writing
#   checksums for the final artifacts.
#
#   The script can:
#     - resolve release parameters interactively or from saved state
#     - stage a clean copy of the source workspace
#     - generate a versioned tar.gz archive
#     - generate and embed an uninstall manifest
#     - update SHA256SUMS and sidecar checksum files
#
# Release model:
#   - Source is treated as the current application or workspace root
#   - Output is written under a staging/releases directory
#   - Artifacts are intended to be reproducible and distributable
#
# Notes:
#   - Honors FLAG_DRYRUN, FLAG_VERBOSE, and FLAG_DEBUG
#   - Supports auto mode and optional reuse of an existing staging tree
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
        # Purpose:
        #   Persist the current release parameters to the framework state store.
        #
        # Behavior:
        #   - Saves all resolved and confirmed release parameters for later reuse.
        #   - Supports repeatable runs through --auto mode.
        #   - Skips state writes when FLAG_DRYRUN is enabled.
        #
        # Inputs (globals):
        #   RELEASE
        #   SOURCE_DIR
        #   STAGING_ROOT
        #   TAR_FILE
        #   FLAG_CLEANUP
        #   FLAG_USEEXISTING
        #   FLAG_DRYRUN
        #
        # Side effects:
        #   - Writes state entries via td_state_set when not in dry-run mode.
        #
        # Returns:
        #   0 on success
        #   Non-zero if state storage fails
        #
        # Usage:
        #   __save_parameters
        #
        # Examples:
        #   __save_parameters || return 1
        #
        # Notes:
        #   - Requires td_bootstrap --state so the state backend is available.
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
        # Purpose:
        #   Resolve and collect all parameters required to prepare a release archive.
        #
        # Behavior:
        #   - Computes default values from framework metadata and workspace paths.
        #   - In auto mode, reuses existing or default values without prompting.
        #   - In interactive mode, prompts for release settings and confirms them.
        #   - Saves confirmed parameters through __save_parameters().
        #
        # Parameters handled:
        #   RELEASE
        #       Release identifier used for staging and filenames
        #   SOURCE_DIR
        #       Source directory to package
        #   STAGING_ROOT
        #       Root directory containing staging files and release outputs
        #   TAR_FILE
        #       Final tar.gz filename
        #   FLAG_CLEANUP
        #       Whether to remove staging files after completion
        #   FLAG_USEEXISTING
        #       Whether to reuse a non-empty staging tree
        #
        # Outputs (globals):
        #   RELEASE
        #   SOURCE_DIR
        #   STAGING_ROOT
        #   TAR_FILE
        #   FLAG_AUTO
        #   FLAG_CLEANUP
        #   FLAG_USEEXISTING
        #
        # Returns:
        #   0 on successful resolution and confirmation
        #   Exits the script with status 1 if the user cancels
        #
        # Usage:
        #   __get_parameters
        #
        # Examples:
        #   __get_parameters || return 1
        #
        # Notes:
        #   - Uses ask() and ask_ok_redo_quit() for interactive input.
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
        # Purpose:
        #   Add or update a SHA256SUMS entry for a release artifact.
        #
        # Behavior:
        #   - Ensures SHA256SUMS contains exactly one entry for the specified filename.
        #   - Removes any existing line for the same filename before appending a new one.
        #   - Stores only the basename in the checksum file.
        #
        # Arguments:
        #   $1  TAR_PATH
        #       Path to the file to hash.
        #   $2  TAR_FILE
        #       Filename to write into SHA256SUMS.
        #   $3  STAGING_ROOT
        #       Directory containing SHA256SUMS.
        #
        # Side effects:
        #   - Creates or updates:
        #       <staging_root>/SHA256SUMS
        #
        # Returns:
        #   0 on success
        #   1 if required arguments are missing or file operations fail
        #
        # Usage:
        #   td_release_write_checksum "$tar_path" "$TAR_FILE" "$STAGING_ROOT"
        #
        # Examples:
        #   td_release_write_checksum "$tar_path_gz" "$TAR_FILE" "$STAGING_ROOT"
        #
        # Notes:
        #   - Idempotent for a given filename.
        #   - Requires sha256sum, sed, awk, and write permission to staging_root.
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
        # Purpose:
        #   Stage a clean release tree and produce a versioned tar.gz archive.
        #
        # Behavior:
        #   - Ensures the release-specific staging directory exists.
        #   - Populates the staging directory from SOURCE_DIR via rsync.
        #   - Reuses existing staging files when requested and non-empty.
        #   - Creates an uncompressed tar archive from the staged files.
        #   - Generates an uninstall manifest from the tar contents.
        #   - Embeds the manifest into the tar archive.
        #   - Compresses the archive to tar.gz.
        #   - Updates SHA256SUMS and writes sidecar .sha256 files.
        #
        # Inputs (globals):
        #   RELEASE
        #   SOURCE_DIR
        #   STAGING_ROOT
        #   TAR_FILE
        #   FLAG_DRYRUN
        #   FLAG_USEEXISTING
        #
        # Side effects:
        #   - Creates and updates staged files and release artifacts under STAGING_ROOT.
        #
        # Output artifacts:
        #   - $STAGING_ROOT/$TAR_FILE
        #   - $STAGING_ROOT/$RELEASE.manifest
        #   - $STAGING_ROOT/SHA256SUMS
        #   - $STAGING_ROOT/$TAR_FILE.sha256
        #   - $STAGING_ROOT/$RELEASE.manifest.sha256
        #
        # Returns:
        #   0 on success
        #   1 on failure to stage, package, hash, or write artifacts
        #
        # Usage:
        #   __create_tar
        #
        # Examples:
        #   __create_tar || return 1
        #
        # Notes:
        #   - In dry-run mode, only reports the intended actions.
        #   - Manifest is generated before embedding, so it does not list itself.
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
        # Purpose:
        #   Execute the release preparation workflow.
        #
        # Behavior:
        #   - Loads and initializes the framework bootstrap.
        #   - Executes builtin framework argument handling.
        #   - Prepares the standard UI state and title bar.
        #   - Resolves release parameters.
        #   - Creates the release archive and related metadata.
        #
        # Arguments:
        #   $@  Framework and script-specific command-line arguments
        #
        # Returns:
        #   Exits with the resulting status from bootstrap or release operations
        #
        # Usage:
        #   main "$@"
        #
        # Examples:
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
            td_bootstrap -- "$@"
            rc=$?

            saydebug "After bootstrap: $rc"
            (( rc != 0 )) && exit "$rc"
                        
        # -- Handle builtin arguments
            saydebug "Calling builtinarg handler"
            td_builtinarg_handler
            saydebug "Exited builtinarg handler"

        # -- UI
            td_update_runmode
            td_print_titlebar
            
        # -- Main script logic

        __get_parameters
        __create_tar
    }

    # Run main with positional args only (not the options)
    main "$@"

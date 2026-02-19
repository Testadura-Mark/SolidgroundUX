#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — td-uninstall
# ------------------------------------------------------------------------------
# Purpose : Removes a Testadura-style installed product using a saved manifest
# Author  : Mark Fieten
# Version : 1.1 (2026-02-19)
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ------------------------------------------------------------------------------
# Notes
#   - Standalone: does NOT source the Testadura framework.
#   - Default behavior uses CURRENT.manifest recorded by td-install.
#   - Only removes files listed in the manifest.
# ==============================================================================

set -euo pipefail

# --- Defaults ------------------------------------------------------------------
    NAME_DEFAULT="SolidgroundUX"

    NAME="$NAME_DEFAULT"
    name_lc="${NAME,,}"

    ROOT="/"          # allow --root ~/dev/target-root for testing
    DRYRUN=0

    STATE_DIR="/var/lib/${name_lc}"
    MANIFEST_DIR="${STATE_DIR}/manifests"
    CURRENT_FILE="${STATE_DIR}/CURRENT.manifest"

    MANIFEST=""

# --- Helpers -------------------------------------------------------------------
    # die
        # Print a fatal error message to stderr and exit immediately.
        #
        # Args:
        #   $*  Message text.
        #
        # Exit:
        #   127 (consistent "fatal" exit used by Testadura tooling).
    die() { printf 'FATAL: %s\n' "$*" >&2; exit 127; }

    # say
        # Print a message to stdout.
        #
        # Args:
        #   $*  Message text.
    say() { printf '%s\n' "$*"; }

    # need_root_reexec
        # Re-exec this uninstaller under sudo when not running as root.
        #
        # Rationale:
        #   Removing installed files under ROOT="/" typically requires root.
        #   Preserves argv exactly.
        #
        # Args:
        #   $@  Original script arguments (pass through unchanged).
        #
        # Behavior:
        #   - If already root: returns normally.
        #   - If not root    : exec sudo -- "$0" "$@" (does not return).
    need_root_reexec() {
        if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
            exec sudo -- "$0" "$@"
        fi
    }

    # set_name
        # Configure product-specific uninstall paths derived from a product name.
        #
        # Derives:
        #   - STATE_DIR     : "/var/lib/<name_lc>"
        #   - MANIFEST_DIR  : "$STATE_DIR/manifests"
        #   - CURRENT_FILE  : "$STATE_DIR/CURRENT.manifest"
        #
        # Args:
        #   $1  Product name (non-empty). Example: "SolidgroundUX".
        #
        # Effects:
        #   Sets globals: NAME, name_lc, STATE_DIR, MANIFEST_DIR, CURRENT_FILE.
        #
        # Exit:
        #   Aborts via die() if name is empty.
    set_name() {
        local n="$1"
        [[ -n "$n" ]] || die "--name requires a non-empty value"

        NAME="$n"
        name_lc="${NAME,,}"

        STATE_DIR="/var/lib/${name_lc}"
        MANIFEST_DIR="${STATE_DIR}/manifests"
        CURRENT_FILE="${STATE_DIR}/CURRENT.manifest"
    }

    # rm_file
        # Remove a file path, honoring dry-run mode.
        #
        # Args:
        #   $1  Absolute file path to remove.
        #
        # Globals:
        #   DRYRUN  If non-zero, do not delete; print the rm command instead.
        #
        # Notes:
        #   - Errors are ignored on actual removal (rm -f + || true).
    rm_file() {
        local p="$1"
        if (( DRYRUN )); then
            say "DRYRUN: rm -f -- '$p'"
        else
            rm -f -- "$p" || true
        fi
    }

    # rmdir_if_empty
        # Remove a directory only if it is empty (honors dry-run mode).
        #
        # Args:
        #   $1  Absolute directory path.
        #
        # Globals:
        #   DRYRUN  If non-zero, do not delete; print the rmdir command instead.
        #
        # Notes:
        #   - Uses ls -A to determine emptiness in dry-run mode.
        #   - On real removal, silently ignores failure (directory not empty, etc.).
    rmdir_if_empty() {
        local d="$1"
        [[ -d "$d" ]] || return 0

        if (( DRYRUN )); then
            if [[ -z "$(ls -A -- "$d" 2>/dev/null || true)" ]]; then
                say "DRYRUN: rmdir -- '$d'"
            fi
            return 0
        fi

        rmdir -- "$d" 2>/dev/null || true
    }

    # resolve_manifest_default
        # Resolve the manifest path to use when none is explicitly provided.
        #
        # Default behavior:
        #   Reads CURRENT_FILE to obtain the manifest filename last installed,
        #   then resolves it under MANIFEST_DIR.
        #
        # Globals (inputs):
        #   CURRENT_FILE, MANIFEST_DIR, STATE_DIR
        #
        # Globals (outputs):
        #   MANIFEST  Set to the resolved manifest path.
        #
        # Exit:
        #   Aborts via die() if:
        #     - CURRENT_FILE is missing/unreadable
        #     - CURRENT_FILE is empty
        #     - Resolved manifest file does not exist
    resolve_manifest_default() {
        local manifest_name=""
        [[ -r "$CURRENT_FILE" ]] || die "No manifest specified and no CURRENT.manifest found in: $STATE_DIR"
        manifest_name="$(cat -- "$CURRENT_FILE")"
        [[ -n "$manifest_name" ]] || die "CURRENT.manifest is empty: $CURRENT_FILE"

        MANIFEST="${MANIFEST_DIR}/${manifest_name}"
        [[ -r "$MANIFEST" ]] || die "Manifest listed in CURRENT.manifest not found: $MANIFEST"
    }

    # show_help
        # Print usage and option help text.
        #
        # Notes:
        #   If --manifest is omitted, the manifest is inferred from:
        #     /var/lib/<name>/CURRENT.manifest
    show_help() {
        printf "Usage: %s [options]\n" "$0"
        printf "\n"
        printf "Uninstalls using a manifest created by td-install.\n"
        printf "If --manifest is omitted, uses /var/lib/<name>/CURRENT.manifest.\n"
        printf "\n"
        printf "Options:\n"
        printf "  -n, --name NAME           product name (default: %s)\n" "$NAME_DEFAULT"
        printf "  -m, --manifest FILE       manifest file to use (overrides CURRENT.manifest)\n"
        printf "  -r, --root PATH           uninstall under PATH instead of /\n"
        printf "  -d, --dry-run             simulate removal\n"
        printf "  -h, --help                show this help\n"
        printf "\n"
        printf "Examples:\n"
        printf "  sudo %s\n" "$0"
        printf "  sudo %s --name SolidgroundUX\n" "$0"
        printf "  %s --root /home/me/dev/target-root --dry-run\n" "$0"
    }

# --- Main ----------------------------------------------------------------------
    # main
        # Entry point: parse options, resolve manifest, remove listed files, then cleanup dirs.
        #
        # Flow:
        #   1) Initialize defaults (set_name)
        #   2) Parse CLI options
        #   3) Normalize ROOT
        #   4) If ROOT="/" and not dry-run: re-exec under sudo if needed
        #   5) Resolve manifest (explicit --manifest or CURRENT.manifest default)
        #   6) Remove files listed in manifest (only those files)
        #   7) Remove empty directories derived from manifest paths (deepest first)
        #
        # Args:
        #   $@  Command-line arguments.
        #
        # Exit:
        #   0 on success; otherwise exits via die() or underlying command failure (set -e).
    main() {
        local -a orig_argv
        local abs=""
        local abs_dir=""

        orig_argv=("$@")

        set_name "$NAME_DEFAULT"

        while [[ $# -gt 0 ]]; do
            case "$1" in
                -n|--name)
                    shift
                    [[ $# -gt 0 ]] || die "--name requires a value"
                    set_name "$1"
                    shift
                    ;;
                -m|--manifest)
                    shift
                    [[ $# -gt 0 ]] || die "--manifest requires a file path"
                    MANIFEST="$1"
                    shift
                    ;;
                -r|--root)
                    shift
                    [[ $# -gt 0 ]] || die "--root requires a path"
                    ROOT="$1"
                    shift
                    ;;
                -d|--dryrun|--dry-run)
                    DRYRUN=1
                    shift
                    ;;
                -h|--help)
                    show_help
                    exit 0
                    ;;
                *)
                    die "Unknown option: $1"
                    ;;
            esac
        done

        # Normalize root (no trailing slash except '/')
        if [[ "$ROOT" != "/" ]]; then
            ROOT="${ROOT%/}"
        fi

        # If uninstalling from / and not dry-running, require root.
        if (( ! DRYRUN )) && [[ "$ROOT" == "/" ]]; then
            need_root_reexec "${orig_argv[@]}"
        fi

        if [[ -z "$MANIFEST" ]]; then
            resolve_manifest_default
        else
            [[ -r "$MANIFEST" ]] || die "Manifest not found or unreadable: $MANIFEST"
        fi

        # Read manifest, remove files
        # Strip leading "./" if present; skip blank lines.
        mapfile -t paths < <(sed -e 's/^\.\///' -e '/^[[:space:]]*$/d' "$MANIFEST")

        # Remove files listed in manifest
        for rel in "${paths[@]}"; do
            abs="${ROOT}/${rel}"
            rm_file "$abs"
        done

        # Remove empty dirs (deepest first)
        mapfile -t dirs < <(
            printf '%s\n' "${paths[@]}" \
            | awk -F/ 'NF>1 { $NF=""; sub(/\/$/, "", $0); print }' \
            | sort -u \
            | awk '{ print length($0) "\t" $0 }' \
            | sort -nr \
            | cut -f2-
        )

        for rel_dir in "${dirs[@]}"; do
            abs_dir="${ROOT}/${rel_dir}"
            rmdir_if_empty "$abs_dir"
        done

        say "Done. (NAME=$NAME, ROOT=$ROOT, DRYRUN=$DRYRUN)"
    }

main "$@"

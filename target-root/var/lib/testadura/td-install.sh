#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — td-install
# ------------------------------------------------------------------------------
# Purpose : Install or update a Testadura-style release package onto a target root
# Author  : Mark Fieten
# Version : 1.2 (2026-02-19)
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ------------------------------------------------------------------------------
# Notes
#   - This installer is standalone: it does NOT source the Testadura framework.
#   - Re-running with a newer package performs an in-place update.
#   - Supports dev installs via --root <path> (extract into a sysroot).
#   - Assumes package tarballs live in the current directory by default.
# ==============================================================================

set -euo pipefail

# --- Defaults ------------------------------------------------------------------
    NAME_DEFAULT="SolidgroundUX"

    NAME="$NAME_DEFAULT"
    name_lc=""

    PKG_GLOB=""
    EXTRACT_ROOT="/"

    STATE_DIR=""
    MANIFEST_DIR=""

# --- Helpers -------------------------------------------------------------------
    # die
        # Print a fatal error message to stderr and exit immediately.
        #
        # Args:
        #   $*  Message text.
        #
        # Exit:
        #   127 (consistent "command not found / fatal" convention used elsewhere).
    die()  { printf 'FATAL: %s\n' "$*" >&2; exit 127; }

    # warn
        # Print a warning message to stderr.
        #
        # Args:
        #   $*  Message text.
    warn() { printf 'WARNING: %s\n' "$*" >&2; }

    # info
        # Print an informational message to stdout.
        #
        # Args:
        #   $*  Message text.
    info() { printf '%s\n' "$*"; }

    # set_name
        # Configure product-specific defaults derived from a product name.
        #
        # Derives:
        #   - PKG_GLOB     : "<NAME>-*.tar*"
        #   - STATE_DIR    : "/var/lib/<name_lc>"
        #   - MANIFEST_DIR : "$STATE_DIR/manifests"
        #
        # Args:
        #   $1  Product name (non-empty). Example: "SolidgroundUX".
        #
        # Effects:
        #   Sets globals: NAME, name_lc, PKG_GLOB, STATE_DIR, MANIFEST_DIR.
        #
        # Exit:
        #   Aborts via die() if name is empty.
    set_name() {
        local n="$1"
        [[ -n "$n" ]] || die "--name requires a non-empty value"

        NAME="$n"
        name_lc="${NAME,,}"

        PKG_GLOB="${NAME}-*.tar*"
        STATE_DIR="/var/lib/${name_lc}"
        MANIFEST_DIR="${STATE_DIR}/manifests"
    }

    # need_root_reexec
        # Re-exec this installer under sudo when not running as root.
        #
        # Rationale:
        #   System installs (EXTRACT_ROOT="/") require root for extraction into /usr/local.
        #   This function preserves the original argv exactly.
        #
        # Args:
        #   $@  Original script arguments (pass through unchanged).
        #
        # Behavior:
        #   - If already root: returns normally.
        #   - If not root    : exec sudo -- "$0" "$@" (does not return).
    need_root_reexec() {
        # Re-exec this script under sudo, preserving all original args.
        if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
            exec sudo -- "$0" "$@"
        fi
    }

    # list_packages
        # List package files in the current directory matching PKG_GLOB.
        #
        # Globals:
        #   PKG_GLOB  Glob pattern (e.g. "SolidgroundUX-*.tar*").
        #
        # Output:
        #   Writes one matching filename per line to stdout.
        #
        # Notes:
        #   - Uses nullglob to avoid emitting the literal glob when no matches exist.
        #   - Only returns files (-f).
    list_packages() {
        local f
        shopt -s nullglob
        for f in $PKG_GLOB; do
            [[ -f "$f" ]] && printf '%s\n' "$f"
        done
        shopt -u nullglob
    }

    # pick_newest
        # Select the newest package filename from list_packages().
        #
        # Selection:
        #   Uses sort -V (version sort) and returns the last entry.
        #
        # Output:
        #   Prints the newest matching filename to stdout (or empty if none).
    pick_newest() {
        list_packages | sort -V | tail -n 1
    }

    # select_interactive
        # Prompt the user to choose a package interactively from the current directory.
        #
        # Preconditions:
        #   - Requires a TTY on stdin.
        #   - Requires at least one matching package (PKG_GLOB).
        #
        # Output:
        #   Prints the selected package filename to stdout.
        #
        # Exit:
        #   - Aborts via die() if no packages exist or user aborts.
        #
        # Notes:
        #   Uses list_packages | sort -V to present a stable ordering.
    select_interactive() {
        local -a pkgs
        local i choice

        mapfile -t pkgs < <(list_packages | sort -V)
        [[ "${#pkgs[@]}" -gt 0 ]] || die "No packages found matching: $PKG_GLOB"

        info ""
        info "Available packages:"
        i=1
        while [[ $i -le "${#pkgs[@]}" ]]; do
            printf "  %2d) %s\n" "$i" "${pkgs[$((i-1))]}"
            i=$((i+1))
        done
        info ""

        while true; do
            read -r -p "Select package number (or empty to abort): " choice
            [[ -n "$choice" ]] || die "Aborted."
            [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Enter a number."; continue; }
            [[ "$choice" -ge 1 && "$choice" -le "${#pkgs[@]}" ]] || { warn "Out of range."; continue; }
            printf '%s\n' "${pkgs[$((choice-1))]}"
            return 0
        done
    }

    # checksum_verify
        # Verify the integrity of a package file using SHA-256 checksums.
        #
        # Lookup order:
        #   1) SHA256SUMS file in the current directory (preferred)
        #      - Requires an entry matching the package basename.
        #      - Verifies only the selected package line (supports rolling SHA256SUMS).
        #   2) Per-package checksum file "<pkg>.sha256"
        #
        # Args:
        #   $1  Package path or filename.
        #
        # Exit:
        #   Aborts via die() if:
        #     - Package does not exist
        #     - Checksum entry is missing
        #     - Verification fails
        #     - No checksum file is available
        #
        # Notes:
        #   Entries in SHA256SUMS must list basenames, not absolute paths.
    checksum_verify() {
        local pkg="$1"
        local pkg_base=""
        local sums_file="SHA256SUMS"
        local per_file=""

        [[ -f "$pkg" ]] || die "Package not found: $pkg"

        pkg_base="$(basename -- "$pkg")"
        per_file="${pkg}.sha256"

        if [[ -r "$sums_file" ]]; then
            # Require an entry for the package basename in SHA256SUMS.
            if ! grep -Fq -- "  $pkg_base" "$sums_file"; then
                die "Checksum file '$sums_file' exists, but has no entry for: $pkg_base"
            fi

            info "Verifying checksum (SHA256SUMS) ..."
            grep -F -- "  $pkg_base" "$sums_file" | sha256sum -c --status \
                || die "Checksum verification failed for: $pkg_base"
            info "Checksum OK."
            return 0
        fi

        if [[ -r "$per_file" ]]; then
            info "Verifying checksum ($(basename -- "$per_file")) ..."
            sha256sum -c --status "$per_file" \
                || die "Checksum verification failed for: $pkg_base"
            info "Checksum OK."
            return 0
        fi

        die "No checksum found. Provide 'SHA256SUMS' or '${pkg}.sha256'."
    }

    # pkg_base_from_archive
        # Derive the release base name from a package filename by stripping tar extensions.
        #
        # Example:
        #   SolidgroundUX-1.1.0.tar.gz -> SolidgroundUX-1.1.0
        #
        # Args:
        #   $1  Package filename.
        #
        # Output:
        #   Prints the derived base name to stdout.
    pkg_base_from_archive() {
        # Strip common tar extensions to get release base name.
        # Example: SolidgroundUX-1.1.0.tar.gz -> SolidgroundUX-1.1.0
        local pkg="$1"
        local base="$pkg"

        base="${base%.tar.gz}"
        base="${base%.tgz}"
        base="${base%.tar.xz}"
        base="${base%.tar}"
        printf '%s\n' "$base"
    }

    # install_manifest_record
        # Save the manifest associated with a package into the product state directory.
        #
        # For package "<base>.tar*", expects manifest "<base>.manifest" next to it.
        #
        # Args:
        #   $1  Package filename.
        #
        # Behavior:
        #   - Copies "<base>.manifest" to $MANIFEST_DIR/
        #   - Writes the manifest filename into $STATE_DIR/CURRENT.manifest
        #
        # Globals:
        #   MANIFEST_DIR, STATE_DIR
        #
        # Notes:
        #   - If no manifest exists, prints a warning and continues.
        #   - Manifest recording is intended for system installs (EXTRACT_ROOT="/").
    install_manifest_record() {
        local pkg="$1"
        local base=""
        local manifest_src=""

        base="$(pkg_base_from_archive "$pkg")"
        manifest_src="${base}.manifest"

        if [[ -r "$manifest_src" ]]; then
            mkdir -p -- "$MANIFEST_DIR"
            cp -f -- "$manifest_src" "$MANIFEST_DIR/" || die "Failed to copy manifest to: $MANIFEST_DIR"
            info "Saved manifest: $MANIFEST_DIR/$(basename -- "$manifest_src")"
            printf '%s\n' "$(basename -- "$manifest_src")" > "$STATE_DIR/CURRENT.manifest" 2>/dev/null || true
        else
            warn "No manifest found next to package ($manifest_src). Uninstall will require a manifest."
        fi
    }

    # extract_package
        # Extract a release package archive into EXTRACT_ROOT.
        #
        # Supported formats:
        #   *.tar, *.tar.gz, *.tgz, *.tar.xz
        #
        # Args:
        #   $1  Package filename.
        #
        # Globals:
        #   EXTRACT_ROOT  Target root ("/" for system install or sysroot for dev install).
        #   dryrun        If non-zero, performs tar --dry-run.
        #
        # Behavior:
        #   - Preserves permissions (-p)
        #   - Does not enforce archive ownership (--no-same-owner)
        #
        # Exit:
        #   Aborts via die() on missing package or unknown archive type.
    extract_package() {
        local pkg="$1"
        local options=""
        local -a tar_extra=()
        local -a dryopt=()

        [[ -f "$pkg" ]] || die "Package not found: $pkg"

        info "Installing: $pkg"
        info "Target    : $EXTRACT_ROOT"
        info ""

        case "$pkg" in
            *.tar)          options="xpf"  ;;
            *.tar.gz|*.tgz) options="xzpf" ;;
            *.tar.xz)       options="xJpf" ;;
            *) die "Unknown archive type: $pkg" ;;
        esac

        # Preserve permissions (-p), but do not force ownership from the archive.
        tar_extra+=(--no-same-owner)

        if (( dryrun )); then
            dryopt+=(--dry-run)
            warn "Dry-run mode: nothing will be written"
        fi

        tar "${dryopt[@]}" "${tar_extra[@]}" -"$options" "$pkg" -C "$EXTRACT_ROOT"

        info ""
        info "Done."
    }

    # show_help
        # Print usage and option help text.
        #
        # Notes:
        #   Kept as a function to allow early --help handling and reuse.
    show_help() {
        printf "Usage: %s [options]\n" "$0"
        printf "\n"
        printf "Installs or updates a release package (tar/tgz/tar.xz) in the current directory.\n"
        printf "Re-running with a newer package performs an in-place update.\n"
        printf "\n"
        printf "Options:\n"
        printf "  -n, --name NAME           product name (default: %s)\n" "$NAME_DEFAULT"
        printf "  -g, --glob PATTERN        package glob override (default: %s-*.tar*)\n" "$NAME_DEFAULT"
        printf "  -a, --auto                install newest matching package automatically\n"
        printf "  -t, --root PATH           extract to PATH instead of /\n"
        printf "      --target-root PATH    alias for --root\n"
        printf "  -d, --dry-run             verify and simulate extraction\n"
        printf "  -s, --no-checksum         skip checksum verification\n"
        printf "  -h, --help                show this help\n"
        printf "\n"
        printf "Examples:\n"
        printf "  %s --auto\n" "$0"
        printf "  %s --name SolidgroundUX --auto\n" "$0"
        printf "  %s --root /home/me/dev/target-root --auto\n" "$0"
    }

# --- Main ----------------------------------------------------------------------
    # main
        # Entry point: parse options, select package, verify, extract, and record manifest.
        #
        # Flow:
        #   1) Initialize defaults (set_name)
        #   2) Parse CLI options
        #   3) If installing to "/" and not dry-run: re-exec under sudo if needed
        #   4) Select package (auto newest or interactive)
        #   5) Verify checksum (unless disabled)
        #   6) Extract package into EXTRACT_ROOT
        #   7) Record manifest + CURRENT.manifest for system installs
        #
        # Args:
        #   $@  Command-line arguments.
        #
        # Exit:
        #   0 on success; otherwise exits via die() or underlying command failure (set -e).
    main() {
        local auto=0
        local pkg=""
        local nochecksum=0
        local -a orig_argv

        orig_argv=("$@")

        dryrun=0
        set_name "$NAME_DEFAULT"

        while [[ $# -gt 0 ]]; do
            case "$1" in
                -n|--name)
                    shift
                    [[ $# -gt 0 ]] || die "--name requires a value"
                    set_name "$1"
                    shift
                    ;;
                -g|--glob)
                    shift
                    [[ $# -gt 0 ]] || die "--glob requires a pattern"
                    PKG_GLOB="$1"
                    shift
                    ;;
                -a|--auto)
                    auto=1
                    shift
                    ;;
                -d|--dryrun|)
                    dryrun=1
                    shift
                    ;;
                -s|--nochecksum)
                    nochecksum=1
                    shift
                    ;;
                -t|--root|--target-root)
                    shift
                    [[ $# -gt 0 ]] || die "--root requires a path"
                    EXTRACT_ROOT="$1"
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

        # If we are going to write to /, ensure we are root BEFORE doing interactive work.
        if (( ! dryrun )) && [[ "$EXTRACT_ROOT" == "/" ]]; then
            need_root_reexec "${orig_argv[@]}"
        fi

        if (( auto )); then
            pkg="$(pick_newest)"
            [[ -n "$pkg" ]] || die "No packages found matching: $PKG_GLOB"
        else
            [[ -t 0 ]] || die "No TTY available. Use --auto."
            pkg="$(select_interactive)"
        fi

        if (( ! nochecksum )); then
            checksum_verify "$pkg"
        fi

        extract_package "$pkg"

        # Record manifest for uninstall (only meaningful for system installs)
        if (( ! dryrun )) && [[ "$EXTRACT_ROOT" == "/" ]]; then
            install_manifest_record "$pkg"
        fi
    }

main "$@"

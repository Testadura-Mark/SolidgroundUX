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
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 127; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

set_name() {
    local n="$1"
    [[ -n "$n" ]] || die "--name requires a non-empty value"

    NAME="$n"
    name_lc="${NAME,,}"

    PKG_GLOB="${NAME}-*.tar*"
    STATE_DIR="/var/lib/${name_lc}"
    MANIFEST_DIR="${STATE_DIR}/manifests"
}

need_root_reexec() {
    # Re-exec this script under sudo, preserving all original args.
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        exec sudo -- "$0" "$@"
    fi
}

list_packages() {
    local f
    shopt -s nullglob
    for f in $PKG_GLOB; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
    shopt -u nullglob
}

pick_newest() {
    list_packages | sort -V | tail -n 1
}

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

show_help() {
    printf "Usage: %s [options]\n" "$0"
    printf "\n"
    printf "Installs or updates a release package (tar/tgz/tar.xz) in the current directory.\n"
    printf "Re-running with a newer package performs an in-place update.\n"
    printf "\n"
    printf "Options:\n"
    printf "  -n, --name NAME           product name (default: %s)\n" "$NAME_DEFAULT"
    printf "  -g, --glob PATTERN        package glob override (default: <NAME>-*.tar*)\n"
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
            -d|--dryrun|--dry-run|--dry-run)
                dryrun=1
                shift
                ;;
            -s|--nochecksum|--no-checksum)
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

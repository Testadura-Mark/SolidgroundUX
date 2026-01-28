#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — install.sh
# -------------------------------------------------------------------------------
# Purpose : Installs SolidgroundUX onto a target system
# Author  : Mark Fieten
# Version : 1.1 (2026-01-28)
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description
#   Assumes a collection of tar-files (.tar, .tar.gz, .tgz, .tar.xz.) in the same
#   directory. Supports dev installs via --root <path>.
set -euo pipefail

# --- Settings ------------------------------------------------------------------
PKG_GLOB="SolidgroundUX-*.tar*"
EXTRACT_ROOT="/"
STATE_DIR="/var/lib/solidgroundux"
MANIFEST_DIR="$STATE_DIR/manifests"

# --- Helpers -------------------------------------------------------------------
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 127; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

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
    local sums_file="SHA256SUMS"
    local per_file="${pkg}.sha256"

    if [[ -r "$sums_file" ]]; then
        # Require an entry for this exact file (basename match)
        if ! grep -Fq -- "  $pkg" "$sums_file"; then
            die "Checksum file '$sums_file' exists, but has no entry for: $pkg"
        fi

        info "Verifying checksum (SHA256SUMS) ..."
        grep -F -- "  $pkg" "$sums_file" | sha256sum -c --status \
            || die "Checksum verification failed for: $pkg"
        info "Checksum OK."
        return 0
    fi

    if [[ -r "$per_file" ]]; then
        info "Verifying checksum ($per_file) ..."
        sha256sum -c --status "$per_file" \
            || die "Checksum verification failed for: $pkg"
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
    local base manifest_src

    base="$(pkg_base_from_archive "$pkg")"
    manifest_src="${base}.manifest"

    if [[ -r "$manifest_src" ]]; then
        mkdir -p "$MANIFEST_DIR"
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
    local -a dryopt=()

    [[ -f "$pkg" ]] || die "Package not found: $pkg"

    info "Installing: $pkg"
    info "Target   : $EXTRACT_ROOT"
    info ""

    case "$pkg" in
        *.tar)          options="xpf"  ;;
        *.tar.gz|*.tgz) options="xzpf" ;;
        *.tar.xz)       options="xJpf" ;;
        *) die "Unknown archive type: $pkg" ;;
    esac

    if (( dryrun )); then
        dryopt=(--dry-run)
        warn "Dry-run mode: nothing will be written"
    fi

    tar "${dryopt[@]}" -"$options" "$pkg" -C "$EXTRACT_ROOT"

    info ""
    info "Done."
}

# --- Main ----------------------------------------------------------------------
main() {
    local auto=0 pkg=""
    local nochecksum=0
    local -a orig_argv
    orig_argv=("$@")

    dryrun=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--auto)             auto=1; shift ;;
            -d|--dryrun|--dry-run) dryrun=1; shift ;;
            -s|--nochecksum|--no-checksum) nochecksum=1; shift ;;
            -t|--target-root)
                shift
                [[ $# -gt 0 ]] || die "-- target-root requires a path"
                EXTRACT_ROOT="$1"
                shift
                ;;
            -g|--glob)
                shift
                [[ $# -gt 0 ]] || die "--glob requires a pattern"
                PKG_GLOB="$1"
                shift
                ;;
            -h|--help)
                printf "Usage: %s [--auto] [--dryrun] [--nochecksum] [--root PATH] [--glob PATTERN]\n" "$0"
                printf "  --auto                    install newest package automatically\n"
                printf "  --dryrun                  verify and simulate extraction\n"
                printf "  --nochecksum              skip checksum verification\n"
                printf "  --target-root     PATH    extract to PATH instead of /\n"
                printf "  --glob                    PATTERN package glob (default: %s)\n" "$PKG_GLOB"
                exit 0
                ;;
            *) die "Unknown option: $1" ;;
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

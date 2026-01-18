#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — install.sh
# -------------------------------------------------------------------------------
# Purpose : Installs SolidgroundUX onto a target system
# Author  : Mark Fieten
# Version : 1.0 (2026-01-03)
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description
#   Assumes a collection of tar-files (.tar, .tar.gz, .tgz, .tar.xz.) in the same
#   directory.
set -euo pipefail

# --- Settings ---------------------------------------------------------------
PKG_GLOB="testadura-*.tar*"
EXTRACT_ROOT="/"

# --- Helpers ----------------------------------------------------------------
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 127; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

need_root() {
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
    # Uses version-sort on filenames (works well if names include x.y.z)
    list_packages | sort -V | tail -n 1
}

select_interactive() {
    local pkgs i choice
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

    # 1) Prefer SHA256SUMS (covers many packages)
    if [[ -r "$sums_file" ]]; then
        # Require an entry for this file
        if ! grep -Fq -- "  $pkg" "$sums_file"; then
            die "Checksum file '$sums_file' exists, but has no entry for: $pkg"
        fi

        info "Verifying checksum (SHA256SUMS) ..."
        # Verify ONLY this file's line(s)
        # shellcheck disable=SC2002
        grep -F -- "  $pkg" "$sums_file" | sha256sum -c --status \
            || die "Checksum verification failed for: $pkg"
        info "Checksum OK."
        return 0
    fi

    # 2) Fallback: per-file checksum
    if [[ -r "$per_file" ]]; then
        info "Verifying checksum ($per_file) ..."
        sha256sum -c --status "$per_file" \
            || die "Checksum verification failed for: $pkg"
        info "Checksum OK."
        return 0
    fi

    # 3) No checksum found
    die "No checksum found. Provide 'SHA256SUMS' or '${pkg}.sha256'."
}

extract_package() {
    local pkg="$1"
    local options=""
    local dryopt=()

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

# --- Main -------------------------------------------------------------------
main() {
    local auto=0 pkg=""
    dryrun=0
    local nochecksum=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--auto)        auto=1; shift ;;
            -d|--dryrun|--dry-run) dryrun=1; shift ;;
            -s|--nochecksum|--no-checksum) nochecksum=1; shift ;;
            -h|--help)
                printf "Usage: %s [--auto] [--dryrun] [--nochecksum]\n" "$0"
                printf "  --auto        install newest package automatically\n"
                printf "  --dryrun      verify and simulate extraction\n"
                printf "  --nochecksum  skip checksum verification\n"
                exit 0
                ;;
            *) die "Unknown option: $1" ;;
        esac
    done

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

    # Only escalate when actually writing
    if (( ! dryrun )); then
        need_root "$@"
    fi

    extract_package "$pkg"
}

main "$@"

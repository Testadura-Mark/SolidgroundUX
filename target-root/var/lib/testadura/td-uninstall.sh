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
die() { printf 'FATAL: %s\n' "$*" >&2; exit 127; }
say() { printf '%s\n' "$*"; }

need_root_reexec() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        exec sudo -- "$0" "$@"
    fi
}

set_name() {
    local n="$1"
    [[ -n "$n" ]] || die "--name requires a non-empty value"

    NAME="$n"
    name_lc="${NAME,,}"

    STATE_DIR="/var/lib/${name_lc}"
    MANIFEST_DIR="${STATE_DIR}/manifests"
    CURRENT_FILE="${STATE_DIR}/CURRENT.manifest"
}

rm_file() {
    local p="$1"
    if (( DRYRUN )); then
        say "DRYRUN: rm -f -- '$p'"
    else
        rm -f -- "$p" || true
    fi
}

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

resolve_manifest_default() {
    local manifest_name=""
    [[ -r "$CURRENT_FILE" ]] || die "No manifest specified and no CURRENT.manifest found in: $STATE_DIR"
    manifest_name="$(cat -- "$CURRENT_FILE")"
    [[ -n "$manifest_name" ]] || die "CURRENT.manifest is empty: $CURRENT_FILE"

    MANIFEST="${MANIFEST_DIR}/${manifest_name}"
    [[ -r "$MANIFEST" ]] || die "Manifest listed in CURRENT.manifest not found: $MANIFEST"
}

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

#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — uninstall.sh
# -------------------------------------------------------------------------------
# Purpose : Removes SolidgroundUX from a target system
# Author  : Mark Fieten
# Version : 1.0 (2026-01-03)
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------

set -euo pipefail

# --- Config -------------------------------------------------------------------
MANIFEST="${1:-}"
DRYRUN="${DRYRUN:-0}"   # export DRYRUN=1 for simulation
ROOT="${ROOT:-/}"       # allow ROOT=~/dev/target-root for testing

if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  printf 'Usage: %s <manifest-file>\n' "$0" >&2
  exit 2
fi

# Normalize root (no trailing slash except '/')
if [[ "$ROOT" != "/" ]]; then
  ROOT="${ROOT%/}"
fi

say() { printf '%s\n' "$*"; }

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

  # Only remove if empty
  if (( DRYRUN )); then
    if [[ -z "$(ls -A -- "$d" 2>/dev/null || true)" ]]; then
      say "DRYRUN: rmdir -- '$d'"
    fi
  else
    rmdir -- "$d" 2>/dev/null || true
  fi
}

# --- Read manifest, remove files ----------------------------------------------
# Strip leading "./" if present; skip blank lines.
mapfile -t paths < <(sed -e 's/^\.\///' -e '/^[[:space:]]*$/d' "$MANIFEST")

# Remove files
for rel in "${paths[@]}"; do
  # Only remove files listed in manifest
  abs="${ROOT}/${rel}"
  rm_file "$abs"
done

# --- Remove empty dirs (deepest first) ----------------------------------------
# Derive dirs from manifest paths, sort by depth descending, unique.
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

say "Done. (ROOT=$ROOT, DRYRUN=$DRYRUN)"

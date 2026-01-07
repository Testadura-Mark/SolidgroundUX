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
set -euo pipefail

SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_FILE")" && pwd)"

PREFIX="/"
DRYRUN=1
FORCE=0

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

Options:
  --prefix <path>   Install into an alternate root (default: /)
                    Example: --prefix /mnt/target
  --dry-run         Show what would be done, without changing anything
  --force           Skip safety checks
  -h, --help        Show this help

Expected layout:
  ./target-root/etc/...
  ./target-root/usr/...

Note:
  Entry points are installed from target-root:
    /usr/local/bin/td-create-workspace
    /usr/local/sbin/td-deploy-workspace
EOF
}

fail() { echo "[FAIL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

run() {
  if [[ "$DRYRUN" -eq 1 ]]; then
    echo "[DRY ] $*"
  else
    "$@"
  fi
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    info "Re-running with sudo..."
    exec sudo -E -- "$SCRIPT_FILE" "$@"
  fi
  fail "Must run as root (or install sudo)."
}

# --- parse args -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || fail "--prefix requires a path"
      PREFIX="$2"
      shift 2
      ;;
    --dry-run)
      DRYRUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1 (use --help)"
      ;;
  esac
done

main() {
  need_root "$@"

  local SRC="$SCRIPT_DIR/target-root"
  [[ -d "$SRC" ]] || fail "Missing $SRC"

  # Safety: target-root should not contain random top-level dirs like ./templates
  # (You currently DO have target-root/templates; move it under usr/local/lib/... first.)
  if [[ -d "$SRC/templates" && "$FORCE" -ne 1 ]]; then
    fail "Found $SRC/templates. Move templates under target-root/usr/local/lib/... (recommended) or re-run with --force."
  fi

  # Normalize prefix
  if [[ "$PREFIX" != "/" ]]; then PREFIX="${PREFIX%/}"; fi

  info "Source : $SRC"
  info "Prefix : $PREFIX"
  info "Dry-run: $DRYRUN"

  # Ensure base dirs exist
  run mkdir -p "$PREFIX/usr/local/bin" "$PREFIX/usr/local/sbin" "$PREFIX/usr/local/lib" "$PREFIX/etc"

  # Copy payload
  if command -v rsync >/dev/null 2>&1; then
    info "Copying with rsync..."
    run rsync -a --delete "$SRC"/ "$PREFIX"/
  else
    info "Copying with cp (rsync not found)..."
    run cp -a "$SRC"/. "$PREFIX"/
  fi

  info "Installed entry points (if present):"
  [[ -e "$PREFIX/usr/local/bin/td-create-workspace" ]] && info "  - $PREFIX/usr/local/bin/td-create-workspace"
  [[ -e "$PREFIX/usr/local/sbin/td-deploy-workspace" ]] && info "  - $PREFIX/usr/local/sbin/td-deploy-workspace"

  info "Done."
}

main

Polished version (minimal change, same spirit)
# =================================================================================
# Testadura — <libname>.sh
# ---------------------------------------------------------------------------------
# Purpose : <short description of what this library provides>
# Author  : Mark Fieten
#
# Design rules:
#   - Library files define functions and constants only.
#   - No auto-execution.
#   - No set -euo pipefail.
#   - No path detection (bootstrap owns all path resolution).
#   - No global behavior changes (UI, logging, shell options).
#   - Safe to source multiple times.
#
# Non-goals:
#   - Executable scripts
#   - User interaction
#   - Policy decisions
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_<LIBNAME>_LOADED:-}" ]] && return 0
    TD_<LIBNAME>_LOADED=1

# --- Internal helpers ------------------------------------------------------------
    # Prefix with __
    # Example:
    # __<libname>_helper() {
    #     :
    # }
# --- Public API ------------------------------------------------------------------
    # prefix with td_
    # Example:
    # td_<libname>_do_something() {
    #     :
    # }



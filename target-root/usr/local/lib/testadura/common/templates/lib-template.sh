# =================================================================================
# Testadura Consultancy — lib-template.sh
# ---------------------------------------------------------------------------------
# Purpose    : Template for Testadura Bash libraries (header + guards + structure)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides a standard skeleton for Testadura framework libraries, including:
#   - Canonical header sections (purpose/description/contracts)
#   - "library only" execution guard (must be sourced, never executed)
#   - Load guard for idempotent sourcing
#   - Suggested naming conventions for internal/public functions
#
# Assumptions:
#   - None by default. Each library should explicitly document:
#       - Whether it is a CORE lib (no framework deps), or
#       - A FRAMEWORK lib (may assume framework/theme primitives exist).
#
# Design rules:
#   - Libraries define functions and constants only.
#   - No auto-execution (must be sourced).
#   - No `set -euo pipefail` or persistent shell-option changes.
#   - No path detection or root resolution (bootstrap owns path resolution).
#   - No global behavior changes (UI routing, logging policy, shell options).
#   - Safe to source multiple times (idempotent load guard).
#
# Non-goals:
#   - Executable scripts (use /bin tools or applets for entry points)
#   - User interaction unless explicitly part of a UI module
#   - Policy decisions (libraries provide mechanisms; callers decide policy)
# =================================================================================
# --- Library guard ----------------------------------------------------------------
    # Derive a unique per-library guard variable from the filename:
    #   ui.sh        -> TD_UI_LOADED
    #   ui-sgr.sh    -> TD_UI_SGR_LOADED
    #   foo-bar.sh   -> TD_FOO_BAR_LOADED
    __lib_base="$(basename "${BASH_SOURCE[0]}")"
    __lib_base="${__lib_base%.sh}"
    __lib_base="${__lib_base//-/_}"
    __lib_guard="TD_${__lib_base^^}_LOADED"

    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
        echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
        exit 2
    }

    # Load guard (safe under set -u)
    [[ -n "${!__lib_guard-}" ]] && return 0
    printf -v "$__lib_guard" '1'


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



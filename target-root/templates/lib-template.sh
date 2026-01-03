# shellcheck shell=bash
# ==============================================================================
# Testadura — <libname>.sh
# ------------------------------------------------------------------------------
# Purpose : <short description of what this library provides>
# Author  : Mark Fieten
#
# Design rules:
#   - Library files define functions and constants only.
#   - No auto-execution.
#   - No set -euo pipefail.
#   - No path detection.
#   - No global behavior changes.
#   - Safe to source multiple times.
# ==============================================================================

[[ -n "${TD_<LIBNAME>_LOADED:-}" ]] && return 0
TD_<LIBNAME>_LOADED=1

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

# Example:
# td_<libname>_do_something() {
#     :
# }

# ------------------------------------------------------------------------------
# Internal helpers (prefix with __td_)
# ------------------------------------------------------------------------------

# __td_<libname>_helper() {
#     :
# }

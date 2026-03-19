# ==================================================================================
# Testadura Consultancy — UI Glyph Definitions
# ----------------------------------------------------------------------------------
# Module     : ui-glyphs.sh
# Purpose    : Centralized Unicode glyph definitions for terminal UI rendering
#
# Description:
#   Provides a shared set of Unicode characters used throughout the framework
#   for rendering structured terminal output, including:
#     - box drawing (light and double line)
#     - common symbols and indicators
#     - math and comparison glyphs
#     - keyboard hints
#     - Greek symbols
#
# Design principles:
#   - Single source of truth for all glyphs
#   - Avoid hardcoded Unicode characters scattered across modules
#   - Improve readability and consistency of terminal UI code
#   - Keep naming predictable and category-based
#
# Naming conventions:
#   LN_*  Light line drawing
#   DL_*  Double line drawing
#   CH_*  General characters
#   KY_*  Keyboard hints
#   GR_*  Greek symbols
#
# Role in framework:
#   - Low-level dependency for UI rendering modules (ui.sh, console, menus)
#   - Used wherever structured terminal output or symbolic indicators are needed
#
# Non-goals:
#   - Rendering logic (this module defines symbols only)
#   - Color/styling (handled in ui.sh)
#
# Author     : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================

set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # __td_lib_guard
        # Purpose:
        #   Ensure the file is sourced as a library and only initialized once.
        #
        # Behavior:
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution if the file is executed instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Skips initialization if the library was already loaded.
        #
        # Inputs:
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals):
        #   TD_<MODULE>_LOADED
        #
        # Returns:
        #   0 if already loaded or successfully initialized.
        #   Exits with code 2 if executed instead of sourced.
        #
        # Usage:
        #   __td_lib_guard
        #
        # Examples:
        #   # Typical usage at top of library file
        #   __td_lib_guard
        #   unset -f __td_lib_guard
        #
        # Notes:
        #   - Guard variable is derived dynamically (e.g. ui-glyphs.sh → TD_UI_GLYPHS_LOADED).
        #   - Safe under `set -u` due to indirect expansion with default.
    __td_lib_guard() {
        local lib_base
        local guard

        lib_base="$(basename "${BASH_SOURCE[0]}")"
        lib_base="${lib_base%.sh}"
        lib_base="${lib_base//-/_}"
        guard="TD_${lib_base^^}_LOADED"

        # Refuse to execute (library only)
        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
            exit 2
        }

        # Load guard (safe under set -u)
        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    __td_lib_guard
    unset -f __td_lib_guard
    
# --- Light line drawing --------------------------------------------------------
    LN_H="─"
    LN_V="│"

    LN_TL="┌"
    LN_TR="┐"
    LN_BL="└"
    LN_BR="┘"

    LN_T="┬"
    LN_B="┴"
    LN_L="├"
    LN_R="┤"
    LN_X="┼"


# --- Double line drawing -------------------------------------------------------
    DL_H="═"
    DL_V="║"

    DL_TL="╔"
    DL_TR="╗"
    DL_BL="╚"
    DL_BR="╝"

    DL_T="╦"
    DL_B="╩"
    DL_L="╠"
    DL_R="╣"
    DL_X="╬"

# --- Common characters ---------------------------------------------------------
    CH_DEG="°"
    CH_COPY="©"
    CH_TM="™"
    CH_REG="®"

    CH_BULLET="•"
    CH_ARROW="→"
    CH_ELLIPSIS="…"

# --- Math / comparison ---------------------------------------------------------
    CH_SQRT="√"
    CH_GE="≥"
    CH_LE="≤"
    CH_NE="≠"
    CH_APPROX="≈"
    CH_INF="∞"

# --- Keyboard hints ------------------------------------------------------------
    KY_ENTER="↵"
    KY_UP="↑"
    KY_DOWN="↓"
    KY_LEFT="←"
    KY_RIGHT="→"

# --- Greek letters -------------------------------------------------------------
    GR_ALPHA="α"
    GR_BETA="β"
    GR_GAMMA="γ"
    GR_DELTA="Δ"
    GR_PI="π"
    GR_OMEGA="Ω"



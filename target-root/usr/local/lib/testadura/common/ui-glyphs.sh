# =================================================================================
# Testadura Consultancy — ui-glyphs
# ---------------------------------------------------------------------------------
# Purpose    : Shared Unicode glyphs for terminal UI, math, and diagnostics
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------

set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # Library-only: must be sourced, never executed.
    # Uses a per-file guard variable derived from the filename, e.g.:
    #   ui.sh      -> TD_UI_LOADED
    #   foo-bar.sh -> TD_FOO_BAR_LOADED
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



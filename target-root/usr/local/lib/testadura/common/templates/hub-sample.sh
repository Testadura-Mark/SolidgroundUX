# =================================================================================
# Testadura Consultancy — sample-module.sh
# ---------------------------------------------------------------------------------
# Purpose    : A reusable module for td-script-hub (or any hub-style menu app).
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   module-template with some sample functions for learning/testing
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_SAMPLEMOD_LOADED:-}" ]] && return 0
    TD_SAMPLEMOD_LOADED=1

# --- Module identity ------------------------------------------------------------
    # Keep names unique + grep-friendly.
    TD_MOD_ID="example"
    TD_MOD_TITLE="Example module"
    TD_MOD_DESC="Shows the recommended structure for a hub module."

    # --- Optional: module-local defaults -------------------------------------------
    # Use : "${VAR:=default}" so hub/state can override.
    : "${EXAMPLE_OPTION:=Yes}"

# --- Handlers ------------------------------------------------------------------
    # Handlers are the ONLY place where effects may happen.
    # Keep them small; delegate heavy logic to helper functions below.

    td_mod_example_do_thing() {
        # Example handler: safe output only
        saystart "Example action"
        sayinfo  "TD_MOD_ID   : $TD_MOD_ID"
        sayinfo  "Option      : ${EXAMPLE_OPTION}"
        sayend   "Done."
    }

    td_mod_example_configure() {
        # Example interactive handler (uses ask)
        saystart "Configure example module"

        ask --label "Enable example option?" --var EXAMPLE_OPTION --default "${EXAMPLE_OPTION}" --colorize both
        sayok "Saved: EXAMPLE_OPTION=${EXAMPLE_OPTION}"

        sayend "Configuration complete."
    }
# --- Menu specs ---------------------------------------------------------------
    # Each entry: "key|group|label|handler|flags|wait"
    # - Leave key empty ("") to auto-assign.
    # - Explicit keys ("2", "10", "V", etc.) are respected.
    # - Later collisions overwrite earlier ones (hub policy).

    declare -a TD_MOD_MENU_SPECS=(
        # --- Examples -------------------------------------------------------------
        "|Examples|Example: run action (2sec)|td_mod_example_do_thing||2"
        "|Examples|Example: configure module(6sec)|td_mod_example_configure||6"
        "10|Examples|Example: configure module (0)|td_mod_example_configure||0"
        "2|Examples|Example: configure module (15)|td_mod_example_configure||15"

        # --- Other Examples -------------------------------------------------------
        "|Other Examples|Example: run action 2|td_mod_example_do_thing||2"
        "|Other Examples|Example: configure module 2|td_mod_example_configure||2"
        "10|Other Examples|Example: configure module (2)|td_mod_example_configure||2"
        "2|Other Examples|Example: configure module (4)|td_mod_example_configure||4"
    )
# --- Public API ------------------------------------------------------------------
    # prefix with td_
    # Example:
    # td_<libname>_do_something() {
    #     :
    # }



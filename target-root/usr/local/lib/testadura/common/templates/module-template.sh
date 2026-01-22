# =================================================================================
# Testadura Consultancy — module-template.sh
# ---------------------------------------------------------------------------------
# Purpose    : A reusable module for td-script-hub (or any hub-style menu app).
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   This module encapsulates a coherent set of related actions that can be
#   exposed through a shared, interactive menu hosted by a script hub.
#
#   The module contributes functionality by:
#     - defining handler functions
#     - optionally defining module-local defaults
#     - registering one or more menu entries (group, key, label, handler)
#
#   The module itself contains no control flow and no startup logic.
#   All behavior is executed only when explicitly invoked by the user
#   via the hub’s menu dispatcher.
#
# Module contract (IMPORTANT):
#   - This file is SOURCED by the hub, not executed.
#   - On load, the module MUST ONLY:
#       * define functions
#       * define defaults/constants
#       * register menu items/groups
#   - The module MUST NOT:
#       * perform actions (no installs, no file changes, no network changes)
#       * exit the shell, call main(), or call long-running logic
#
# Design notes:
#   - Composition over inheritance: modules contribute actions + registrations.
#   - All effects happen only inside handlers invoked by the hub dispatcher.
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
# --- Registration --------------------------------------------------------------
    # Register menu items at source-time (this is allowed).
    # Keys should be unique across the hub. If collision: hub should overwrite/update.

    td_menu_register_group "Examples"

    td_menu_register_item \
        --key     "E" \
        --group   "Examples" \
        --label   "Example: run action" \
        --handler "td_mod_example_do_thing" \
        --flags   ""

    td_menu_register_item \
        --key     "C" \
        --group   "Examples" \
        --label   "Example: configure module" \
        --handler "td_mod_example_configure" \
        --flags   ""
# --- Public API ------------------------------------------------------------------
    # prefix with td_
    # Example:
    # td_<libname>_do_something() {
    #     :
    # }



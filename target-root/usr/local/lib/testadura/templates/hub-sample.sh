# =================================================================================
# Testadura Consultancy — sample-module.sh
# ---------------------------------------------------------------------------------
# Purpose    : Example hub module for td-script-hub (menu specs + handlers)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Demonstrates the canonical structure of a "hub module":
#   - Provides module identity metadata (TD_MOD_*)
#   - Declares module-local defaults (override-friendly)
#   - Exposes handlers that implement actions
#   - Publishes menu entries via TD_MOD_MENU_SPECS for td-script-hub to consume
#
# Assumptions:
#   - This is a FRAMEWORK module (hub will source it).
#   - say* and ask exist when handlers are invoked.
#   - The hub owns routing, policies, and rendering decisions.
#
# Contract:
#   - Sourcing this module must be side-effect free (no work performed on load).
#   - Only handlers may perform effects (I/O, mutations, prompts, execution).
#   - Menu specs are declarative; collisions/ordering are hub policy.
# =================================================================================
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

        # Refuse to execute (module/library only)
        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            echo "This is a library/module; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
            exit 2
        }

        # Load guard (safe under set -u)
        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    __td_lib_guard
    unset -f __td_lib_guard

# --- Module identity -------------------------------------------------------------
    # These are read by the hub to build titles, headers, module lists, etc.
    #
    # Contract:
    #   - TD_MOD_ID must be unique across all loaded modules.
    #   - IDs should be grep-friendly (lowercase, no spaces, stable).
    #
    # Required:
    #   TD_MOD_ID, TD_MOD_TITLE
    #
    # Optional:
    #   TD_MOD_DESC
    TD_MOD_ID="example"
    TD_MOD_TITLE="Example module"
    TD_MOD_DESC="Shows the recommended structure for a hub module."

# --- Module defaults -------------------------------------------------------------
    # Module-local defaults (override-friendly).
    #
    # Rule:
    #   Use : "${VAR:=default}" so values can be overridden by:
    #     - config
    #     - state restore
    #     - environment
    #     - hub policy
    #
    # Avoid:
    #   VAR="default"  (would clobber overrides)
    : "${EXAMPLE_OPTION:=Yes}"

# --- Handlers --------------------------------------------------------------------
    # Handlers are the ONLY place where effects may happen.
    #
    # Handler contract:
    #   - Must return 0 on success, non-zero on failure.
    #   - Must be safe to call multiple times.
    #   - May use say*/ask/td_print_*; must not assume full-screen UI.
    #
    # Naming:
    #   td_mod_<id>_<action>  (stable, explicit, grep-friendly)

    td_mod_example_do_thing() {
        saystart "Example action"
        sayinfo  "TD_MOD_ID : $TD_MOD_ID"
        sayinfo  "Option    : ${EXAMPLE_OPTION}"
        sayend   "Done."
        return 0
    }

    td_mod_example_configure() {
        saystart "Configure example module"

        ask \
            --label "Enable example option?" \
            --var EXAMPLE_OPTION \
            --default "${EXAMPLE_OPTION}" \
            --colorize both

        sayok "Saved: EXAMPLE_OPTION=${EXAMPLE_OPTION}"
        sayend "Configuration complete."
        return 0
    }

# --- Menu specs ------------------------------------------------------------------
    # Menu specifications consumed by td-script-hub.
    #
    # Each entry is a single pipe-delimited record:
    #   "key|group|label|handler|flags|wait"
    #
    # Fields:
    #   key     : explicit hotkey ("1", "A", "V") or empty "" for auto-assign
    #   group   : group name for menu organization
    #   label   : label shown in the menu
    #   handler : function name to call when selected
    #   flags   : reserved (hub-defined behavior; may be empty)
    #   wait    : seconds to show an auto-continue dialog after running (0 = none)
    #
    # Notes:
    #   - Collisions and auto-key behavior are hub policy.
    #   - Menu specs should be declarative only; do not embed execution logic here.
    #
    # Important:
    #   - TD_MOD_MENU_SPECS should be an indexed array.
    #   - Use declare -a so intent is explicit and predictable.
    declare -a TD_MOD_MENU_SPECS=(
        # --- Examples -------------------------------------------------------------
        "|Examples|Example: run action (2s)|td_mod_example_do_thing||2"
        "|Examples|Example: configure module (6s)|td_mod_example_configure||6"
        "10|Examples|Example: configure module (0)|td_mod_example_configure||0"
        "2|Examples|Example: configure module (15s)|td_mod_example_configure||15"

        # --- Other Examples -------------------------------------------------------
        "|Other Examples|Example: run action 2 (2s)|td_mod_example_do_thing||2"
        "|Other Examples|Example: configure module 2 (2s)|td_mod_example_configure||2"
        "10|Other Examples|Example: configure module (2s)|td_mod_example_configure||2"
        "2|Other Examples|Example: configure module (4s)|td_mod_example_configure||4"
    )

# --- Public API ------------------------------------------------------------------
    # Optional exports for hub or other modules.
    #
    # Prefer:
    #   - small query helpers (no effects)
    #   - state accessors
    #
    # Avoid:
    #   - auto-running behavior
    #   - heavy logic that belongs in handlers
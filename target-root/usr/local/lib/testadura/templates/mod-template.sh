# ==================================================================================
# Testadura Consultancy — Console Module Template
# ----------------------------------------------------------------------------------
# Module     : console-mod-sample.sh
# Purpose    : Canonical template for sgnd-console modules
#
# Description:
#   Provides the standard structure for modules that extend sgnd-console with:
#     - one or more menu groups
#     - one or more registered menu actions
#     - optional internal helper functions
#
#   Console modules are source-only plugin libraries. Their only intended
#   load-time side effect is self-registration with sgnd-console.
#
# Design principles:
#   - Modules define functions first, then register themselves explicitly
#   - Registration is data-driven through sgnd_console_register_group/item
#   - Keep module logic local and menu-facing
#   - Avoid framework-wide policy decisions inside modules
#
# Role in framework:
#   - Extends sgnd-console with domain-specific actions and menu entries
#   - Acts as a lightweight plugin layer on top of the console host
#   - May depend on framework and sgnd-console primitives already being loaded
#
# Assumptions:
#   - Loaded by sgnd-console after framework bootstrap is complete
#   - sgnd_console_register_group and sgnd_console_register_item are available
#   - Framework helpers such as say* and td_print_* may be used
#
# Non-goals:
#   - Standalone execution
#   - Bootstrap, path resolution, or framework initialization
#   - Full-screen UI behavior outside the sgnd-console host
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


# --- Internal helpers ------------------------------------------------------------
    # Naming:
    #   - Prefix internal-only helpers with "__"
    #   - Keep internal helpers module-local and menu-focused
    #
    # Example:
    #   __sample_format_status() { :; }

# --- Public module actions -------------------------------------------------------
    # Naming:
    #   - Use clear action-style names for functions registered as menu handlers
    #   - Registered handlers do not need a td_ prefix; they belong to the module surface
    #
    # Example:
    #   sample_show_message() { :; }
    #   sys_status() { :; }

# --- Console registration --------------------------------------------------------
    # Allowed side effect:
    #   - On source, the module may register groups and items with sgnd-console.
    #
    # Example:
    #   sgnd_console_register_group "system" "System tools" "General system operations"
    #
    #   sgnd_console_register_item \
    #       "sys-status" \
    #       "system" \
    #       "System status" \
    #       "sys_status" \
    #       "Show system status" \
    #       0 \
    #       15



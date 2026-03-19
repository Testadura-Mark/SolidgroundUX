# ==================================================================================
# Testadura Consultancy — Library Template
# ----------------------------------------------------------------------------------
# Module     : lib-template.sh
# Purpose    : Canonical template for Testadura Bash libraries
#
# Description:
#   Provides the standard structure for framework libraries, including:
#     - canonical script header sections
#     - library-only execution guard (must be sourced, never executed)
#     - idempotent load guard
#     - naming conventions for internal and public functions
#     - reference function header layout
#
# Design principles:
#   - Libraries define functions and constants only
#   - No auto-execution (must always be sourced)
#   - Keep behavior deterministic and side-effect aware
#   - Separate mechanism (library) from policy (caller)
#
# Role in framework:
#   - Base template for all SolidGroundUX library modules
#   - Defines structure, conventions, and documentation standards
#
# Non-goals:
#   - Executable scripts (use exe-template.sh)
#   - Application logic
#   - Framework bootstrap or path resolution
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
    #   - Prefix internal-only helpers with "__" (never "td_")
    # Example:
    #   __<libname>_helper() { :; }
# --- Public API ------------------------------------------------------------------
    # Naming:
    #   - Prefix public functions with "td_" (never "__")
    # Example:
    #   td_<libname>_do_something() { :; }

    # Default function header
        # <function_name>
        # Purpose:
        #   <one-line description>
        #
        # Behavior:
        #   <optional: key behavior summary when non-trivial>
        #
        # Arguments:
        #   $1  ...
        #   $2  ...
        #
        # Inputs (globals):
        #   FOO, BAR   (only if used)
        #
        # Outputs (globals):
        #   BAZ        (only if set)
        #
        # Output:
        #   Writes ... to stdout/stderr (only if applicable)
        #
        # Side effects:
        #   Creates/updates/deletes files, sets permissions, etc.
        #
        # Returns:
        #   0 on success, non-zero on failure
        #
        # Usage:
        #   <function_name> arg1 arg2
        #
        # Examples:
        #   <function_name> "value"
        #
        # Notes:
        #   - Edge cases / gotchas



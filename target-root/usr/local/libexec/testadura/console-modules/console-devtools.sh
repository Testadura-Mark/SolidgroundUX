# =================================================================================
# Testadura Consultancy — console-mod-sample.sh
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
#   - No auto-execution (must be sourced), upon sourcing the module registers
#     itself with sgnd-console
#   - Avoids changing shell options beyond strict-unset/pipefail (set -u -o pipefail).
#     (No set -e; no shopt.)
#   - No path detection or root resolution (bootstrap owns path resolution).
#   - No framework policy decisions. May emit say* diagnostics and use td_print_* helpers for display.
#   - Safe to source multiple times (idempotent load guard).
#
# Non-goals:
#   - Executable scripts (use /bin tools or applets for entry points)
#   - User interaction unless explicitly part of a UI module
#   - Policy decisions (libraries provide mechanisms; callers decide policy)
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
    __exe_createworkspace()
    {
            __sgnd_run_script "create-workspace.sh" --showenv
    }
    
        __exe_deployworkspace()
    {
            __sgnd_run_script "deploy-workspace.sh" --showenv
    }

        __exe_preparerelease()
    {
            __sgnd_run_script "prepare-release.sh" --showenv
    }
# --- Public API ------------------------------------------------------------------
#    sample_show_message() {
#        sayinfo "Sample module action executed"
#    }

# sys_status() {
#     sayinfo "System status"
# }

# --- Console registration --------------------------------------------------------
# Allowed side-effect: module self-registers with sgnd-console

    sgnd_console_register_group "devtools" "Developer tools" "Tool scripts to create, deploy and release VSC-workspaces" 0 1 900

    sgnd_console_register_item "createws" "devtools" "Create workspace" "__exe_createworkspace" "Create a template workspace with target-root structure" 0 15 
    sgnd_console_register_item "deployws" "devtools" "Deploy workspace" "__exe_deployworkspace" "Deploy target-root structure from workspace to root" 0 15
    sgnd_console_register_item "preprel" "devtools" "Prepare release" "__exe_preparerelease" "Create a tar-file from workspace with checksums and manifests" 0 15

# sgnd_console_register_item "other-sample-message" "system" "Another Sample message" "sample_show_message" "Show a simple demo message" 0 7
# sgnd_console_register_item "sample-message" "" "Sample message" "sample_show_message" "Show a simple demo message" 0 7



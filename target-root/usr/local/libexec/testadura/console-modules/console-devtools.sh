# ==================================================================================
# Testadura Consultancy — Developer Tools Console Module
# ----------------------------------------------------------------------------------
# Module     : console-devtools.sh
# Purpose    : sgnd-console module exposing developer tooling actions
#
# Description:
#   Provides a console module that registers developer-oriented actions in
#   sgnd-console, allowing common tooling scripts to be launched from the
#   interactive console host.
#
#   The module currently exposes actions for:
#     - creating a new workspace
#     - deploying a workspace
#     - preparing a release archive
#
# Design principles:
#   - Console modules are source-only plugin libraries
#   - Functions are defined first, then registered explicitly
#   - Registration is the only intended load-time side effect
#   - Module actions delegate execution to the shared sgnd-console runtime
#
# Role in framework:
#   - Extends sgnd-console with developer workflow actions
#   - Acts as a lightweight plugin layer on top of the console host
#   - Uses __sgnd_run_script to execute related tooling scripts consistently
#
# Assumptions:
#   - Loaded by sgnd-console after framework bootstrap is complete
#   - sgnd_console_register_group and sgnd_console_register_item are available
#   - __sgnd_run_script is available in the host environment
#
# Non-goals:
#   - Standalone execution
#   - Framework bootstrap or path resolution
#   - Direct implementation of workspace/deploy/release logic
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
        #   __td_lib_guard
        #   unset -f __td_lib_guard
        #
        # Notes:
        #   - Guard variable is derived dynamically from the filename.
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
    # __exe_createworkspace
        # Purpose:
        #   Launch the create-workspace developer tool through the sgnd-console runtime.
        #
        # Behavior:
        #   - Delegates execution to __sgnd_run_script.
        #   - Invokes create-workspace.sh
        #
        # Returns:
        #   Exit code of the executed script.
        #
        # Usage:
        #   __exe_createworkspace
        #
        # Examples:
        #   __exe_createworkspace    
    __exe_createworkspace()
    {
            __sgnd_run_script "create-workspace.sh"
    }
    
    # __exe_deployworkspace
        # Purpose:
        #   Launch the deploy-workspace developer tool through the sgnd-console runtime.
        #
        # Behavior:
        #   - Delegates execution to __sgnd_run_script.
        #   - Invokes deploy-workspace.sh 
        # Returns:
        #   Exit code of the executed script.
        #
        # Usage:
        #   __exe_deployworkspace
        #
        # Examples:
        #   __exe_deployworkspace
    __exe_deployworkspace()
    {
            __sgnd_run_script "deploy-workspace.sh" 
    }

    # __exe_preparerelease
        # Purpose:
        #   Launch the prepare-release developer tool through the sgnd-console runtime.
        #
        # Behavior:
        #   - Delegates execution to __sgnd_run_script.
        #   - Invokes prepare-release.sh 
        #
        # Returns:
        #   Exit code of the executed script.
        #
        # Usage:
        #   __exe_preparerelease
        #
        # Examples:
        #   __exe_preparerelease
    __exe_preparerelease()
    {
            __sgnd_run_script "prepare-release.sh" 
    }
# --- Public API ------------------------------------------------------------------
#    sample_show_message() {
#        sayinfo "Sample module action executed"
#    }

# sys_status() {
#     sayinfo "System status"
# }

# --- Console registration --------------------------------------------------------
    # Allowed side effect:
    #   - On source, the module registers its groups and menu items with sgnd-console.

    sgnd_console_register_group "devtools" "Developer tools" "Tool scripts to create, deploy and release VSC-workspaces" 0 1 900

    sgnd_console_register_item "createws" "devtools" "Create workspace" "__exe_createworkspace" "Create a template workspace with target-root structure" 0 15 
    sgnd_console_register_item "deployws" "devtools" "Deploy workspace" "__exe_deployworkspace" "Deploy target-root structure from workspace to root" 0 15
    sgnd_console_register_item "preprel" "devtools" "Prepare release" "__exe_preparerelease" "Create a tar-file from workspace with checksums and manifests" 0 15



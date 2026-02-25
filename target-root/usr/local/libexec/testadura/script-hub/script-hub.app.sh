#!/usr/bin/env bash
# ==================================================================================
# Testadura Applet Definition
# ----------------------------------------------------------------------------------
# This file is sourced by script-hub.sh when --app/--applet is used.
# Keep it declarative: variable assignments only (no side effects).
# ==================================================================================
set -uo pipefail
# --- Identity ---------------------------------------------------------------
TD_SCRIPT_TITLE="Script hub"
TD_SCRIPT_DESC=""

# Stable hub identifier (used for defaults and paths)
HUB_ID=script-hub

# --- Module directory -------------------------------------------------------
MOD_DIR=/home/sysadmin/dev/solidgroundux/target-root/usr/local/lib/testadura/common/tools/hub/script-hub

# --- Optional defaults ------------------------------------------------------
# Example:
# SOME_FLAG_DEFAULT=1

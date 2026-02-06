# =================================================================================
# Testadura Consultancy — td-globals.sh
# ---------------------------------------------------------------------------------
# Purpose    : Framework-wide global variable definitions and defaults
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Declares the set of global variables used by the Testadura framework, including:
#   - Canonical variable names
#   - Default values
#   - Groupings of globals (e.g., system vs user variables)
#
#   This file defines names and defaults only. It establishes the *shape* of the
#   framework environment but does not interpret, load, or apply configuration.
#
# Assumptions:
#   - Sourced early during bootstrap.
#   - May be referenced by multiple framework layers (ui, say, ask, args).
#
# Rules / Contract:
#   - No side effects beyond variable definition.
#   - No runtime detection, validation, or mutation.
#   - No UI, logging, or I/O of any kind.
#   - No policy decisions (what values mean is handled elsewhere).
#
# Non-goals:
#   - Loading or parsing configuration files
#   - Applying configuration precedence or overrides
#   - Runtime environment detection
#   - UI output, logging, or user interaction
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_GLOBALS_LOADED:-}" ]] && return 0
    TD_GLOBALS_LOADED=1

# --- Framework info ---------------------------------------------------------------
    TD_PRODUCT="SolidgroundUX"
    TD_VERSION="1.0-R2-beta"
    TD_VERSION_DATE="2026-01-08"
    TD_COMPANY="Testadura Consultancy"
    TD_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework metadata ------------------------------------------------------
    TD_FRAMEWORK_GLOBALS=(    
        "system|TD_SYSCFG_DIR|Framework-wide system configuration directory|"
        "system|TD_SYSCFG_FILE|Framework-wide system configuration file|"

        "system|TD_LOGFILE_ENABLED|Enable or disable logfile output|"
        "system,user|TD_CONSOLE_MSGTYPES|Console message types to display|"
        "system|TD_LOG_PATH|Primary log file or directory path|"
        "system,user|TD_ALTLOG_PATH|Alternate log path override|"
        "system|TD_LOG_MAX_BYTES|Maximum log file size before rotation|"
        "system|TD_LOG_KEEP|Number of rotated log files to retain|"
        "system|TD_LOG_COMPRESS|Compress rotated log files|"

        "user|TD_STATE_DIR|User-specific persistent state directory|"
        "user|TD_USRCFG_DIR|User-specific configuration directory|"
        "user|TD_USRCFG_FILE|User-specific configuration file|"

        "system,user|TD_UI_STYLE|Default UI style file (basename or path)|"
        "system,user|TD_UI_PALETTE|Default UI palette file (basename or path)|"

        "user|SAY_COLORIZE_DEFAULT|Default colorized console output setting|"
        "user|SAY_DATE_DEFAULT|Default timestamp visibility|"
        "user|SAY_SHOW_DEFAULT|Default console message visibility|"
        "user|SAY_DATE_FORMAT|Default date/time format for console output|"
    )

    TD_CORE_LIBS=(
        args.sh
        cfg.sh
        core.sh
        ui.sh
        ui-say.sh
        ui-ask.sh
        ui-dlg.sh
    )
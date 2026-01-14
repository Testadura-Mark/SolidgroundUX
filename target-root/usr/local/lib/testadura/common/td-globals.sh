# --- Framwork info ---------------------------------------------------------------
    TD_PRODUCT="SolidgroundUX"
    TD_VERSION="1.1-beta"
    TD_VERSION_DATE="2026-01-08"
    TD_COMPANY="Testadura Consultancy"
    TD_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framwork settings (overridden by scripts when sourced) ----------------------  

    TD_STATE_DIR="${TD_STATE_DIR:-"$TD_APPLICATION_ROOT/var/testadura"}" # State directory path
    
    TD_LOGFILE_ENABLED="${TD_LOGFILE_ENABLED:-0}"  # Enable logging to file (1=yes,0=no)
    TD_CONSOLE_MSGTYPES="${TD_CONSOLE_MSGTYPES:-STRT|WARN|FAIL|END}"  # Enable logging to file (1=yes,0=no)
    TD_LOG_PATH="${TD_LOG_PATH:-$TD_FRAMEWORK_ROOT/var/log/testadura/solidgroundux.log}" # Log file path
    TD_ALTLOG_PATH="${TD_ALTLOG_PATH:-$HOME/.state/testadura/solidgroundux.log}" # Alternate Log file path
    TD_LOG_MAX_BYTES="${TD_LOG_MAX_BYTES:-$((25 * 1024 * 1024))}" # 25 MiB
    TD_LOG_KEEP="${TD_LOG_KEEP:-20}" # keep N rotated logs
    TD_LOG_COMPRESS="${TD_LOG_COMPRESS:-1}" # gzip rotated logs (1/0)

# -- SAY TD_GLOBALS
    SAY_DATE_DEFAULT="${SAY_DATE_DEFAULT:-0}" # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="${SAY_SHOW_DEFAULT:-label}" # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT="${SAY_COLORIZE_DEFAULT:-label}" # none|label|msg|both|all|date
    #SAY_WRITELOG_DEFAULT="${SAY_WRITELOG_DEFAULT:-0}" # 0 = no log, 1 = log
    SAY_DATE_FORMAT="${SAY_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}" # date format for --date

    reroot-framework()
    {
        TD_COMMON_LIB="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common"
        TD_STATE_DIR="$TD_APPLICATION_ROOT/var/testadura" # State directory path
        TD_CFG_DIR="$TD_APPLICATION_ROOT/etc/testadura" # Config directory path
        TD_LOG_PATH="$TD_FRAMEWORK_ROOT/var/log/testadura/solidgroundux.log" # Log file path
    }
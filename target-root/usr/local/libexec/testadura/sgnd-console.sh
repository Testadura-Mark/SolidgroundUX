#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — sgnd-console
# ----------------------------------------------------------------------------------
# Purpose : Canonical executable template for Testadura scripts
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in via TD_ARGS_SPEC and TD_SCRIPT_GLOBALS.
# ------------------------------------------------------------------------------
# How to use this template (Edit Map)
# 1) Set identity fields in "Script metadata (identity)" (DESC, VERSION, etc.)
# 2) Add required libraries to TD_USING (optional)
# 3) Define TD_ARGS_SPEC if your script has CLI options (optional)
# 4) Add TD_SCRIPT_EXAMPLES for --help (recommended)
# 5) List intentional global variables in TD_SCRIPT_GLOBALS (recommended)
# 6) Implement your logic inside main() under "-- Main script logic"
#
# IMPORTANT:
#   - Never read prompts from stdin in executables. Use /dev/tty (or ask/td_dlg_*).
#   - Never print UI to stdout if stdout may be piped; prefer say*/td_print_* which can route.
#   - Do NOT modify the bootstrap loader unless you are developing the framework.
# ==================================================================================
set -uo pipefail

# --- Bootstrap --------------------------------------------------------------------
    # __framework_locator
        # Resolve, create, and load the SolidGroundUX bootstrap configuration.
        #
        # Purpose:
        #   Establish the two root variables that define the framework layout:
        #
        #       TD_FRAMEWORK_ROOT
        #       TD_APPLICATION_ROOT
        #
        #   Once these are known, all other framework paths can be derived from
        #   them by td-bootstrap.sh and the common libraries.
        #
        # Search order:
        #   1. User configuration
        #        ~/.config/testadura/solidgroundux.cfg
        #
        #   2. System configuration
        #        /etc/testadura/solidgroundux.cfg
        #
        #   User configuration overrides system configuration.
        #
        # Sudo behavior:
        #   When running under sudo, the lookup still prefers the invoking user's
        #   home configuration (derived from SUDO_USER) rather than /root, so a
        #   developer's user override remains active under elevation.
        #
        # Creation behavior:
        #   If no configuration file exists:
        #
        #     - non-root user → create in ~/.config/testadura
        #     - root user     → create in /etc/testadura
        #
        #   When created interactively, prompt for:
        #
        #       TD_FRAMEWORK_ROOT     [default: /]
        #       TD_APPLICATION_ROOT   [default: TD_FRAMEWORK_ROOT]
        #
        #   In non-interactive mode, defaults are used automatically.
        #
        # Result:
        #   Sources the selected configuration file and ensures:
        #
        #       TD_FRAMEWORK_ROOT defaults to /
        #       TD_APPLICATION_ROOT defaults to TD_FRAMEWORK_ROOT
        #
        # Returns:
        #   0   success
        #   126 configuration unreadable / invalid
        #   127 configuration directory or file could not be created
    __framework_locator (){
        local cfg_home="$HOME"

        if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            cfg_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        fi

        local cfg_user="$cfg_home/.config/testadura/solidgroundux.cfg"
        local cfg_sys="/etc/testadura/solidgroundux.cfg"
        local cfg=""
        local fw_root="/"
        local app_root="$fw_root"
        local reply

        # Determine existing configuration
        if [[ -r "$cfg_user" ]]; then
            cfg="$cfg_user"

        elif [[ -r "$cfg_sys" ]]; then
            cfg="$cfg_sys"

        else
            # Determine creation location
            if [[ $EUID -eq 0 ]]; then
                cfg="$cfg_sys"
            else
                cfg="$cfg_user"
            fi

            # Interactive prompts (first run only)
            if [[ -t 0 && -t 1 ]]; then

                sayinfo "SolidGroundUX bootstrap configuration"
                sayinfo "No configuration file found."
                sayinfo "Creating: $cfg"

                printf "TD_FRAMEWORK_ROOT [/] : " > /dev/tty
                read -r reply < /dev/tty
                fw_root="${reply:-/}"

                printf "TD_APPLICATION_ROOT [/] : " > /dev/tty
                read -r reply < /dev/tty
                app_root="${reply:-$fw_root}"
            fi

            # Validate paths (must be absolute)
            case "$fw_root" in
                /*) ;;
                *) sayfail "ERR: TD_FRAMEWORK_ROOT must be an absolute path"; return 126 ;;
            esac

            case "$app_root" in
                /*) ;;
                *) sayfail "ERR: TD_APPLICATION_ROOT must be an absolute path"; return 126 ;;
            esac

            # Create configuration file
            mkdir -p "$(dirname "$cfg")" || return 127

            # write cfg file 
            {
                printf '%s\n' "# SolidGroundUX bootstrap configuration"
                printf '%s\n' "# Auto-generated on first run"
                printf '\n'
                printf 'TD_FRAMEWORK_ROOT=%q\n' "$fw_root"
                printf 'TD_APPLICATION_ROOT=%q\n' "$app_root"
            } > "$cfg" || return 127

            saydebug "Created bootstrap cfg: $cfg"
        fi

        # Load configuration
        if [[ -r "$cfg" ]]; then
            # shellcheck source=/dev/null
            source "$cfg"

            : "${TD_FRAMEWORK_ROOT:=/}"
            : "${TD_APPLICATION_ROOT:=$TD_FRAMEWORK_ROOT}"
        else
            sayfail "Cannot read bootstrap cfg: $cfg"
            return 126
        fi

        saydebug "Bootstrap cfg loaded: $cfg, TD_FRAMEWORK_ROOT=$TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT=$TD_APPLICATION_ROOT"

    }

    # __load_bootstrapper
        # Resolve and source the framework bootstrap library.
        #
        # Purpose:
        #   Load the canonical td-bootstrap.sh entry library after the framework
        #   roots have been established by __framework_locator.
        #
        # Behavior:
        #   1. Calls __framework_locator to load or create the bootstrap cfg.
        #   2. Derives the bootstrap path from TD_FRAMEWORK_ROOT.
        #   3. Verifies that td-bootstrap.sh is readable.
        #   4. Sources td-bootstrap.sh into the current shell.
        #
        # Path rule:
        #   If TD_FRAMEWORK_ROOT is "/":
        #
        #       /usr/local/lib/testadura/common/td-bootstrap.sh
        #
        #   Otherwise:
        #
        #       $TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common/td-bootstrap.sh
        #
        # Notes:
        #   - This function performs executable-level startup resolution.
        #   - td-bootstrap.sh is expected to derive secondary paths from the
        #     already-established root variables, not rediscover them.
        #
        # Returns:
        #   0   success
        #   126 bootstrap library unreadable
    __load_bootstrapper(){
        local bootstrap=""

        __framework_locator || return $?

        if [[ "$TD_FRAMEWORK_ROOT" == "/" ]]; then
            bootstrap="/usr/local/lib/testadura/common/td-bootstrap.sh"
        else
            bootstrap="${TD_FRAMEWORK_ROOT%/}/usr/local/lib/testadura/common/td-bootstrap.sh"
        fi

        [[ -r "$bootstrap" ]] || {
            printf "FATAL: Cannot read bootstrap: %s\n" "$bootstrap" >&2
            return 126
        }
        
        saydebug "Loading $bootstrap"
            
        # shellcheck source=/dev/null
        source "$bootstrap"
    }

    # Minimal colors
    MSG_CLR_INFO=$'\e[38;5;250m'
    MSG_CLR_STRT=$'\e[38;5;82m'
    MSG_CLR_OK=$'\e[38;5;82m'
    MSG_CLR_WARN=$'\e[1;38;5;208m'
    MSG_CLR_FAIL=$'\e[38;5;196m'
    MSG_CLR_CNCL=$'\e[0;33m'
    MSG_CLR_END=$'\e[38;5;82m'
    MSG_CLR_EMPTY=$'\e[2;38;5;250m'
    MSG_CLR_DEBUG=$'\e[1;35m'

    TUI_COMMIT=$'\e[2;37m'
    RESET=$'\e[0m'

    # Minimal UI
    saystart()   { printf '%sSTART%s\t%s\n' "${MSG_CLR_STRT-}" "${RESET-}" "$*" >&2; }
    sayinfo()    { 
        if (( ${FLAG_VERBOSE:-0} )); then
            printf '%sINFO%s \t%s\n' "${MSG_CLR_INFO-}" "${RESET-}" "$*" >&2; 
        fi
    }
    sayok()      { printf '%sOK%s   \t%s\n' "${MSG_CLR_OK-}"   "${RESET-}" "$*" >&2; }
    saywarning() { printf '%sWARN%s \t%s\n' "${MSG_CLR_WARN-}" "${RESET-}" "$*" >&2; }
    sayfail()    { printf '%sFAIL%s \t%s\n' "${MSG_CLR_FAIL-}" "${RESET-}" "$*" >&2; }
    saydebug() {
        if (( ${FLAG_DEBUG:-0} )); then
            printf '%sDEBUG%s \t%s\n' "${MSG_CLR_DEBUG-}" "${RESET-}" "$*" >&2;
        fi
    }
    saycancel() { printf '%sCANCEL%s\t%s\n' "${MSG_CLR_CNCL-}" "${RESET-}" "$*" >&2; }
    sayend() { printf '%sEND%s   \t%s\n' "${MSG_CLR_END-}" "${RESET-}" "$*" >&2; }

# --- Script metadata (identity) ---------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Solidground Console"
    : "${TD_SCRIPT_DESC:=Interactive console module host}"
    : "${TD_SCRIPT_VERSION:=1.0}"
    : "${TD_SCRIPT_BUILD:=20260312}"
    : "${TD_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${TD_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${TD_SCRIPT_COPYRIGHT:=© 2025 Mark Fieten — Testadura Consultancy}"
    : "${TD_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.0}"

# --- Script metadata (framework integration) --------------------------------------
    # TD_USING
        # Libraries to source from TD_COMMON_LIB.
        # These are loaded automatically by td_bootstrap AFTER core libraries.
        #
        # Example:
        #   TD_USING=( net.sh fs.sh )
        #
        # Leave empty if no extra libs are needed.
    TD_USING=(
        td-datatable.sh
    )

    # TD_ARGS_SPEC 
        # Optional: script-specific arguments
        # --- Example: Arguments
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        #   var     = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    TD_ARGS_SPEC=(
        "appcfg||value|VAL_APPCFG|Path to console app config file|"
    )

    # TD_SCRIPT_EXAMPLES
        # Optional: examples for --help output.
        # Each entry is a string that will be printed verbatim.
        #
        # Example:
        #   TD_SCRIPT_EXAMPLES=(
        #       "Example usage:"
        #       "  script.sh --verbose --mode fast"
        #       "  script.sh -v -m slow"
        #   )
        #
        # Leave empty if no examples are needed.
    TD_SCRIPT_EXAMPLES=(
        "Examples:"
        "  sgnd-console.sh"
        "  sgnd-console.sh --appcfg ./my-console.cfg"
    ) 

    # TD_SCRIPT_GLOBALS
        # Explicit declaration of global variables intentionally used by this script.
        #
        # Purpose:
        #   - Declares which globals are part of the script’s public/config contract.
        #   - Enables optional configuration loading when non-empty.
        #
        # Behavior:
        #   - If this array is non-empty, td_bootstrap enables config integration.
        #   - Variables listed here may be populated from configuration files.
        #   - Unlisted globals will NOT be auto-populated.
        #
        # Use this to:
        #   - Document intentional globals
        #   - Prevent accidental namespace leakage
        #   - Make configuration behavior explicit and predictable
        #
        # Only list:
        #   - Variables that must be globally accessible
        #   - Variables that may be defined in config files
        #
        # Leave empty if:
        #   - The script does not use configuration-driven globals
    TD_SCRIPT_GLOBALS=(
    )

    # TD_STATE_VARIABLES
        # List of variables participating in persistent state.
        #
        # Purpose:
        #   - Declares which variables should be saved/restored when state is enabled.
        #
        # Behavior:
        #   - Only used when td_bootstrap is invoked with --state.
        #   - Variables listed here are serialized on exit (if TD_STATE_SAVE=1).
        #   - On startup, previously saved values are restored before main logic runs.
        #
        # Contract:
        #   - Variables must be simple scalars (no arrays/associatives unless explicitly supported).
        #   - Script remains fully functional when state is disabled.
        #
        # Leave empty if:
        #   - The script does not use persistent state.
    TD_STATE_VARIABLES=(
    )

    # TD_ON_EXIT_HANDLERS
        # List of functions to be invoked on script termination.
        #
        # Purpose:
        #   - Allows scripts to register cleanup or finalization hooks.
        #
        # Behavior:
        #   - Functions listed here are executed during framework exit handling.
        #   - Execution order follows array order.
        #   - Handlers run regardless of normal exit or controlled termination.
        #
        # Contract:
        #   - Functions must exist before exit occurs.
        #   - Handlers must not call exit directly.
        #   - Handlers should be idempotent (safe if executed once).
        #
        # Typical uses:
        #   - Cleanup temporary files
        #   - Persist additional state
        #   - Release locks
        #
        # Leave empty if:
        #   - No custom exit behavior is required.
    TD_ON_EXIT_HANDLERS=(
    )
    
    # State persistence is opt-in.
        # Scripts that want persistent state must:
        #   1) set TD_STATE_SAVE=1
        #   2) call td_bootstrap --state
    TD_STATE_SAVE=0

# --- Local scripts and definitions ------------------------------------------------d
 # -- Console state
    SGND_GROUP_SCHEMA="key|label|desc|source|builtin"
    declare -ag SGND_GROUP_ROWS=()

    SGND_ITEM_SCHEMA="key|group|label|handler|desc|source|builtin|waitsecs"
    declare -ag SGND_ITEM_ROWS=()

    SGND_MODULE_SCHEMA="id|name|desc|source"
    declare -ag SGND_MODULE_ROWS=()

    SGND_CONSOLE_TITLE="Solidground Console"
    SGND_CONSOLE_DESC="Interactive scalable console module host"
    SGND_CONSOLE_MODULE_DIR=""
    SGND_CURRENT_MODULE=""
    SGND_LAST_WAITSECS=15

    SGND_CLEAR_ONRENDER=1

 # -- Module loading and registration 

    __sgnd_console_register_builtin_items() {
        SGND_GROUP_RUNTIME="runtime"
        SGND_GROUP_SESSION="session"

        sgnd_console_register_group "$SGND_GROUP_RUNTIME" "Runtime toggles" "" 1
        sgnd_console_register_group "$SGND_GROUP_SESSION" "Session" "" 1

        sgnd_console_register_item "B" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_debug)" "__sgnd_console_toggle_debug" "Toggle debug output" 1 0
        sgnd_console_register_item "D" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_dryrun)" "__sgnd_console_toggle_dryrun" "Toggle dry-run mode" 1 0
        sgnd_console_register_item "L" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_logfile)" "__sgnd_console_toggle_logfile" "Toggle logfile output" 1 0
        sgnd_console_register_item "V" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_verbose)" "__sgnd_console_toggle_verbose" "Toggle verbose output" 1 0

        sgnd_console_register_item "C" "$SGND_GROUP_SESSION" "$(__sgnd_console_label_clearonrender)" "__sgnd_console_toggle_clearonrender" "Toggle clear screen before rendering" 1 0
        sgnd_console_register_item "R" "$SGND_GROUP_SESSION" "Redraw menu" "__sgnd_console_redraw" "Refresh console display" 1 0
        sgnd_console_register_item "Q" "$SGND_GROUP_SESSION" "Quit" "__sgnd_console_quit" "Exit console" 1 0
    }

    __sgnd_console_register_fallback_group() {
        local key="${1:?missing group key}"
        local label="Other"
        local module_id=""
        local module_name=""
        local i
        local row_count=0

        case "$key" in
            module:*)
                module_id="${key#module:}"
                row_count="$(td_dt_row_count SGND_MODULE_ROWS)"

                for (( i=0; i<row_count; i++ )); do
                    if [[ "$(td_dt_get "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS "$i" id)" == "$module_id" ]]; then
                        module_name="$(td_dt_get "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS "$i" name)"
                        break
                    fi
                done

                if [[ -n "${module_name//[[:space:]]/}" ]]; then
                    label="$module_name"
                else
                    label="$module_id"
                fi
                ;;
        esac

        sgnd_console_register_group "$key" "$label" "" 0
    }

    __sgnd_console_group_exists() {
        local key="${1:?missing group key}"

        td_dt_has_row "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS key "$key"
    }

    __sgnd_console_load_config() {
        local cfg="${VAL_APPCFG-}"
        local cfg_dir

        : "${SGND_CONSOLE_TITLE:=SolidgroundUX Console}"
        : "${SGND_CONSOLE_DESC:=Interactive script host}"
        SGND_CONSOLE_MODULE_DIR="${TD_SCRIPT_DIR}/console-modules"

        if [[ -n "$cfg" ]]; then
            if [[ ! -e "$cfg" ]]; then
                __sgnd_console_create_appcfg "$cfg" || return $?
            fi

            [[ -r "$cfg" ]] || {
                sayfail "Cannot read appcfg: $cfg"
                return 126
            }

            cfg="$(readlink -f -- "$cfg")"
            cfg_dir="$(dirname -- "$cfg")"

            # shellcheck source=/dev/null
            source "$cfg"

            : "${SGND_CONSOLE_TITLE:=${TD_SCRIPT_TITLE}}"
            : "${SGND_CONSOLE_DESC:=${TD_SCRIPT_DESC}}"
            : "${SGND_CONSOLE_MODULE_DIR:=./console-modules}"

            case "$SGND_CONSOLE_MODULE_DIR" in
                /*) ;;
                *) SGND_CONSOLE_MODULE_DIR="${cfg_dir}/${SGND_CONSOLE_MODULE_DIR}" ;;
            esac
        fi

        SGND_CONSOLE_MODULE_DIR="$(readlink -f -- "$SGND_CONSOLE_MODULE_DIR")"

        saydebug "Console title: $SGND_CONSOLE_TITLE"
        saydebug "Console desc : $SGND_CONSOLE_DESC"
        saydebug "Module dir    : $SGND_CONSOLE_MODULE_DIR"
    }

    __sgnd_console_create_appcfg() {
        local cfg="${1:?missing cfg path}"
        local cfg_dir
        local cfg_title="Solidground Console"
        local cfg_desc="Interactive host for console modules"
        local cfg_moddir="./console-modules"

        cfg_dir="$(cd -- "$(dirname -- "$cfg")" && pwd -P 2>/dev/null || dirname -- "$cfg")"

        sayinfo "Console appcfg not found; creating: $cfg"

        if [[ -t 0 && -t 1 ]]; then
            ask --label "Title" \
                --default "$cfg_title" \
                --var cfg_title

            ask --label "Description" \
                --default "$cfg_desc" \
                --var cfg_desc

            ask --label "Module directory" \
                --default "$cfg_moddir" \
                --var cfg_moddir
        fi

        mkdir -p -- "$(dirname -- "$cfg")" || {
            sayfail "Cannot create config directory for: $cfg"
            return 127
        }

        {
            printf "SGND_CONSOLE_TITLE=%q\n" "$cfg_title"
            printf "SGND_CONSOLE_DESC=%q\n" "$cfg_desc"
            printf "SGND_CONSOLE_MODULE_DIR=%q\n" "$cfg_moddir"
        } > "$cfg" || {
            sayfail "Cannot write appcfg: $cfg"
            return 127
        }

        sayok "Created appcfg: $cfg"
    }

    __sgnd_console_load_modules() {
        local mod_dir="${SGND_CONSOLE_MODULE_DIR:?missing module dir}"
        local mod
        local found=0

        [[ -d "$mod_dir" ]] || {
            sayfail "Module directory not found: $mod_dir"
            return 126
        }

        shopt -s nullglob
        for mod in "$mod_dir"/*.sh; do
            found=1
            SGND_CURRENT_MODULE="$(basename "${mod%.sh}")"
            saydebug "Loading module: $mod"

            # shellcheck source=/dev/null
            source "$mod" || {
                sayfail "Failed to load module: $mod"
                unset SGND_CURRENT_MODULE
                shopt -u nullglob
                return 126
            }
        done
        shopt -u nullglob
        unset SGND_CURRENT_MODULE

        (( found )) || saywarning "No modules found in: $mod_dir"
    }

    __sgnd_console_valid_choices_csv() {
        local i
        local out=""
        local visible_num=0
        local builtin=""
        local key=""

        for (( i=0; i<$(td_dt_row_count SGND_ITEM_ROWS); i++ )); do
            [[ -n "$out" ]] && out+=","

            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"

            if (( builtin )); then
                out+="$key"
            else
                visible_num=$((visible_num + 1))
                out+="$visible_num"
            fi
        done

        printf '%s' "$out"
    }

 # -- Render menu
    __sgnd_console_calc_label_width() {
        local i
        local row_count=0
        local builtin="0"
        local display_key=""
        local label=""
        local left_text=""
        local width=0
        local max_width=0
        local visible_num=0

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            else
                visible_num=$((visible_num + 1))
                display_key="$visible_num"
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label)"
            left_text="${display_key}) ${label}"
            width="$(td_visible_length "$left_text")"

            (( width > max_width )) && max_width="$width"
        done

        (( max_width > 35 )) && max_width=35
        printf '%s\n' "$max_width"
    }

    __sgnd_console_render_menu() {
        local gi
        local row_count=0
        local group_key=""
        local builtin="0"

        __sgnd_console_refresh_builtin_labels
        SGND_RENDER_DISPLAY_NUM=0
        SGND_RENDER_LABEL_WIDTH="$(__sgnd_console_calc_label_width)"

        __sgnd_console_render_menu_title

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( gi=0; gi<row_count; gi++ )); do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" builtin)"
            (( builtin )) && continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)"
            __sgnd_console_render_group "$group_key"
        done

        for (( gi=0; gi<row_count; gi++ )); do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" builtin)"
            (( builtin )) || continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)"
            __sgnd_console_render_group "$group_key"
        done
    }

    __sgnd_console_render_menu_title() {
        (( ! SGND_CLEAR_ONRENDER )) || clear

        width="$(td_terminal_width)"

        td_print_sectionheader --border "$DL_H" --maxwidth "$width"
        td_print --pad 4 "$(td_sgr "$WHITE" "" "$FX_BOLD")${SGND_CONSOLE_TITLE}${RESET}"
        td_print --pad 4 "$(td_sgr "$SILVER" "" "$FX_ITALIC")${SGND_CONSOLE_DESC}"
        td_print_sectionheader --border "$LN_H" --maxwidth "$width"
        td_print
    }

    __sgnd_console_render_group() {
        local group_key="${1:?missing group key}"
        local _pad=2
        local _tpad=3

        local gi
        local ii
        local row_count=0
        local label=""
        local desc=""
        local group_label=""
        local found_group=0
        local display_key=""
        local item_group=""
        local builtin="0"

        local left_text=""
        local left_width=0
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local desc_width=0
        local term_width=80
        local gap=3

        local label_clr="${SILVER}"
        local value_clr="$(td_sgr "$SILVER" "" "$FX_ITALIC")"

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( gi=0; gi<row_count; gi++ )); do
            if [[ "$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)" == "$group_key" ]]; then
                group_label="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" label)"
                found_group=1
                break
            fi
        done

        (( found_group )) || return 0

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - _tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        td_print --text "$group_label"
        left_width="$(td_visible_length "$group_label")"
        td_print_sectionheader --border "$LN_H" --maxwidth "$left_width"

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( ii=0; ii<row_count; ii++ )); do
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
            [[ "$item_group" == "$group_key" ]] || continue

            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" key)"
            else
                SGND_RENDER_DISPLAY_NUM=$((SGND_RENDER_DISPLAY_NUM + 1))
                display_key="$SGND_RENDER_DISPLAY_NUM"
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" label)"
            desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" desc)"
            left_text="${display_key}) ${label}"

            if [[ -z "$desc" ]]; then
                printf '%*s%s' "$_tpad" "" "$label_clr"
                td_padded_visible "$left_text" "$left_width_max"
                printf '%s\n' "$RESET"
                continue
            fi

            local first_line=1
            local wrapped_line=""

            while IFS= read -r wrapped_line; do
                if (( first_line )); then
                    printf '%*s%s' "$_tpad" "" "$label_clr"
                    td_padded_visible "$left_text" "$left_width_max"
                    printf '%s%*s%s%s%s\n' \
                        "$RESET" \
                        "$gap" "" \
                        "$value_clr" "$wrapped_line" "$RESET"
                    first_line=0
                else
                    printf '%*s%*s%*s%s%s%s\n' \
                        "$_tpad" "" \
                        "$left_width_max" "" \
                        "$gap" "" \
                        "$value_clr" "$wrapped_line" "$RESET"
                fi
            done < <(td_wrap_words --width "$desc_width" --text "$desc")
        done
        
        td_print
    }
 # -- Menu actions
    __sgnd_console_dispatch() {
        local choice="${1:?missing choice}"
        local handler=""
        local i
        local row_count=0
        local visible_num=0
        local builtin="0"
        local key=""

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            for (( i=0; i<row_count; i++ )); do
                builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
                (( builtin )) && continue

                visible_num=$((visible_num + 1))

                if [[ "$choice" == "$visible_num" ]]; then
                    handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" handler)"
                    SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" waitsecs)"
                    "$handler"
                    return $?
                fi
            done
        fi

        for (( i=0; i<row_count; i++ )); do
            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"

            if [[ "${choice^^}" == "${key^^}" ]]; then
                handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" handler)"
                SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" waitsecs)"
                "$handler"
                return $?
            fi
        done

        saywarning "Invalid selection: $choice"
        return 1
    }
    
    __sgnd_console_toggle_clearonrender() {
        : "${SGND_CLEAR_ONRENDER:=1}"

        if (( SGND_CLEAR_ONRENDER )); then
            SGND_CLEAR_ONRENDER=0
            sayinfo "Clear-on-render disabled"
        else
            SGND_CLEAR_ONRENDER=1
            sayinfo "Clear-on-render enabled"
        fi
    }

    __sgnd_console_toggle_dryrun() {
        : "${FLAG_DRYRUN:=0}"

        if (( FLAG_DRYRUN )); then
            FLAG_DRYRUN=0
            sayinfo "Dry-run disabled"
        else
            FLAG_DRYRUN=1
            sayinfo "Dry-run enabled"
        fi
        
    }

    __sgnd_console_toggle_debug() {
        : "${FLAG_DEBUG:=0}"

        if (( FLAG_DEBUG )); then
            FLAG_DEBUG=0
            sayinfo "Debug disabled"
        else
            FLAG_DEBUG=1
            sayinfo "Debug enabled"
        fi
        td_update_runmode
    }

    __sgnd_console_toggle_verbose() {
        : "${FLAG_VERBOSE:=0}"

        if (( FLAG_VERBOSE )); then
            FLAG_VERBOSE=0
            sayinfo "Verbose disabled"
        else
            FLAG_VERBOSE=1
            sayinfo "Verbose enabled"
        fi
    }

    __sgnd_console_toggle_logfile() {
        : "${TD_LOGFILE_ENABLED:=0}"

        if (( TD_LOGFILE_ENABLED )); then
            TD_LOGFILE_ENABLED=0
            sayinfo "Logfile disabled"
        else
            TD_LOGFILE_ENABLED=1
            sayinfo "Logfile enabled"
        fi
    }

    __sgnd_console_redraw() {
        return 0
    }
    __sgnd_console_quit() {
        return 200
    }

 # -- Display helpers

    __sgnd_console_refresh_builtin_labels() {
        local i
        local row_count=0
        local key=""

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"

            case "${key^^}" in
                B)
                    td_dt_set "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label "$(__sgnd_console_label_debug)"
                    ;;
                C)
                    td_dt_set "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label "$(__sgnd_console_label_clearonrender)"
                    ;;
                D)
                    td_dt_set "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label "$(__sgnd_console_label_dryrun)"
                    ;;
                L)
                    td_dt_set "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label "$(__sgnd_console_label_logfile)"
                    ;;
                V)
                    td_dt_set "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label "$(__sgnd_console_label_verbose)"
                    ;;                
            esac
        done
    }

    __sgnd_console_onoff() {
        local value="${1:-0}"
        local onclr="${2:-$BRIGHT_GREEN}"
        local offclr="${3:-$DARK_SILVER}"

        if (( value )); then
            printf '%sOn%s' "$(td_sgr "$onclr")" "$RESET"
        else
            printf '%sOff%s' "$(td_sgr "$offclr")" "$RESET"
        fi
    }

    __sgnd_console_label_clearonrender() {
        : "${SGND_CLEAR_ONRENDER:=1}"
        printf 'Clear screen: %s' "$(__sgnd_console_onoff "$SGND_CLEAR_ONRENDER")"
    }

    __sgnd_console_label_dryrun() {
        : "${FLAG_DRYRUN:=0}"
        printf 'Dry-run: %s' "$(__sgnd_console_onoff "$FLAG_DRYRUN" "$BRIGHT_GREEN" "$BRIGHT_ORANGE")"
    }

    __sgnd_console_label_debug() {
        : "${FLAG_DEBUG:=0}"
        printf 'Debug: %s' "$(__sgnd_console_onoff "$FLAG_DEBUG")"
    }

    __sgnd_console_label_verbose() {
        : "${FLAG_VERBOSE:=0}"
        printf 'Verbose: %s' "$(__sgnd_console_onoff "$FLAG_VERBOSE")"
    }

    __sgnd_console_label_logfile() {
        : "${TD_LOGFILE_ENABLED:=0}"
        printf 'Logfile: %s' "$(__sgnd_console_onoff "$TD_LOGFILE_ENABLED")"
    }

# --- Main sequence ----------------------------------------------------------------
    __sgnd_console_run() {
        local choice=""
        local valid_choices=""
        local rc=0

        while true; do
            __sgnd_console_render_menu
            valid_choices="$(__sgnd_console_valid_choices_csv)"
            
            td_print_sectionheader --border "$DL_H" --maxwidth "$(td_terminal_width)"
            td_choose \
                --label "Select option" \
                --choices "$valid_choices" \
                --displaychoices 0 \
                --keepasking 1 \
                --var choice

            __sgnd_console_dispatch "$choice"
            rc=$?

            if (( rc == 200 )); then
                sayinfo "Exiting console"
                return 0
            fi
            saydebug "Calling ask_continue with $SGND_LAST_WAITSECS ?"
            if (( ${SGND_LAST_WAITSECS:-0} > 0 )); then
                saydebug "Calling ask_continue with $SGND_LAST_WAITSECS"
                ask_continue "" "${SGND_LAST_WAITSECS}"
            fi
        done
    }

# --- Public API -------------------------------------------------------------------
    sgnd_console_register_item() {
        local key="${1:?missing key}"
        local group="${2:-}"
        local label="${3:?missing label}"
        local handler="${4:?missing handler}"
        local desc="${5:-}"
        local builtin="${6:-0}"
        local waitsecs="${7:-15}"
        local source="${SGND_CURRENT_MODULE:-}"

        if td_dt_has_row "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS key "$key"; then
            sayfail "Duplicate menu key: $key"
            return 1
        fi

        declare -F "$handler" >/dev/null || {
            sayfail "Handler not defined for menu key '$key': $handler"
            return 1
        }

        if [[ -z "$group" ]]; then
            group="module:${SGND_CURRENT_MODULE:-default}"
        fi

        if ! __sgnd_console_group_exists "$group"; then
            __sgnd_console_register_fallback_group "$group"
        fi

        td_dt_append "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS \
            "$key" "$group" "$label" "$handler" "$desc" "$source" "$builtin" "$waitsecs" || {
            sayfail "Failed to register item: $key"
            return 1
        }
    }

    sgnd_console_register_group() {
        local key="${1:?missing group key}"
        local label="${2:?missing group label}"
        local desc="${3:-}"
        local builtin="${4:-0}"
        local source="${SGND_CURRENT_MODULE:-}"

        if td_dt_has_row "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS key "$key"; then
            return 0
        fi

        td_dt_append "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS \
            "$key" "$label" "$desc" "$source" "$builtin" || {
            sayfail "Failed to register group: $key"
            return 1
        }
    }
# --- Main -------------------------------------------------------------------------
    # main
        # Purpose:
        #   Canonical script entry point.
        #
        # Behavior:
        #   - Resolves and loads the framework bootstrap library.
        #   - Initializes framework runtime via td_bootstrap.
        #   - Executes builtin framework arguments.
        #   - Prints the standard title bar.
        #   - Runs script-specific logic.
        #
        # Arguments:
        #   $@  Framework and script-specific command-line arguments.
        #
        # Returns:
        #   Exits with the status produced by bootstrap or script logic.
    main() {
        # -- Bootstrap
            local rc=0

            __load_bootstrapper || exit $?            

            # Recognized switches:
            #     --state      -> enable saving state variables 
            #     --autostate  -> enable state support and auto-save TD_STATE_VARIABLES on exit
            #     --needroot   -> restart script if not root
            #     --cannotroot -> exit script if root
            #     --log        -> enable file logging
            #     --console    -> enable console logging
            # Example:
            #   td_bootstrap --state --needroot -- "$@"
            td_bootstrap -- "$@"
            rc=$?

            saydebug "After bootstrap: $rc"
            (( rc != 0 )) && exit "$rc"
                        
        # -- Handle builtin arguments
            saydebug "Calling builtinarg handler"
            td_builtinarg_handler
            saydebug "Exited builtinarg handler"

        # -- UI
            td_update_runmode
            #td_print_titlebar

        
        # -- Main script logic

        declare -F td_dt_append >/dev/null || {
            sayfail "td-datatable.sh did not load correctly"
            exit 126
        }
        __sgnd_console_load_config || exit $?
        __sgnd_console_register_builtin_items || exit $?
        __sgnd_console_load_modules || exit $?

        if (( $(td_dt_row_count SGND_ITEM_ROWS) == 0 )); then
            saywarning "No menu items registered"
        fi

            __sgnd_console_run
    }

    # Entrypoint: td_bootstrap will split framework args from script args.
    main "$@"
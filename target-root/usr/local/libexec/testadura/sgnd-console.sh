#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — sgnd-console
# ----------------------------------------------------------------------------------
# Purpose : Interactive console host for SolidGround/Testadura modules
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   sgnd-console is a modular terminal UI host that loads console modules from a
#   configured module directory and presents their actions through a grouped menu.
#
# Features:
#   - Dynamic module loading from a console module directory
#   - Table-backed registration of groups and items
#   - Builtin runtime/session actions (debug, dry-run, logfile, verbose, redraw, quit)
#   - Hidden key-dispatchable builtin toggles via the status bar
#   - Visible, hidden, and disabled menu-item states
#   - Immediate hotkeys for selected builtin actions
#
# Design:
#   - Executable scripts are explicit: resolve paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Menu state is data-driven through SGND_* table models.
#   - Builtin actions may remain dispatchable even when hidden from the menu body.
#
# Notes:
#   - Prompts read from /dev/tty, never stdin.
#   - UI should not be printed to stdout when stdout may be piped.
#   - Bootstrap/path resolution remains delegated to the framework bootstrapper.
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

# --- Local scripts and definitions ------------------------------------------------
 # -- Console state
    SGND_GROUP_SCHEMA="key|label|desc|source|builtin|visible|ord"
    declare -ag SGND_GROUP_ROWS=()

    SGND_ITEM_SCHEMA="key|group|label|handler|desc|source|builtin|waitsecs|visible"
    declare -ag SGND_ITEM_ROWS=()

    SGND_MODULE_SCHEMA="id|name|desc|source"
    declare -ag SGND_MODULE_ROWS=()



    SGND_CONSOLE_TITLE="Solidground Console"
    SGND_CONSOLE_DESC="Interactive scalable console module host"
    SGND_CONSOLE_MODULE_DIR=""
    SGND_CURRENT_MODULE=""
    SGND_LAST_WAITSECS=15

    declare -ag SGND_VISIBLE_ITEM_INDEXES=()
    declare -ag SGND_GROUP_RENDER_INDEXES=()

    SGND_CLEAR_ONRENDER=1

    SGND_PAGE_INDEX=0
    declare -ag SGND_PAGE_STARTS=()
    SGND_PAGE_HAS_PREV=0
    SGND_PAGE_HAS_NEXT=0
    SGND_PAGE_MAX_ROWS=6
        
 # -- Module loading and registration 
    # __sgnd_console_register_builtin_items
        # Purpose:
        #   Register the console's builtin groups and builtin menu actions.
        #
        # Behavior:
        #   - Defines the builtin group keys used by the console.
        #   - Registers runtime/session groups.
        #   - Registers builtin items such as debug, dry-run, logfile, verbose,
        #     clear-screen, redraw, and quit.
        #   - Some builtin items may be hidden from the menu body while still
        #     remaining dispatchable by key.
        #
        # Returns:
        #   0 on success
        #   non-zero if group/item registration fails
    __sgnd_console_register_builtin_items() {
        SGND_GROUP_RUNTIME="runtime"
        SGND_GROUP_SESSION="session"

        sgnd_console_register_group "$SGND_GROUP_RUNTIME" "Runtime toggles" "" 1 0 980
        sgnd_console_register_group "$SGND_GROUP_SESSION" "Console Session" "" 1 1 990

        sgnd_console_register_item "B" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_debug)" "__sgnd_console_toggle_debug" "Toggle debug output" 1 0 0
        sgnd_console_register_item "D" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_dryrun)" "__sgnd_console_toggle_dryrun" "Toggle dry-run mode" 1 0 0
        sgnd_console_register_item "L" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_logfile)" "__sgnd_console_toggle_logfile" "Toggle logfile output" 1 0 0
        sgnd_console_register_item "V" "$SGND_GROUP_RUNTIME" "$(__sgnd_console_label_verbose)" "__sgnd_console_toggle_verbose" "Toggle verbose output" 1 0 1

        sgnd_console_register_item "C" "$SGND_GROUP_SESSION" "$(__sgnd_console_label_clearonrender)" "__sgnd_console_toggle_clearonrender" "Toggle clear screen before rendering" 1 0 0
        sgnd_console_register_item "<" "$SGND_GROUP_SESSION" "Previous page" "__sgnd_console_prevpage" "Show previous menu page" 1 0 0
        sgnd_console_register_item ">" "$SGND_GROUP_SESSION" "Next page" "__sgnd_console_nextpage" "Show next menu page" 1 0 0
        sgnd_console_register_item "R" "$SGND_GROUP_SESSION" "Redraw menu" "__sgnd_console_redraw" "Refresh console display" 1 0 1
        sgnd_console_register_item "Q" "$SGND_GROUP_SESSION" "Quit" "__sgnd_console_quit" "Exit console" 1 0 1
    }

    # __sgnd_console_register_fallback_group
        # Purpose:
        #   Create a fallback group when an item references a group that has not
        #   been registered explicitly.
        #
        # Behavior:
        #   - Uses "Other" as the default label.
        #   - For keys of the form "module:<id>", attempts to resolve the module
        #     name from SGND_MODULE_ROWS and use that as the group label.
        #   - Registers the derived group as a non-builtin visible group.
        #
        # Arguments:
        #   $1  GROUP_KEY   Missing group key to register.
        #
        # Returns:
        #   0 on success
        #   non-zero if registration fails
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

        sgnd_console_register_group "$key" "$label" "" 0 1 800
    }

    # __sgnd_console_group_exists
        # Purpose:
        #   Test whether a group key already exists in the console group model.
        #
        # Arguments:
        #   $1  GROUP_KEY   Group key to test.
        #
        # Returns:
        #   0 if the group exists
        #   1 if the group does not exist
    __sgnd_console_group_exists() {
        local key="${1:?missing group key}"

        td_dt_has_row "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS key "$key"
    }
    # __sgnd_console_load_config
        # Purpose:
        #   Load console-specific configuration and resolve the module directory.
        #
        # Behavior:
        #   - Applies built-in defaults for title, description, and module directory.
        #   - If --appcfg was provided and the file does not exist, creates it.
        #   - Sources the appcfg when present.
        #   - Resolves a relative module directory against the appcfg directory.
        #   - Normalizes SGND_CONSOLE_MODULE_DIR to an absolute path.
        #
        # Configuration variables:
        #   SGND_CONSOLE_TITLE
        #   SGND_CONSOLE_DESC
        #   SGND_CONSOLE_MODULE_DIR
        #
        # Returns:
        #   0   success
        #   126 unreadable config
        #   127 config could not be created/written
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

    # __sgnd_console_create_appcfg
        # Purpose:
        #   Create a new console app configuration file with sensible defaults.
        #
        # Behavior:
        #   - Prompts interactively for title, description, and module directory
        #     when running on a TTY.
        #   - Uses defaults automatically in non-interactive mode.
        #   - Creates the parent directory if needed.
        #   - Writes a minimal shell-style config file.
        #
        # Arguments:
        #   $1  CFG_PATH   Path of the appcfg file to create.
        #
        # Returns:
        #   0   success
        #   127 config directory/file could not be created
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

    # __sgnd_console_load_modules
        # Purpose:
        #   Source all console module scripts from the configured module directory.
        #
        # Behavior:
        #   - Verifies that the module directory exists.
        #   - Sources each "*.sh" module file in that directory.
        #   - Sets SGND_CURRENT_MODULE while loading each module so registration
        #     APIs can attribute source ownership correctly.
        #   - Warns when no modules are found.
        #
        # Returns:
        #   0   success
        #   126 module directory missing or module load failed
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

 # -- Render menu helpers
    # __sgnd_console_nextpage
        # Purpose:
        #   Advance to the next rendered menu page when available.
        #
        # Returns:
        #   0 always
    __sgnd_console_nextpage() {
        __sgnd_console_build_pages

        if (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )); then
            SGND_PAGE_INDEX=$(( SGND_PAGE_INDEX + 1 ))
        fi

        return 0
    }

    # __sgnd_console_prevpage
        # Purpose:
        #   Return to the previous rendered menu page when available.
        #
        # Returns:
        #   0 always

    __sgnd_console_prevpage() {
        if (( SGND_PAGE_INDEX > 0 )); then
            SGND_PAGE_INDEX=$(( SGND_PAGE_INDEX - 1 ))
        fi

        return 0
    }

    # __sgnd_console_build_pages
        # Purpose:
        #   Simulate pagination and determine the start item of each page.
        #
        # Output:
        #   Populates SGND_PAGE_STARTS with visible item indexes.
        #
        # Returns:
        #   0 always
    __sgnd_console_build_pages() {
        local body_height=0
        local used_lines=0
        local visible_count=0
        local visible_i=0
        local row_index=0
        local group_key=""
        local current_group=""
        local item_lines=0
        local header_lines=0
        local needed_lines=0

        SGND_PAGE_STARTS=()

        __sgnd_console_collect_group_render_indexes
        __sgnd_console_collect_visible_item_indexes

        visible_count="${#SGND_VISIBLE_ITEM_INDEXES[@]}"
        body_height="$(__sgnd_console_body_height)"

        (( visible_count == 0 )) && return 0

        SGND_PAGE_STARTS+=(0)

        for (( visible_i=0; visible_i<visible_count; visible_i++ )); do
            row_index="${SGND_VISIBLE_ITEM_INDEXES[$visible_i]}"
            group_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
            item_lines="$(__sgnd_console_measure_item_lines "$row_index")"

            needed_lines="$item_lines"

            if [[ "$group_key" != "$current_group" ]]; then
                header_lines="$(__sgnd_console_measure_group_header_lines)"
                needed_lines=$(( needed_lines + header_lines ))
            fi

            if (( used_lines + needed_lines > body_height )); then
                SGND_PAGE_STARTS+=("$visible_i")
                used_lines=0
                current_group=""
            fi

            if [[ "$group_key" != "$current_group" ]]; then
                header_lines="$(__sgnd_console_measure_group_header_lines)"
                used_lines=$(( used_lines + header_lines ))
                current_group="$group_key"
            fi

            used_lines=$(( used_lines + item_lines ))
        done
    }

    # __sgnd_console_body_height
        # Purpose:
        #   Return the maximum number of body rows to render on one page.
        #
        # Output:
        #   Prints the configured maximum body row count.
        #
        # Returns:
        #   0 always
    __sgnd_console_body_height() {
        local body_height="${SGND_PAGE_MAX_ROWS:-20}"

        (( body_height < 5 )) && body_height=5
        printf '%s\n' "$body_height"
    }

    # __sgnd_console_measure_item_lines
        # Purpose:
        #   Measure how many screen lines a menu item will occupy when rendered.
        #
        # Arguments:
        #   $1  ROW_INDEX   Row index in SGND_ITEM_ROWS
        #
        # Output:
        #   Prints the rendered line count.
        #
        # Returns:
        #   0 always
    __sgnd_console_measure_item_lines() {
        local row_index="${1:?missing row index}"
        local desc=""
        local term_width=80
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local gap=3
        local tpad=3
        local desc_width=0
        local wrapped_count=0
        local line=""

        desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" desc)"

        if [[ -z "$desc" ]]; then
            printf '1\n'
            return 0
        fi

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        while IFS= read -r line; do
            wrapped_count=$(( wrapped_count + 1 ))
        done < <(td_wrap_words --width "$desc_width" --text "$desc")

        (( wrapped_count < 1 )) && wrapped_count=1
        printf '%s\n' "$wrapped_count"
    }

    # __sgnd_console_measure_group_header_lines
    __sgnd_console_measure_group_header_lines() {
        # group label + underline
        printf '2\n'
    }

    # __sgnd_console_visible_item_count
    __sgnd_console_visible_item_count() {
        printf '%s\n' "${#SGND_VISIBLE_ITEM_INDEXES[@]}"
    }

    # __sgnd_console_get_visible_row_index
    __sgnd_console_get_visible_row_index() {
        local visible_index="${1:?missing visible index}"

        if (( visible_index < 0 || visible_index >= ${#SGND_VISIBLE_ITEM_INDEXES[@]} )); then
            return 1
        fi

        printf '%s\n' "${SGND_VISIBLE_ITEM_INDEXES[$visible_index]}"
    }

    # __sgnd_console_valid_choices_csv
        # Purpose:
            #   Build the current valid choice list for the console prompt.
            #
            # Behavior:
            #   - Includes builtin item keys directly so builtin hotkeys remain
            #     dispatchable even when hidden from the menu body.
            #   - Includes numbered choices for non-builtin items based on the
            #     canonical visible menu order.
            #
            # Output:
            #   Prints a comma-separated choice list suitable for td_choose_immediate.
            #
            # Returns:
            #   0 always
    __sgnd_console_valid_choices_csv() {
        local i
        local out=""
        local row_count=0
        local builtin="0"
        local key=""

        __sgnd_console_collect_visible_item_indexes

        for (( i=1; i<=${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            [[ -n "$out" ]] && out+=","
            out+="$i"
        done

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
            (( builtin )) || continue

            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            [[ -n "$out" ]] && out+=","
            out+="$key"
        done

        printf '%s' "$out"
    }

     # __sgnd_flag_is_on
        #
        # Evaluates whether a given flag value represents a logical "true".
        #
        # This helper normalizes various truthy representations commonly used in
        # environment variables and CLI parsing, allowing consistent flag handling
        # across the framework.
        #
        # Accepted truthy values:
        #   1, true, TRUE, yes, YES, on, ON
        #
        # All other values (including empty or undefined) are treated as false.
        #
        # Parameters:
        #   $1  - Value to evaluate
        #
        # Returns:
        #   0 (true)  if the value is considered "on"
        #   1 (false) otherwise
        #
        # Usage:
        #   if __sgnd_flag_is_on "${FLAG_DEBUG:-0}"; then
        #       echo "Debug enabled"
        #   fi
        #
        # Notes:
        # - Safe to use with unset variables via default expansion (${VAR:-0})
        # - Designed for internal framework use
    __sgnd_flag_is_on() {
        case "${1:-}" in
            1|true|TRUE|yes|YES|on|ON) return 0 ;;
            *) return 1 ;;
        esac
    }

    # __sgnd_console_get_visible_display_number
        # Purpose:
        #   Resolve the visible numeric display number for an item row index.
        #
        # Arguments:
        #   $1  ROW_INDEX   Index in SGND_ITEM_ROWS
        #
        # Output:
        #   Prints the 1-based display number, or nothing if not visible.
        #
        # Returns:
        #   0 if the item is in the visible numeric order
        #   1 otherwise
    __sgnd_console_get_visible_display_number() {
        local row_index="${1:?missing row index}"
        local i

        for (( i=0; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            if [[ "${SGND_VISIBLE_ITEM_INDEXES[$i]}" == "$row_index" ]]; then
                printf '%s\n' "$((i + 1))"
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_collect_visible_item_indexes
        # Purpose:
        #   Build the canonical visible numeric menu order for non-builtin items.
        #
        # Behavior:
        #   - Traverses groups in canonical render order.
        #   - Includes only non-builtin items.
        #   - Within each group, preserves item registration order.
        #   - Includes only items whose visible state is:
        #       1 = visible/enabled
        #       2 = visible/disabled
        #   - Excludes hidden items (state 0).
        #
        # Output:
        #   Populates SGND_VISIBLE_ITEM_INDEXES with SGND_ITEM_ROWS row indexes.
        #
        # Returns:
        #   0 always
    __sgnd_console_collect_visible_item_indexes() {
        local gi
        local ii
        local item_row_count=0
        local group_key=""
        local group_builtin="0"
        local item_group=""
        local item_builtin="0"
        local item_state="1"

        SGND_VISIBLE_ITEM_INDEXES=()

        __sgnd_console_collect_group_render_indexes
        item_row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for gi in "${SGND_GROUP_RENDER_INDEXES[@]}"; do
            group_builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" builtin)"
            (( group_builtin )) && continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)"

            for (( ii=0; ii<item_row_count; ii++ )); do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
                [[ "$item_group" == "$group_key" ]] || continue

                item_builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" builtin)"
                (( item_builtin )) && continue

                item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
                case "$item_state" in
                    1|2)
                        SGND_VISIBLE_ITEM_INDEXES+=("$ii")
                        ;;
                esac
            done
        done
    }

    # __sgnd_console_calc_label_width
        # Purpose:
        #   Calculate the left-column width needed for rendered menu items.
        #
        # Behavior:
        #   - Includes builtin items.
        #   - Includes non-builtin items present in the canonical visible order.
        #   - Caps the final width at 35 characters.
        #
        # Output:
        #   Prints the calculated width to stdout.
        #
        # Returns:
        #   0 always
    __sgnd_console_calc_label_width() {
        local i
        local row_count=0
        local builtin="0"
        local display_key=""
        local label=""
        local left_text=""
        local width=0
        local max_width=0

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            else
                display_key="$(__sgnd_console_get_visible_display_number "$i" 2>/dev/null)" || continue
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label)"
            left_text="${display_key}) ${label}"
            width="$(td_visible_length "$left_text")"

            (( width > max_width )) && max_width="$width"
        done

        (( max_width > 35 )) && max_width=35
        printf '%s\n' "$max_width"
    }

    # __sgnd_console_find_visible_pos_for_row
        # Purpose:
        #   Find the visible-order position for a row index in SGND_ITEM_ROWS.
        #
        # Arguments:
        #   $1  ROW_INDEX
        #
        # Output:
        #   Prints the 0-based visible position.
        #
        # Returns:
        #   0 if found
        #   1 otherwise
    __sgnd_console_find_visible_pos_for_row() {
        local row_index="${1:?missing row index}"
        local i

        for (( i=0; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            if [[ "${SGND_VISIBLE_ITEM_INDEXES[$i]}" == "$row_index" ]]; then
                printf '%s\n' "$i"
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_group_continues_after_visible_pos
        # Purpose:
        #   Determine whether a group has more visible items after a given visible
        #   position in the canonical visible item order.
        #
        # Arguments:
        #   $1  GROUP_KEY
        #   $2  LAST_VISIBLE_POS
        #
        # Returns:
        #   0 if the group continues on a later page
        #   1 otherwise
    __sgnd_console_group_continues_after_visible_pos() {
        local group_key="${1:?missing group key}"
        local last_visible_pos="${2:?missing visible position}"
        local i
        local row_index=0
        local item_group=""

        for (( i=last_visible_pos + 1; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            row_index="${SGND_VISIBLE_ITEM_INDEXES[$i]}"
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"

            if [[ "$item_group" == "$group_key" ]]; then
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_collect_group_render_indexes
        # Purpose:
        #   Build the canonical render order for menu groups.
        #
        # Behavior:
        #   - Includes all registered groups.
        #   - Sorts non-builtin groups before builtin groups.
        #   - Within each bucket, sorts by ascending ord.
        #   - For equal ord values, preserves registration order.
        #
        # Output:
        #   Populates SGND_GROUP_RENDER_INDEXES with SGND_GROUP_ROWS row indexes
        #   in render order.
        #
        # Returns:
        #   0 always
    __sgnd_console_collect_group_render_indexes() {
        local i
        local row_count=0
        local builtin="0"
        local ord="1000"

        local -a sortable_rows=()
        local -a sorted_rows=()

        SGND_GROUP_RENDER_INDEXES=()

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$i" builtin)"
            ord="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$i" ord)"
            : "${ord:=1000}"

            # sort key = builtin bucket | ord | original row index
            # non-builtin first, builtin last
            sortable_rows+=("$(printf '%d|%08d|%08d' "$builtin" "$ord" "$i")")
        done

        if (( ${#sortable_rows[@]} == 0 )); then
            return 0
        fi

        mapfile -t sorted_rows < <(printf '%s\n' "${sortable_rows[@]}" | sort -t '|' -k1,1n -k2,2n -k3,3n)

        for i in "${!sorted_rows[@]}"; do
            SGND_GROUP_RENDER_INDEXES+=("${sorted_rows[$i]##*|}")
        done
    }
    
    # __sgnd_console_render_page_rows
        # Purpose:
        #   Render a prepared page selection of groups and item rows.
        #
        # Arguments:
        #   $1  Name of array variable containing ordered group keys
        #   $2  Name of array variable containing ordered item row indexes
        #
        # Returns:
        #   0 always
    __sgnd_console_render_page_rows() {
        local -n _page_groups="$1"
        local -n _page_rows="$2"

        local group_key=""
        local row_index=0
        local label=""
        local desc=""
        local display_key=""
        local item_group=""
        local item_state="1"

        local left_text=""
        local left_width=0
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local desc_width=0
        local term_width=80
        local gap=3
        local tpad=3

        local label_style=""
        local value_style=""
        local normal_label_style="$(td_sgr "$SILVER")"
        local normal_value_style="$(td_sgr "$SILVER" "" "$FX_ITALIC")"
        local disabled_label_style="$(td_sgr "$DARK_SILVER" "" "$FX_FAINT")"
        local disabled_value_style="$(td_sgr "$DARK_SILVER" "" "$FX_FAINT" "$FX_ITALIC")"

        local wrapped_line=""
        local first_line=1
        local group_label=""
        local group_label_display=""
        local gi

        local group_last_row_index=-1
        local group_last_visible_pos=-1

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        for group_key in "${_page_groups[@]}"; do
            group_label=""
            group_last_row_index=-1
            group_last_visible_pos=-1

            for (( gi=0; gi<$(td_dt_row_count SGND_GROUP_ROWS); gi++ )); do
                if [[ "$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)" == "$group_key" ]]; then
                    group_label="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" label)"
                    break
                fi
            done

            [[ -n "$group_label" ]] || continue

            for row_index in "${_page_rows[@]}"; do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
                [[ "$item_group" == "$group_key" ]] || continue
                group_last_row_index="$row_index"
            done

            group_label_display="$group_label"

            if (( group_last_row_index >= 0 )); then
                group_last_visible_pos="$(__sgnd_console_find_visible_pos_for_row "$group_last_row_index" 2>/dev/null || printf '%s' '-1')"

                if (( group_last_visible_pos >= 0 )); then
                    if __sgnd_console_group_continues_after_visible_pos "$group_key" "$group_last_visible_pos"; then
                        group_label_display="${group_label} ....."
                    fi
                fi
            fi

            td_print --text "$group_label_display"
            left_width="$(td_visible_length "$group_label_display")"
            td_print_sectionheader --border "$LN_H" --maxwidth "$left_width"

            for row_index in "${_page_rows[@]}"; do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
                [[ "$item_group" == "$group_key" ]] || continue

                item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" visible)"
                case "$item_state" in
                    1|2) ;;
                    *) continue ;;
                esac

                display_key="$(__sgnd_console_get_visible_display_number "$row_index")" || continue

                if (( item_state == 2 )); then
                    label_style="$disabled_label_style"
                    value_style="$disabled_value_style"
                else
                    label_style="$normal_label_style"
                    value_style="$normal_value_style"
                fi

                label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" label)"
                desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" desc)"
                left_text="${display_key}) ${label}"

                if [[ -z "$desc" ]]; then
                    printf '%*s%s' "$tpad" "" "$label_style"
                    td_padded_visible "$left_text" "$left_width_max"
                    printf '%s\n' "$RESET"
                    continue
                fi

                first_line=1
                while IFS= read -r wrapped_line; do
                    if (( first_line )); then
                        printf '%*s%s' "$tpad" "" "$label_style"
                        td_padded_visible "$left_text" "$left_width_max"
                        printf '%s%*s%s%s%s\n' \
                            "$RESET" \
                            "$gap" "" \
                            "$value_style" "$wrapped_line" "$RESET"
                        first_line=0
                    else
                        printf '%*s%*s%*s%s%s%s\n' \
                            "$tpad" "" \
                            "$left_width_max" "" \
                            "$gap" "" \
                            "$value_style" "$wrapped_line" "$RESET"
                    fi
                done < <(td_wrap_words --width "$desc_width" --text "$desc")
            done

            td_print
        done
    }
 # -- Render menu
        # __sgnd_console_render_menu_body_paged
            # Purpose:
            #   Render the paged non-builtin body of the console menu.
            #
            # Behavior:
            #   - Starts at SGND_PAGE_START_ITEM in canonical visible item order.
            #   - Renders only items that fit in the available body height.
            #   - Prints group headers only when at least one item from that group fits.
            #   - Updates SGND_PAGE_NEXT_START_ITEM, SGND_PAGE_HAS_PREV, SGND_PAGE_HAS_NEXT.
            #
            # Returns:
            #   0 always
        __sgnd_console_render_menu_body_paged() {
            local body_height=0
            local used_lines=0

            local visible_count=0
            local visible_i=0
            local row_index=0
            local group_key=""
            local current_group=""
            local item_lines=0
            local header_lines=0
            local needed_lines=0

            local pending_group=""
            local -a page_rows=()
            local -a page_groups=()

            __sgnd_console_collect_group_render_indexes
            __sgnd_console_collect_visible_item_indexes
            __sgnd_console_build_pages

            visible_count="${#SGND_VISIBLE_ITEM_INDEXES[@]}"
            body_height="$(__sgnd_console_body_height)"

                        SGND_PAGE_HAS_PREV=0
            SGND_PAGE_HAS_NEXT=0

            if (( visible_count == 0 )); then
                return 0
            fi

            if (( SGND_PAGE_INDEX < 0 )); then
                SGND_PAGE_INDEX=0
            fi

            if (( SGND_PAGE_INDEX >= ${#SGND_PAGE_STARTS[@]} )); then
                SGND_PAGE_INDEX=0
            fi

            (( SGND_PAGE_INDEX > 0 )) && SGND_PAGE_HAS_PREV=1
            (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )) && SGND_PAGE_HAS_NEXT=1

            local page_start_item=0
            local page_end_item="$visible_count"

            page_start_item="${SGND_PAGE_STARTS[$SGND_PAGE_INDEX]}"

            if (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )); then
                page_end_item="${SGND_PAGE_STARTS[$((SGND_PAGE_INDEX + 1))]}"
            fi

            for (( visible_i=page_start_item; visible_i<page_end_item; visible_i++ )); do
                row_index="${SGND_VISIBLE_ITEM_INDEXES[$visible_i]}"
                group_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
                item_lines="$(__sgnd_console_measure_item_lines "$row_index")"

                needed_lines="$item_lines"

                if [[ "$group_key" != "$current_group" ]]; then
                    header_lines="$(__sgnd_console_measure_group_header_lines)"
                    needed_lines=$(( needed_lines + header_lines ))
                fi

                if [[ "$group_key" != "$current_group" ]]; then
                    page_groups+=("$group_key")
                    current_group="$group_key"
                    used_lines=$(( used_lines + header_lines ))
                fi

                page_rows+=("$row_index")
                used_lines=$(( used_lines + item_lines ))
            done

            __sgnd_console_render_page_rows page_groups page_rows
        }
    
    # __sgnd_console_render_menu
        # Purpose:
        #   Render the complete console menu for the current state.
        #
        # Behavior:
        #   - Refreshes builtin labels so toggle-driven labels stay current.
        #   - Builds the canonical group render order.
        #   - Builds the canonical visible item order.
        #   - Renders the menu title/header.
        #   - Renders groups in canonical render order.
        #   - Renders the bottom status/toggle bar last.
        #
        # Returns:
        #   0 always
    __sgnd_console_render_menu() {
        local idx=""
        local group_key=""
        local builtin="0"

        __sgnd_console_refresh_builtin_labels
        __sgnd_console_collect_group_render_indexes
        __sgnd_console_collect_visible_item_indexes
        SGND_RENDER_LABEL_WIDTH="$(__sgnd_console_calc_label_width)"

        __sgnd_console_render_menu_title
        __sgnd_console_render_menu_body_paged

        for idx in "${SGND_GROUP_RENDER_INDEXES[@]}"; do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$idx" builtin)"
            (( builtin )) || continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$idx" key)"
            __sgnd_console_render_group "$group_key"
        done

        __sgnd_console_render_togglebar
    }

    # __sgnd_console_render_menu_title
        # Purpose:
        #   Render the console title and description banner.
        #
        # Behavior:
        #   - Clears the screen first when SGND_CLEAR_ONRENDER is enabled.
        #   - Prints the console title and description with section borders.
        #
        # Returns:
        #   0 always
    __sgnd_console_render_menu_title() {
        (( ! SGND_CLEAR_ONRENDER )) || clear
        
        local width=80
        width="$(td_terminal_width)"

        td_print_sectionheader --border "$DL_H" --maxwidth "$width"
        td_print --pad 4 "$(td_sgr "$WHITE" "" "$FX_BOLD")${SGND_CONSOLE_TITLE}${RESET}"
        td_print --pad 4 "$(td_sgr "$SILVER" "" "$FX_ITALIC")${SGND_CONSOLE_DESC}"
        td_print_sectionheader --border "$LN_H" --maxwidth "$width"
        td_print
    }

    # __sgnd_console_render_group
        # Purpose:
        #   Render one menu group and its visible items.
        #
        # Behavior:
        #   - Skips the group if it does not exist, is hidden, or contains no
        #     renderable items.
        #   - Renders items whose state is:
        #       1 = visible/enabled
        #       2 = visible/disabled
        #   - Skips hidden items (state 0).
        #   - Renders disabled items faint.
        #   - Uses builtin keys directly and numbers visible non-builtin items.
        #
        # Arguments:
        #   $1  GROUP_KEY   Group key to render.
        #
        # Returns:
        #   0 always
    __sgnd_console_render_group() {
        local group_key="${1:?missing group key}"
        local _tpad=3

        local gi
        local ii
        local row_count=0
        local label=""
        local desc=""
        local group_label=""
        local found_group=0
        local group_state=1
        local display_key=""
        local item_group=""
        local builtin="0"
        local item_state="1"
        local has_renderable_items=0

        local left_text=""
        local left_width=0
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local desc_width=0
        local term_width=80
        local gap=3

        local label_style=""
        local value_style=""
        local normal_label_style="$(td_sgr "$SILVER")"
        local normal_value_style="$(td_sgr "$SILVER" "$FX_ITALIC")"
        local disabled_label_style="$(td_sgr "$DARK_SILVER" "$FX_FAINT")"
        local disabled_value_style="$(td_sgr "$DARK_SILVER" "$FX_FAINT" "$FX_ITALIC")"

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( gi=0; gi<row_count; gi++ )); do
            if [[ "$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)" == "$group_key" ]]; then
                group_label="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" label)"
                group_state="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" visible)"
                found_group=1
                break
            fi
        done

        (( found_group )) || return 0
        (( group_state != 0 )) || return 0

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( ii=0; ii<row_count; ii++ )); do
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
            [[ "$item_group" == "$group_key" ]] || continue

            item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
            case "$item_state" in
                1|2)
                    has_renderable_items=1
                    break
                    ;;
            esac
        done

        (( has_renderable_items )) || return 0

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

            item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
            case "$item_state" in
                1|2) ;;
                *) continue ;;
            esac

            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" key)"
            else
                display_key="$(__sgnd_console_get_visible_display_number "$ii")" || continue
            fi

            if (( item_state == 2 )); then
                label_style="$disabled_label_style"
                value_style="$disabled_value_style"
            else
                label_style="$normal_label_style"
                value_style="$normal_value_style"
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" label)"
            desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" desc)"
            left_text="${display_key}) ${label}"

            if [[ -z "$desc" ]]; then
                printf '%*s%s' "$_tpad" "" "$label_style"
                td_padded_visible "$left_text" "$left_width_max"
                printf '%s\n' "$RESET"
                continue
            fi

            local first_line=1
            local wrapped_line=""

            while IFS= read -r wrapped_line; do
                if (( first_line )); then
                    printf '%*s%s' "$_tpad" "" "$label_style"
                    td_padded_visible "$left_text" "$left_width_max"
                    printf '%s%*s%s%s%s\n' \
                        "$RESET" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                    first_line=0
                else
                    printf '%*s%*s%*s%s%s%s\n' \
                        "$_tpad" "" \
                        "$left_width_max" "" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                fi
            done < <(td_wrap_words --width "$desc_width" --text "$desc")
        done

        td_print
    }

    __sgnd_console_render_togglebar() {
        local render_width=80
        local pad=3
        local gap=3

        local debug_text=""
        local dryrun_text=""
        local logfile_text=""
        local verbose_text=""
        local clearscr_text=""
        local prevtext=""
        local nexttext=""

        local bar_text=""
        local visible_len=0
        local left_pad=0

        local prev_enabled=0
        local next_enabled=0

        render_width="$(td_terminal_width)"

        debug_text="$(__sgnd_console_toggleword "DEBUG"   "B" "${FLAG_DEBUG:-0}")"
        dryrun_text="$(__sgnd_console_toggleword "DRYRUN" "D" "${FLAG_DRYRUN:-0}" "${TUI_DRYRUN}" "${TUI_COMMIT}")"
        logfile_text="$(__sgnd_console_toggleword "LOG"   "L" "${TD_LOGFILE_ENABLED:-0}")"
        verbose_text="$(__sgnd_console_toggleword "VERBOSE" "V" "${FLAG_VERBOSE:-0}")"
        clearscr_text="$(__sgnd_console_toggleword "CLRSCR" "C" "${SGND_CLEAR_ONRENDER:-0}")"

        (( SGND_PAGE_INDEX > 0 )) && prev_enabled=1
        (( SGND_PAGE_INDEX + 1 < ${#SGND_PAGE_STARTS[@]} )) && next_enabled=1

        prevtext="$(__sgnd_console_toggleword "<<PREV" "<" "$prev_enabled")"
        nexttext="$(__sgnd_console_toggleword "NEXT>>" ">" "$next_enabled")"

        local page_text=""
        local page_count="${#SGND_PAGE_STARTS[@]}"

        saydebug "Pagecount: ${page_count}"
        saydebug "Page index: ${SGND_PAGE_INDEX}"
        if (( page_count > 1 )); then
            page_text="Page $((SGND_PAGE_INDEX + 1))/$page_count"
            page_text="$(td_sgr "$SILVER" "" "$FX_ITALIC")${page_text}${RESET}"
        fi

        bar_text="${prevtext}$(td_string_repeat ' ' "$gap")${debug_text}$(td_string_repeat ' ' "$gap")${dryrun_text}$(td_string_repeat ' ' "$gap")${page_text}$(td_string_repeat ' ' "$gap")${logfile_text}$(td_string_repeat ' ' "$gap")${verbose_text}$(td_string_repeat ' ' "$gap")${clearscr_text}$(td_string_repeat ' ' "$gap")${nexttext}"

        visible_len="$(td_visible_length "$bar_text")"
        left_pad=$(( (render_width - visible_len) / 2 ))
        (( left_pad < pad )) && left_pad="$pad"

        td_print_sectionheader --border "$DL_H" --maxwidth "$render_width"
        printf '%*s%s\n' "$left_pad" "" "$bar_text"
    }
    
 # -- Menu actions
    # __sgnd_console_dispatch
        # Purpose:
        #   Dispatch a user menu choice to the matching handler.
        #
        # Behavior:
        #   - Numeric choices resolve against the canonical visible non-builtin
        #     menu order.
        #   - Hidden non-builtin items are excluded from numbering and dispatch.
        #   - Disabled items are recognized but not executed.
        #   - Key dispatch still works for builtin items even when hidden from
        #     the menu body.
        #
        # Arguments:
        #   $1  CHOICE   Numeric selection or registered item key.
        #
        # Returns:
        #   Handler return code when dispatched
        #   1 when invalid or disabled
    __sgnd_console_dispatch() {
        local choice="${1:?missing choice}"
        local handler=""
        local label=""
        local state="1"
        local row_index=0
        local i
        local row_count=0
        local key=""

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            __sgnd_console_collect_visible_item_indexes

            if (( choice < 1 || choice > ${#SGND_VISIBLE_ITEM_INDEXES[@]} )); then
                saywarning "Invalid selection: $choice"
                return 1
            fi

            row_index="${SGND_VISIBLE_ITEM_INDEXES[$((choice - 1))]}"
            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" label)"
            state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" visible)"

            if (( state == 2 )); then
                saywarning "Option disabled: $label"
                return 1
            fi

            handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" handler)"
            SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" waitsecs)"
            "$handler"
            return $?
        fi

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"

            if [[ "${choice^^}" == "${key^^}" ]]; then
                state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" visible)"
                label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label)"

                if (( state == 2 )); then
                    saywarning "Option disabled: $label"
                    return 1
                fi

                handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" handler)"
                SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" waitsecs)"
                "$handler"
                return $?
            fi
        done

        saywarning "Invalid selection: $choice"
        return 1
    }
    
    # __sgnd_console_toggle_clearonrender
        # Purpose:
        #   Toggle whether the console clears the screen before each render.
        #
        # Behavior:
        #   - Flips SGND_CLEAR_ONRENDER between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_toggle_dryrun
        # Purpose:
        #   Toggle dry-run mode for the current session.
        #
        # Behavior:
        #   - Flips FLAG_DRYRUN between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_toggle_debug
        # Purpose:
        #   Toggle debug output for the current session.
        #
        # Behavior:
        #   - Flips FLAG_DEBUG between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #   - Calls td_update_runmode so framework UI/debug state stays synchronized.
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_toggle_verbose
        # Purpose:
        #   Toggle verbose output for the current session.
        #
        # Behavior:
        #   - Flips FLAG_VERBOSE between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_toggle_logfile
        # Purpose:
        #   Toggle logfile output for the current session.
        #
        # Behavior:
        #   - Flips TD_LOGFILE_ENABLED between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_redraw
        # Purpose:
        #   No-op action used to force a menu redraw cycle.
        #
        # Returns:
        #   0 always
    __sgnd_console_redraw() {
        return 0
    }

    # __sgnd_console_quit
        # Purpose:
        #   Signal the console loop to terminate.
        #
        # Returns:
        #   200 as a sentinel value consumed by __sgnd_console_run
    __sgnd_console_quit() {
        return 200
    }

    # __sgnd_run_script
        #
        # Resolves and executes a script within the sgnd-console environment, while
        # transparently propagating framework-level flags to the target script.
        #
        # Responsibilities:
        # - Resolves relative script paths against $TD_SCRIPT_DIR
        # - Normalizes the script path (if readlink is available)
        # - Verifies existence and executability of the script
        # - Forwards framework flags (dry-run, verbose, debug, logfile)
        # - Preserves and forwards all original arguments
        #
        # Parameters:
        #   $1      - Script path (absolute or relative to $TD_SCRIPT_DIR)
        #   $@      - Additional arguments passed to the target script
        #
        # Framework flags propagated (if enabled):
        #   FLAG_DRYRUN         -> --dryrun
        #   FLAG_VERBOSE        -> --verbose
        #   FLAG_DEBUG          -> --debug
        #   TD_LOGFILE_ENABLED  -> --logfile <file>
        #
        # Behavior:
        # - Relative paths are resolved against $TD_SCRIPT_DIR
        # - Script must exist and be executable (-f and -x checks)
        # - Execution is performed directly (respects script shebang)
        #
        # Returns:
        #   Exit code of the executed script
        #   1 if validation fails (missing or non-executable script)
        #
        # Logging:
        # - Emits debug output via saydebug before execution
        # - Emits failures via sayfail
        #
        # Example:
        #   __sgnd_run_script "jobs/import.sh" --customer 42
        #
        # Notes:
        # - Uses argument arrays to preserve proper quoting
        # - Acts as a central execution wrapper for all console scripts
        # - Intended as a core part of the sgnd execution pipeline
    __sgnd_run_script() {
        local script="${1:?missing script}"
        shift || true

        local resolved="$script"
        local -a script_args=()

        case "$script" in
            /*) ;;
            *)
                resolved="${TD_SCRIPT_DIR%/}/$script"
                ;;
        esac

        if command -v readlink >/dev/null 2>&1; then
            resolved="$(readlink -f -- "$resolved" 2>/dev/null || printf '%s' "$resolved")"
        fi

        [[ -f "$resolved" ]] || {
            sayfail "Script not found: $resolved"
            return 1
        }

        [[ -x "$resolved" ]] || {
            sayfail "Script not executable: $resolved"
            return 1
        }

        __sgnd_flag_is_on "${FLAG_DRYRUN:-0}"        && script_args+=("--dryrun")
        __sgnd_flag_is_on "${FLAG_VERBOSE:-0}"       && script_args+=("--verbose")
        __sgnd_flag_is_on "${FLAG_DEBUG:-0}"         && script_args+=("--debug")
        __sgnd_flag_is_on "${TD_LOGFILE_ENABLED:-0}" && [[ -n "${LOG_FILE:-}" ]] && script_args+=("--logfile" "$LOG_FILE")

        script_args+=("$@")

        saydebug "Executing script: $resolved ${script_args[*]}"

        "$resolved" "${script_args[@]}"
    }

 # -- Display helpers

    # __sgnd_console_refresh_builtin_labels
        # Purpose:
        #   Refresh dynamic labels for builtin toggle items.
        #
        # Behavior:
        #   - Scans registered items by key.
        #   - Recomputes labels for builtin items whose label reflects current state
        #     (e.g. Debug: On/Off).
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_toggleword
        # Purpose:
        #   Render a styled toggle-bar word with an emphasized hotkey character.
        #
        # Behavior:
        #   - Applies active/inactive styling depending on STATE.
        #   - Highlights HOTKEY within WORD using underline and emphasis.
        #   - Special-cases DRYRUN so the inactive display text becomes COMMIT(D).
        #   - If HOTKEY is not present in WORD, renders WORD as-is.
        #
        # Arguments:
        #   $1  WORD      Display word.
        #   $2  HOTKEY    Character to highlight within WORD.
        #   $3  STATE     1=active, 0=inactive.
        #   $4  ONCLR     Optional active color escape/value.
        #   $5  OFFCLR    Optional inactive color escape/value.
        #
        # Output:
        #   Prints the styled text to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_toggleword() {
        local word="${1:?missing word}"
        local hotkey="${2:?missing hotkey}"
        local state="${3:-0}"

        local onclr="${4:-$GREEN}"
        local offclr="${5:-$DARK_SILVER}"

        local word_style=""
        local key_style=""
        local prefix=""
        local suffix=""

        if (( state )); then
            word_style="$(td_sgr "$onclr" "$FX_BOLD")"
            key_style="$(td_sgr "$onclr" "$FX_BOLD" "$FX_UNDERLINE")"
        else
            if [[ "$word" == "DRYRUN" ]]; then
                word="COMMIT(D)"
            fi
            word_style="$(td_sgr "$offclr")"
            key_style="$(td_sgr "$offclr" "$FX_BOLD" "$FX_UNDERLINE")"
        fi

        prefix="${word%%"$hotkey"*}"
        suffix="${word#*"$hotkey"}"

        if [[ "$word" == "$prefix" ]]; then
            printf '%s%s%s' "$word_style" "$word" "$RESET"
            return 0
        fi

        printf '%s%s%s%s%s%s%s' \
            "$word_style" "$prefix" \
            "$key_style" "$hotkey" \
            "$RESET" \
            "$word_style" "$suffix" \
            "$RESET"
    }

    # __sgnd_console_onoff
        # Purpose:
        #   Render a colored "On" or "Off" state fragment.
        #
        # Arguments:
        #   $1  VALUE    Truthy numeric state.
        #   $2  ONCLR    Optional color for the On state.
        #   $3  OFFCLR   Optional color for the Off state.
        #
        # Output:
        #   Prints the styled state text to stdout (no newline).
        #
        # Returns:
        #   0 always
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

    # __sgnd_console_label_clearonrender
        # Purpose:
        #   Build the current label text for the clear-on-render builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_clearonrender() {
        : "${SGND_CLEAR_ONRENDER:=1}"
        printf 'Clear screen: %s' "$(__sgnd_console_onoff "$SGND_CLEAR_ONRENDER")"
    }

    # __sgnd_console_label_dryrun
        # Purpose:
        #   Build the current label text for the dry-run builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_dryrun() {
        : "${FLAG_DRYRUN:=0}"
        printf 'Dry-run: %s' "$(__sgnd_console_onoff "$FLAG_DRYRUN" "$TUI_DRYRUN" "$TUI_COMMIT")"
    }

    # __sgnd_console_label_debug
        # Purpose:
        #   Build the current label text for the debug builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_debug() {
        : "${FLAG_DEBUG:=0}"
        printf 'Debug: %s' "$(__sgnd_console_onoff "$FLAG_DEBUG")"
    }

    # __sgnd_console_label_verbose
        # Purpose:
        #   Build the current label text for the verbose builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_verbose() {
        : "${FLAG_VERBOSE:=0}"
        printf 'Verbose: %s' "$(__sgnd_console_onoff "$FLAG_VERBOSE")"
    }

    # __sgnd_console_label_logfile
        # Purpose:
        #   Build the current label text for the logfile builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_logfile() {
        : "${TD_LOGFILE_ENABLED:=0}"
        printf 'Logfile: %s' "$(__sgnd_console_onoff "$TD_LOGFILE_ENABLED")"
    }

# --- Main sequence ----------------------------------------------------------------
    # __sgnd_console_run
        # Purpose:
        #   Run the interactive console event loop.
        #
        # Behavior:
        #   - Renders the menu.
        #   - Builds the valid choice list for the current menu state.
        #   - Reads a choice via td_choose_immediate.
        #   - Dispatches the selected handler.
        #   - Exits cleanly when the quit sentinel (200) is returned.
        #   - Optionally pauses after actions according to SGND_LAST_WAITSECS.
        #
        # Returns:
        #   0 on normal console exit
        #   1 on input/read failure
    __sgnd_console_run() {
        local choice=""
        local valid_choices=""
        local rc=0

        while true; do
            __sgnd_console_render_menu
            valid_choices="$(__sgnd_console_valid_choices_csv)"
            
            td_print_sectionheader --border "$DL_H" --maxwidth "$(td_terminal_width)"
            td_choose_immediate \
                --label "Select option" \
                --choices "$valid_choices" \
                --instantchoices "B,D,L,V,C,<,>" \
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
    # sgnd_console_register_item
        # Purpose:
        #   Register one menu item in the console item model.
        #
        # Behavior:
        #   - Validates key uniqueness.
        #   - Verifies that the handler function exists.
        #   - Assigns a default module-based group when GROUP is empty.
        #   - Auto-registers a fallback group when needed.
        #   - Appends the item row to SGND_ITEM_ROWS.
        #
        # Arguments:
        #   $1  KEY       Unique item key.
        #   $2  GROUP     Target group key (optional).
        #   $3  LABEL     Display label.
        #   $4  HANDLER   Function name to invoke.
        #   $5  DESC      Optional description.
        #   $6  BUILTIN   1=builtin item, 0=normal item.
        #   $7  WAITSECS  Post-action wait duration.
        #   $8  VISIBLE   0=hidden, 1=visible/enabled, 2=visible/disabled.
        #
        # Returns:
        #   0 on success
        #   1 on validation or append failure
    sgnd_console_register_item() {
        local key="${1:?missing key}"
        local group="${2:-}"
        local label="${3:?missing label}"
        local handler="${4:?missing handler}"
        local desc="${5:-}"
        local builtin="${6:-0}"
        local waitsecs="${7:-15}"
        local visible="${8:-1}"
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
            "$key" "$group" "$label" "$handler" "$desc" "$source" "$builtin" "$waitsecs" "$visible" || {
            sayfail "Failed to register item: $key"
            return 1
        }
    }

    # sgnd_console_register_group
        # Purpose:
        #   Register one menu group in the console group model.
        #
        # Behavior:
        #   - Ignores duplicate group keys.
        #   - Appends a new group row to SGND_GROUP_ROWS when absent.
        #
        # Arguments:
        #   $1  KEY      Unique group key.
        #   $2  LABEL    Display label.
        #   $3  DESC     Optional description.
        #   $4  BUILTIN  1=builtin group, 0=normal group.
        #   $5  VISIBLE  0=hidden, 1=visible/enabled, 2=visible/disabled.
        #
        # Returns:
        #   0 on success
        #   1 on append failure
    sgnd_console_register_group() {
        local key="${1:?missing group key}"
        local label="${2:?missing group label}"
        local desc="${3:-}"
        local builtin="${4:-0}"
        local visible="${5:-1}"
        local ord="${6:-1000}"
        local source="${SGND_CURRENT_MODULE:-}"

        if td_dt_has_row "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS key "$key"; then
            return 0
        fi

        td_dt_append "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS \
            "$key" "$label" "$desc" "$source" "$builtin" "$visible" "$ord" || {
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
        #   - Loads console configuration and builtin/module registrations.
        #   - Starts the interactive console loop.
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
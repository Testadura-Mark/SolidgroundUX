#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — script-hub.sh
# ----------------------------------------------------------------------------------
# Purpose : A generic, modular menu host
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   Script Hub is a generic, framework-level console for discovering and
#   orchestrating modular Testadura / SolidGround tools.
#
#   Functionality is provided entirely by modules, which register menu
#   entries and handlers into a shared runtime model. The hub itself
#   contains no business logic and remains stable as the system grows.
#
# Design notes:
#   - Strict separation of concerns: orchestration vs. functionality.
#   - Modules are declarative and side-effect free at load time.
#   - Menu structure is treated as data, not control flow.
#   - Extensibility is achieved through module discovery, not modification.
# =================================================================================

set -euo pipefail
# --= Find bootstrapper
    BOOTSTRAP="/usr/local/lib/testadura/common/td-bootstrap.sh"

    if [[ -r "$BOOTSTRAP" ]]; then
        # shellcheck disable=SC1091
        source "$BOOTSTRAP"
    else
        # Only prompt if interactive
        if [[ -t 0 ]]; then
            printf "\n"
            printf "Framework not installed in the default location."
            printf "Are you developing the framework or using a custom install path?\n\n"

            read -r -p "Enter framework root path (or leave empty to abort): " _root
            [[ -n "$_root" ]] || exit 127

            BOOTSTRAP="$_root/usr/local/lib/testadura/common/td-bootstrap.sh"
            if [[ ! -r "$BOOTSTRAP" ]]; then
                printf "FATAL: No td-bootstrap.sh found at provided location: $BOOTSTRAP"
                exit 127
            fi

            # Persist for next runs
            CFG="$HOME/.config/testadura/bootstrap.conf"
            mkdir -p "$(dirname "$CFG")"
            printf 'TD_FRAMEWORK_ROOT=%q\n' "$_root" > "$CFG"

            # shellcheck disable=SC1091
            source "$CFG"
            # shellcheck disable=SC1091
            source "$BOOTSTRAP"
        else
            printf "FATAL: Testadura framework not installed ($BOOTSTRAP missing)" >&2
            exit 127
        fi
    fi

# --- Script metadata -------------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Script Hub"
    TD_SCRIPT_DESC="A generic, modular menu host that composes independent script modules into a unified interactive toolbox."
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

    MOD_DIR="${MOD_DIR:-$TD_SCRIPT_DIR/mods}"
    TD_SCRIPT_SETTINGS=(
        MOD_DIR
        MNU_TITLE
    )

# --- Using / imports -------------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )

# --- Argument specification and processing ---------------------------------------
    # --- Example: Arguments -------------------------------------------------------
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
    # ------------------------------------------------------------------------
    TD_ARGS_SPEC=(
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "statereset|r|flag|FLAG_STATERESET|Reset the state file|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output, show arguments|"    
        "moddir||value|VAL_MODDIR|Override module directory|"
        "title||value|VAL_TITLE|Menu title to be displayed in the header|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        "  $TD_SCRIPT_NAME -d"
        ""
        "Show arguments:"
        "  $TD_SCRIPT_NAME --verbose"
        "  $TD_SCRIPT_NAME -v"
    ) 

# --- local script functions ------------------------------------------------------
    # -- Data model ---------------------------------------------------------------
        # Directory where modules are found
        MOD_DIR="${MOD_DIR:-$TD_SCRIPT_DIR/mods}"
        
        # Each entry: "source|key|group|label|handler|flags"
        declare -a TD_MENU_SPECS=()

        # Groups (display order is first-seen order)
        declare -a TD_MENU_GROUPS=()

        # Menu loop control
        TD_MENU_EXIT=0

    # -- Compiled menu model (parallel arrays)
        declare -a TD_MENU_GROUPS=()
        declare -a TD_MENU_KEYS=()
        declare -a TD_MENU_GROUP=()
        declare -a TD_MENU_LABEL=()
        declare -a TD_MENU_HANDLER=()
        declare -a TD_MENU_FLAGS=()

        td_menu_reset_compiled() {
            TD_MENU_GROUPS=()
            TD_MENU_KEYS=()
            TD_MENU_GROUP=()
            TD_MENU_LABEL=()
            TD_MENU_HANDLER=()
            TD_MENU_FLAGS=()
        }

        td_menu_reset_specs() {
            TD_MENU_SPECS=()
        }

        td_menu_spec_add() {
            local spec="${1:-}"
            [[ -n "$spec" ]] || { sayfail "td_menu_spec_add: spec required"; return 2; }
            TD_MENU_SPECS+=("$spec")
        }

        td_menu_specs_add_many() {
            local s
            for s in "$@"; do
                td_menu_spec_add "$s"
            done
        }

        td_menu_key_exists() {
            local key="${1:-}"
            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                [[ "${TD_MENU_KEYS[$i]^^}" == "${key^^}" ]] && return 0
            done
            return 1
        }

        td_menu_group_seen_add() {
            local group="${1:-}"
            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                [[ "$g" == "$group" ]] && return 0
            done
            TD_MENU_GROUPS+=("$group")
        }

        td_menu_register_compiled_item() {
            local key="${1:-}" group="${2:-}" label="${3:-}" handler="${4:-}" flags="${5:-}"

            td_menu_group_seen_add "$group"

            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                if [[ "${TD_MENU_KEYS[$i]^^}" == "${key^^}" ]]; then
                    # Collision policy: later wins (overwrite)
                    TD_MENU_KEYS[$i]="$key"
                    TD_MENU_GROUP[$i]="$group"
                    TD_MENU_LABEL[$i]="$label"
                    TD_MENU_HANDLER[$i]="$handler"
                    TD_MENU_FLAGS[$i]="$flags"
                    return 0
                fi
            done

            TD_MENU_KEYS+=("$key")
            TD_MENU_GROUP+=("$group")
            TD_MENU_LABEL+=("$label")
            TD_MENU_HANDLER+=("$handler")
            TD_MENU_FLAGS+=("$flags")
        }

        td_menu_add_builtins_specs() {
            td_menu_specs_add_many \
                "V|Run modes|Toggle Verbose mode|td_menu_toggle_verbose|" \
                "D|Run modes|Toggle Dry-Run mode|td_menu_toggle_dryrun|" \
                "X|Run modes|Exit|td_menu_exit|"
        }

        td_menu_load_modules_specs() {
            if [[ ! -d "$MOD_DIR" ]]; then
                saywarning "No module directory: $MOD_DIR"
                return 0
            fi

            local f s
            shopt -s nullglob

            for f in "$MOD_DIR"/*.sh; do
                unset TD_MOD_MENU_SPECS || true
                # shellcheck disable=SC1090
                source "$f"

                if declare -p TD_MOD_MENU_SPECS >/dev/null 2>&1; then
                    local modbase
                    modbase="$(basename -- "$f")"

                    for s in "${TD_MOD_MENU_SPECS[@]}"; do
                        td_menu_spec_add "${modbase}|${s}"
                    done
                else
                    (( FLAG_VERBOSE )) && saydebug "Module provided no TD_MOD_MENU_SPECS: $(basename -- "$f")"
                fi
            done

            shopt -u nullglob
        }

       td_menu_build_from_specs() {
            td_menu_reset_compiled

            local spec src key group label handler flags
            local -a parts=()
            local auto=1

            for spec in "${TD_MENU_SPECS[@]}"; do
                td_split_pipe "$spec" parts

                # Accept either:
                #   5 parts: key|group|label|handler|flags
                #   6 parts: src|key|group|label|handler|flags
                if (( ${#parts[@]} == 5 )); then
                    src=""
                    key="${parts[0]}"
                    group="${parts[1]}"
                    label="${parts[2]}"
                    handler="${parts[3]}"
                    flags="${parts[4]}"
                elif (( ${#parts[@]} == 6 )); then
                    src="${parts[0]}"
                    key="${parts[1]}"
                    group="${parts[2]}"
                    label="${parts[3]}"
                    handler="${parts[4]}"
                    flags="${parts[5]}"
                else
                    sayfail "Menu spec has invalid field count (${#parts[@]}): $spec"
                    continue
                fi

                [[ -n "$group"   ]] || { sayfail "Menu spec missing group: $spec"; continue; }
                [[ -n "$label"   ]] || { sayfail "Menu spec missing label: $spec"; continue; }
                [[ -n "$handler" ]] || { sayfail "Menu spec missing handler: $spec"; continue; }

                if [[ -z "$key" ]]; then
                    while td_menu_key_exists "$auto"; do
                        auto=$((auto + 1))
                    done
                    key="$auto"
                    auto=$((auto + 1))
                fi

                td_menu_register_compiled_item "$key" "$group" "$label" "$handler" "${flags:-}"
            done
        }

        # -- td_menu_render -------------------------------------------------------
            # Render the menu using SolidgroundUX printing primitives.
            #
            # Notes:
            #   - Uses td_print_titlebar, td_print_sectionheader, td_print, td_print_fill.
            #   - Disabled items are shown with "disabled" color (TUI_DISABLED).
        td_menu_render() {
            local _pad=2
            local _tpad=$((_pad + 3))

            clear

            # Optional: show args in verbose
            if (( FLAG_VERBOSE )); then
                td_showarguments
                td_print
            fi

            td_print_titlebar --text "$MNU_TITLE" --right "$RUN_MODE" 
            td_print

            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                td_print_sectionheader --text "$g" --pad "$_pad" --padend 1

                local i
                for i in "${!TD_MENU_KEYS[@]}"; do
                    [[ "${TD_MENU_GROUP[$i]}" == "$g" ]] || continue

                    local key="${TD_MENU_KEYS[$i]}"
                    local label="${TD_MENU_LABEL[$i]}"
                    local flags="${TD_MENU_FLAGS[$i]}"

                    if td_menu_is_disabled "$flags"; then
                        td_print_fill --left "${key}) ${label}" --leftclr "$TUI_DISABLED" --padleft "$_tpad"
                    else
                        td_print --text "${key}) ${label}" --pad "$_tpad"
                    fi
                done

                td_print
            done
        }

        # -- td_menu_dispatch -----------------------------------------------------
            # Dispatch a menu choice to its handler.
            #
            # Behavior:
            #   - Validates the key
            #   - Checks disabled policy
            #   - Ensures handler exists (declare -F)
            #   - Calls handler
        td_menu_dispatch() {
            local choice="${1:-}"
            local idx=""

            [[ -n "$choice" ]] || { saywarning "No selection."; return 0; }

            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                if [[ "${TD_MENU_KEYS[$i]^^}" == "${choice^^}" ]]; then
                    idx="$i"
                    break
                fi
            done

            [[ -n "$idx" ]] || { saywarning "Invalid option: $choice"; return 0; }

            local handler="${TD_MENU_HANDLER[$idx]}"
            local flags="${TD_MENU_FLAGS[$idx]}"

            if td_menu_is_disabled "$flags"; then
                saywarning "Option '${choice^^}' is disabled in the current mode."
                return 0
            fi

            if ! declare -F "$handler" >/dev/null 2>&1; then
                sayfail "Handler not found: $handler"
                return 1
            fi

            "$handler"
        }

        # -- td_menu_is_disabled --------------------------------------------------
            # Return 0 if the menu item should be shown as disabled in the current run mode.
            #
            # Supported flags (extend as you like):
            #   - disabled               Always disabled
            #   - disabled_if_dryrun      Disabled when FLAG_DRYRUN is true
            #
            # Usage:
            #   if td_menu_is_disabled "$flags"; then ...
        td_menu_is_disabled() {
            local flags="${1:-}"

            [[ ",$flags," == *",disabled,"* ]] && return 0
            if (( FLAG_DRYRUN )) && [[ ",$flags," == *",disabled_if_dryrun,"* ]]; then
                return 0
            fi
            return 1
        }

        # --- td_menu_refresh_runmodes ---------------------------------------------------
            # Refresh dynamic runmode menu labels (Verbose/Dryrun) so they show ON/OFF status.
            # Call this right before rendering the menu.
        td_menu_refresh_runmodes() {
            local verb_onoff
            local dry_onoff

            if (( FLAG_VERBOSE )); then
                verb_onoff="${TUI_ENABLED}ON${RESET}"
            else
                verb_onoff="${TUI_DISABLED}OFF${RESET}"
            fi

            if (( FLAG_DRYRUN )); then
                dry_onoff="${TUI_ENABLED}ON${RESET}"
            else
                dry_onoff="${TUI_DISABLED}OFF${RESET}"
            fi

            td_menu_set_label "V" "Toggle Verbose mode (${verb_onoff})"
            td_menu_set_label "D" "Toggle Dry-Run mode (${dry_onoff})"
        }

        # --- td_menu_set_label -----------------------------------------------------------
            # Update the label text for an already-registered menu item by key (case-insensitive).
            # Useful for dynamic menu text (run modes, status indicators, etc.).
            # Usage: td_menu_set_label "V" "Toggle Verbose mode (ON)"
        td_menu_set_label() {
            local key="$1"
            local label="$2"

            [[ -n "${key:-}" ]]   || { sayfail "td_menu_set_label: key required"; return 2; }
            [[ -n "${label:-}" ]] || { sayfail "td_menu_set_label: label required"; return 2; }

            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                if [[ "${TD_MENU_KEYS[$i]^^}" == "${key^^}" ]]; then
                    TD_MENU_LABEL[$i]="$label"
                    return 0
                fi
            done

            sayfail "td_menu_set_label: key not registered: $key"
            return 2
        }

        td_menu_toggle_verbose() {
            (( FLAG_VERBOSE )) && FLAG_VERBOSE=0 || FLAG_VERBOSE=1
            (( FLAG_VERBOSE )) && sayinfo "Verbose mode enabled." || sayinfo "Verbose mode disabled."
        }

        td_menu_toggle_dryrun() {
            (( FLAG_DRYRUN )) && FLAG_DRYRUN=0 || FLAG_DRYRUN=1
            td_update_runmode
            (( FLAG_DRYRUN )) && saywarning "Dry-Run mode enabled." || saywarning "Dry-Run mode disabled."
        }

        td_menu_exit() {
            TD_MENU_EXIT=1
        }

    # -- Helpers ------------------------------------------------------------------
        td_hub_resolve_moddir() {
            local raw="${VAL_MODDIR:-}"
            local hub_id=""

            # 1) Explicit moddir wins
            if [[ -n "$raw" ]]; then
                # Treat "./..." or "../..." as relative to script dir
                if [[ "$raw" == ./* || "$raw" == ../* ]]; then
                    MOD_DIR="$TD_SCRIPT_DIR/$raw"
                else
                    MOD_DIR="$raw"
                fi
                return 0
            fi

            # 2) Default: derive hub id
            hub_id="${TD_HUB_ID:-}"
            if [[ -z "$hub_id" ]]; then
                hub_id="$(td_slugify "${MNU_TITLE:-$TD_SCRIPT_NAME}")"
            fi

            # 3) Default module directory is based on hub_id
            MOD_DIR="$TD_SCRIPT_DIR/$hub_id"
        }
        # --- td_split_pipe
            # Split a pipe-delimited string into an array, preserving empty trailing fields.
            # Usage:
            #   local -a parts=()
            #   td_split_pipe "$spec" parts
        td_split_pipe() {
            local s="${1-}"
            local -n out="$2"

            out=()
            local rest="$s"

            while :; do
                out+=("${rest%%|*}")
                if [[ "$rest" == *"|"* ]]; then
                    rest="${rest#*|}"
                else
                    break
                fi
            done
        }

# === main() must be the last function in the script ==============================
    main() {
    # --- Bootstrap ---------------------------------------------------------------
        #   --ui            Initialize UI layer (ui_init after libs)
        #   --state         Load persistent state (td_state_load)
        #   --cfg           Load configuration (td_cfg_load)
        #   --needroot      Enforce execution as root
        #   --cannotroot    Enforce execution as non-root
        #   --args          Enable argument parsing (default: on; included for symmetry)
        #   --initcfg       Allow creation of missing config templates during bootstrap
        #
        #   --              End bootstrap options; remaining args are passed to td_parse_args
        td_bootstrap --state --needroot -- "$@"
        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi

    # --- Main script logic here --------------------------------------------------
       
        # -- Resolve menu title
            MNU_TITLE="${TD_SCRIPT_TITLE:-Solidground Script Hub}"
            if [[ -n "${VAL_TITLE:-}" ]]; then
                MNU_TITLE="${VAL_TITLE}"
            fi

        # --- Resolve module directory --------------------------------------------------
            td_hub_resolve_moddir

            saydebug "Using module directory: $MOD_DIR"
        # --- Build menu
            td_menu_reset_specs
            td_menu_add_builtins_specs
            td_menu_load_modules_specs
            td_menu_build_from_specs

        # --- Menu loop
            local choice=""
            while (( ! TD_MENU_EXIT )); do
                td_menu_refresh_runmodes
                td_menu_render

                # Build choices string dynamically (e.g. "1-9,A,B,D,V,X")
                # For now, accept any key and validate in dispatch.
                local choices
                choices="$(printf '%s,' "${TD_MENU_KEYS[@]}")"
                choices="${choices%,}"   # trim trailing comma

                td_choose --label "Select option" --choices "$choices" --var choice

                td_menu_dispatch "$choice"

                # Return to menu after action
                ask_autocontinue 2 || true
            done

            sayinfo "Exiting..."
    }

    # Run main with positional args only (not the options)
    main "$@"

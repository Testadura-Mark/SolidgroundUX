#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — script-hub.sh
# ----------------------------------------------------------------------------------
# Purpose : Generic, modular menu host for Testadura / SolidGround tooling
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Overview:
    #   Script Hub is a framework-level interactive console responsible for
    #   discovering, composing, and orchestrating modular command-line tools.
    #
    #   All functional behavior is provided by external modules. These modules
    #   register menu specifications declaratively into a shared runtime model.
    #   The hub itself contains no business logic and remains stable as the
    #   system evolves.
    #
# Key concepts:
    #   - Applets:
    #       Optional declarative configuration files (*.app.sh) that define
    #       hub identity, defaults, and module discovery paths.
    #
    #   - Modules:
    #       Self-contained scripts that register menu entries and handlers.
    #       Modules are sourced for registration only and must be free of
    #       side effects at load time.
    #
    #   - Menu model:
    #       Menu structure is treated as data (specifications + compilation),
    #       not control flow. Ordering, grouping, and rendering are separate
    #       concerns.
    #
# Design principles:
    #   - Strict separation of concerns:
    #       * Hub: orchestration and lifecycle
    #       * Modules: functionality
    #       * Framework: bootstrap, UI, argument parsing
    #
    #   - Declarative first:
    #       Modules and applets declare intent; the hub composes behavior.
    #
    #   - Predictable execution:
    #       No hidden side effects during discovery or registration.
    #
    #   - Extensible by discovery, not modification:
    #       New functionality is added by dropping modules into a directory,
    #       not by editing the hub itself.
# ==================================================================================

set -euo pipefail
# --- Find and source bootstrapper
    # Persist framework root for future runs (developer convenience).
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

    TD_SCRIPT_SETTINGS=(
        HUB_ROOT
        HUB_ID
        MOD_DIR
        MNU_TITLE
    )


# --- Using / imports -------------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )

# --- Argument specification and processing ---------------------------------------
    # --- Example: Arguments ------------------------------------------------------
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
    # ---------------------------------------------------------------------------
    TD_ARGS_SPEC=(
        "title|t|value|VAL_TITLE|Menu title to be displayed in the header|"
        "applet|a|value|VAL_APP|Path to an application configuration file|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        ""
        "Show verbose logging:"
        "  $TD_SCRIPT_NAME --verbose"
    ) 

# --- local script functions ------------------------------------------------------
    # -- Data model
       # File locations for *.app.sh and hub-modules
        HUB_ROOT="${HUB_ROOT:-$TD_SCRIPT_DIR/hub}"
        HUB_ID="${HUB_ID:-$TD_SCRIPT_NAME}"
        MOD_DIR="${MOD_DIR:-}"   # resolved later

        # Each entry: "source|key|group|label|handler|flags"
        declare -a TD_MENU_SPECS=()

        # Groups (display order is first-seen order)
        declare -a TD_MENU_GROUPS=()

        # Menu loop control
        TD_MENU_EXIT=0

        # Compiled menu model (parallel arrays)
        declare -a TD_MENU_GROUPS=()
        declare -a TD_MENU_KEYS=()
        declare -a TD_MENU_GROUP=()
        declare -a TD_MENU_LABEL=()
        declare -a TD_MENU_HANDLER=()
        declare -a TD_MENU_FLAGS=()
        declare -a TD_MENU_WAIT=()

    # -- Compose menu
        # td_menu_spec_add
            # Register a single raw menu specification.
            # The spec must be a pipe-delimited string in one of the supported formats:
            #   "key|group|label|handler|flags"
            #   "source|key|group|label|handler|flags"
            # Specs are stored verbatim and processed later during menu build.
        td_menu_spec_add() {
            local spec="${1:-}"
            [[ -n "$spec" ]] || { sayfail "td_menu_spec_add: spec required"; return 2; }
            TD_MENU_SPECS+=("$spec")
        }
        # td_menu_specs_add_many
            # Register multiple menu specifications in one call.
            # Each argument is passed through td_menu_spec_add.
            # Convenience helper for builtins and module loaders.
        td_menu_specs_add_many() {
            local s
            for s in "$@"; do
                td_menu_spec_add "$s"
            done
        }
        # td_menu_group_seen_add
            # Register a menu group if it has not been seen before.
            # Groups are kept in first-seen order and drive section ordering
            # during menu rendering.
        td_menu_group_seen_add() {
            local group="${1:-}"
            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                [[ "$g" == "$group" ]] && return 0
            done
            TD_MENU_GROUPS+=("$group")
        }
        # td_menu_register_compiled_item
            # Register a fully compiled menu item into the parallel menu arrays.
            # If the key already exists, the existing entry is overwritten
            # Collision policy: later wins (should be rare after key normalization).
            # Also ensures the item's group is recorded in the group list.
        td_menu_register_compiled_item() {
            local key="${1:-}" group="${2:-}" label="${3:-}" handler="${4:-}" flags="${5:-}" wait="${6:-}"

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
                    TD_MENU_WAIT[$i]="$wait"
                    return 0
                fi
            done

            TD_MENU_KEYS+=("$key")
            TD_MENU_GROUP+=("$group")
            TD_MENU_LABEL+=("$label")
            TD_MENU_HANDLER+=("$handler")
            TD_MENU_FLAGS+=("$flags")
            TD_MENU_WAIT+=("$wait")
        }
        # td_menu_add_builtins_specs
            # Register built-in menu specifications provided by the hub itself.
            # Typically includes run mode toggles and exit actions.
            # Builtins are added before module specs so their keys are reserved.
        td_menu_add_builtins_specs() {
            td_menu_specs_add_many \
                "builtin|V|Run modes|Toggle Verbose mode|td_menu_toggle_verbose||2" \
                "builtin|D|Run modes|Toggle Dry-Run mode|td_menu_toggle_dryrun||2" \
                "builtin|X|Run modes|Exit|td_menu_exit||1"
        }
        # td_menu_reset_compiled
            # Reset the compiled menu model.
            # Clears all parallel arrays that represent the finalized menu
            # (keys, groups, labels, handlers, flags).
            # Call before rebuilding the menu from specs.
        td_menu_reset_compiled() {
            TD_MENU_GROUPS=()
            TD_MENU_KEYS=()
            TD_MENU_GROUP=()
            TD_MENU_LABEL=()
            TD_MENU_HANDLER=()
            TD_MENU_FLAGS=()
            TD_MENU_WAIT=()
        }
        # td_menu_reset_specs
            # Reset the raw menu specification list.
            # Removes all previously registered menu specs (from modules and builtins).
            # Typically called before reloading modules.
        td_menu_reset_specs() {
            TD_MENU_SPECS=()
        }

    # -- Assemble menu
        # td_menu_build_from_specs
            # Build the compiled menu model from raw menu specifications.
            #
            # Responsibilities:
            #   - Parse pipe-delimited menu specs
            #   - Validate required fields (group, label, handler)
            #   - Normalize menu keys:
            #       * auto-assign numeric keys if missing
            #       * auto-renumber keys on collision
            #       * enforce global key uniqueness
            #   - Track menu groups in first-seen order
            #   - Prepare menu items for later ordering and rendering
            #
            # This function establishes the menu's identity model.
            # Ordering and rendering are applied in later steps.
        td_menu_build_from_specs() {
            td_menu_reset_compiled

            local spec src key group label handler flags wait
            local -a parts=()

            # Track used keys (global) while building.
            # Store uppercase keys for case-insensitive matching.
            declare -A used_keys=()

            local auto=1

            # Temporary list: "group|weight|key|label|handler|flags"
            local -a items=()

            for spec in "${TD_MENU_SPECS[@]}"; do
                wait="" 
                td_split_pipe "$spec" parts

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
                elif (( ${#parts[@]} == 7 )); then
                    src="${parts[0]}"
                    key="${parts[1]}"
                    group="${parts[2]}"
                    label="${parts[3]}"
                    handler="${parts[4]}"
                    flags="${parts[5]}"
                    wait="${parts[6]}"
                else
                    sayfail "Menu spec has invalid field count (${#parts[@]}): $spec"
                    continue
                fi

                [[ -n "$group"   ]] || { sayfail "Menu spec missing group: $spec"; continue; }
                [[ -n "$label"   ]] || { sayfail "Menu spec missing label: $spec"; continue; }
                [[ -n "$handler" ]] || { sayfail "Menu spec missing handler: $spec"; continue; }

                # --- Normalize key: if empty OR already used => allocate next number
                local ukey="${key^^}"

                if [[ -z "$key" || -n "${used_keys[$ukey]+x}" ]]; then
                    if (( FLAG_VERBOSE )); then
                        if [[ -z "$key" ]]; then
                            saydebug "Menu item has no key; auto-assigning numeric key."
                        elif [[ -n "${used_keys[$ukey]+x}" ]]; then
                            saydebug "Menu key collision on '$key'; auto-assigning numeric key."
                        fi
                    fi
                    while :; do
                        local akey="${auto}"
                        local aukey="${akey^^}"
                        if [[ -z "${used_keys[$aukey]+x}" ]]; then
                            key="$akey"
                            ukey="$aukey"
                            used_keys["$ukey"]=1
                            auto=$((auto + 1))
                            break
                        fi
                        auto=$((auto + 1))
                    done
                else
                    used_keys["$ukey"]=1
                fi

                local weight
                weight="$(td_menu_key_weight "$key")"

                td_menu_group_seen_add "$group"
                items+=( "$group|$weight|$key|$label|$handler|$flags|$wait" )
            done

            # --- Determine group order (Run modes always last)
            local -a ordered_groups=()
            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                [[ "$g" == "Run modes" ]] && continue
                ordered_groups+=( "$g" )
            done
            ordered_groups+=( "Run modes" )

            # --- Build compiled arrays (ordering by group happens here; key sorting later)
            local entry grp w k l h f wait
            for grp in "${ordered_groups[@]}"; do
                for entry in "${items[@]}"; do
                    IFS='|' read -r g w k l h f wait <<< "$entry"
                    [[ "$g" == "$grp" ]] || continue
                    td_menu_register_compiled_item "$k" "$g" "$l" "$h" "$f" "$wait"
                done
            done
        }
        # td_menu_apply_ordering
            # Apply menu ordering policies:
            #   - "Run modes" group always last
            #   - Items sorted by group order, then by key weight (numeric order for numbers)
        td_menu_apply_ordering() {
            td_menu_force_group_last "Run modes"

            # Map group -> order index
            declare -A grp_idx=()
            local gi=0
            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                grp_idx["$g"]="$gi"
                gi=$((gi + 1))
            done

            # Build sortable records: "groupIndex|keyWeight|origIndex"
            local -a records=()
            local i w gix
            for i in "${!TD_MENU_KEYS[@]}"; do
                g="${TD_MENU_GROUP[$i]}"
                gix="${grp_idx[$g]:-9999}"
                w="$(td_menu_key_weight "${TD_MENU_KEYS[$i]}")"
                records+=( "${gix}|${w}|${i}" )
            done

            # Sort and rebuild arrays
            local sorted
            sorted="$(printf '%s\n' "${records[@]}" | sort -t'|' -k1,1n -k2,2 -k3,3n)"

            local -a n_keys=() n_group=() n_label=() n_handler=() n_flags=() n_wait=()
            local idx
            while IFS='|' read -r _ _ idx; do
                n_keys+=( "${TD_MENU_KEYS[$idx]}" )
                n_group+=( "${TD_MENU_GROUP[$idx]}" )
                n_label+=( "${TD_MENU_LABEL[$idx]}" )
                n_handler+=( "${TD_MENU_HANDLER[$idx]}" )
                n_flags+=( "${TD_MENU_FLAGS[$idx]}" )
                n_wait+=( "${TD_MENU_WAIT[$idx]}" )
            done <<< "$sorted"

            TD_MENU_KEYS=( "${n_keys[@]}" )
            TD_MENU_GROUP=( "${n_group[@]}" )
            TD_MENU_LABEL=( "${n_label[@]}" )
            TD_MENU_HANDLER=( "${n_handler[@]}" )
            TD_MENU_FLAGS=( "${n_flags[@]}" )
            TD_MENU_WAIT=( "${n_wait[@]}" )
        }
        # td_menu_load_modules_specs
            # Discover and load menu specifications from module scripts.
            # Each module is sourced and may define TD_MOD_MENU_SPECS.
            # Module-provided specs are prefixed with the module filename
            # as their source identifier.
            # Modules must be declarative and side-effect free at load time.
        td_menu_load_modules_specs() {
            if [[ ! -d "$MOD_DIR" ]]; then
                saywarning "No module directory: $MOD_DIR"
                return 0
            fi

            local f s
            shopt -s nullglob

            for f in "$MOD_DIR"/*.sh; do
                # Clear any previous module's exported specs before sourcing the next module.
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
        # td_menu_render
            # Render the menu using SolidgroundUX printing primitives.
            #
            # Notes:
            #   - Uses td_print_titlebar, td_print_sectionheader, td_print, td_print_fill.
            #   - Disabled items are shown with "disabled" color (TUI_DISABLED).
        td_menu_render() {
            local _pad=2
            local _tpad=$((_pad + 3))

            # Optional: show args in verbose
            if (( FLAG_VERBOSE )); then
                td_showarguments
                td_print
            else
                clear
            fi

            td_print_titlebar --text "$MNU_TITLE" --right "$RUN_MODE" 

            local g
            for g in "${TD_MENU_GROUPS[@]}"; do
                td_print_sectionheader --text "$g" --pad "$_pad" --padend 1

                local i
                for i in "${!TD_MENU_KEYS[@]}"; do
                    [[ "${TD_MENU_GROUP[$i]}" == "$g" ]] || continue

                    local key="${TD_MENU_KEYS[$i]}"
                    local label="${TD_MENU_LABEL[$i]}"
                    local flags="${TD_MENU_FLAGS[$i]}"

                    # Print an empty line before if item is X
                    saydebug "${g} ${key^^}"
                    if [[ "$g" == "Run modes" && "${key^^}" == "X" ]]; then
                        td_print
                    fi

                    if td_menu_is_disabled "$flags"; then
                        td_print_fill --left "${key}) ${label}" --leftclr "$TUI_DISABLED" --padleft "$_tpad"
                    else
                        td_print --text "${key}) ${label}" --pad "$_tpad"
                    fi
                done
                if [[ "$g" == "Run modes" && "${key^^}" == "X" ]]; then
                        td_print_sectionheader --border "-" 
                else
                    td_print
                fi
            done
        }

    # -- Menu helpers
        # td_menu_force_group_last
            # Ensure a specific group is the last entry in TD_MENU_GROUPS (if present).
        td_menu_force_group_last() {
            local target="$1"
            local -a tmp=()
            local g found=0

            for g in "${TD_MENU_GROUPS[@]}"; do
                [[ "$g" == "$target" ]] && { found=1; continue; }
                tmp+=("$g")
            done

            (( found )) && tmp+=("$target")
            TD_MENU_GROUPS=("${tmp[@]}")
        }
        # td_menu_is_disabled
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
        # td_menu_key_exists
            # Check whether a menu key is already registered in the compiled menu.
            # Comparison is case-insensitive.
            # Returns 0 if the key exists, 1 otherwise.
            # Used primarily during key normalization and collision detection.
        td_menu_key_exists() {
            local key="${1:-}"
            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                [[ "${TD_MENU_KEYS[$i]^^}" == "${key^^}" ]] && return 0
            done
            return 1
        }
        # td_menu_key_weight
            # Returns a sortable weight for a menu key.
            # Numeric keys sort numerically; non-numeric keys sort after numbers.
        td_menu_key_weight() {
            local key="$1"

            if [[ "$key" =~ ^[0-9]+$ ]]; then
                printf '%05d' "$key"
            else
                # Non-numeric keys go after numeric ones, keep stable order later
                printf 'Z_%s' "$key"
            fi
        }
        # td_menu_refresh_runmodes
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
        # td_menu_set_label 
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
        # td_menu_wait_after_action
            # Apply post-action wait behavior for a menu selection.
            #
            # Looks up the menu item by key and applies its configured wait time.
            # The wait time is defined declaratively in the menu specification
            # and represents the number of seconds to pause after the action
            # completes, allowing the user to review output.
            #
            # Behavior:
            #   - wait > 0 : pause for the given number of seconds
            #   - wait = 0 : return immediately to the menu
            #   - unset    : fall back to the hub default
            #
            # This keeps wait behavior centralized and avoids sleeps or pauses
            # inside individual menu action handlers.
        td_menu_wait_after_action() {
            local key="${1:-}"
            [[ -n "$key" ]] || return 0

            local i
            for i in "${!TD_MENU_KEYS[@]}"; do
                if [[ "${TD_MENU_KEYS[$i]^^}" == "${key^^}" ]]; then
                    local w="${TD_MENU_WAIT[$i]:-2}"

                    # Accept integer or decimal seconds (ask_autocontinue seems to accept decimals)
                    if [[ -n "$w" && ! "$w" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                        saywarning "Invalid wait value for key '${key^^}': '$w' (expected seconds)"
                        w=2
                    fi

                    (( $(printf '%.0f' "$w") > 0 )) && ask_autocontinue "$w" || true
                    return 0
                fi
            done

            # Key not found (should be rare because dispatch already validated)
            return 0
        }
    # -- Menu actions
        # td_menu_dispatch
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

        # td_menu_toggle_verbose
            # Menu action: toggle verbose mode.
            #
            # Toggles FLAG_VERBOSE between enabled and disabled states.
            # When enabled, additional diagnostic information is shown,
            # including argument dumps and debug output.
            # This action updates runtime behavior immediately.
        td_menu_toggle_verbose() {
            (( FLAG_VERBOSE )) && FLAG_VERBOSE=0 || FLAG_VERBOSE=1
            (( FLAG_VERBOSE )) && sayinfo "Verbose mode enabled." || sayinfo "Verbose mode disabled."
        }
        # td_menu_toggle_dryrun
            # Menu action: toggle dry-run mode.
            #
            # Toggles FLAG_DRYRUN between enabled and disabled states.
            # When enabled, actions are simulated and no changes are applied.
            # Also refreshes the displayed run mode indicator.
        td_menu_toggle_dryrun() {
            (( FLAG_DRYRUN )) && FLAG_DRYRUN=0 || FLAG_DRYRUN=1
            td_update_runmode
            (( FLAG_DRYRUN )) && saywarning "Dry-Run mode enabled." || saywarning "Dry-Run mode disabled."
        }
        # td_menu_exit
            # Menu action: exit the menu loop.
            #
            # Signals the main menu loop to terminate.
            # Control returns to the caller after cleanup and final messaging.
        td_menu_exit() {
            TD_MENU_EXIT=1
        }

    # -- Helpers
        # td_hub_create_app_stub
            # Create a new applet definition file with inferred defaults.
            #
            # Inference:
            #   - App base name is derived from the applet filename.
            #   - TD_SCRIPT_TITLE:
            #       * VAL_TITLE if provided
            #       * otherwise app name with '-' and '_' replaced by spaces
            #   - HUB_ID:
            #       * derived from app name (no character substitution)
            #   - MOD_DIR:
            #       * mods/<HUB_ID>
        td_hub_create_app_stub() {
            local app_file="$1"
            [[ -n "$app_file" ]] || return 1

            local base
            base="$(basename -- "$app_file")"
            base="${base%.app.sh}"

            local hub_id="$base"

            local app_dir="$HUB_ROOT/$hub_id"
            mkdir -p -- "$app_dir" || {
                sayfail "Failed to create applet directory: $app_dir"
                return 2
            }

            local title
            if [[ -n "${VAL_TITLE:-}" ]]; then
                title="$VAL_TITLE"
            else
                title="${base//[-_]/ }"
                # Capitalize first character only
                title="$(printf '%s\n' "$title" | sed 's/^\([a-z]\)/\U\1/')"
            fi

            printf '%s\n' '#!/usr/bin/env bash' >  "$app_file"
            printf '%s\n' '# ==================================================================================' >> "$app_file"
            printf '%s\n' '# Testadura Applet Definition' >> "$app_file"
            printf '%s\n' '# ----------------------------------------------------------------------------------' >> "$app_file"
            printf '%s\n' '# This file is sourced by script-hub.sh when --app/--applet is used.' >> "$app_file"
            printf '%s\n' '# Keep it declarative: variable assignments only (no side effects).' >> "$app_file"
            printf '%s\n' '# ==================================================================================' >> "$app_file"
            printf '\n' >> "$app_file"

            printf '%s\n' '# --- Identity ---------------------------------------------------------------' >> "$app_file"
            printf 'TD_SCRIPT_TITLE="%s"\n' "$title" >> "$app_file"
            printf '%s\n' 'TD_SCRIPT_DESC=""' >> "$app_file"
            printf '\n' >> "$app_file"

            printf '%s\n' '# Stable hub identifier (used for defaults and paths)' >> "$app_file"
            printf 'HUB_ID=%q\n' "$hub_id" >> "$app_file"
            printf '\n' >> "$app_file"

            printf '%s\n' '# --- Module directory -------------------------------------------------------' >> "$app_file"
            printf 'MOD_DIR=%q\n' "$app_dir" >> "$app_file"
            printf '\n' >> "$app_file"

            printf '%s\n' '# --- Optional defaults ------------------------------------------------------' >> "$app_file"
            printf '%s\n' '# Example:' >> "$app_file"
            printf '%s\n' '# SOME_FLAG_DEFAULT=1' >> "$app_file"

            chmod +x "$app_file" 2>/dev/null || true

        }
        # td_hub_load_app
            # Load (and optionally create) an applet definition file when --app/--applet is provided.
            #
            # Resolution rules:
            #   - If VAL_APP is an absolute path: use it verbatim.
            #   - Otherwise: resolve the applet definition as $HUB_ROOT/<app>.app.sh.
            #
            # Behavior:
            #   - If the resolved applet definition does not exist, a stub file is created
            #     under the hub root.
            #   - The applet file is then sourced to establish the hub namespace and
            #     apply identity and configuration defaults.
            #
            # Applet files are declarative and side-effect free at load time.
            # They define the identity and defaults for a specific hub namespace.
            #
            # Applet files may override hub-level defaults such as:
            #   - HUB_ID          (hub namespace identifier)
            #   - TD_SCRIPT_TITLE   (menu title)
            #   - TD_SCRIPT_DESC    (description text)
            #   - MOD_DIR           (module discovery override)
            #
            # Modules associated with an applet are discovered under:
            #   $HUB_ROOT/<HUB_ID>/
        td_hub_load_app() {
            local app="${VAL_APP:-}"
            [[ -n "$app" ]] || return 0

            local app_file=""

            # Absolute path → trust user
            if [[ "$app" == /* ]]; then
                app_file="$app"
            else
                if [[ ! "$app" =~ ^[A-Za-z0-9._-]+$ ]]; then
                    sayfail "Invalid app name: '$app'"
                    return 2
                fi
                app_file="$HUB_ROOT/$app.app.sh"
                HUB_ID="$app"
                HUB_DIR="$HUB_ROOT/$HUB_ID"
            fi

            if [[ ! -e "$app_file" ]]; then
                local dir
                dir="$(dirname -- "$app_file")"
                mkdir -p -- "$dir" || { sayfail "Failed to create directory: $dir"; return 2; }

                saywarning "Applet definition not found; creating: $app_file"
                td_hub_create_app_stub "$app_file"
                if td_dlg_autocontinue 10 "$HUB_ID.app.sh was created, choose O to open and edit 2" "APO"; then
                    rc=0
                else
                    rc=$?
                fi
                case "$rc" in
                    0) 
                        return 0
                        ;;
                    1) 
                        return 0
                        ;;
                    10)
                        saydebug "Opening $app_file for editing"
                        td_open_editor "$app_file"
                        ;;
                    *)
                        continue
                        ;;
                esac
                sayinfo "Applet stub created. Edit it to define title, module directory, etc."
            fi

            if [[ ! -r "$app_file" ]]; then
                sayfail "Applet definition not readable: $app_file"
                return 2
            fi

            (( FLAG_VERBOSE )) && saydebug "Loading applet definition: $app_file"
            
            # Sanitize file, make sure first character is #
            sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' "$app_file"

            # shellcheck disable=SC1090
            source "$app_file"
        }
        
        # td_hub_resolve_identity
            # Resolve hub identity fields (title/desc/etc) using precedence.
            #
            # Precedence:
            #   1) CLI overrides (VAL_TITLE etc)
            #   2) App file overrides (TD_SCRIPT_TITLE etc)
            #   3) Script defaults (hardcoded metadata in this script)
            #
            # Output:
            #   - Sets MNU_TITLE
            #   - (Optionally sets TD_SCRIPT_DESC in case you display it somewhere)
        td_hub_resolve_identity() {
            # Start from whatever is already set by script metadata / app file.
            MNU_TITLE="${TD_SCRIPT_TITLE:-Script Hub}"

            # CLI override wins.
            if [[ -n "${VAL_TITLE:-}" ]]; then
                MNU_TITLE="${VAL_TITLE}"
            fi
        }

        # td_hub_resolve_moddir
            # Resolve the module directory used for menu discovery.
            #
            # Precedence:
            #   1) CLI override: --moddir (VAL_MODDIR)
            #   2) App definition: MOD_DIR (may be set by the sourced applet file)
            #   3) Default:        $HUB_ROOT/<HUB_ID>
            #
            # Behavior:
            #   - The hub root ($HUB_ROOT) is ensured to exist and represents the
            #     canonical namespace for all applets.
            #   - When an applet is active, its default module directory is the
            #     directory named after HUB_ID under the hub root.
            #   - Relative paths (from CLI or app definition) are interpreted
            #     relative to $HUB_ROOT/<HUB_ID>.
            #   - Absolute paths are honored verbatim.
            #
            # Directory handling:
            #   - Framework-owned paths (hub root, applet default directories,
            #     and applet-relative paths) are created automatically if missing.
            #   - Absolute paths supplied via the CLI are treated as user-owned
            #     and must already exist; they are validated but not created.
        td_hub_resolve_moddir() {
            local raw=""
            local ensure=1

            # Ensure hub root exists (framework-owned)
            ensure_dir "$HUB_ROOT" || {
                sayfail "Failed to create hub root: $HUB_ROOT"
                return 2
            }

            # Precedence: CLI > app > default
            if [[ -n "${VAL_MODDIR:-}" ]]; then
                raw="${VAL_MODDIR}"
            elif [[ -n "${MOD_DIR:-}" ]]; then
                raw="${MOD_DIR}"
            fi

            # Resolve module directory
            if [[ -n "$raw" ]]; then
                if [[ "$raw" == /* ]]; then
                    MOD_DIR="$raw"
                    ensure=0   # user-supplied absolute path → validate only
                else
                    MOD_DIR="$HUB_ROOT/$HUB_ID/$raw"
                fi
            else
                MOD_DIR="$HUB_ROOT/$HUB_ID"
            fi

            # Ensure or validate
            local created_moddir=0

            if [[ ! -d "$MOD_DIR" ]]; then
                if (( ensure )); then
                    # Track whether we're creating the default applet directory
                    if [[ "$MOD_DIR" == "$HUB_ROOT/$HUB_ID" ]]; then
                        created_moddir=1
                    fi

                    ensure_writable_dir "$MOD_DIR" || {
                        sayfail "Failed to create module directory: $MOD_DIR"
                        return 2
                    }
                    saydebug "Ensured $MOD_DIR exists."
                else
                    sayfail "Module directory does not exist: $MOD_DIR"
                    return 2
                fi
            fi

            # If we created a new applet directory, also ensure the applet definition exists
            if (( created_moddir )); then
                local app_file="$HUB_ROOT/$HUB_ID.app.sh"
                if [[ ! -e "$app_file" ]]; then
                    saywarning "Applet definition not found; creating: $app_file"
                    td_hub_create_app_stub "$app_file" || return 2
                fi
            fi

            saydebug "Using module directory: $MOD_DIR"
        }
        # td_split_pipe
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
# --- Main Sequence ---------------------------------------------------------------
    # td_builtinarg_handler
        # Handle framework builtin arguments after bootstrap and script setup.
        #
        # This function enacts standard, framework-defined command-line flags that are
        # parsed during bootstrap and exposed as FLAG_* variables.
        #
        # Behavior:
        #   - Info-only builtins (e.g. --help, --showargs) are executed and cause an
        #     immediate exit.
        #   - Mutating builtins (e.g. --resetstate) are executed and execution continues.
        #   - Dry-run mode is respected where applicable.
        #
        # Intended usage:
        #   Call once from the executable script, after td_bootstrap and after the script
        #   has defined its argument specification and config/state context.
        #
        # Customization:
        #   Scripts may override this function to alter or extend builtin argument
        #   handling. If overridden, the script author is responsible for the resulting
        #   behavior.
    td_builtinarg_handler(){
        # Info-only builtins: perform action and EXIT.
        if (( FLAG_HELP )); then
            td_showhelp
            exit 0
        fi

        if (( FLAG_SHOWARGS )); then
            td_showarguments
            exit 0
        fi

        # Mutating builtins: perform action and CONTINUE.
        if (( FLAG_STATERESET )); then
            if (( FLAG_DRYRUN )); then
                sayinfo "Would have reset state file."
            else
                td_state_reset
                sayinfo "State file reset as requested."
            fi
        fi
    }
# --- main -----------------------------------------------------------------------
    # main MUST BE LAST function in script
        # Main entry point for the executable script.
        #
        # Execution flow:
        #   1) Invoke td_bootstrap to initialize the framework environment, parse
        #      framework-level arguments, and optionally load UI, state, and config.
        #   2) Abort immediately if bootstrap reports an error condition.
        #   3) Enact framework builtin arguments (help, showargs, state reset, etc.).
        #      Info-only builtins terminate execution; mutating builtins may continue.
        #   4) Continue with script-specific logic.
        #
        # Bootstrap options used here:
        #   --state         Load persistent state via td_state_load
        #   --needroot     Enforce execution as root
        #   --             End of bootstrap options; remaining args are script arguments
        #
        # Notes:
        #   - Builtin argument handling is centralized in td_builtinarg_handler.
        #   - Scripts may override builtin handling, but doing so transfers
        #     responsibility for correct behavior to the script author.
    main() {
        # -- Bootstrap
            td_bootstrap --state --needroot -- "$@"
            rc=$?
            if (( rc != 0 )); then
                exit "$rc"
            fi

            # -- Handle builtin arguments
                td_builtinarg_handler

            # -- UI
                td_print_titlebar

        # -- Main script logic    

            # Resolve applet (optional), then resolve identity + module directory
                td_hub_load_app
                td_hub_resolve_identity
                td_hub_resolve_moddir

                saydebug "Using module directory: $MOD_DIR Menu title: $MNU_TITLE"
            # Build menu
                td_menu_reset_specs
                td_menu_add_builtins_specs
                td_menu_load_modules_specs
                td_menu_build_from_specs
                td_menu_apply_ordering

            # Menu loop
                local choice=""
                while (( ! TD_MENU_EXIT )); do
                    td_menu_refresh_runmodes
                    td_menu_render

                    # Build choices string dynamically (e.g. "1-9,A,B,D,V,X")
                    # For now, accept any key and validate in dispatch.
                    local choices
                    choices="$(printf '%s,' "${TD_MENU_KEYS[@]}")"
                    choices="${choices%,}"   # trim trailing comma

                    td_choose --label "Select option" --choices "$choices" --var choice --displaychoices 0

                    td_menu_dispatch "$choice"
                    td_menu_wait_after_action "$choice"
                done

                sayinfo "Exiting..."
    }

    # Run main with positional args only (not the options)
    main "$@"

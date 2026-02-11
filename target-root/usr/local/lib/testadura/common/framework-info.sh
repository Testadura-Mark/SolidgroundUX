# =================================================================================
# Testadura Consultancy — framework-info.sh
# ---------------------------------------------------------------------------------
# Purpose    : Container for framework and environment info functions
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   This library contains "show/print" helpers that produce formatted diagnostics
#   for:
#     - script metadata
#     - framework metadata
#     - parsed arguments (script + framework)
#     - script configuration globals
#     - framework configuration globals
#
# Design notes:
#   - This module is presentation/orchestration: it does not load config files or
#     parse arguments; it only reads globals that other libraries maintain.
#   - Printing primitives are provided by ui.sh (td_print_*, td_print_labeledvalue).
#
# Inputs (globals expected):
#   - Metadata: TD_SCRIPT_*, TD_PRODUCT, TD_VERSION, TD_VERSION_DATE, TD_COMPANY, ...
#   - Arg specs: TD_ARGS_SPEC, TD_BUILTIN_ARGS, TD_POSITIONAL, and the FLAG_*/VALUE_*
#   - Config specs: TD_SCRIPT_GLOBALS, TD_FRAMEWORK_GLOBALS (pipe-separated entries)
#
# Provides:
#   - td_showenvironment
#   - td_print_metadata
#   - td_print_framework_metadata
#   - td_print_args
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    __lib_base="$(basename "${BASH_SOURCE[0]}")"
    __lib_base="${__lib_base%.sh}"
    __lib_base="${__lib_base//-/_}"
    __lib_guard="TD_${__lib_base^^}_LOADED"

    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    __section_indent=2
    __items_indent=3

    # Load guard
    [[ -n "${!__lib_guard:-}" ]] && return 0
    printf -v "$__lib_guard" '1'

# --- Internal helpers ------------------------------------------------------------
    # __td_print_arg_spec_entry
        #   Print one argument spec entry (from TD_ARGS_SPEC / TD_BUILTIN_ARGS) as:
        #     --long (-s) : VAR = <value>
        #
        #   Spec format:
        #     long|short|type|varname|help|choices
        #
        # Notes:
        #   - This is a display helper only; it does not parse args.
    __td_print_arg_spec_entry() {
        local entry="$1"

        local name short type varname help choices
        local label value

        IFS='|' read -r name short type varname help choices <<<"$entry"

        if [[ -n "${short:-}" ]]; then
            label="--$name (-$short)"
        else
            label="--$name"
        fi

        if [[ -n "${varname:-}" ]]; then
            value="${varname} = ${!varname-<unset>}"
        else
            value="<no var>"
        fi

        td_print_labeledvalue "$label" "$value" --pad "$__items_indent"
    }

    # __td_print_arg_spec_list
        #   Print all entries from a named spec array with a section header.
        #
        # Usage:
        #   __td_print_arg_spec_list "Script arguments"    "TD_ARGS_SPEC"
        #   __td_print_arg_spec_list "Framework arguments" "TD_BUILTIN_ARGS"
        #
        # Behavior:
        #   - If the array is undefined or empty, prints nothing.
    __td_print_arg_spec_list() {
        local header="$1"
        local array_name="$2"

        declare -p "$array_name" >/dev/null 2>&1 || return 0

        local -n specs_ref="$array_name"
        (( ${#specs_ref[@]} > 0 )) || return 0

       

        local entry
        local _printed_header=0
        for entry in "${specs_ref[@]}"; do
            if (( !_printed_header )); then
                td_print_sectionheader --text "$header" --padleft "$__section_indent"
                _printed_header=1
            fi
            __td_print_arg_spec_entry "$entry"
        done
    }
# --- Public API ------------------------------------------------------------------
    # td_print_cfg  
        #   Print config variables described by a "spec array" in two passes:
        #     - System globals: entries with scope 'system' or 'both'
        #     - User globals  : entries with scope 'user' (or 'usr') or 'both'
        #
        #   The spec array items are pipe-separated:
        #     scope|VARNAME|description|default
        #
        #   Scope semantics:
        #     system : system-level cfg (e.g. /etc)
        #     user   : user-level cfg (e.g. ~/.config)   (sometimes named 'usr' elsewhere)
        #     both   : common/shared keys (printed in both sections)
        #
        # Usage:
        #   td_print_cfg TD_FRAMEWORK_GLOBALS both
        #   td_print_cfg TD_SCRIPT_GLOBALS    system
        #   td_print_cfg TD_SCRIPT_GLOBALS    user
        #
        # Notes:
        #   - Values are resolved by indirection: ${!VARNAME}
        #   - If VARNAME is unset, the 'default' field is shown instead.
    td_print_cfg(){
        local -n source_array="$1"
        local filter="${2:-both}"

        
        __print_cfg_pass() {
            local header_text="$1"
            shift
            local -a accept_scopes=( "$@" )

            td_print_sectionheader --text "$header_text" --padleft "$__section_indent"

            local item scope name desc default
            for item in "${source_array[@]}"; do
                IFS='|' read -r scope name desc default <<<"$item"

                local ok=0
                local s
                for s in "${accept_scopes[@]}"; do
                    if [[ "$scope" == "$s" ]]; then
                        ok=1
                        break
                    fi
                done
                (( ok )) || continue

                local value="${!name:-$default}"
                td_print_labeledvalue "$name" "$value" --pad "$__items_indent"
            done
        }

        if ( [[ "$filter" == "system" ]] || [[ "$filter" == "both" ]] ); then
              __print_cfg_pass "System globals" system both
              td_print
        fi
        
        if ( [[ "$filter" == "user" ]] || [[ "$filter" == "both" ]] ); then
            __print_cfg_pass "User globals" user both
            td_print
        fi
    }
    # td_print_framework_metadata
        #   Print framework identity and versioning fields (product/company/license).
        #   Expects TD_PRODUCT, TD_VERSION, TD_VERSION_DATE, TD_COMPANY, TD_COPYRIGHT, TD_LICENSE.
    td_print_framework_metadata() {
        td_print_sectionheader --text "Framework metadata" --padleft "$__section_indent"
        td_print_labeledvalue "Product"      "$TD_PRODUCT" --pad "$__items_indent"
        td_print_labeledvalue "Version"      "$TD_VERSION" --pad "$__items_indent"
        td_print_labeledvalue "Release date" "$TD_VERSION_DATE" --pad "$__items_indent"
        td_print_labeledvalue "Company"      "$TD_COMPANY" --pad "$__items_indent"
        td_print_labeledvalue "Copyright"    "$TD_COPYRIGHT" --pad "$__items_indent"
        td_print_labeledvalue "License"      "$TD_LICENSE" --pad "$__items_indent"
        td_print
    }

    # td_print_metadata
        #   Print script identity fields (file/dir/version/description).
        #   Expects TD_SCRIPT_FILE, TD_SCRIPT_DESC, TD_SCRIPT_DIR, TD_SCRIPT_VERSION, TD_SCRIPT_BUILD.
    td_print_metadata(){
        td_print_sectionheader --text "Script metadata" --padleft "$__section_indent"
        td_print_labeledvalue "File"               "$TD_SCRIPT_FILE" --pad "$__items_indent"
        td_print_labeledvalue "Script description" "$TD_SCRIPT_DESC" --pad "$__items_indent"
        td_print_labeledvalue "Script dir"         "$TD_SCRIPT_DIR" --pad "$__items_indent"
        td_print_labeledvalue "Script version"     "$TD_SCRIPT_VERSION (build $TD_SCRIPT_BUILD)" --pad "$__items_indent"
        td_print
    }   

    # td_print_args
        #   Print a formatted overview of:
        #     - Script argument specs (TD_ARGS_SPEC)
        #     - Framework/builtin argument specs (TD_BUILTIN_ARGS)
        #     - Positional arguments (TD_POSITIONAL)
        #
        # Notes:
        #   - Shows current values by reading the varname field from each spec entry.
    td_print_args() {

        # Script args first
        td_print
        __td_print_arg_spec_list "Script arguments" "TD_ARGS_SPEC" --padleft "$__section_indent"

        # Builtins last
        td_print
        __td_print_arg_spec_list "Framework arguments" "TD_BUILTIN_ARGS" --padleft "$__section_indent"

        # Positional
        if declare -p TD_POSITIONAL >/dev/null 2>&1 && (( ${#TD_POSITIONAL[@]} > 0 )); then
            td_print
            td_print_sectionheader --text "Positional arguments" --padleft "$__section_indent"

            local i
            for i in "${!TD_POSITIONAL[@]}"; do
                td_print_labeledvalue "Arg[$i]" "${TD_POSITIONAL[$i]}" --pad "$__items_indent"
            done
        fi
        td_print
    }

    td_print_state(){
        
        td_state_list_keys | {
            local _printed_header=0
            while IFS='|' read -r key value; do
                if (( !_printed_header )); then
                    td_print_sectionheader --text "State variables" --padleft "$__section_indent"
                    _printed_header=1
                fi
                td_print_labeledvalue "$key" "$value" --pad "$__items_indent"
            done
            td_print
        }
    }

    # td_showenvironment
        #   Print a full diagnostic snapshot of the current script/framework context.
        #
        # Includes:
        #   - script title bar + metadata
        #   - parsed argument overview
        #   - script configuration globals (system/user)
        #   - framework metadata
        #   - framework configuration globals (system/user)
        #
        # Typical use:
        #   - invoked by a bootstrap flag such as --showenv
        #
        # Returns:
        #   0 always (display function; does not enforce state).
    td_showenvironment() {
        
        td_print_titlebar    
        td_print

        td_print_metadata

        td_print_sectionheader --text "Command line arguments"
        td_print_args        
        
        td_print_state

        td_print_sectionheader --text "Script configuration ($TD_SCRIPT_NAME.cfg)"
        td_print_cfg TD_SCRIPT_GLOBALS both

        td_print_sectionheader --border "-" --text "Framework configuration ($TD_FRAMEWORK_CFG_BASENAME)" 

        td_print_framework_metadata

        td_print_cfg TD_FRAMEWORK_GLOBALS both

        td_print_sectionheader --border "="

        return 0
    }

    
    

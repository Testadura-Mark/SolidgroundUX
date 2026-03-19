# ==================================================================================
# Testadura Consultancy — SolidGround Framework Info Library
# ----------------------------------------------------------------------------------
# Module  : framework-info.sh
# Purpose : Presentation and diagnostic helpers for framework, script, arguments,
#           configuration, and runtime state.
#
# Scope   :
#   - Read-only rendering of framework and script context
#   - Formatted output for diagnostics, debugging, and inspection
#   - Aggregation of metadata, arguments, configuration, and state
#
# Design  :
#   - Pure presentation layer (no parsing, no config loading)
#   - Depends on globals prepared by args.sh, cfg.sh, and bootstrap layers
#   - Uses ui.sh for all rendering primitives
#
# Notes   :
#   - Intended for diagnostics (e.g. --env, debug output)
#   - Safe to call at any point after bootstrap
#
# Author  : Mark Fieten
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
        #   # Typical usage at top of library file
        #   __td_lib_guard
        #   unset -f __td_lib_guard
        #
        # Notes:
        #   - Guard variable is derived dynamically (e.g. ui-glyphs.sh → TD_UI_GLYPHS_LOADED).
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
    : "${__section_indent:=2}"
    : "${__items_indent:=4}"
    
    # __td_print_arg_spec_entry
        # Purpose:
        #   Render a single TD_ARGS_SPEC / TD_BUILTIN_ARGS entry as a labeled value line.
        #
        # Arguments:
        #   $1  Spec entry string in format:
        #         name|short|type|varname|help|choices
        #
        # Inputs (globals):
        #   __items_indent  : indentation used for td_print_labeledvalue
        #
        # Behavior:
        #   - Builds an option label:
        #       --name (-s)  when short is present
        #       --name       otherwise
        #   - Resolves current value via indirect expansion of varname:
        #       varname = ${!varname-<unset>}
        #
        # Outputs:
        #   Prints one formatted line via td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Usage:
        #   __td_print_arg_spec_entry "debug|d|flag|FLAG_DEBUG|Enable debug mode|"
        #
        # Notes:
        #   - Display helper only; does not parse arguments.
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
        # Purpose:
        #   Print all argument spec entries from a named array, with a section header.
        #
        # Arguments:
        #   $1  Header text (e.g. "Script arguments").
        #   $2  Array variable name containing spec entries (e.g. "TD_ARGS_SPEC").
        #
        # Inputs (globals):
        #   __section_indent : indentation for section header
        #   __items_indent   : indentation for entries
        #
        # Behavior:
        #   - If the named array is undefined or empty: prints nothing.
        #   - Otherwise prints a section header once, then one line per entry.
        #
        # Outputs:
        #   Prints formatted section and entries.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Usage:
        #   __td_print_arg_spec_list "Script arguments" "TD_ARGS_SPEC"
        #
        # Notes:
        #   - Requires bash 4.3+ (nameref).
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
        # Purpose:
        #   Print configuration variables described by a spec array.
        #
        # Arguments:
        #   $1  Spec array name (nameref) containing entries:
        #         scope|VARNAME|description|default_or_extra
        #   $2  Filter scope selector: system | user | both (default: both)
        #
        # Inputs (globals):
        #   __section_indent, __items_indent
        #
        # Behavior:
        #   - Prints system and/or user globals depending on filter.
        #   - Resolves values via ${!name:-default}.
        #
        # Outputs:
        #   Prints formatted configuration values.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Usage:
        #   td_print_cfg TD_SCRIPT_GLOBALS both
        #   td_print_cfg TD_FRAMEWORK_GLOBALS system
        #
        # Notes:
        #   - Requires bash 4.3+ (nameref).
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
        # Purpose:
        #   Print framework identity and versioning metadata.
        #
        # Inputs (globals):
        #   TD_PRODUCT, TD_VERSION, TD_VERSION_DATE,
        #   TD_COMPANY, TD_COPYRIGHT, TD_LICENSE
        #
        # Behavior:
        #   - Prints a "Framework metadata" section.
        #
        # Outputs:
        #   Prints formatted metadata values.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_framework_metadata
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
        # Purpose:
        #   Print script identity and build metadata.
        #
        # Inputs (globals):
        #   TD_SCRIPT_FILE, TD_SCRIPT_DESC, TD_SCRIPT_DIR,
        #   TD_SCRIPT_VERSION, TD_SCRIPT_BUILD
        #
        # Outputs:
        #   Prints formatted metadata values.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_metadata
    td_print_metadata(){
        td_print_sectionheader --text "Script metadata" --padleft "$__section_indent"
        td_print_labeledvalue "File"               "$TD_SCRIPT_FILE" --pad "$__items_indent"
        td_print_labeledvalue "Script description" "$TD_SCRIPT_DESC" --pad "$__items_indent"
        td_print_labeledvalue "Script dir"         "$TD_SCRIPT_DIR" --pad "$__items_indent"
        td_print_labeledvalue "Script version"     "$TD_SCRIPT_VERSION (build $TD_SCRIPT_BUILD)" --pad "$__items_indent"
        td_print
    }   

    # td_print_args
        # Purpose:
        #   Print a formatted overview of parsed arguments and their current values.
        #
        # Inputs (globals):
        #   TD_ARGS_SPEC, TD_BUILTIN_ARGS, TD_POSITIONAL
        #
        # Behavior:
        #   - Prints script args, framework args, and positional args.
        #
        # Outputs:
        #   Prints formatted argument overview.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_args
    td_print_args() {

        # Script args first
        td_print
        __td_print_arg_spec_list "Script arguments" "TD_ARGS_SPEC"

        # Builtins last
        td_print
        __td_print_arg_spec_list "Framework arguments" "TD_BUILTIN_ARGS" 

        # Positional
        if declare -p TD_POSITIONAL >/dev/null 2>&1 && (( ${#TD_POSITIONAL[@]} > 0 )); then
            td_print
            td_print_sectionheader --text "Positional arguments" 

            local i
            for i in "${!TD_POSITIONAL[@]}"; do
                td_print_labeledvalue "Arg[$i]" "${TD_POSITIONAL[$i]}"
            done
        fi
        td_print
    }

    # td_print_state
        # Purpose:
        #   Print the current persistent state key/value pairs.
        #
        # Inputs:
        #   td_state_list_keys output (key|value)
        #
        # Outputs:
        #   Prints formatted state variables.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_state
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

    # td_print_license
        # Purpose:
        #   Print the framework license text, including acceptance status.
        #
        # Inputs (globals):
        #   TD_DOCS_DIR, TD_LICENSE_FILE, TD_LICENSE_ACCEPTED
        #
        # Behavior:
        #   - Prints license file if readable.
        #   - Shows acceptance status.
        #
        # Outputs:
        #   Prints formatted license text.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_license
    td_print_license() {
        
        local license_file="$TD_DOCS_DIR/$TD_LICENSE_FILE"
        local status_text="${TUI_INVALID}NOT ACCEPTED${RESET}"
        if (( TD_LICENSE_ACCEPTED )); then
            status_text="${TUI_VALID}[ACCEPTED]${RESET}"
        fi

        saydebug "td_print_license: license status is: $status_text"
        saydebug "td_print_license: looking for license file at: $license_file"

        if [[ -r "$license_file" ]]; then
            saydebug "td_print_license: found license file, printing"
            td_print
            td_print_sectionheader --text "$TD_PRODUCT license $status_text" --padleft "$__section_indent"
            td_print
            td_print_file "$license_file"
            td_print
            td_print_sectionheader --border "-"
        else
            saydebug "td_print_license: license file not found or not readable: $license_file"
        fi
    }

    # td_print_readme
        # Purpose:
        #   Print the framework README file if present.
        #
        # Inputs (globals):
        #   TD_DOCS_DIR
        #
        # Outputs:
        #   Prints README contents.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_readme
    td_print_readme() {
        local readme_file="$TD_DOCS_DIR/README.md"
        if [[ -r "$readme_file" ]]; then
            td_print_file "$readme_file"
        fi
    }

    # td_showenvironment
        # Purpose:
        #   Print a full diagnostic snapshot of the current script/framework context.
        #
        # Inputs (globals expected):
        #   Metadata, arguments, configuration specs, and state variables.
        #
        # Behavior:
        #   - Prints metadata, arguments, state, and configuration in structured order.
        #
        # Outputs:
        #   Prints complete environment overview.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_showenvironment
        #
        # Example:
        #   if (( FLAG_DEBUG )); then
        #       td_showenvironment
        #   fi
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

    
    

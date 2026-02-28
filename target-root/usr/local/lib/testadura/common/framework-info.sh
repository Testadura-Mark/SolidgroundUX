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
#   - Layout: __section_indent, __items_indent (provided by ui layer or defaulted here)
#
# Provides:
#   - td_showenvironment
#   - td_print_metadata
#   - td_print_framework_metadata
#   - td_print_args
#   - td_print_cfg
#   - td_print_state
#   - td_print_license
#   - td_print_readme
# =================================================================================
set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # Library-only: must be sourced, never executed.
    # Uses a per-file guard variable derived from the filename, e.g.:
    #   ui.sh      -> TD_UI_LOADED
    #   foo-bar.sh -> TD_FOO_BAR_LOADED
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
        # Notes:
        #   - Does not parse arguments; display only.
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
        #   Prints formatted section and entries via td_print_sectionheader and td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Requires:
        #   bash 4.3+ (nameref).
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
        #   __section_indent : indentation for section headers
        #   __items_indent   : indentation for entries
        #
        # Behavior:
        #   - Prints in up to two passes:
        #       "System globals" for scope in {system, both}
        #       "User globals"   for scope in {user, both}
        #     depending on filter.
        #   - For each entry, prints:
        #       name = ${!name:-default}
        #   - Emits a blank td_print line after each rendered pass.
        #
        # Outputs:
        #   Prints formatted output via td_print_sectionheader and td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Notes:
        #   - Uses an inner helper (__print_cfg_pass) scoped to this function.
        #   - 'desc' is currently parsed but not displayed.
        #
        # Requires:
        #   bash 4.3+ (nameref).
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
        #   - Prints a "Framework metadata" section header.
        #   - Prints each field as labeled values.
        #
        # Outputs:
        #   Prints formatted output via td_print_sectionheader and td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
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
        # Behavior:
        #   - Prints a "Script metadata" section header.
        #   - Prints labeled values for file, description, directory, version/build.
        #
        # Outputs:
        #   Prints formatted output via td_print_sectionheader and td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
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
        #   TD_ARGS_SPEC     : script argument spec array (optional)
        #   TD_BUILTIN_ARGS  : framework argument spec array (optional)
        #   TD_POSITIONAL    : array of remaining positional args (optional)
        #   For each spec entry: varname is resolved via ${!varname-<unset>}
        #
        # Behavior:
        #   - Prints:
        #       1) Script arguments (TD_ARGS_SPEC)
        #       2) Framework arguments (TD_BUILTIN_ARGS)
        #       3) Positional arguments (TD_POSITIONAL), if any
        #   - Each spec entry is rendered by __td_print_arg_spec_entry.
        #
        # Outputs:
        #   Prints formatted sections and labeled lines.
        #
        # Returns:
        #   0 always (display helper).
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
        #   td_state_list_keys output as lines formatted:
        #     key|value
        #
        # Behavior:
        #   - Reads td_state_list_keys and prints a "State variables" section header
        #     only if at least one key is present.
        #   - Prints each key/value as labeled values.
        #
        # Outputs:
        #   Prints formatted output via td_print_sectionheader and td_print_labeledvalue.
        #
        # Returns:
        #   0 always (display helper).
        #
        # Notes:
        #   - Runs the while-loop in a subshell due to the pipeline; local variables
        #     remain local to the grouped block as written.
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
        #   TD_DOCS_DIR, TD_LICENSE_FILE, TD_PRODUCT
        #   TD_LICENSE_ACCEPTED
        #   TUI_VALID, TUI_INVALID, RESET
        #
        # Behavior:
        #   - Builds license file path: "$TD_DOCS_DIR/$TD_LICENSE_FILE".
        #   - Computes status tag:
        #       [ACCEPTED] when TD_LICENSE_ACCEPTED != 0
        #       NOT ACCEPTED otherwise
        #   - If file is readable: prints header + file contents.
        #   - If not readable: emits debug diagnostics only.
        #
        # Outputs:
        #   Prints formatted output and file contents via td_print_* helpers.
        #
        # Returns:
        #   0 always (display helper).
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
        #   Print the framework README file (if present).
        #
        # Inputs (globals):
        #   TD_DOCS_DIR
        #
        # Behavior:
        #   - Looks for "$TD_DOCS_DIR/README.md".
        #   - If readable, prints it via td_print_file.
        #
        # Outputs:
        #   Prints file contents when present.
        #
        # Returns:
        #   0 always (display helper).
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
        #   - Metadata: TD_SCRIPT_*, TD_PRODUCT, TD_VERSION, ...
        #   - Args: TD_ARGS_SPEC, TD_BUILTIN_ARGS, TD_POSITIONAL, FLAG_*/VALUE_* vars
        #   - Config specs: TD_SCRIPT_GLOBALS, TD_FRAMEWORK_GLOBALS
        #   - Config names: TD_SCRIPT_NAME, TD_FRAMEWORK_CFG_BASENAME
        #
        # Behavior:
        #   Prints, in order:
        #     - Titlebar and script metadata
        #     - Command line arguments overview
        #     - Persistent state variables
        #     - Script configuration (system/user)
        #     - Framework configuration header + framework metadata
        #     - Framework configuration (system/user)
        #
        # Outputs:
        #   Prints formatted diagnostic output via td_print_* helpers.
        #
        # Returns:
        #   0 always (display helper).
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

    
    

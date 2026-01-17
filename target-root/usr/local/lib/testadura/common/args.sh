# ==================================================================================
# Testadura Consultancy — args.sh
# ----------------------------------------------------------------------------------
# Purpose    : Declarative CLI argument parsing based on TD_ARGS_SPEC
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
    #   Provides a minimal, deterministic argument parser driven by TD_ARGS_SPEC.
    #   The parser initializes option variables strictly from the spec and returns:
    #     HELP_REQUESTED  : 0|1
    #     TD_POSITIONAL   : array of remaining (non-option) arguments
    #
    #   Includes a basic help generator (td_show_help) based on TD_ARGS_SPEC.
    #
# Assumptions:
    #   - This is a FRAMEWORK library (may depend on the framework as it exists).
    #   - TD_ARGS_SPEC is defined by the caller before td_parse_args is invoked.
    #   - Option variables are created/initialized strictly from TD_ARGS_SPEC.
    #
# Rules / Contract:
    #   - Library-only: must be sourced, never executed.
    #   - No global shell-option changes (no set -euo pipefail).
    #   - Parsing is deterministic and explicit: only the outputs listed above plus
    #     spec-defined option variables are produced.
    #   - No UI behavior beyond basic help text (formatting belongs in ui layer).
    #   - No config loading, runtime detection, or application policy decisions.
    #
# TD_ARGS_SPEC format (array of strings, one per option):
#   "name|short|type|var|help|choices"
    #
    # Fields:
    #   name    : long option name WITHOUT leading "--" (e.g. "config")
    #   short   : short option WITHOUT leading "-" (e.g. "c") or empty
    #   type    : flag | value | enum
    #   var     : variable name to set (e.g. "CFG_FILE")
    #   help    : help text for td_show_help()
    #   choices : enum only: comma-separated allowed values (e.g. "dev,prd")
    #             for flag/value: leave empty (keep trailing '|')
    #
# Conventions:
    #   - flag  -> default 0, set to 1 if present
    #   - value -> consumes next token
    #   - enum  -> consumes next token and validates against choices
    #
# Public API:
    #   td_parse_args "$@"
    #   td_show_help
    #
# Non-goals:
    #   - Subcommands or nested argument trees
    #   - Conditional/computed defaults (beyond spec initialization)
    #   - UI formatting beyond basic help text
# ==================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_ARG_LOADED:-}" ]] && return 0
    TD_ARG_LOADED=1

# --- Helper funtions -------------------------------------------------------------
    # Split spec into internal temp variables
    __td_arg_split() {
        local spec="$1"
        IFS='|' read -r __td_name __td_short __td_type __td_var __td_help __td_choices <<< "$spec"
    }

    # Find the matching spec line for a given option token.
    # wanted:
    #   "config" (from --config) OR "c" (from -c)
    # Prints the full spec line to stdout if found.
    __td_arg_find_spec() {
        local wanted="$1"
        local spec

        for spec in "${TD_ARGS_SPEC[@]:-}"; do
            __td_arg_split "$spec"
            if [[ "$__td_name" == "$wanted" || "$__td_short" == "$wanted" ]]; then
                printf '%s\n' "$spec"
                return 0
            fi
        done

        return 1
    }

    # Validate an enum value against a comma-separated choices string.
    # Returns 0 if ok, 1 if not.
    __td_arg_validate_enum() {
        local value="$1"
        local choices_csv="$2"

        local choice
        local ok=0
        local choices_arr=()

        IFS=',' read -r -a choices_arr <<< "$choices_csv"
        for choice in "${choices_arr[@]}"; do
            if [[ "$choice" == "$value" ]]; then
                ok=1
                break
            fi
        done

        [[ "$ok" -eq 1 ]]
    }

    # Initialize option variables from ARGS_SPEC.
    # (idempotent: re-running sets them back to defaults)
    __td_arg_init_defaults() {
        if ! declare -p TD_ARGS_SPEC >/dev/null 2>&1; then
            return 0
        fi

        local spec
        for spec in "${TD_ARGS_SPEC[@]:-}"; do
            __td_arg_split "$spec"
            [[ -n "${__td_var:-}" && -n "${__td_type:-}" ]] || continue

            case "$__td_type" in
                flag)  printf -v "$__td_var" '0' ;;
                value) printf -v "$__td_var" ''  ;;
                enum)  printf -v "$__td_var" ''  ;;
            esac
        done
    }  
        # Print a key-value pair
    __td_print_global() {
        local name="$1"
        local value

        [[ -z "$name" ]] && return 0

        # Optional safety check
        if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            td_print_labeledvalue "$name" "<invalid name>"
            return 0
        fi

        # Safe under set -u
        value="${!name-<unset>}"
        td_print_labeledvalue "$name" "$value"
    }
# --- Public API ------------------------------------------------------------------
    # --- td_show_help ------------------------------------------------------------
        # Generate and print command-line help text derived from TD_ARGS_SPEC.
        #
        # Summary:
        #   Emits a standard "Usage / Options / Examples" help block for the current
        #   script, using declarative metadata instead of hardcoded option handling.
        #
        # Inputs (globals):
        #   TD_SCRIPT_NAME       : Optional; defaults to basename of TD_SCRIPT_FILE or $0
        #   TD_SCRIPT_FILE       : Optional; used to derive script name
        #   SCRIPT_DESC          : Optional; short script description
        #   SCRIPT_EXAMPLES[]    : Optional; example usage strings
        #   TD_ARGS_SPEC[]       : Optional; argument specification array
        #
        # Behavior:
        #   - Always prints a usage line and basic help header.
        #   - Prints "-h, --help" implicitly (handled by td_parse_args).
        #   - Iterates TD_ARGS_SPEC to render options, types, and help text.
        #   - Renders enum choices as "{a|b|c}".
        #   - Prints examples section if SCRIPT_EXAMPLES is defined.
        #
        # Outputs:
        #   - Writes formatted help text to stdout.
        #
        # Return value:
        #   - Always returns 0.
        #
        # Non-goals:
        #   - Argument parsing or validation
        #   - UI theming or colorization
        #   - Dynamic help generation based on runtime state
        # ------------------------------------------------------------------------------
    td_show_help() {
        local script_name="${TD_SCRIPT_NAME:-$(basename "${TD_SCRIPT_FILE:-$0}")}"

        echo "Usage: $script_name [options] [--] [args...]"
        echo
        echo "${SCRIPT_DESC:-No description available}"
        echo
        echo "Options:"
        echo "  -h, --help           Show this help and exit"

        if declare -p TD_ARGS_SPEC >/dev/null 2>&1; then
            local spec opt meta

            for spec in "${TD_ARGS_SPEC[@]:-}"; do
                __td_arg_split "$spec"

                # Skip malformed/empty spec entries
                [[ -n "${__td_name:-}" && -n "${__td_type:-}" && -n "${__td_var:-}" ]] || continue

                if [[ -n "${__td_short:-}" ]]; then
                    opt="-$__td_short, --$__td_name"
                else
                    opt="    --$__td_name"
                fi

                meta=""
                case "$__td_type" in
                    value) meta=" VALUE" ;;
                    enum)  meta=" {${__td_choices//,/|}}" ;;
                    flag)  meta="" ;;
                    *)     meta="" ;;
                esac

                printf "  %-20s %s\n" "$opt$meta" "${__td_help:-}"
            done
        fi

        if declare -p TD_SCRIPT_EXAMPLES >/dev/null 2>&1; then
            echo
            echo "Examples:"
            local ex
            for ex in "${TD_SCRIPT_EXAMPLES[@]:-}"; do
                printf "  %s\n" "$ex"
            done
        fi
    }

    # --- td_parse_args -----------------------------------------------------------
        # Parse command-line arguments according to TD_ARGS_SPEC.
        #
        # Summary:
        #   Parses CLI arguments using a declarative specification and produces a
        #   deterministic set of outputs: option variables, HELP_REQUESTED, and
        #   TD_POSITIONAL.
        #
        # Usage:
        #   td_parse_args "$@"
        #
        # Inputs:
        #   "$@"                 : Script arguments (post-bootstrap)
        #
        # Inputs (globals):
        #   TD_ARGS_SPEC[]       : Argument specification array
        #
        # Outputs (globals):
        #   HELP_REQUESTED       : 0|1 (set when -h/--help encountered)
        #   TD_POSITIONAL[]      : Remaining non-option arguments
        #   <option vars>        : Variables defined by TD_ARGS_SPEC (initialized)
        #
        # Behavior:
        #   - Initializes all option variables to defaults based on spec.
        #   - Supports:
        #       --long
        #       -s (short)
        #       flag | value | enum option types
        #   - Stops parsing on:
        #       "--"  → everything after is positional
        #       first non-option token → token and rest become positional
        #   - Validates enum values strictly against declared choices.
        #
        # Return values:
        #   0  Success
        #   1  Unknown option, missing value, or invalid enum value
        #
        # Non-goals:
        #   - Subcommand parsing
        #   - Option clustering (-abc)
        #   - Implicit defaults beyond spec initialization
        #   - UI formatting or help display
        # ------------------------------------------------------------------------------
    td_parse_args() {
        HELP_REQUESTED=0
        TD_POSITIONAL=()

        __td_arg_init_defaults
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -h|--help)
                    HELP_REQUESTED=1
                    shift
                    ;;

                --)
                    shift
                    TD_POSITIONAL+=("$@")
                    break
                    ;;

                --*)
                    # Long option
                if [[ ! -v TD_ARGS_SPEC ]]; then
                        echo "Unknown option: $1 (no TD_ARGS_SPEC defined)" >&2
                        return 1
                    fi

                    local opt spec
                    opt="${1#--}"
                    spec="$(__td_arg_find_spec "$opt" || true)"
                    [[ -n "${spec:-}" ]] || { echo "Unknown option: $1" >&2; return 1; }

                    __td_arg_split "$spec"

                    case "$__td_type" in
                        flag)
                            printf -v "$__td_var" '1'
                            shift
                            ;;

                        value)
                            [[ $# -ge 2 ]] || { echo "Missing value for --$opt" >&2; return 1; }
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        enum)
                            [[ $# -ge 2 ]] || { echo "Missing value for --$opt" >&2; return 1; }
                            if ! __td_arg_validate_enum "$2" "${__td_choices:-}"; then
                                echo "Invalid value '$2' for --$opt (allowed: ${__td_choices:-<none>})" >&2
                                return 1
                            fi
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        *)
                            echo "Invalid spec type '$__td_type' for --$opt" >&2
                            return 1
                            ;;
                    esac
                    ;;

                -?*)
                    # Short option (no clustering; "-abc" is treated as "a bc" not supported)
                    if [[ ! -v TD_ARGS_SPEC ]]; then
                        echo "Unknown option: $1 (no TD_ARGS_SPEC defined)" >&2
                        return 1
                    fi

                    local sopt spec
                    sopt="${1#-}"
                    spec="$(__td_arg_find_spec "$sopt" || true)"
                    [[ -n "${spec:-}" ]] || { echo "Unknown option: $1" >&2; return 1; }

                    __td_arg_split "$spec"

                    case "$__td_type" in
                        flag)
                            printf -v "$__td_var" '1'
                            shift
                            ;;

                        value)
                            [[ $# -ge 2 ]] || { echo "Missing value for -$sopt" >&2; return 1; }
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        enum)
                            [[ $# -ge 2 ]] || { echo "Missing value for -$sopt" >&2; return 1; }
                            if ! __td_arg_validate_enum "$2" "${__td_choices:-}"; then
                                echo "Invalid value '$2' for -$sopt (allowed: ${__td_choices:-<none>})" >&2
                                return 1
                            fi
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        *)
                            echo "Invalid spec type '$__td_type' for -$sopt" >&2
                            return 1
                            ;;
                    esac
                    ;;

                *)
                    # First positional => stop parsing and keep rest as positional
                    TD_POSITIONAL+=("$@")
                    break
                    ;;
            esac
        done

        return 0
    }

    # --- td_showarguments -----------------------------------------------------------
        # Display a formatted diagnostic overview of script, framework, and arguments.
        #
        # Summary:
        #   Prints a human-readable snapshot of the current execution context, including:
        #   - Script metadata
        #   - Framework/product metadata
        #   - System and user framework globals
        #   - Parsed arguments and flags
        #   - Positional arguments
        #
        # Intended use:
        #   - Debugging
        #   - Verbose / dry-run reporting
        #   - Support diagnostics
        #
        # Inputs (globals):
        #   Script metadata:
        #     TD_SCRIPT_FILE, TD_SCRIPT_NAME, TD_SCRIPT_DESC, TD_SCRIPT_DIR
        #     TD_SCRIPT_VERSION, TD_SCRIPT_BUILD
        #
        #   Framework metadata:
        #     TD_PRODUCT, TD_VERSION, TD_VERSION_DATE
        #     TD_COMPANY, TD_COPYRIGHT, TD_LICENSE
        #
        #   Argument data:
        #     TD_ARGS_SPEC[], TD_POSITIONAL[]
        #
        #   UI dependencies:
        #     td_print_subheader
        #     td_print_labeledvalue
        #     td_print_globals
        #
        # Behavior:
        #   - Outputs structured sections with subheaders.
        #   - Displays option variables defined by TD_ARGS_SPEC and their current values.
        #   - Displays positional arguments with index.
        #
        # Outputs:
        #   - Writes formatted diagnostic output to stdout.
        #
        # Return value:
        #   - Always returns 0.
        #
        # Non-goals:
        #   - Argument parsing or validation
        #   - Machine-readable output
        #   - Configuration mutation
        # ------------------------------------------------------------------------------
    td_showarguments() {
            
            _borderclr=${CLI_BORDER}
            printf "\n"
            td_print_sectionheader --text "Configuration data" --border "=" 
            td_print_sectionheader --text "Script info ($RUN_MODE)"
            td_print_labeledvalue "File" "$TD_SCRIPT_FILE"
            td_print_labeledvalue "Script" "$TD_SCRIPT_NAME"
            td_print_labeledvalue "Script description" "$TD_SCRIPT_DESC"
            td_print_labeledvalue "Script dir" "$TD_SCRIPT_DIR"
            td_print_labeledvalue "Script version" "$TD_SCRIPT_VERSION (build $TD_SCRIPT_BUILD)"
            printf "\n"
            
            td_print_sectionheader --text "Framework info"
            td_print_labeledvalue "Product"      "$TD_PRODUCT"
            td_print_labeledvalue "Version"      "$TD_VERSION"
            td_print_labeledvalue "Release date" "$TD_VERSION_DATE"
            td_print_labeledvalue "Company"      "$TD_COMPANY"
            td_print_labeledvalue "Copyright"    "$TD_COPYRIGHT"
            td_print_labeledvalue "License"      "$TD_LICENSE"
            printf "\n"

            td_print_sectionheader --text "System framework settings"
            td_print_globals sys
            printf "\n"

            td_print_sectionheader --text "User framework settings"
            td_print_globals usr
            printf "\n"
            
            td_print_sectionheader --text "Arguments / Flags:"

            local entry varname
            for entry in "${TD_ARGS_SPEC[@]:-}"; do
                IFS='|' read -r name short type var help choices <<< "$entry"
                varname="${var}"
                local label="--$name (-$short)"
                local value="$varname = ${!varname}"
                #td_print_labeledvalue "  --%s (-%s) " " %s = %s\n" "$name" "$short" "$varname" "${!varname:-<unset>}"
                td_print_labeledvalue "$label" "$value"
            done
            if (( ${#TD_POSITIONAL[@]} > 0 )); then
                td_print_sectionheader --label  "Positional arguments:"
            fi
            
            for i in "${!TD_POSITIONAL[@]}"; do
                td_print_labeledvalue "Arg[$i]" "${TD_POSITIONAL[i]}"
            done

            td_print_sectionheader --border "=" 
            printf '\n'
    }
   
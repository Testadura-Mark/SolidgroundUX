# ==================================================================================
# Testadura Consultancy — SolidGround Arguments Library
# ----------------------------------------------------------------------------------
# Module  : args.sh
# Purpose : Command-line argument parsing and normalization for SolidGround scripts.
#
# Scope   :
#   - Flag parsing (short and long options)
#   - Default value handling
#   - Argument validation and normalization
#
# Design  :
#   - Stateless parsing helpers
#   - No side effects beyond setting expected globals
#   - Consistent behavior across all SolidGround entry scripts
#
# Notes   :
#   - Intended to be sourced by executable scripts (exe-template)
#   - Keeps CLI behavior predictable and reusable
#
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================
set -uo pipefail
# --- Library guard ----------------------------------------------------------------
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

# --- Helper functions -------------------------------------------------------------
    # __td_arg_split
        # Purpose:
        #   Split a single TD_ARGS_SPEC definition into internal scratch variables.
        #
        # Behavior:
        #   - Reads one pipe-delimited spec string.
        #   - Assigns each field to the corresponding __td_* scratch variable.
        #   - Performs parsing only; does not validate semantic correctness.
        #
        # Arguments:
        #   $1  SPEC
        #       TD_ARGS_SPEC entry in the format:
        #       "name|short|type|var|help|choices"
        #
        # Outputs (globals):
        #   __td_name
        #   __td_short
        #   __td_type
        #   __td_var
        #   __td_help
        #   __td_choices
        #
        # Side effects:
        #   - Overwrites the current __td_* scratch field variables.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __td_arg_split "$spec"
        #
        # Examples:
        #   __td_arg_split "config|c|value|CFG_FILE|Config file path|"
        #   printf '%s\n' "$__td_var"
        #
        # Notes:
        #   - Intended as an internal helper for spec-driven parsing.
    __td_arg_split() {
        local spec="$1"
        IFS='|' read -r __td_name __td_short __td_type __td_var __td_help __td_choices <<< "$spec"
    }

    # __td_arg_find_spec
        # Purpose:
        #   Find the effective argument specification that matches a long or short option token.
        #
        # Behavior:
        #   - Iterates over TD_EFFECTIVE_ARGS_SPEC in order.
        #   - Splits each spec entry into scratch fields.
        #   - Matches against either the long name or short name.
        #   - Prints the full matching spec line when found.
        #
        # Arguments:
        #   $1  TOKEN
        #       Option token without leading dashes:
        #       - "config" for --config
        #       - "c"      for -c
        #
        # Inputs (globals):
        #   TD_EFFECTIVE_ARGS_SPEC
        #
        # Output:
        #   Prints the matching full spec line to stdout.
        #
        # Side effects:
        #   - Updates __td_* scratch variables while scanning.
        #
        # Returns:
        #   0 if a matching spec is found.
        #   1 if no matching spec exists.
        #
        # Usage:
        #   spec="$(__td_arg_find_spec "config")"
        #
        # Examples:
        #   spec="$(__td_arg_find_spec "c")" || return 1
        #   __td_arg_split "$spec"
    __td_arg_find_spec() {
        local wanted="$1"
        local spec

        for spec in "${TD_EFFECTIVE_ARGS_SPEC[@]:-}"; do
            __td_arg_split "$spec"
            if [[ "$__td_name" == "$wanted" || "$__td_short" == "$wanted" ]]; then
                printf '%s\n' "$spec"
                return 0
            fi
        done

        return 1
    }
    
    # __td_arg_validate_enum
        # Purpose:
        #   Validate whether a value is present in a comma-separated enum choice list.
        #
        # Behavior:
        #   - Splits the supplied CSV string into individual allowed values.
        #   - Compares the requested value against each entry.
        #   - Succeeds on the first exact match.
        #
        # Arguments:
        #   $1  VALUE
        #       Value to validate.
        #   $2  CHOICES_CSV
        #       Comma-separated allowed values (for example: "dev,prd").
        #
        # Returns:
        #   0 if VALUE is allowed.
        #   1 if VALUE is not found in CHOICES_CSV.
        #
        # Usage:
        #   __td_arg_validate_enum "$mode" "dev,prd,tst"
        #
        # Examples:
        #   if __td_arg_validate_enum "$2" "${__td_choices:-}"; then
        #       printf 'valid\n'
        #   fi
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

    # __td_arg_init_defaults
        # Purpose:
        #   Initialize option variables and build the effective argument specification list.
        #
        # Behavior:
        #   - Selects argument specs from TD_BUILTIN_ARGS, TD_ARGS_SPEC, or both.
        #   - Initializes each declared option variable according to its type:
        #       flag  -> 0
        #       value -> ""
        #       enum  -> ""
        #   - Rebuilds TD_EFFECTIVE_ARGS_SPEC in parse order.
        #
        # Arguments:
        #   $1  SOURCE
        #       Spec source selector:
        #       builtins | script | both
        #       Default: both
        #
        # Inputs (globals):
        #   TD_BUILTIN_ARGS
        #   TD_ARGS_SPEC
        #
        # Outputs (globals):
        #   TD_EFFECTIVE_ARGS_SPEC
        #
        # Side effects:
        #   - Creates or resets variables declared in the selected spec set.
        #   - Overwrites TD_EFFECTIVE_ARGS_SPEC.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __td_arg_init_defaults "both"
        #
        # Examples:
        #   __td_arg_init_defaults "script"
        #   __td_arg_init_defaults "${TD_ARGS_SOURCE:-both}"
        #
        # Notes:
        #   - Re-running the function resets declared option variables to their defaults.
        #   - Does not validate spec correctness beyond presence of type and variable name.
    __td_arg_init_defaults() {
        local source="${1:-both}"
        local -a args=()

        case "$source" in
            builtins)
                if declare -p TD_BUILTIN_ARGS >/dev/null 2>&1; then
                    args+=( "${TD_BUILTIN_ARGS[@]}" )
                fi
                ;;
            script)
                if declare -p TD_ARGS_SPEC >/dev/null 2>&1; then
                    args+=( "${TD_ARGS_SPEC[@]}" )
                fi
                ;;
            both|*)
                if declare -p TD_BUILTIN_ARGS >/dev/null 2>&1; then
                    args+=( "${TD_BUILTIN_ARGS[@]}" )
                fi
                if declare -p TD_ARGS_SPEC >/dev/null 2>&1; then
                    args+=( "${TD_ARGS_SPEC[@]}" )
                fi
                ;;
        esac

        local spec
        for spec in "${args[@]}"; do
            __td_arg_split "$spec"
            [[ -n "${__td_var:-}" && -n "${__td_type:-}" ]] || continue

            case "$__td_type" in
                flag)  printf -v "$__td_var" '0' ;;
                value) printf -v "$__td_var" ''  ;;
                enum)  printf -v "$__td_var" ''  ;;
            esac
        done

        TD_EFFECTIVE_ARGS_SPEC=( "${args[@]}" )
    }

# --- Public API -------------------------------------------------------------------
    __header_indent=2
    __text_indent=3

    # Global Arrays
    TD_BUILTIN_ARGS=(
        "dryrun|D|flag|FLAG_DRYRUN|Emulate only; do not perform actions|"
        "debug||flag|FLAG_DEBUG|Show debug messages|"
        "help|H|flag|FLAG_HELP|Show command-line help and exit|"
        "showargs|A|flag|FLAG_SHOWARGS|Print parsed arguments and exit|"
        "showcfg|C|flag|FLAG_SHOWCFG|Print configuration values and exit|"
        "showenv|E|flag|FLAG_SHOWENV|Print all info (args, cfg, state) and exit|"
        "showmeta|M|flag|FLAG_SHOWMETA|Shows framework and script metadata and exit|"
        "showstate|S|flag|FLAG_SHOWSTATE|Print state values and exit|"
        "showlicense|L|flag|FLAG_SHOWLICENSE|Show framework license and exit|"
        "showreadme||flag|FLAG_SHOWREADME|Show framework README and exit|"
        "statereset|R|flag|FLAG_STATERESET|Reset the state file|"
        "verbose|V|flag|FLAG_VERBOSE|Enable verbose output|"
    )

    TD_BUILTIN_EXAMPLES=(
         "  ${TD_SCRIPT_NAME:-<script>} --dryrun --verbose"
    ) 

    # td_show_help
        # Purpose:
        #   Render and display the generated help text for the current script.
        #
        # Behavior:
        #   - Builds help output from the active argument specification set.
        #   - Includes built-in arguments when configured to do so.
        #   - Renders usage, option descriptions, and related help sections.
        #   - Prints the final help text to stdout.
        #
        # Inputs (globals):
        #   TD_SCRIPT_NAME
        #   TD_SCRIPT_DESC
        #   TD_ARGS_SPEC
        #   TD_BUILTIN_ARGS
        #   TD_ARGS_SOURCE
        #   TD_EFFECTIVE_ARGS_SPEC
        #
        # Side effects:
        #   - Writes help text to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_show_help
        #
        # Examples:
        #   td_show_help
        #
        #   TD_ARGS_SOURCE="both"
        #   td_show_help
        #
        # Notes:
        #   - Intended for direct CLI help rendering.
        #   - Built-in options are only shown when included in the effective spec set.
    td_show_help() {
        local include_builtins="${1:-1}"
        local script_name="${TD_SCRIPT_NAME:-$(basename "${TD_SCRIPT_FILE:-$0}")}"
        local spaces="   "

        td_print_sectionheader --text "$script_name" 
        td_print "${spaces}Usage:" 
        td_print "\t$script_name [options] [--] [args...]\n" 
        td_print "${spaces}Description:" 
        td_print "\t${TD_SCRIPT_DESC:-No description available}\n" 

        td_print_sectionheader --text "Script options:" --padleft "$__header_indent"

        if declare -p TD_ARGS_SPEC >/dev/null 2>&1; then
            local spec opt meta

            for spec in "${TD_ARGS_SPEC[@]}"; do
                __td_arg_split "$spec"

                # Skip malformed/empty spec entries
                [[ -n "${__td_name:-}" && -n "${__td_type:-}" && -n "${__td_var:-}" ]] || continue

                if [[ -n "${__td_short:-}" ]]; then
                    opt="-$__td_short, --$__td_name"
                else
                    opt="--$__td_name"
                fi

                meta=""
                case "$__td_type" in
                    value) meta=" VALUE" ;;
                    enum)  meta=" {${__td_choices//,/|}}" ;;
                    flag)  meta="" ;;
                esac

                td_print_labeledvalue "$opt$meta" "${__td_help:-}" --pad "$__text_indent" --textclr "$RESET" --valueclr "$RESET" --width 18
            done
        fi

        if (( include_builtins )); then
            if declare -p TD_BUILTIN_ARGS >/dev/null 2>&1; then
                td_print
                td_print_sectionheader --text "Builtin options:" --padleft "$__header_indent"

                local spec opt meta

                for spec in "${TD_BUILTIN_ARGS[@]}"; do
                    __td_arg_split "$spec"

                    # Skip malformed/empty spec entries
                    [[ -n "${__td_name:-}" && -n "${__td_type:-}" && -n "${__td_var:-}" ]] || continue

                    # Avoid duplicating help line (already printed above)
                    if [[ "${__td_name}" == "help" ]]; then
                        continue
                    fi

                    if [[ -n "${__td_short:-}" ]]; then
                        opt="-$__td_short, --$__td_name"
                    else
                        opt="--$__td_name"
                    fi

                    meta=""
                    case "$__td_type" in
                        value) meta=" VALUE" ;;
                        enum)  meta=" {${__td_choices//,/|}}" ;;
                        flag)  meta="" ;;
                    esac

                    td_print_labeledvalue "$opt$meta" "${__td_help:-}" --pad "$__text_indent" --textclr "$RESET" --valueclr "$RESET" --width 18
                done
            fi 
        fi

        local -a examples=()

        if (( include_builtins )) && 
            declare -p TD_BUILTIN_EXAMPLES >/dev/null 2>&1 && 
            declare -p TD_SCRIPT_EXAMPLES  >/dev/null 2>&1; then
                td_array_union examples TD_SCRIPT_EXAMPLES TD_BUILTIN_EXAMPLES
        elif (( include_builtins )) && declare -p TD_BUILTIN_EXAMPLES >/dev/null 2>&1; then
            examples=( "${TD_BUILTIN_EXAMPLES[@]}" )
        elif declare -p TD_SCRIPT_EXAMPLES >/dev/null 2>&1; then
           examples=( "${TD_SCRIPT_EXAMPLES[@]}" )
        fi

        if (( ${#examples[@]} > 0 )); then
            td_print
            td_print_sectionheader --text "Examples:" --padleft "$__header_indent"

            local ex
            for ex in "${examples[@]}"; do
                td_print "$spaces$ex"
            done
        fi
        
        td_print
        td_print_sectionheader
    }

    # td_parse_args
        # Purpose:
        #   Parse command-line arguments according to the effective argument specification.
        #
        # Behavior:
        #   - Initializes option variables from the selected spec source.
        #   - Processes long and short options, including grouped short flags where supported.
        #   - Assigns values to the configured target variables.
        #   - Validates enum arguments against their declared choice list.
        #   - Collects positional arguments into TD_POSITIONAL_ARGS.
        #   - Applies unknown-argument handling according to TD_ARGMODE.
        #
        # Arguments:
        #   $@  ARGS
        #       Command-line arguments to parse.
        #
        # Inputs (globals):
        #   TD_ARGS_SPEC
        #   TD_BUILTIN_ARGS
        #   TD_ARGS_SOURCE
        #   TD_ARGMODE
        #
        # Outputs (globals):
        #   TD_EFFECTIVE_ARGS_SPEC
        #   TD_POSITIONAL_ARGS
        #   Variables declared in the selected argument specs
        #
        # Side effects:
        #   - Resets declared argument variables to their default state before parsing.
        #   - Rebuilds TD_EFFECTIVE_ARGS_SPEC.
        #   - Updates TD_POSITIONAL_ARGS.
        #   - May print diagnostics for invalid or unknown arguments.
        #
        # Returns:
        #   0 if parsing succeeds.
        #   1 if parsing fails due to invalid input or strict-mode argument rejection.
        #
        # Usage:
        #   td_parse_args "$@"
        #
        # Examples:
        #   td_parse_args "$@"
        #
        #   TD_ARGMODE="strict"
        #   td_parse_args "$@" || return 1
        #
        #   TD_ARGMODE="stop-at-unknown"
        #   td_parse_args "$@"
        #
        # Notes:
        #   - The effective spec set is determined by TD_ARGS_SOURCE.
        #   - Intended as the primary public entry point for argument parsing.
    td_parse_args() {

        local stop_at_unknown=0

        # Optional mode switch
        if [[ "${1-}" == "--stop-at-unknown" ]]; then
            stop_at_unknown=1
            shift
        fi

        # Default parse source (kept for compatibility if you still use it)
        local source="${TD_ARGS_SOURCE:-both}"

        # Reset positional array
        TD_POSITIONAL=()

        # Initialize variables from spec defaults
        __td_arg_init_defaults "$source"

        # Main parse loop
        while [[ $# -gt 0 ]]; do
            saydebug "Parsing argument $1"
            case "$1" in

                # Explicit end-of-options marker
                --)
                    shift
                    TD_POSITIONAL+=("$@")
                    break
                    ;;

                # Long option: --option
                --*)
                    local opt spec
                    opt="${1#--}"

                    spec="$(__td_arg_find_spec "$opt" || true)"

                    if [[ -z "${spec:-}" ]]; then
                        if (( stop_at_unknown )); then
                            TD_POSITIONAL+=("$@")
                            break
                        fi
                        echo "Unknown option: $1" >&2
                        return 1
                    fi

                    __td_arg_split "$spec"

                    case "$__td_type" in
                        flag)
                            printf -v "$__td_var" '1'
                            shift
                            ;;

                        value)
                            if [[ $# -lt 2 ]]; then
                                echo "Missing value for --$opt" >&2
                                return 1
                            fi
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        enum)
                            if [[ $# -lt 2 ]]; then
                                echo "Missing value for --$opt" >&2
                                return 1
                            fi

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

                # Short option: -o
                -?*)
                    local sopt spec
                    sopt="${1#-}"

                    # Only single short options supported
                    if [[ "${#sopt}" -ne 1 ]]; then
                        echo "Unknown option: $1" >&2
                        return 1
                    fi

                    spec="$(__td_arg_find_spec "$sopt" || true)"

                    if [[ -z "${spec:-}" ]]; then
                        if (( stop_at_unknown )); then
                            TD_POSITIONAL+=("$@")
                            break
                        fi
                        echo "Unknown option: $1" >&2
                        return 1
                    fi

                    __td_arg_split "$spec"

                    case "$__td_type" in
                        flag)
                            printf -v "$__td_var" '1'
                            shift
                            ;;

                        value)
                            if [[ $# -lt 2 ]]; then
                                echo "Missing value for -$sopt" >&2
                                return 1
                            fi
                            printf -v "$__td_var" '%s' "$2"
                            shift 2
                            ;;

                        enum)
                            if [[ $# -lt 2 ]]; then
                                echo "Missing value for -$sopt" >&2
                                return 1
                            fi

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

                # Positional or first unknown
                *)
                    TD_POSITIONAL+=("$@")
                    break
                    ;;
            esac
        done

        return 0
    }

    # td_builtinarg_handler
        # Purpose:
        #   Apply framework-defined built-in argument behavior after argument parsing.
        #
        # Behavior:
        #   - Evaluates built-in framework flags after td_parse_args has populated them.
        #   - Applies common runtime settings such as debug, verbose, dryrun, and logging.
        #   - Handles immediate built-in actions such as help or version display when present.
        #   - Exits early when a built-in action fully satisfies program flow.
        #
        # Inputs (globals):
        #   Built-in argument variables initialized through TD_BUILTIN_ARGS
        #   TD_SCRIPT_NAME
        #   TD_SCRIPT_VERSION
        #   TD_LOGFILE_ENABLED
        #   TD_LOG_TO_CONSOLE
        #
        # Side effects:
        #   - Updates framework runtime globals based on parsed built-in options.
        #   - May write informational output to stdout.
        #   - May terminate script execution early for handled built-in actions.
        #
        # Returns:
        #   0 if built-in handling succeeds.
        #
        # Usage:
        #   td_parse_args "$@" || return 1
        #   td_builtinarg_handler
        #
        # Examples:
        #   td_parse_args "$@" || return 1
        #   td_builtinarg_handler
        #
        #   td_parse_args "$@" || exit 1
        #   td_builtinarg_handler
        #   main
        #
        # Notes:
        #   - Intended to be called immediately after td_parse_args.
        #   - Centralizes framework-level option behavior so scripts do not need to duplicate it.
    td_builtinarg_handler(){
        # Info-only builtins: perform action and EXIT.
        if (( FLAG_HELP )); then
            td_show_help
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWARGS )); then
            td_print_args
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWMETA )); then
            td_print_metadata
            td_print
            td_print_framework_metadata
            sayend "Information displayed"
            exit 0
        fi
        
        if (( FLAG_SHOWCFG )); then
            td_print_sectionheader --text "Script configuration ($TD_SCRIPT_NAME.cfg)"
            td_print_cfg TD_SCRIPT_GLOBALS both
            td_print_sectionheader --border "-" --text "Framework configuration ($TD_FRAMEWORK_CFG_BASENAME)"
            td_print_cfg TD_FRAMEWORK_GLOBALS both
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWSTATE )); then
            td_print_state
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWENV )); then
            td_showenvironment
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWLICENSE )); then
            saydebug "Showing license as requested"
            td_print_license
            sayend "Information displayed"
            exit 0
        fi

        if (( FLAG_SHOWREADME )); then
            saydebug "Showing README as requested"
            td_print_readme
            sayend "Information displayed"
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






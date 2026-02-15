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
# --- Library guard ----------------------------------------------------------------
    # Derive a unique per-library guard variable from the filename:
    #   ui.sh        -> TD_UI_LOADED
    #   ui-sgr.sh    -> TD_UI_SGR_LOADED
    #   foo-bar.sh   -> TD_FOO_BAR_LOADED
    # Note:
    #   Guard variables (__lib_*) are internal globals by convention; they are not part
    #   of the public API and may change without notice.
    __lib_base="$(basename "${BASH_SOURCE[0]}")"
    __lib_base="${__lib_base%.sh}"
    __lib_base="${__lib_base//-/_}"
    __lib_guard="TD_${__lib_base^^}_LOADED"

    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
        echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
        exit 2
    }

    # Load guard (safe under set -u)
    [[ -n "${!__lib_guard-}" ]] && return 0
    printf -v "$__lib_guard" '1'

# --- Helper functions -------------------------------------------------------------
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

        for spec in "${TD_EFFECTIVE_ARGS_SPEC[@]:-}"; do
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
    __header_indent=2
    __text_indent=3
    
    # td_showhelp
        # Generate and print command-line help text derived from TD_ARGS_SPEC, with an
        # optional builtins section derived from TD_BUILTIN_ARGS.
        #
        # Usage:
        #   td_showhelp [include_builtins]
        #
        # Parameters:
        #   include_builtins : 1 to include framework builtins (default), 0 to omit.
        #
        # Notes:
        #   - "-h, --help" is printed implicitly (handled by td_parse_args).
        #   - Script options come from TD_ARGS_SPEC.
        #   - Builtin options (if enabled) come from TD_BUILTIN_ARGS and are shown in a
        #     separate section to clearly distinguish framework flags from script flags.
    td_showhelp() {
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

        if declare -p TD_SCRIPT_EXAMPLES >/dev/null 2>&1; then
            td_print
            td_print_sectionheader "Examples:" --padleft "$__header_indent"
            local ex
            for ex in "${TD_SCRIPT_EXAMPLES[@]}"; do
                td_print "$spaces$ex"
            done
        fi
        
        td_print
        td_print_sectionheader
    }


    # td_parse_args
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
   
    TD_BUILTIN_ARGS=(
        "dryrun|D|flag|FLAG_DRYRUN|Emulate only; do not perform actions|"
        'debug||flag|FLAG_DEBUG|Show debug messages'
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
        "  $TD_SCRIPT_NAME --dryrun --verbose --initcfg"
    ) 
    td_parse_args() {
        local source="${1:-both}"
        shift || true

        TD_POSITIONAL=()

        __td_arg_init_defaults "$source"

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --)
                    shift
                    TD_POSITIONAL+=("$@")
                    break
                    ;;

                --*)
                    local opt spec
                    opt="${1#--}"

                    spec="$(__td_arg_find_spec "$opt" || true)"

                    if [[ -z "${spec:-}" ]]; then
                        # Builtins pass: unknown option belongs to script => stop + hand off remainder
                        if [[ "$source" == "builtins" ]]; then
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
                    local sopt spec
                    sopt="${1#-}"

                    spec="$(__td_arg_find_spec "$sopt" || true)"

                    if [[ -z "${spec:-}" ]]; then
                        if [[ "$source" == "builtins" ]]; then
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
                    TD_POSITIONAL+=("$@")
                    break
                    ;;
            esac
        done

        return 0
    }

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
            td_print_args
            exit 0
        fi

        if (( FLAG_SHOWMETA )); then
            td_print_metadata
            td_print
            td_print_framework_metadata
            exit 0
        fi
        
        if (( FLAG_SHOWCFG )); then
            td_print_sectionheader --text "Script configuration ($TD_SCRIPT_NAME.cfg)"
            td_print_cfg TD_SCRIPT_GLOBALS both
            td_print_sectionheader --border "-" --text "Framework configuration ($TD_FRAMEWORK_CFG_BASENAME)"
            td_print_cfg TD_FRAMEWORK_GLOBALS both
            exit 0
        fi

        if (( FLAG_SHOWSTATE )); then
            td_print_state
            exit 0
        fi

        if (( FLAG_SHOWENV )); then
            td_showenvironment
            exit 0
        fi

        if (( FLAG_SHOWLICENSE )); then
            saydebug "Showing license as requested"
            td_print_license
            exit 0
        fi

        if (( FLAG_SHOWREADME )); then
            saydebug "Showing README as requested"
            td_print_readme
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






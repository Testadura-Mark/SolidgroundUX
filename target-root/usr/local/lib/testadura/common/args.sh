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
#     TD_POSITIONAL   : array of remaining (non-option) arguments
#
#   Includes a basic help generator (td_show_help) based on TD_ARGS_SPEC.
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - TD_ARGS_SPEC is defined by the caller before td_parse_args is invoked.
#   - Option variables are created/initialized strictly from the effective spec set
#     (TD_ARGS_SPEC and/or TD_BUILTIN_ARGS depending on TD_ARGS_SOURCE).
#
# Design rules:
#   - Libraries define functions and constants only.
#   - No auto-execution (must be sourced).
#   - Avoids changing shell options beyond strict-unset/pipefail (set -u -o pipefail).
#     (No set -e; no shopt.)
#   - No path detection or root resolution (bootstrap owns path resolution).
#   - No global behavior changes (UI routing, logging policy, shell options).
#   - Safe to source multiple times (idempotent load guard).
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
#   td_builtinarg_handler
#
# Non-goals:
#   - Subcommands or nested argument trees
#   - Conditional/computed defaults (beyond spec initialization)
#   - UI styling policy (colors/icons/themes). Help rendering may use td_print_* helpers.
# ==================================================================================
set -uo pipefail
# --- Library guard ----------------------------------------------------------------
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

# --- Helper functions -------------------------------------------------------------
    # __td_arg_split
        # Purpose:
        #   Split one TD_ARGS_SPEC line into internal scratch fields.
        #
        # Arguments:
        #   $1  Spec string: "name|short|type|var|help|choices"
        #
        # Outputs (globals):
        #   __td_name
        #   __td_short
        #   __td_type
        #   __td_var
        #   __td_help
        #   __td_choices
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Parsing only; does not validate field values.
    __td_arg_split() {
        local spec="$1"
        IFS='|' read -r __td_name __td_short __td_type __td_var __td_help __td_choices <<< "$spec"
    }

    # __td_arg_find_spec
        # Purpose:
        #   Locate the matching spec line for a given option token.
        #
        # Arguments:
        #   $1  Wanted option token (without dashes):
        #       - "config" from --config
        #       - "c"      from -c
        #
        # Inputs (globals):
        #   TD_EFFECTIVE_ARGS_SPEC
        #
        # Output:
        #   Prints the matching full spec line to stdout.
        #
        # Returns:
        #   0 if found, 1 if no match exists.
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
        #   Validate an enum value against a comma-separated list of allowed values.
        #
        # Arguments:
        #   $1  Value to validate.
        #   $2  Allowed values as CSV (e.g. "dev,prd").
        #
        # Returns:
        #   0 if value matches one allowed choice, 1 otherwise.
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
        #   Initialize option variables from the active argument specifications.
        #
        # Arguments:
        #   $1  Spec source selector:
        #       builtins | script | both (default: both)
        #
        # Inputs (globals):
        #   TD_BUILTIN_ARGS (optional)
        #   TD_ARGS_SPEC    (optional)
        #
        # Outputs (globals):
        #   - Creates/resets variables declared by spec:
        #       flag  -> 0
        #       value -> ""
        #       enum  -> ""
        #   - Builds TD_EFFECTIVE_ARGS_SPEC as the concatenated spec list in parse order.
        #
        # Behavior:
        #   - Idempotent: re-running resets variables back to default values.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Does not validate spec correctness beyond presence of var/type fields.
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
        #   Print command-line help derived from TD_ARGS_SPEC and (optionally) TD_BUILTIN_ARGS.
        #
        # Arguments:
        #   $1  include_builtins
        #       1 to include framework builtins (default), 0 to omit.
        #
        # Inputs (globals):
        #   TD_SCRIPT_NAME / TD_SCRIPT_FILE / TD_SCRIPT_DESC (optional)
        #   TD_ARGS_SPEC (optional)
        #   TD_BUILTIN_ARGS (optional)
        #   TD_SCRIPT_EXAMPLES (optional)
        #   TD_BUILTIN_EXAMPLES (optional)
        #
        # Behavior:
        #   - Prints Usage and Description sections.
        #   - Renders "Script options" from TD_ARGS_SPEC (if defined).
        #   - Renders "Builtin options" from TD_BUILTIN_ARGS (if enabled).
        #   - Merges and prints Examples when available.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - The help flag itself is handled by td_builtinarg_handler (after parse).
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
        #   Parse command-line arguments according to the active TD_ARGS_SPEC set.
        #
        # Arguments:
        #   --stop-at-unknown (optional)
        #     Stop parsing on the first unknown option and return remaining args as positional.
        #   $@  Command-line arguments to parse.
        #
        # Inputs (globals):
        #   TD_ARGS_SOURCE (optional; builtins | script | both; default: both)
        #   TD_BUILTIN_ARGS (optional)
        #   TD_ARGS_SPEC (optional)
        #
        # Outputs (globals):
        #   - Sets variables defined by the effective spec list (flags/values/enums).
        #   - TD_POSITIONAL contains remaining arguments after parsing.
        #   - TD_EFFECTIVE_ARGS_SPEC contains the spec list used for this parse.
        #
        # Behavior:
        #   - Supports long options (--name) and single short options (-n).
        #   - Stops at "--" and treats the remainder as positional.
        #   - In strict mode, unknown options are errors.
        #   - In stop-at-unknown mode, unknown options end parsing without error.
        #
        # Returns:
        #   0 on success.
        #   1 on error (unknown option in strict mode, missing value, invalid enum, invalid spec type).
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
        #   Execute framework builtin flags (FLAG_*) that were parsed during bootstrap.
        #
        # Inputs (globals):
        #   FLAG_HELP, FLAG_SHOWARGS, FLAG_SHOWMETA, FLAG_SHOWCFG, FLAG_SHOWSTATE,
        #   FLAG_SHOWENV, FLAG_SHOWLICENSE, FLAG_SHOWREADME, FLAG_STATERESET, FLAG_DRYRUN
        #   TD_SCRIPT_NAME, TD_FRAMEWORK_CFG_BASENAME
        #
        # Behavior:
        #   - Info-only builtins render output and exit immediately:
        #       help, showargs, showmeta, showcfg, showstate, showenv, showlicense, showreadme
        #   - Mutating builtins perform actions and continue:
        #       statereset (respects dryrun)
        #
        # Returns:
        #   Does not return when an info-only builtin is triggered (exits the process).
        #   Otherwise returns 0 after performing any mutating builtins.
        #
        # Notes:
        #   - Call once from the entry script after td_bootstrap and after script cfg/state setup.
        #   - Scripts may override this function; overriding scripts own resulting behavior.
    td_builtinarg_handler(){
        # Info-only builtins: perform action and EXIT.
        if (( FLAG_HELP )); then
            td_show_help
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






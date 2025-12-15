# shellcheck shell=bash
# ============================================================================
# Testadura — args.sh
# ---------------------------------------------------------------------------
# Purpose : Minimal argument parsing based on a declarative ARGS_SPEC array.
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design goals:
#   - No magic execution on source (library only).
#   - No global behavior changes (no set -euo pipefail here).
#   - Predictable output:
#       HELP_REQUESTED  : 0|1
#       TD_POSITIONAL   : array of remaining (non-option) args
#   - Option variables are created/initialized based on ARGS_SPEC.
#
# ARGS_SPEC format (array of strings, one per option):
#   "name|short|type|var|help|choices"
#
# Fields:
#   name    : long option name WITHOUT leading "--" (e.g. "config")
#   short   : short option WITHOUT leading "-" (e.g. "c") or empty
#   type    : flag | value | enum
#   var     : variable name to set (e.g. "CFG_FILE")
#   help    : help text for td_show_help()
#   choices : for enum only: comma-separated allowed values (e.g. "dev,prd")
#             for flag/value: keep empty (best: keep trailing '|')
#
# Conventions:
#   - flag  -> default 0, set to 1 if present
#   - value -> consumes next token
#   - enum  -> consumes next token and validates against choices
#
# Public API:
#   td_parse_args "$@"
#   td_show_help
# ============================================================================

[[ -n "${TD_ARG_LOADED:-}" ]] && return 0
TD_ARG_LOADED=1

# ----------------------------------------------------------------------------
# Internal: split spec into internal temp variables
# ----------------------------------------------------------------------------
__td_arg_split() {
    local spec="$1"
    IFS='|' read -r __td_name __td_short __td_type __td_var __td_help __td_choices <<< "$spec"
}

# ----------------------------------------------------------------------------
# Internal: find the matching spec line for a given option token.
# wanted:
#   "config" (from --config) OR "c" (from -c)
# Prints the full spec line to stdout if found.
# ----------------------------------------------------------------------------
__td_arg_find_spec() {
    local wanted="$1"
    local spec

    for spec in "${ARGS_SPEC[@]:-}"; do
        __td_arg_split "$spec"
        if [[ "$__td_name" == "$wanted" || "$__td_short" == "$wanted" ]]; then
            printf '%s\n' "$spec"
            return 0
        fi
    done

    return 1
}

# ----------------------------------------------------------------------------
# Help generator
# Uses:
#   SCRIPT_NAME, SCRIPT_DESC, SCRIPT_EXAMPLES (optional)
# ----------------------------------------------------------------------------
td_show_help() {
    local script_name="${SCRIPT_NAME:-$(basename "${SCRIPT_FILE:-$0}")}"

    echo "Usage: $script_name [options] [--] [args...]"
    echo
    echo "${SCRIPT_DESC:-No description available}"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help and exit"

    if declare -p ARGS_SPEC >/dev/null 2>&1; then
        local spec opt meta

        for spec in "${ARGS_SPEC[@]:-}"; do
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

    if declare -p SCRIPT_EXAMPLES >/dev/null 2>&1; then
        echo
        echo "Examples:"
        local ex
        for ex in "${SCRIPT_EXAMPLES[@]:-}"; do
            printf "  %s\n" "$ex"
        done
    fi
}

# ----------------------------------------------------------------------------
# Initialize option variables from ARGS_SPEC.
# (idempotent: re-running sets them back to defaults)
# ----------------------------------------------------------------------------
__td_arg_init_defaults() {
    if ! declare -p ARGS_SPEC >/dev/null 2>&1; then
        return 0
    fi

    local spec
    for spec in "${ARGS_SPEC[@]:-}"; do
        __td_arg_split "$spec"
        [[ -n "${__td_var:-}" && -n "${__td_type:-}" ]] || continue

        case "$__td_type" in
            flag)  printf -v "$__td_var" '0' ;;
            value) printf -v "$__td_var" ''  ;;
            enum)  printf -v "$__td_var" ''  ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# Validate an enum value against a comma-separated choices string.
# Returns 0 if ok, 1 if not.
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# Parse CLI args.
#
# Outputs:
#   HELP_REQUESTED=0|1
#   TD_POSITIONAL=(remaining args)
#
# Behavior:
#   - Stops option parsing at "--" and everything after becomes positional.
#   - Stops option parsing at first non-option token (adds it + rest to positional).
#     (If you prefer "continue scanning", we can change that.)
# ----------------------------------------------------------------------------
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
                if ! declare -p ARGS_SPEC >/dev/null 2>&1; then
                    echo "Unknown option: $1 (no ARGS_SPEC defined)" >&2
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
                if ! declare -p ARGS_SPEC >/dev/null 2>&1; then
                    echo "Unknown option: $1 (no ARGS_SPEC defined)" >&2
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

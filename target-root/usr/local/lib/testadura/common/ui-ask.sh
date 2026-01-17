# =================================================================================
# Testadura Consultancy — ui-ask.sh
# ---------------------------------------------------------------------------------
# Purpose    : Interactive prompting and input helpers (TTY-driven)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides standardized helpers for obtaining interactive input from the user:
#   - Prompts with labels and editable defaults (readline)
#   - Validation hooks (type/FS/network validators)
#   - Choice helpers (yes/no, ok/cancel, ok/redo/quit, continue, autocontinue)
#
#   Input is read directly from the terminal and is independent of stdin, so these
#   functions can be used safely in scripts that consume stdin (pipes/redirects).
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - A TTY is available for interactive input (/dev/tty or -t checks).
#   - Theme variables and RESET are available (e.g., CLR_LABEL, CLR_INPUT, CLR_TEXT,
#     CLR_DEFAULT, CLR_VALID, CLR_INVALID, RESET).
#   - Optional integration with ui-say.sh may exist (e.g., saydebug/sayfail), but
#     this module does not define message policy.
#
# Rules / Contract:
#   - Interactive by design; may block waiting for user input.
#   - No message formatting or logging policy (see ui-say.sh for output semantics).
#   - No application logic; callers decide what inputs mean and how to act on them.
#   - Safe to source multiple times (must be guarded).
#   - Library-only: must be sourced, never executed.
#
# Non-goals:
#   - Non-interactive/batch input processing
#   - Formatted message output or logging policy beyond minimal prompt rendering
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_UIASK_LOADED:-}" ]] && return 0
    TD_UIASK_LOADED=1

# --- ask -------------------------------------------------------------------------
    # Prompt for interactive input (reads from TTY, independent of stdin).
    #
    # Usage:
    #   ask [--label TEXT] [--default VALUE] [--colorize MODE]
    #       [--validate FUNC] [--echo] [--var NAME] [--] [LABEL]
    #
    # Options:
    #   --label TEXT       Prompt label (or 1st positional token)
    #   --default VALUE    Editable default (readline -i)
    #   --var NAME         Store result in NAME (else: prints value when --echo)
    #   --validate FUNC    Validator: FUNC "$value" (non-zero => re-prompt)
    #   --colorize MODE    none|label|input|both
    #   --echo             Echo value with ✓/✗ after entry
    #
    # Examples:
    #   ask --label "IP" --default "127.0.0.1" --validate validate_ip --var BIND_IP
    #   email="$(ask --label "Email" --default "user@example.com" --echo)"
ask(){
    local label="" var_name="" colorize="both"
    local validate_fn="" def_value="" echo_input=0

    # ---- parse options ------------------------------------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label)    label="$2"; shift 2 ;;
            --var)      var_name="$2"; shift 2 ;;
            --colorize) colorize="$2"; shift 2 ;;
            --validate) validate_fn="$2"; shift 2 ;;
            --default)  def_value="$2"; shift 2 ;;
            --echo)     echo_input=1; shift ;;
            --)         shift; break ;;
            *)          [[ -z "$label" ]] && label="$1"; shift ;;
        esac
    done

    # ---- resolve color mode -------------------------------------------------
    
    local label_color="$CLR_LABEL"
    local input_color="$CLR_INPUT"
    local default_color="$CLR_DEFAULT"

    case "$colorize" in
        label)
            label_color="$CLR_LABEL"
            ;;
        input)
            input_color="$CLR_INPUT"
            ;;
        both)
            label_color="$CLR_LABEL"
            input_color="$CLR_INPUT"
            ;;
        none|*) ;;
    esac
    
    # ---- build prompt -------------------------------------------------------
    local prompt=""
    if [[ -n "$label" ]]; then
        # label in label_color, then ": ", then switch to input_color for typing
        prompt+="${label_color}${label}${RESET}: ${input_color}"
    fi

    # ---- use bash readline pre-fill (-i) -----------------------------------
    local value ok
    if [[ -n "$def_value" ]]; then
        # LABEL is a real prompt (not editable), def_value is editable
        IFS= read -e -p "$prompt" -i "$def_value" value
        [[ -z "$value" ]] && value="$def_value"
    else
        # no default — simple prompt
        IFS= read -e -p "$prompt" value
    fi

    # reset color after the line, so the rest of the script isn't tinted
    printf "%b" "$RESET"

    # ---- validation ---------------------------------------------------------
    ok=1
    if [[ -n "$validate_fn" ]]; then
        if "$validate_fn" "$value"; then
            ok=1
        else
            ok=0
        fi
    fi

    # ---- echo with ✓ / ✗ ----------------------------------------------------
    if (( echo_input )); then
        if (( ok )); then
            printf "  %b%s%b %b✓%b\n" \
                "$input_color" "$value" "$RESET" \
                "$CLR_VALID" "$RESET"
        else
            printf "  %b%s%b %b✗%b\n" \
                "$CLR_INPUT" "$value" "$RESET" \
                "$CLR_INVALID" "$RESET"
        fi
    fi

    # Re-prompt on validation failure
    if (( !ok )); then
        printf "%bInvalid value. Please try again.%b\n" "$CLR_INVALID" "$RESET"
        ask "$@"   # recursive retry
        return
    fi

    # ---- return value -------------------------------------------------------
    if [[ -n "$var_name" ]]; then
        printf -v "$var_name" '%s' "$value"
    elif [[ "$echo_input" -eq 1 ]]; then
        printf "%s\n" "$value"
    fi
}
# --- ask shorthand ---------------------------------------------------------------
    # Convenience wrappers around ask() for common prompt patterns.
    ask_yesno(){
        local prompt="$1"
        local yn_response

        ask --label "$prompt [Y/n]" --default "Y" --var yn_response

        case "${yn_response^^}" in
            Y|YES) return 0 ;;
            N|NO)  return 1 ;;
            *)     return 1 ;; # fallback to No
        esac
    }
    ask_noyes() {
        local prompt="$1"
        local ny_response

        ask --label "$prompt [y/N]" --default "N" --var ny_response

        case "${ny_response^^}" in
            Y|YES) return 0 ;;
            N|NO)  return 1 ;;
            *)     return 1 ;;
        esac
    }
    ask_okcancel() {
        local prompt="$1"
        local oc_response

        ask --label "$prompt [OK/Cancel]" --default "OK" --var oc_response

        case "${oc_response^^}" in
            OK)     return 0 ;;
            CANCEL) return 1 ;;
            *)      return 1 ;;
        esac
    }

    # Example usage:
        #             
        #   decision=0
        #   ask_ok_redo_quit "Continue with domain join?" || decision=$?
        #   case "$decision" in
        #       0)  sayinfo "Proceding"
        #           break ;;
        #       1)  sayinfo "Redo" ;;
        #       2)  saycancel "Cancelled as per user request"; exit 1 ;;
        #       *)  sayfail "Unexpected response: $decision"; exit 2 ;;
        #   esac       
    ask_ok_redo_quit() {
        local prompt="$1"
        local orq_response=""

        ask --label "$prompt [OK/Redo/Quit]" --default "OK" --var orq_response

        # Trim whitespace (left + right)
        orq_response="${orq_response#"${orq_response%%[![:space:]]*}"}"
        orq_response="${orq_response%"${orq_response##*[![:space:]]}"}"

        local upper="${orq_response^^}"
        #saydebug "Response: '%s' -> '%s'\n" "$orq_response" "$upper"
        case "$upper" in
            ""|OK|O)        return 0  ;;  # Enter defaults to OK
            REDO|R)         return 1 ;;
            QUIT|Q|EXIT)    return 2 ;;
            *)              return 3 ;;
        esac
    }
    ask_continue() {
        local prompt="${1:-Press Enter to continue...}"
        read -rp "$prompt" _
    }
    ask_autocontinue() {
        # Usage: AutoContinue [seconds]
        # Returns:
        #   0 = continue
        #   1 = cancelled
        local seconds="${1:-5}"

        # Non-interactive: never block
        if [[ ! -t 0 || ! -t 1 ]]; then
            return 0
        fi

        local paused=0
        local key=""

        while true; do
            if (( paused )); then
                printf "${CLR_TEXT}\nPaused. Press any key to continue, or 'c' to cancel... ${RESET}"
                IFS= read -r -n 1 -s key
            else
                printf "\r\033[K${CLR_TEXT}Continuing in %ds… (any key=now, p=pause, c=cancel) ${RESET}" "$seconds"
                IFS= read -r -n 1 -s -t 1 key || key=""
            fi

            if [[ -n "$key" ]]; then
                case "$key" in
                    p|P)
                        paused=1
                        printf "\n"
                        continue
                        ;;
                    c|C|q|Q|$'\e')
                        printf "\n${CLR_CNCL}Cancelled.${RESET}\n"
                        return 1
                        ;;
                    *)
                        printf "\n"
                        return 0
                        ;;
                esac
            fi

            if (( ! paused )); then
                ((seconds--))
                if (( seconds <= 0 )); then
                    printf "\n"
                    return 0
                fi
            fi
        done
    } 
# --- File system validations -----------------------------------------------------
    validate_file_exists() {
        local path="$1"

        [[ -f "$path" ]] && return 0    # valid
        return 1                        # invalid
    }
    validate_path_exists() {
        [[ -e "$1" ]] && return 0
        return 1
    }
    validate_dir_exists() {
        [[ -d "$1" ]] && return 0
        return 1
    }
    validate_executable() {
        [[ -x "$1" ]] && return 0
        return 1
    }
    validate_file_not_exists() {
        [[ ! -f "$1" ]] && return 0
        return 1
    }

# --- Type validations ------------------------------------------------------------
    validate_int() {
        [[ "$1" =~ ^-?[0-9]+$ ]] && return 0
        return 1
    }
    validate_numeric() {
        [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && return 0
        return 1
    }
    validate_text() {
        [[ -n "$1" ]] && return 0
        return 1
    }
    validate_bool() {
        case "${1,,}" in
            y|yes|n|no|true|false|1|0)
                return 0 ;;
            *)
                return 1 ;;
        esac
    }
    validate_date() {
        [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && return 0
        return 1
    }
    validate_ip() {
        local ip="$1"
        local IFS='.'
        local -a octets

        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

        read -r -a octets <<< "$ip"

        for o in "${octets[@]}"; do
            (( o >= 0 && o <= 255 )) || return 1
        done

        return 0
    }
    validate_cidr(){ [[ $1 =~ ^([0-9]|[12][0-9]|3[0-2])$ ]]; }
    validate_slug() {
        [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] && return 0
        return 1
    }
    validate_fs_name() {
        [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && return 0
      return 1
    }
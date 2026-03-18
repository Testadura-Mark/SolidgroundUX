# ==================================================================================
# Testadura Consultancy — ui-ask.sh
# ----------------------------------------------------------------------------------
# Purpose    : Interactive prompting and input helpers (TTY-driven)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   Provides standardized helpers for obtaining interactive input from the user:
#     - Prompts with labels and editable defaults (readline-style UX)
#     - Optional validation hooks (type/FS/network validators)
#     - Choice helpers (yes/no, ok/cancel, ok/redo/quit, continue, autocontinue)
#
#   Designed for "interactive control" flows in CLI scripts and framework tools.
#
# Terminal I/O model:
#   - Prompts should read from the controlling terminal (e.g., /dev/tty) rather than
#     stdin, so these functions can be used in scripts that also consume stdin
#     (pipes/redirects). If no TTY is available, functions should either:
#       - return immediately with a sensible default, or
#       - fail explicitly (caller decides policy).
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - A TTY is available for interactive use (-t checks and/or /dev/tty).
#   - Theme variables and RESET exist (e.g., TUI_LABEL, TUI_INPUT, TUI_TEXT,
#     TUI_DEFAULT, TUI_VALID, TUI_INVALID, RESET).
#   - Optional integration with ui-say.sh may exist (saydebug/saywarning/sayfail),
#     but this module does not define message policy.
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
# Non-goals:
#   - Non-interactive/batch input processing
#   - Rich form UIs (menus, curses layouts, etc.)
#   - Centralized logging/formatting policy beyond minimal prompting
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
    
# --- Helpers ---------------------------------------------------------------------
    # __expand_choices
        # Purpose:
        #   Expand a comma-separated choice specification into individual allowed values.
        #
        # Arguments:
        #   $1  Choice spec string. Supports:
        #       - Literal tokens: "dev,acc,prod"
        #       - Simple ranges:  "A-Z", "0-9" (single ASCII [[:alnum:]] endpoints)
        #       - Optional whitespace around tokens: "A-Z, 1-3, foo"
        #
        # Behavior:
        #   - Splits on commas, trims whitespace per token.
        #   - Expands valid ASCII ranges X-Y into X..Y (inclusive).
        #   - Rejects reverse ranges (e.g. "Z-A") and skips them (warns if saywarning exists).
        #   - Leaves non-range tokens as-is (including empty tokens, if present in input).
        #
        # Outputs:
        #   Prints one expanded value per line (suitable for `mapfile -t`).
        #
        # Returns:
        #   0 always (expansion helper; invalid ranges are skipped, not fatal).
        #
        # Dependencies:
        #   saywarning (optional) : used when rejecting a range.
        #
        # Examples:
        #   mapfile -t opts < <(__expand_choices "A-C, x, 1-3")
        #   # opts => ( "A" "B" "C" "x" "1" "2" "3" )
    __expand_choices() {
        local spec="$1"
        local -a out=()
        local part start end i

        IFS=',' read -r -a parts <<< "$spec"

        for part in "${parts[@]}"; do
            # trim leading/trailing spaces
            part="${part#"${part%%[![:space:]]*}"}"
            part="${part%"${part##*[![:space:]]}"}"

            if [[ "$part" =~ ^([[:alnum:]])-([[:alnum:]])$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"

                local s e
                s=$(printf '%d' "'$start")
                e=$(printf '%d' "'$end")

                # Reject reverse ranges (strict is better for ops tools)
                if (( s > e )); then
                    saywarning "Invalid range: $part"
                    continue
                fi

                for (( i=s; i<=e; i++ )); do
                    # Convert ASCII code to actual character
                    out+=( "$(printf '\\%03o' "$i")" )
                done
            else
                out+=( "$part" )
            fi
        done

        # Interpret the \ooo sequences into characters
        for part in "${out[@]}"; do
            printf '%b\n' "$part"
        done
    }

    # td__choice_is_valid
        # Purpose:
        #   Validate a single choice against a td_choose-style choices list.
        #
        # Usage:
        #   if td__choice_is_valid "$value" "$choices"; then ...
        #
        # Arguments:
        #   $1  VALUE    Value to validate.
        #   $2  CHOICES  Comma-separated tokens and/or ranges.
        #
        # Behavior:
        #   - If CHOICES is empty: returns success.
        #   - Expands CHOICES via __expand_choices.
        #   - Compares case-insensitively.
        #
        # Returns:
        #   0 if valid
        #   1 if invalid
    td__choice_is_valid() {
        local value="${1-}"
        local choices="${2-}"
        local opt=""
        local -a expanded=()

        [[ -z "$choices" ]] && return 0

        mapfile -t expanded < <(__expand_choices "$choices")
        saydebug "td__choice_is_valid: choices=[$choices] expanded=[${expanded[*]}] value=[$value]"

        for opt in "${expanded[@]}"; do
            if [[ "${value^^}" == "${opt^^}" ]]; then
                return 0
            fi
        done

        return 1
    }

    # td_ask_action
        # Purpose:
        #   Shared helper for ask_* wrappers:
        #     - non-interactive default
        #     - optional timed dialog via td_dlg_autocontinue
        #     - normalize timed dialog outcome into a small generic action set
        #
        # Usage:
        #   action="$( td_ask_action DEFAULT_ACTION ENTER_ACTION PROMPT SECONDS DLG_KEYS)"
        #
        # Arguments:
        #   $1  DEFAULT_ACTION  Token used for non-interactive and timeout
        #                       (e.g. YES, NO, OK).
        #   $2  ENTER_ACTION    Token used when Enter is accepted by the timed dialog
        #                       (usually the same as DEFAULT_ACTION).
        #   $3  PROMPT          Prompt text including suffix
        #                       (e.g. "Proceed? [Y/n]").
        #   $4  SECONDS         Countdown seconds; 0 disables timed dialog.
        #   $5  DLG_KEYS        td_dlg_autocontinue key map for the timed phase only.
        #
        # Output:
        #   Prints one token:
        #       DEFAULT_ACTION / ENTER_ACTION / REDO / CANCEL / QUIT / TYPE
        #
        # Notes:
        #   - This helper implements only the reduced timed-dialog action model.
        #   - Wrapper-specific typed semantics (such as Y/N, OK/Cancel, etc.)
        #     are applied only after TYPE fallback.
        #   - Expects td_dlg_autocontinue to return:
        #       0=continue, 1=timeout, 2=cancel, 3=redo, 4=quit, 5=typed-fallback
    td_ask_action() {
        local default_action="${1:?}"
        local enter_action="${2:?}"
        local prompt="${3:-}"
        local seconds="${4:-0}"
        local dlg_keys="${5:-}"

        # Non-interactive: never block; return the wrapper default.
        td_has_tty || {
            printf '%s' "$default_action"
            return 0
        }

        if (( seconds > 0 )); then
            td_dlg_autocontinue "$seconds" "$prompt" "$dlg_keys"
            local rc=$?

            case "$rc" in
                0) printf '%s' "$enter_action" ;;
                1) printf '%s' "$default_action" ;;
                2) printf '%s' "CANCEL" ;;
                3) printf '%s' "REDO" ;;
                4) printf '%s' "QUIT" ;;
                5) printf '%s' "TYPE" ;;
                *) printf '%s' "TYPE" ;;
            esac
            return 0
        fi

        printf '%s' "TYPE"
    }
    
# --- ask -------------------------------------------------------------------------
    # ask
        # Purpose:
        #   Prompt for interactive input from the controlling terminal (/dev/tty),
        #   with optional defaulting, validation, and result delivery.
        #
        # Usage:
        #   ask [--label TEXT] [--default VALUE] [--colorize MODE]
        #       [--validate FUNC] [--echo] [--var NAME] [--] [LABEL]
        #
        # Arguments:
        #   LABEL (positional) : used as label when --label is omitted.
        #
        # Options:
        #   --label TEXT       Prompt label text.
        #   --default VALUE    Editable default (readline -i). Empty entry uses default.
        #   --validate FUNC    Validation callback invoked as: FUNC "$value"
        #                      - return 0   => accept
        #                      - return !=0 => reject and re-prompt
        #   --colorize MODE    none|label|input|both (default: both)
        #   --var NAME         Store the accepted value into shell variable NAME.
        #   --echo             Additionally echo the typed value with ✓/✗ feedback to /dev/tty.
        #                      (Also prints the accepted value to stdout when --var is not used.)
        #
        # Inputs (globals):
        #   Theme: TUI_LABEL, TUI_INPUT, TUI_VALID, TUI_INVALID, RESET
        #
        # Behavior:
        #   - Reads from /dev/tty via `read -u`, not stdin (safe in piped/redirected scripts).
        #   - Uses readline editing (-e) and optional prefill (-i).
        #   - If validation fails, prints an error message and re-prompts.
        #
        # Outputs:
        #   - If --var is set: assigns result to that variable (no stdout output).
        #   - Else if --echo is set: prints accepted value to stdout (one line).
        #   - If --echo is set: prints ✓/✗ feedback to /dev/tty regardless of --var.
        #
        # Returns:
        #   0  on success (accepted input)
        #   2  if /dev/tty cannot be opened (no TTY available)
        #
        # Notes:
        #   - Re-prompt uses recursion (ask calls itself). Consider a loop if you expect
        #     unbounded invalid attempts.
        #   - When neither --var nor --echo is provided, the accepted value is not emitted.
    ask(){
        local label="" var_name="" colorize="both"
        local validate_fn="" def_value="" echo_input=0
        local -a _orig_args=( "$@" )
        
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
        
        local label_color="$TUI_LABEL"
        local input_color="$TUI_INPUT"

        case "$colorize" in
            label)
                label_color="$TUI_LABEL"
                ;;
            input)
                input_color="$TUI_INPUT"
                ;;
            both)
                label_color="$TUI_LABEL"
                input_color="$TUI_INPUT"
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
        local tty_fd
        exec {tty_fd}</dev/tty || { printf "%bNo TTY available%b\n" "$TUI_INVALID" "$RESET"; return 2; }

        if [[ -n "$def_value" ]]; then
            IFS= read -u "$tty_fd" -e -p "$prompt" -i "$def_value" value
            [[ -z "$value" ]] && value="$def_value"
        else
            IFS= read -u "$tty_fd" -e -p "$prompt" value
        fi
        exec {tty_fd}<&-

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
        # echo result to TTY (keep stdout clean) with colorized ✓/✗ feedback on validation
        if (( echo_input )); then
            if (( ok )); then
                printf "  %b%s%b %b✓%b\n" \
                    "$input_color" "$value" "$RESET" \
                    "$TUI_VALID" "$RESET" >/dev/tty
            else
                printf "  %b%s%b %b✗%b\n" \
                    "$TUI_INPUT" "$value" "$RESET" \
                    "$TUI_INVALID" "$RESET" >/dev/tty
            fi
        fi

        # Re-prompt on validation failure
        if (( !ok )); then
            printf "%bInvalid value. Please try again.%b\n" "$TUI_INVALID" "$RESET"
            ask "${_orig_args[@]}"   # recursive retry
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

    # ask_yesno
        # Prompt a Yes/No question (default: Yes), optionally with auto-continue.
        #
        # Usage:
        #   ask_yesno "Question?" [AUTO_CONFIRM_SECONDS]
        #
        # Returns:
        #   0  Yes
        #   1  No
    ask_yesno() {
        local prompt="${1:?}"
        local seconds="${2:-0}"
        local yn_response=""
        local action=""

        action="$( td_ask_action "YES" "YES" "$prompt [Y/n]" "$seconds" "ECPQT")"

        case "$action" in
            YES)    return 0 ;;
            CANCEL|QUIT) return 1 ;;
            TYPE) ;;
            *) return 1 ;;
        esac

        ask --label "$prompt [Y/n]" --default "Y" --var yn_response

        case "${yn_response^^}" in
            Y|YES|"") return 0 ;;
            N|NO)     return 1 ;;
            *)        return 1 ;;
        esac
    }

    # ask_noyes
        # Prompt a Yes/No question (default: No), optionally with auto-continue.
        #
        # Usage:
        #   ask_noyes "Question?" [AUTO_CONFIRM_SECONDS]
        #
        # Returns:
        #   0  Yes
        #   1  No
    ask_noyes() {
        local prompt="${1:?}"
        local seconds="${2:-0}"
        local ny_response=""
        local action=""

        action="$( td_ask_action "NO" "NO" "$prompt [y/N]" "$seconds" "ECPQT")"

        case "$action" in
            NO)     return 1 ;;     # default/enter/timeout
            CANCEL|QUIT) return 1 ;;
            TYPE) ;;
        esac

        ask --label "$prompt [y/N]" --default "N" --var ny_response

        case "${ny_response^^}" in
            Y|YES)   return 0 ;;
            N|NO|"") return 1 ;;
            *)       return 1 ;;
        esac
    }

    # ask_okcancel
        # Prompt an OK/Cancel confirmation (default: OK), optionally with auto-continue.
        #
        # Usage:
        #   ask_okcancel "Apply changes?" [AUTO_CONFIRM_SECONDS]
        #
        # Returns:
        #   0  OK
        #   1  Cancel
    ask_okcancel() {
        local prompt="${1:?}"
        local seconds="${2:-0}"
        local oc_response=""
        local action=""

        action="$( td_ask_action "OK" "OK" "$prompt [OK/Cancel]" "$seconds" "ECPQT")"

        case "$action" in
            OK)     return 0 ;;
            CANCEL|QUIT) return 1 ;;
            TYPE) ;;
        esac

        ask --label "$prompt [OK/Cancel]" --default "OK" --var oc_response

        case "${oc_response^^}" in
            OK|"")     return 0 ;;
            CANCEL)    return 1 ;;
            *)         return 1 ;;
        esac
    }

    # ask_continue
        # Pause execution until Enter is pressed, optionally auto-continuing.
        #
        # Usage:
        #   ask_continue
        #   ask_continue AUTO_SECONDS
        #   ask_continue "Prompt"
        #   ask_continue "Prompt" AUTO_SECONDS
        #   ask_continue "" AUTO_SECONDS
        #
        # Behavior:
        #   - With one numeric argument, treat it as AUTO_SECONDS.
        #   - With empty prompt, no prompt text is shown.
        #
        # Returns:
        #   0 always
    ask_continue() {
        local prompt="Press Enter to continue..."
        local seconds=0
        local action=""

        case $# in
            0)
                ;;
            1)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    prompt=" "
                    seconds="$1"
                else
                    prompt="$1"
                fi
                ;;
            *)
                prompt="$1"
                seconds="${2:-0}"
                ;;
        esac

        action="$(td_ask_action "OK" "OK" "$prompt" "$seconds" "EPT")"
        if [[ "$action" != "TYPE" ]]; then
            return 0
        fi

        local tty_fd
        exec {tty_fd}</dev/tty || return 0

        if [[ -n "$prompt" ]]; then
            IFS= read -u "$tty_fd" -r -p "$prompt" _
        else
            IFS= read -u "$tty_fd" -r _
        fi

        exec {tty_fd}<&-
    }

    # td_choose
        # Purpose:
        #   Prompt for a user choice, optionally constrained to a set/range of allowed values.
        #
        # Usage:
        #   td_choose "Enter value" --var VALUE
        #   td_choose --label "Environment" --choices "dev,acc,prod" --var env
        #   td_choose --label "Drive" --choices "A-D, X" --var drive
        #
        # Options:
        #   --label TEXT            Prompt label (fallback: first positional token).
        #   --var NAME              Destination variable name (default: "choice").
        #   --choices LIST          Allowed values (comma-separated tokens and/or ranges).
        #   --displaychoices 0|1    Append "[choices]" to the label (default: 1).
        #   --keepasking 0|1        Re-prompt on invalid input (default: 1).
        #   --colorize MODE         Passed through to ask --colorize (default: both).
        #
        # Behavior:
        #   - Always prompts via ask() and captures raw user input.
        #   - If --choices is empty: accepts any input.
        #   - If --choices is provided:
        #       - Expands ranges via __expand_choices
        #       - Validates case-insensitively
        #       - On invalid input:
        #           - warns (saywarning)
        #           - re-prompts if keepasking=1
        #   - Always assigns the final captured value to --var (even if invalid and keepasking=0).
        #
        # Outputs:
        #   None (communication is via variable assignment).
        #
        # Returns:
        #   0 always (no validity contract yet).
        #
        # Notes:
        #   - If you want a validity signal later, a clean contract is:
        #       0=valid, 1=invalid (when keepasking=0)
    td_choose() {
        local label=""
        local choices=""
        local colorize="both"
        local displaychoices=1
        local keepasking=1
        local varname="choice"
        local -a _opts=()

        local _choice=""
        local _valid=0
        local opt=""

        # --- Parse options --------------------------------------------------------
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label)       label="$2"; shift 2 ;;
                --var)         varname="$2"; shift 2 ;;
                --colorize)    colorize="$2"; shift 2 ;;
                --choices)     choices="$2"; shift 2 ;;
                --displaychoices) displaychoices="$2"; shift 2 ;;
                --keepasking)  keepasking="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    [[ -z "$label" ]] && label="$1"
                    shift
                    ;;
            esac
        done

        # --- Append choices to label (if requested) ------------------------------
        if [[ -n "$choices" && "$displaychoices" -eq 1 ]]; then
            label+=" [$choices]"
        fi

        # --- Ask loop -------------------------------------------------------------
        while :; do
            ask --label "$label" --var _choice --colorize "$colorize"

            # --- No choices constraint → accept immediately -----------------------
            if [[ -z "$choices" ]]; then
                break
            fi

        # --- Validate choice --------------------------------------------------
        if td__choice_is_valid "$_choice" "$choices"; then
            break
        fi

            # --- Invalid choice ---------------------------------------------------
            saywarning "Invalid choice: $_choice"

            (( keepasking )) || break
        done

        # --- Assign to requested variable ----------------------------------------
        printf -v "$varname" '%s' "$_choice"
    }
    
    # td_choose_immediate
        # Purpose:
        #   Prompt for a user choice using immediate-capable TTY input, optionally
        #   constrained to a set/range of allowed values.
        #
        # Usage:
        #   td_choose_immediate --label "Select option" --choices "1,2,3,Q" --var choice
        #   td_choose_immediate --label "Select option" --choices "$valid" \
        #       --instantchoices "B,D,L,V,C" --var choice
        #
        # Options:
        #   --label TEXT            Prompt label (fallback: first positional token).
        #   --var NAME              Destination variable name (default: "choice").
        #   --choices LIST          Allowed values (comma-separated tokens and/or ranges).
        #   --instantchoices LIST   Choices that should be accepted immediately without
        #                           Enter (comma-separated tokens and/or ranges).
        #   --displaychoices 0|1    Append "[choices]" to the label (default: 1).
        #   --keepasking 0|1        Re-prompt on invalid input (default: 1).
        #
        # Behavior:
        #   - Reads input directly from /dev/tty (not stdin).
        #   - Input matching --instantchoices is accepted immediately.
        #   - All other input is buffered until Enter.
        #   - Backspace edits buffered input.
        #   - If --choices is empty: accepts any input.
        #   - If --choices is provided:
        #       - Expands ranges via __expand_choices
        #       - Validates case-insensitively
        #       - On invalid input:
        #           - warns (saywarning)
        #           - re-prompts if keepasking=1
        #
        # Outputs:
        #   None (communication is via variable assignment).
        #
        # Returns:
        #   0 always (no validity contract yet).
        #
        # Notes:
        #   - Intended for menu-style UIs where some hotkeys should react immediately
        #     while normal choices still require Enter.
        #   - Input is uppercased before immediate-choice comparison.
    td_choose_immediate() {
        local label=""
        local choices=""
        local instantchoices=""
        local displaychoices=1
        local keepasking=1
        local varname="choice"

        local _choice=""

        # --- Parse options --------------------------------------------------------
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label)          label="$2"; shift 2 ;;
                --var)            varname="$2"; shift 2 ;;
                --choices)        choices="$2"; shift 2 ;;
                --instantchoices) instantchoices="$2"; shift 2 ;;
                --displaychoices) displaychoices="$2"; shift 2 ;;
                --keepasking)     keepasking="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    [[ -z "$label" ]] && label="$1"
                    shift
                    ;;
            esac
        done

        # --- Append choices to label ---------------------------------------------
        if [[ -n "$choices" && "$displaychoices" -eq 1 ]]; then
            label+=" [$choices]"
        fi

        # --- Ask loop -------------------------------------------------------------
        while :; do
            local key=""
            local buffer=""
            local candidate=""

            printf '%s: ' "$label" > /dev/tty

            while true; do
                IFS= read -r -s -n 1 key < /dev/tty || return 1

                case "$key" in
                    "")
                        # Enter confirms buffered input
                        if [[ -n "$buffer" ]]; then
                            printf '\n' > /dev/tty
                            _choice="$buffer"
                            break
                        fi
                        ;;

                    $'\177'|$'\b')
                        # Backspace
                        if [[ -n "$buffer" ]]; then
                            buffer="${buffer%?}"
                            printf '\b \b' > /dev/tty
                        fi
                        ;;

                    *)
                        candidate="${key^^}"

                        # Immediate only for configured instant choices
                        if [[ -n "$instantchoices" ]] && td__choice_is_valid "$candidate" "$instantchoices"; then
                            printf '\n' > /dev/tty
                            _choice="$candidate"
                            break
                        fi

                        # Otherwise buffer normally
                        buffer+="$key"
                        printf '%s' "$key" > /dev/tty
                        ;;
                esac
            done

            # --- No choices constraint -------------------------------------------
            if [[ -z "$choices" ]]; then
                break
            fi

            # --- Validate choice --------------------------------------------------
            if td__choice_is_valid "$_choice" "$choices"; then
                break
            fi

            # --- Invalid choice ---------------------------------------------------
            saywarning "Invalid choice: $_choice"

            (( keepasking )) || break
        done

        # --- Assign result --------------------------------------------------------
        printf -v "$varname" '%s' "$_choice"
    }

    # ask_ok_redo_quit
        # Purpose:
        #   Convenience wrapper for a standard OK / Redo / Quit decision prompt.
        #
        #   Provides a simple API that optionally uses the timed soft-dialog engine
        #   (td_dlg_autocontinue) for a countdown confirmation phase, while preserving
        #   the traditional typed prompt fallback via ask().
        #
        #   This function normalizes the dialog result into a stable ORQ return
        #   contract so calling code does not need to understand the dialog engine.
        #
        # Usage:
        #   ask_ok_redo_quit "Proceed with operation?" [AUTO_CONFIRM_SECONDS]
        #
        # Arguments:
        #   $1  Prompt text (without suffix).
        #
        #   $2  AUTO_CONFIRM_SECONDS
        #       Optional countdown before automatically continuing.
        #
        #       0 (default)
        #           Skip timed dialog and immediately show the typed prompt.
        #
        #       >0
        #           Display a non-blocking timed dialog using td_dlg_autocontinue().
        #           If no key is pressed before timeout, OK is assumed.
        #
        # Behavior:
        #   Non-interactive environment:
        #       If stdin/stdout are not attached to a TTY, the function returns OK
        #       immediately to avoid blocking scripts or pipelines.
        #
        #   Timed dialog phase (if seconds > 0):
        #       Delegates UI handling to td_dlg_autocontinue().
        #
        #       Supported actions:
        #           Enter        => OK
        #           R            => Redo
        #           C / Esc      => Cancel (treated as Quit)
        #           Q            => Quit
        #           P / Space    => Pause/resume countdown
        #           Other key    => Switch to typed prompt mode
        #
        #       Timeout:
        #           Automatically continues with OK.
        #
        #   Typed prompt phase:
        #       Uses ask() to read a token and interprets the response.
        #
        #       Accepted inputs (case-insensitive):
        #           "" / OK / O                => OK
        #           REDO / R                   => Redo
        #           QUIT / Q / EXIT / CANCEL   => Quit
        #
        # Inputs (globals):
        #   ask()                 Interactive input helper
        #   td_dlg_autocontinue() Timed dialog engine
        #
        # Returns:
        #   0  OK / Continue
        #   1  Redo
        #   2  Quit / Cancel
        #   3  Invalid input (typed prompt only)
        #
        # Notes:
        #   - This function defines the canonical ORQ interaction pattern used
        #     throughout the Testadura script framework.
        #   - The timed dialog UI and key handling are implemented by
        #     td_dlg_autocontinue(); this function only maps the results into
        #     the ORQ return contract.
    ask_ok_redo_quit() {
        local prompt="${1-}"
        local seconds="${2:-0}"
        local orq_response=""

        # Non-interactive: never block; default OK
        td_has_tty || return 0  

        if (( seconds > 0 )); then
            # Use tty-based soft dialog for the timed phase:
            # E=Enter->OK, R=redo, C=cancel, P=pause, Q=quit, T=typed fallback, H=hide key legend
            td_dlg_autocontinue "$seconds" "$prompt [OK/Redo/Quit]" "ERCPQTH"
            local rc=$?

            case "$rc" in
                0|1)  return 0 ;;  # Enter or timeout => OK
                3)    return 1 ;;  # redo
                2|4)  return 2 ;;  # cancel/quit => Quit/Cancel
                5)    ;;           # typed fallback requested
                *)    ;;           # ignore anything else and fall through to typed
            esac
        fi

        # Full typed prompt (original behavior)
        ask --label "$prompt [OK/Redo/Quit]" --var orq_response

        # Trim whitespace
        orq_response="${orq_response#"${orq_response%%[![:space:]]*}"}"
        orq_response="${orq_response%"${orq_response##*[![:space:]]}"}"

        local upper="${orq_response^^}"
        case "$upper" in
            ""|OK|O)                    return 0 ;;
            REDO|R)                     return 1 ;;
            QUIT|Q|EXIT|CANCEL|C)       return 2 ;;
            *)                          return 3 ;;
        esac
    }
# --- File system validations -----------------------------------------------------
    # validate_file_exists
        # Purpose:
        #   Validate that PATH exists and is a regular file.
        #
        # Arguments:
        #   $1  PATH
        #
        # Returns:
        #   0  valid
        #   1  invalid
    validate_file_exists() {
        local path="$1"

        [[ -f "$path" ]] && return 0    # valid
        return 1                        # invalid
    }

    # validate_path_exists
        # Purpose:
        #   Validate that a path exists (file/dir/symlink/etc).
        #
        # Arguments:
        #   $1  Path
        #
        # Returns:
        #   0  → exists
        #   1  → does not exist
    validate_path_exists() {
        [[ -e "$1" ]] && return 0
        return 1
    }

    # validate_dir_exists
        # Purpose:
        #   Validate that a path exists and is a directory.
        #
        # Arguments:
        #   $1  Path
        #
        # Returns:
        #   0  → exists and is a directory
        #   1  → missing or not a directory
    validate_dir_exists() {
        [[ -d "$1" ]] && return 0
        return 1
    }

    # validate_executable
        # Purpose:
        #   Validate that a path exists and is executable.
        #
        # Arguments:
        #   $1  Path
        #
        # Returns:
        #   0  → executable
        #   1  → not executable / missing
        #
        # Example:
        #   validate_executable "/usr/bin/git" || __boot_fail "git missing" 127
    validate_executable() {
        [[ -x "$1" ]] && return 0
        return 1
    }

    # validate_file_not_exists
        # Purpose:
        #   Validate that a file path does NOT exist as a regular file.
        #
        # Arguments:
        #   $1  Path
        #
        # Returns:
        #   0  → file does not exist
        #   1  → file exists
        #
        # Example:
        #   validate_file_not_exists "$target" || __boot_fail "Refusing to overwrite $target" 1
    validate_file_not_exists() {
        [[ ! -f "$1" ]] && return 0
        return 1
    }

# --- Type validations ------------------------------------------------------------
    # validate_int
        #
        # Validate an integer (base-10), allowing an optional leading minus sign.
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → valid integer (e.g. 0, 42, -7)
        #   1  → invalid
        #
        # Example:
        #   validate_int "$age" || saywarning "Age must be an integer"
    validate_int() {
        [[ "$1" =~ ^-?[0-9]+$ ]] && return 0
        return 1
    }

    # validate_numeric
        #
        # Validate a numeric value (integer or decimal), allowing optional leading minus.
        # Accepts dot as decimal separator (e.g. 12.34).
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → valid numeric (e.g. 10, -3, 0.5, -12.34)
        #   1  → invalid
        #
        # Notes:
        #   - Does not accept scientific notation (e.g. 1e-3).
        #   - Does not accept comma decimals (e.g. 1,5).
        #
        # Example:
        #   validate_numeric "$price" || saywarning "Price must be numeric"
    validate_numeric() {
        [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && return 0
        return 1
    }

    # validate_text
        #
        # Validate that a value is non-empty.
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → non-empty
        #   1  → empty
        #
        # Example:
        #   validate_text "$name" || saywarning "Name is required"
    validate_text() {
        [[ -n "$1" ]] && return 0
        return 1
    }

    # validate_bool
        #
        # Validate common boolean representations.
        #
        # Accepted values (case-insensitive):
        #   y, yes, n, no, true, false, 1, 0
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → recognized boolean token
        #   1  → invalid
        #
        # Example:
        #   validate_bool "$enabled" || saywarning "Expected boolean (yes/no/true/false/1/0)"
    validate_bool() {
        case "${1,,}" in
            y|yes|n|no|true|false|1|0)
                return 0 ;;
            *)
                return 1 ;;
        esac
    }

    # validate_date
        #
        # Validate a date in ISO format: YYYY-MM-DD
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → matches YYYY-MM-DD pattern
        #   1  → invalid
        #
        # Notes:
        #   - This validates format only; it does not reject impossible dates like
        #     2026-99-99.
        #
        # Example:
        #   validate_date "$start_date" || saywarning "Expected YYYY-MM-DD"
    validate_date() {
        [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && return 0
        return 1
    }

    # validate_ip
        #
        # Validate an IPv4 address (dotted decimal).
        #
        # Arguments:
        #   $1  IP address string
        #
        # Returns:
        #   0  → valid IPv4 address (0-255 per octet)
        #   1  → invalid
        #
        # Example:
        #   validate_ip "$host_ip" || saywarning "Invalid IP address: $host_ip"
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

    # validate_cidr
        #
        # Validate an IPv4 CIDR prefix length (0..32).
        #
        # Arguments:
        #   $1  Prefix length
        #
        # Returns:
        #   0  → valid CIDR prefix length (0-32)
        #   1  → invalid
        #
        # Example:
        #   validate_cidr "$mask" || saywarning "CIDR must be between 0 and 32"
    validate_cidr(){  
        [[ "$1" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] && return 0
        return 1
    }

    # validate_slug
        #
        # Validate a "slug" identifier consisting of:
        #   letters, digits, dot, underscore, hyphen
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → valid slug
        #   1  → invalid
        #
        # Example:
        #   validate_slug "$project" || saywarning "Invalid slug: $project"
    validate_slug() {
        [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] && return 0
        return 1
    }

    # validate_fs_name
        #
        # Validate a filesystem-friendly name consisting of:
        #   letters, digits, dot, underscore, hyphen
        #
        # Arguments:
        #   $1  Value
        #
        # Returns:
        #   0  → valid filesystem-friendly name
        #   1  → invalid
        #
        # Example:
        #   validate_fs_name "$dir" || saywarning "Invalid directory name: $dir"
    validate_fs_name() {
        [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && return 0
        return 1
    }
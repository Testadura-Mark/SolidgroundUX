# ==================================================================================
# Testadura Consultancy — Interactive Prompting Module
# ----------------------------------------------------------------------------------
# Module     : ui-ask.sh
# Purpose    : Interactive prompting and validated input helpers for TTY-driven scripts
#
# Description:
#   Provides a consistent framework layer for interactive user input in terminal
#   scripts and tools. This module covers:
#     - editable prompts with defaults
#     - validation-aware input loops
#     - normalized decision helpers (yes/no, ok/cancel, ok/redo/quit, continue)
#     - constrained choice input, including immediate key-based selection
#
# Terminal I/O model:
#   - Reads from the controlling terminal (/dev/tty), not stdin
#   - Safe for use in scripts that also consume piped or redirected stdin
#   - Falls back to sensible defaults or explicit failure when no TTY is available
#
# Design principles:
#   - Keep prompting behavior consistent across the framework
#   - Separate prompt mechanics from message/logging policy
#   - Support both typed input and timed dialog-based interaction
#   - Normalize wrapper behavior so calling code stays simple
#
# Role in framework:
#   - Provides the interactive input layer for CLI tools and framework utilities
#   - Builds on lower-level UI rendering and optional dialog helpers
#   - Complements ui.sh and ui-dlg.sh rather than replacing them
#
# Non-goals:
#   - Non-interactive batch input processing
#   - Rich full-screen terminal forms or menu systems
#   - Centralized logging or output policy
#
# Author     : Mark Fieten
# Copyright  : © 2025 Mark Fieten — Testadura Consultancy
# License    : Testadura Non-Commercial License (TD-NC) v1.0
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
        #   Shared helper for ask_* wrappers that normalizes timed and non-interactive
        #   prompt behavior into a small generic action set.
        #
        # Behavior:
        #   - Returns DEFAULT_ACTION immediately when no TTY is available.
        #   - Optionally invokes td_dlg_autocontinue for a timed interaction phase.
        #   - Maps dialog return codes to normalized action tokens.
        #   - Falls back to TYPE when typed input should be collected by the caller.
        #
        # Arguments:
        #   $1  DEFAULT_ACTION
        #       Action used for non-interactive mode and timeout.
        #   $2  ENTER_ACTION
        #       Action used when Enter is accepted by the timed dialog.
        #   $3  PROMPT
        #       Prompt text, including any suffix such as "[Y/n]".
        #   $4  SECONDS
        #       Countdown seconds; 0 disables timed dialog behavior.
        #   $5  DLG_KEYS
        #       Key map passed to td_dlg_autocontinue.
        #
        # Output:
        #   Prints one normalized action token to stdout:
        #     DEFAULT_ACTION / ENTER_ACTION / REDO / CANCEL / QUIT / TYPE
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   action="$(td_ask_action "YES" "YES" "Proceed? [Y/n]" 5 "ECPQT")"
        #
        # Examples:
        #   action="$(td_ask_action "OK" "OK" "Continue?" 10 "EPT")"
        #
        # Notes:
        #   - Intended as an internal helper for ask_* wrappers.
        #   - Wrapper-specific meaning is applied only after TYPE fallback.
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
        # Behavior:
        #   - Reads from /dev/tty rather than stdin, so it remains safe in scripts
        #     that consume piped or redirected stdin.
        #   - Supports readline-style editing and optional prefilled defaults.
        #   - Optionally validates the entered value through a callback function.
        #   - Re-prompts recursively when validation fails.
        #   - Can either assign the result to a variable or echo it to stdout.
        #
        # Arguments:
        #   LABEL
        #       Positional fallback label when --label is omitted.
        #
        # Options:
        #   --label TEXT
        #       Prompt label text.
        #   --default VALUE
        #       Editable default value; empty entry resolves to this value.
        #   --validate FUNC
        #       Validation callback invoked as: FUNC "$value"
        #       Return 0 to accept, non-zero to reject and re-prompt.
        #   --colorize MODE
        #       Prompt coloring mode: none | label | input | both
        #       Default: both
        #   --var NAME
        #       Destination variable name for the accepted value.
        #   --echo
        #       Echo accepted input with ✓ / ✗ feedback to /dev/tty.
        #       Also prints the accepted value to stdout when --var is not used.
        #
        # Inputs (globals):
        #   TUI_LABEL
        #   TUI_INPUT
        #   TUI_VALID
        #   TUI_INVALID
        #   RESET
        #
        # Outputs (globals):
        #   Assigns the accepted value to --var NAME when provided.
        #
        # Output:
        #   - Prints validation feedback to /dev/tty when --echo is enabled.
        #   - Prints the accepted value to stdout only when --var is not used and
        #     --echo is enabled.
        #
        # Returns:
        #   0  on accepted input
        #   2  if /dev/tty cannot be opened
        #
        # Usage:
        #   ask --label "Project name" --var project
        #   ask --label "Environment" --default "dev" --var env
        #   ask --label "Release date" --validate validate_date --var release_date
        #
        # Examples:
        #   ask --label "Project name" --var project_name
        #
        #   ask --label "Environment" --default "dev" --var env
        #
        #   ask --label "Release date" --validate validate_date --var release_date
        #
        # Notes:
        #   - Re-prompt currently uses recursion; convert to a loop later if you want
        #     to avoid recursive retries entirely.
        #   - When neither --var nor --echo is supplied, the accepted value is kept
        #     local and not emitted.
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
        # Purpose:
        #   Prompt a Yes/No question with default Yes, optionally using timed auto-continue.
        #
        # Behavior:
        #   - Uses td_ask_action for non-interactive and timed-dialog handling.
        #   - Falls back to typed input via ask() when needed.
        #   - Treats Enter and timeout as Yes.
        #
        # Arguments:
        #   $1  PROMPT
        #       Question text without suffix.
        #   $2  SECONDS
        #       Optional auto-confirm timeout in seconds.
        #
        # Returns:
        #   0 if the final answer is Yes.
        #   1 if the final answer is No, Cancel, or Quit.
        #
        # Usage:
        #   ask_yesno "Proceed with installation?"
        #
        # Examples:
        #   if ask_yesno "Overwrite existing file?" 5; then
        #       overwrite_file
        #   fi
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
        # Purpose:
        #   Prompt a Yes/No question with default No, optionally using timed auto-continue.
        #
        # Behavior:
        #   - Uses td_ask_action for non-interactive and timed-dialog handling.
        #   - Falls back to typed input via ask() when needed.
        #   - Treats Enter and timeout as No.
        #
        # Arguments:
        #   $1  PROMPT
        #       Question text without suffix.
        #   $2  SECONDS
        #       Optional auto-confirm timeout in seconds.
        #
        # Returns:
        #   0 if the final answer is Yes.
        #   1 if the final answer is No, Cancel, or Quit.
        #
        # Usage:
        #   ask_noyes "Delete all generated files?"
        #
        # Examples:
        #   if ask_noyes "Reset the state file?" 10; then
        #       td_state_reset
        #   fi
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
        # Purpose:
        #   Prompt an OK/Cancel confirmation with default OK, optionally using timed auto-continue.
        #
        # Behavior:
        #   - Uses td_ask_action for non-interactive and timed-dialog handling.
        #   - Falls back to typed input via ask() when needed.
        #   - Treats Enter and timeout as OK.
        #
        # Arguments:
        #   $1  PROMPT
        #       Confirmation text without suffix.
        #   $2  SECONDS
        #       Optional auto-confirm timeout in seconds.
        #
        # Returns:
        #   0 if the final answer is OK.
        #   1 if the final answer is Cancel or Quit.
        #
        # Usage:
        #   ask_okcancel "Apply changes?"
        #
        # Examples:
        #   if ask_okcancel "Publish release now?" 5; then
        #       publish_release
        #   fi
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
        # Purpose:
        #   Pause execution until Enter is pressed, optionally auto-continuing after a delay.
        #
        # Behavior:
        #   - Accepts either a prompt, a timeout, or both.
        #   - Uses td_ask_action for the timed phase when seconds > 0.
        #   - Reads directly from /dev/tty for the typed phase.
        #
        # Arguments:
        #   $1  PROMPT or SECONDS
        #       Prompt text, or timeout seconds when numeric.
        #   $2  SECONDS
        #       Optional timeout when the first argument is a prompt.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   ask_continue
        #   ask_continue 5
        #   ask_continue "Press Enter to continue..."
        #   ask_continue "Continuing shortly..." 10
        #
        # Examples:
        #   ask_continue "Review complete. Press Enter to proceed."
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
        #   Prompt for a user choice, optionally constrained to a set or range of allowed values.
        #
        # Behavior:
        #   - Prompts via ask() and stores the typed value.
        #   - Accepts any input when no choices constraint is provided.
        #   - Validates case-insensitively against expanded choices when provided.
        #   - Re-prompts on invalid input when keepasking=1.
        #   - Always assigns the final captured value to the requested variable.
        #
        # Options:
        #   --label TEXT
        #       Prompt label.
        #   --var NAME
        #       Destination variable name. Default: choice
        #   --choices LIST
        #       Allowed values as comma-separated tokens and/or ranges.
        #   --displaychoices 0|1
        #       Append [choices] to the label. Default: 1
        #   --keepasking 0|1
        #       Re-prompt on invalid input. Default: 1
        #   --colorize MODE
        #       Passed through to ask(). Default: both
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_choose --label "Environment" --choices "dev,acc,prod" --var env
        #
        # Examples:
        #   td_choose --label "Environment" --choices "dev,acc,prod" --var env
        #
        #   td_choose --label "Drive" --choices "A-D,X" --var drive
        #
        # Notes:
        #   - Validity is enforced by re-prompting, not by the return code.
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
        #   Prompt for a user choice using immediate-capable TTY input, with optional
        #   instant hotkeys and constrained allowed values.
        #
        # Behavior:
        #   - Reads directly from /dev/tty.
        #   - Accepts configured instant choices immediately without Enter.
        #   - Buffers all other input until Enter is pressed.
        #   - Supports backspace editing for buffered input.
        #   - Validates against the allowed choice list when provided.
        #   - Re-prompts on invalid input when keepasking=1.
        #
        # Options:
        #   --label TEXT
        #       Prompt label.
        #   --var NAME
        #       Destination variable name. Default: choice
        #   --choices LIST
        #       Allowed values as comma-separated tokens and/or ranges.
        #   --instantchoices LIST
        #       Choices accepted immediately without Enter.
        #   --displaychoices 0|1
        #       Append [choices] to the label. Default: 1
        #   --keepasking 0|1
        #       Re-prompt on invalid input. Default: 1
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_choose_immediate --label "Select option" --choices "1,2,3,Q" --var choice
        #
        # Examples:
        #   td_choose_immediate --label "Select option" --choices "1,2,3,Q" --var choice
        #
        #   td_choose_immediate \
        #       --label "Action" \
        #       --choices "1-9,B,D,L,V,C,Q" \
        #       --instantchoices "B,D,L,V,C,Q" \
        #       --var action
        #
        # Notes:
        #   - Intended for menu-style UIs where some hotkeys should react immediately.
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
        #   Prompt for a standard OK / Redo / Quit decision, optionally with timed auto-continue.
        #
        # Behavior:
        #   - Returns immediately with OK in non-interactive mode.
        #   - Optionally uses td_dlg_autocontinue for a timed decision phase.
        #   - Falls back to typed input via ask() when needed.
        #   - Normalizes all interaction paths into a stable ORQ return contract.
        #
        # Arguments:
        #   $1  PROMPT
        #       Prompt text without suffix.
        #   $2  SECONDS
        #       Optional auto-confirm timeout in seconds.
        #
        # Returns:
        #   0  OK / continue
        #   1  Redo
        #   2  Quit / Cancel
        #   3  Invalid typed input
        #
        # Usage:
        #   ask_ok_redo_quit "Proceed with operation?"
        #
        # Examples:
        #   case $? in
        #       0) proceed ;;
        #       1) retry ;;
        #       2) exit 1 ;;
        #   esac
        #
        # Notes:
        #   - Defines the canonical ORQ interaction pattern for the framework.
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
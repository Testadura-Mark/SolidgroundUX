# ==================================================================================
# Testadura Consultancy — Timed Dialog Helpers
# ----------------------------------------------------------------------------------
# Module     : ui-dlg.sh
# Purpose    : Non-blocking and timed dialog helpers for TTY-driven terminal scripts
#
# Description:
#   Provides lightweight dialog-style helpers that render a short status block to
#   the controlling terminal and accept simple key-driven decisions.
#
#   This module is intended for "soft prompt" flows such as:
#     - timed auto-continue prompts
#     - pause/resume dialogs
#     - cancel / redo / quit decision blocks
#     - small guided interaction without full-screen UI frameworks
#
# Terminal I/O model:
#   - Writes directly to /dev/tty, independent of stdin/stdout redirection
#   - Uses minimal ANSI cursor movement to redraw the dialog block in place
#   - Returns decision codes instead of enforcing application policy
#
# Design principles:
#   - Keep dialog behavior lightweight and terminal-safe
#   - Separate decision mechanics from higher-level application flow
#   - Avoid full-screen UI dependencies
#   - Provide stable return contracts for wrapper functions
#
# Role in framework:
#   - Supports timed and non-blocking interaction patterns
#   - Complements ui-ask.sh (typed prompts) and ui-say.sh (message output)
#   - Used where a richer confirmation flow is needed without leaving the normal terminal
#
# Non-goals:
#   - General-purpose prompting (see ui-ask.sh)
#   - Typed message output (see ui-say.sh)
#   - Full-screen terminal UI frameworks
#
# Author     : Mark Fieten
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
    # __dlg_keymap
        # Purpose:
        #   Build a human-readable key legend string for the current dialog state.
        #
        # Behavior:
        #   - Includes only the actions enabled by the supplied choice string.
        #   - Adapts the pause legend to "pause" or "resume" based on PAUSED.
        #   - Returns a semicolon-separated legend without a trailing delimiter.
        #
        # Arguments:
        #   $1  CHOICES
        #       Choice specification describing enabled dialog keys.
        #   $2  PAUSED
        #       Optional paused state flag:
        #       1 = paused
        #       0 = not paused
        #       Default: 0
        #
        # Output:
        #   Prints the legend string to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __dlg_keymap "AERCPQ" 0
        #
        # Examples:
        #   legend="$(__dlg_keymap "ERCPQ" 1)"
        #
        # Notes:
        #   - Intended as an internal rendering helper.
    __dlg_keymap(){
        local choices="$1"
        local keymap=""
        local paused="${2:-0}"

        [[ "$choices" == *"E"* ]] && keymap+="Enter=continue; "
        [[ "$choices" == *"R"* ]] && keymap+="R=redo; "
        [[ "$choices" == *"C"* ]] && keymap+="C/Esc=cancel; "

        [[ "$choices" == *"Q"* ]] && keymap+="Q=quit; "
        [[ "$choices" == *"A"* ]] && keymap+="Press any key to continue; "
        
        if [[ "$choices" == *"P"* ]]; then
            if (( paused )); then
                keymap+="P/Space=resume; "
            else
                keymap+="P/Space=pause; "
            fi
        fi

        # Trim trailing "; "
        keymap="${keymap%; }"

        printf '%s' "$keymap"
    }

# --- Public API ------------------------------------------------------------------
    # td_dlg_autocontinue
        # Purpose:
        #   Render a timed dialog on /dev/tty with a countdown and simple key-driven actions.
        #
        # Behavior:
        #   - Displays an optional message, optional key legend, and countdown line.
        #   - Redraws the dialog block in place using minimal cursor movement.
        #   - Supports pause/resume, continue, cancel, redo, quit, and custom keys.
        #   - Returns immediately with success when no usable /dev/tty is available.
        #
        # Arguments:
        #   $1  SECONDS
        #       Countdown duration in seconds.
        #       Default: 5
        #   $2  MESSAGE
        #       Optional text shown above the countdown.
        #   $3  CHOICES
        #       Enabled key set.
        #       Default: AERCPQ
        #
        # Supported reserved keys:
        #   A  Any key continues
        #   E  Enter continues
        #   R  Redo
        #   C  Cancel
        #   P  Pause / resume
        #   Q  Quit
        #   H  Hide key legend
        #
        # Custom keys:
        #   - Any non-reserved single-character key in CHOICES is treated as a custom key.
        #   - Custom keys return 10 for the first custom key, 11 for the second, and so on.
        #
        # Inputs (globals):
        #   TUI_TEXT
        #   WHITE
        #   FX_ITALIC
        #   RESET
        #
        # Returns:
        #   0   continue
        #   1   timeout / auto-continue
        #   2   cancel
        #   3   redo
        #   4   quit
        #   10+ custom key index
        #
        # Usage:
        #   td_dlg_autocontinue 5 "Continuing shortly..." "AERCPQ"
        #
        # Examples:
        #   td_dlg_autocontinue 10 "Proceed with installation?" "ERCPQ"
        #
        #   case $? in
        #       0)  continue_flow ;;
        #       1)  timeout_flow ;;
        #       2)  cancel_flow ;;
        #       3)  redo_flow ;;
        #       4)  quit_flow ;;
        #   esac
        #
        # Notes:
        #   - This function defines dialog mechanics only; callers interpret the return code.
    td_dlg_autocontinue() {
        local seconds="${1:-5}"
        local msg="${2:-}"
        local dlgchoices="${3:-AERCPQ}"
        dlgchoices="${dlgchoices^^}"

        local tty="/dev/tty"
        [[ -r "$tty" && -w "$tty" ]] || return 0

        # --- Helpers ---------------------------------------------------------------
        # Reserved keys are matched case-insensitively.
        local reserved="AERCPQH"

        # Build a de-duplicated list of custom keys in encounter order.
        # Excludes reserved letters (A/E/R/C/P/Q/H), but allows Enter/Space/Esc behavior
        # through the existing logic.
        local custom_keys=""
        local _ch=""
        local i=0

        for (( i=0; i<${#dlgchoices}; i++ )); do
            _ch="${dlgchoices:i:1}"
            # Normalize to uppercase for reserved detection
            if [[ "$reserved" == *"$_ch"* ]]; then
                continue
            fi
            # Skip duplicates
            if [[ "$custom_keys" == *"$_ch"* ]]; then
                continue
            fi
            custom_keys+="${_ch}"
        done

        # Return code for a custom key, or empty if not a custom key.
        # Custom keys are matched exactly as provided, but also accept case-insensitive
        # match if the provided key is alphabetic.
        td__dlg_custom_rc_for_key() {
            local pressed="${1:-}"
            local j=0
            local k=""

            for (( j=0; j<${#custom_keys}; j++ )); do
                k="${custom_keys:j:1}"
                if [[ "$pressed" == "$k" ]]; then
                    printf '%d' "$((10 + j))"
                    return 0
                fi
                # If both are letters, accept case-insensitive match
                if [[ "$pressed" =~ ^[A-Za-z]$ && "$k" =~ ^[A-Za-z]$ ]]; then
                    if [[ "${pressed^^}" == "${k^^}" ]]; then
                        printf '%d' "$((10 + j))"
                        return 0
                    fi
                fi
            done

            return 1
        }

        # --- Runtime state --------------------------------------------------------
        local paused=0
        local key=""
        local got=0

        local lines=1
        local hide_keymap=0
        if [[ "$dlgchoices" == *"H"* ]]; then
            hide_keymap=1
        else
            hide_keymap=0
            ((lines++))
        fi

        if [[ -n "$msg" ]]; then
            ((lines++))
        fi

        local clr
        clr="$(td_sgr "$WHITE" "$FX_ITALIC")"

        while true; do
            local line_keymap
            line_keymap="$(__dlg_keymap "$dlgchoices" "$paused")"

            # Message line (optional)
            if [[ -n "$msg" ]]; then
                printf '\r\e[K%s\n' "${TUI_TEXT}${msg}${RESET}" >"$tty"
            fi

            # Keymap line
            if (( ! hide_keymap )); then
                printf '\r\e[K%s\n' "${TUI_TEXT}${line_keymap}${RESET}" >"$tty"
            fi

            if (( paused )); then
                printf '\r\e[K%sPaused... Press P or Space to resume countdown%s' \
                    "$clr" "$RESET" >"$tty"
            else
                printf '\r\e[K%sContinuing in %ds...%s' \
                    "$clr" "$seconds" "$RESET" >"$tty"
            fi

            # Read key
            got=0
            key=""
            if (( paused )); then
                if IFS= read -r -n 1 -s key <"$tty"; then got=1; fi
            else
                if IFS= read -r -n 1 -s -t 1 key <"$tty"; then got=1; fi
            fi

            # Move cursor back up to redraw block next iteration (IMPORTANT: to tty)
                # We move (lines-1) lines up (to the start of the block) and return to column 0,
                # so the next print redraws the block in place.
                # Assumes the block is exactly 'lines' lines tall (message + optional keymap + countdown)
            if (( lines > 1 )); then
                printf '\e[%dA' "$((lines-1))" >"$tty"
            fi
            printf '\r' >"$tty"

            if (( got )); then
                [[ -z "$key" ]] && key=$'\n'

                case "$key" in
                    p|P|" ")
                        [[ "$dlgchoices" == *"P"* ]] || continue
                        (( paused )) && paused=0 || paused=1
                        continue
                        ;;

                    r|R)
                        [[ "$dlgchoices" == *"R"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 3
                        ;;

                    c|C|$'\e')
                        [[ "$dlgchoices" == *"C"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 2
                        ;;

                    q|Q)
                        [[ "$dlgchoices" == *"Q"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 4
                        ;;

                    $'\n'|$'\r')
                        [[ "$dlgchoices" == *"E"* ]] || continue
                        # If you want Enter to count as "any key", use:
                        # [[ "$dlgchoices" == *"E"* || "$dlgchoices" == *"A"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 0
                        ;;

                    *)
                        # 1) Custom key? return 10+
                        local rc=""
                        rc="$(td__dlg_custom_rc_for_key "$key" 2>/dev/null || true)"
                        if [[ -n "$rc" ]]; then
                            printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                            return "$rc"
                        fi

                        # 2) Fallback to "any key continues" if enabled
                        [[ "$dlgchoices" == *"A"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 0
                        ;;
                esac
            fi


            if (( ! paused )); then      
                ((seconds--))
                if (( seconds < 0 )); then
                    printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                    saydebug '%s\n' "${TUI_TEXT}Auto-continued.${RESET}" >"$tty"
                    return 1
                fi
            fi
        done
    }

    # td_prompt_fromlist
        # Purpose:
        #   Prompt for a list of state or configuration entries described by state-spec lines.
        #
        # Behavior:
        #   - Parses each spec line via td_parse_statespec.
        #   - Resolves the target variable name, label, default value, and validator.
        #   - Uses the current shell value when present, otherwise the spec default.
        #   - Calls ask() for each valid entry and stores results directly in the target variables.
        #   - Optionally auto-aligns labels based on the longest label in the input list.
        #
        # Options:
        #   --labelwidth N
        #       Fixed label width. Default: 0
        #   --autoalign
        #       Compute label width from the longest label in the provided specs.
        #   --colorize MODE
        #       Passed through to ask --colorize.
        #       Default: both
        #   --
        #       End of options; remaining arguments are spec lines.
        #
        # Spec format:
        #   Each spec line is parsed by td_parse_statespec and is expected to provide:
        #     __statekey
        #     __statelabel
        #     __statedefault
        #     __statevalidate
        #
        # Inputs (globals / dependencies):
        #   td_parse_statespec
        #   __td_is_ident
        #   td_trim
        #   td_fill_right
        #   ask
        #   saywarning
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_prompt_fromlist --autoalign -- "${TD_STATE_VARIABLES[@]}"
        #
        # Examples:
        #   td_prompt_fromlist --autoalign --colorize both -- \
        #       "HOST|Host name|localhost|validate_text|" \
        #       "PORT|Port|8080|validate_int|"
        #
        # Notes:
        #   - Invalid state keys are skipped with a warning.
        #   - Results are assigned directly to the variables named by each spec.
    td_prompt_fromlist() {
        local labelwidth=0
        local autoalign=0
        local colorize="both"

        # ---- parse optional parameters ---------------------------------
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --labelwidth)
                    labelwidth="$2"
                    shift 2
                    ;;
                --autoalign)
                    autoalign=1
                    shift
                    ;;
                --colorize)
                    colorize="$2"
                    shift 2
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    break
                    ;;
            esac
        done

        # ---- compute labelwidth if autoalign is enabled -----------------
        if (( autoalign )) && (( labelwidth <= 0 )); then
            local line key label def validator
            local w=0

            for line in "$@"; do
                td_parse_statespec "$line"
                key="$(td_trim "$__statekey")"
                label="$(td_trim "$__statelabel")"

                __td_is_ident "$key" || continue
                [[ -n "$label" ]] || label="$key"

                ((${#label} > w)) && w=${#label}
            done

            labelwidth="$w"
        fi

        # ---- main prompt loop ------------------------------------------
        local line key label def validator
        local current chosen

        for line in "$@"; do
            td_parse_statespec "$line"

            key="$(td_trim "$__statekey")"
            label="$(td_trim "$__statelabel")"
            def="$(td_trim "$__statedefault")"
            validator="$(td_trim "$__statevalidate")"

            __td_is_ident "$key" || { saywarning "Skipping invalid state key: '$key'"; continue; }
            [[ -n "$label" ]] || label="$key"

            # ---- optional label alignment --------------------------------
            if (( labelwidth > 0 )); then
                label="$(td_fill_right "$label" "$labelwidth" " ")"
            fi

            current="${!key-}"
            if [[ -n "$current" ]]; then
                chosen="$current"
            else
                chosen="$def"
            fi

            if [[ -n "$validator" ]]; then
                ask --label "$label" --var "$key" \
                    --default "$chosen" \
                    --validate "$validator" \
                    --colorize "$colorize"
            else
                ask --label "$label" --var "$key" \
                    --default "$chosen" \
                    --colorize "$colorize"
            fi
        done
    }




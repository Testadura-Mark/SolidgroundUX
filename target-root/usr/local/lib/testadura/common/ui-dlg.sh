# =================================================================================
# Testadura Consultancy — ui-dlg.sh
# ---------------------------------------------------------------------------------
# Purpose    : Non-blocking / timed dialog helpers (TTY status blocks + key handling)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides small dialog-style helpers that render a short status block to the
#   terminal and accept simple key-driven decisions (e.g., auto-continue with
#   pause/cancel/redo/quit). Designed for scripts that want a "soft prompt"
#   experience without full-screen UI frameworks.
#
#   Key characteristics:
#   - Writes directly to /dev/tty (independent of stdin/stdout redirection)
#   - Uses minimal ANSI cursor movement to redraw the dialog block in-place
#   - Returns decision codes instead of enforcing application policy
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - A TTY is available (/dev/tty present and readable/writable).
#   - Theme variables and RESET exist (e.g., TUI_TEXT, TUI_LABEL, RESET).
#   - No full-screen mode is assumed; the caller controls broader UI flow.
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
#   - General-purpose prompting (see ui-ask.sh)
#   - Typed/structured message output (see ui-say.sh)
#   - Full-screen UI frameworks (alternate screen, panes, widgets)
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
    # __dlg_keymap
        # Purpose:
        #   Build a human-readable key legend string for a dialog's current state.
        #
        # Usage:
        #   __dlg_keymap CHOICES [PAUSED]
        #
        # Arguments:
        #   $1  CHOICES : choice string (typically uppercase) describing enabled keys.
        #   $2  PAUSED  : 1 if dialog is currently paused, otherwise 0 (default: 0).
        #
        # Behavior:
        #   - Builds a semicolon-separated legend based on CHOICES:
        #       E => "Enter=continue"
        #       R => "R=redo"
        #       C => "C/Esc=cancel"
        #       Q => "Q=quit"
        #       A => "Press any key to continue"
        #       P => "P/Space=pause" or "P/Space=resume" depending on PAUSED
        #   - Trims the trailing delimiter.
        #
        # Outputs:
        #   Prints the legend string to stdout (no newline policy implied by caller).
        #
        # Returns:
        #   0 always.
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
        #   Render a non-blocking/timed "soft dialog" on /dev/tty with a countdown
        #   and simple key-driven decisions.
        #
        # Usage:
        #   td_dlg_autocontinue [SECONDS] [MESSAGE] [CHOICES]
        #
        # Arguments:
        #   $1  SECONDS : countdown seconds until auto-continue (default: 5).
        #   $2  MESSAGE : optional message shown above the countdown/key legend.
        #   $3  CHOICES : enabled key set (default: "AERCPQ").
        #                Case-insensitive; internally normalized to uppercase.
        #
        # CHOICES (reserved actions):
        #   A  Any key => continue (fallback behavior for unrecognized keys)
        #   E  Enter   => continue
        #   R  R       => redo
        #   C  C/Esc   => cancel
        #   P  P/Space => pause/resume countdown
        #   Q  Q       => quit
        #   H  Hide key legend line
        #
        # CHOICES (custom keys):
        #   Any other single-character keys included in CHOICES are treated as custom return keys.
        #   They do not trigger an action; instead the function returns:
        #     10 for the first custom key (in encounter order),
        #     11 for the second, etc.
        #
        # Behavior:
        #   - Writes the dialog block to /dev/tty (stdin/stdout redirection-safe).
        #   - Redraws in-place using minimal cursor movement (up N lines + carriage return).
        #   - If paused, blocks waiting for a key; otherwise checks for a key with a 1s timeout
        #     and decrements the countdown.
        #   - If /dev/tty is not readable/writable, returns immediately (no dialog shown).
        #
        # Inputs (globals):
        #   Styling: TUI_TEXT, WHITE, FX_ITALIC, RESET (and td_sgr).
        #
        # Returns:
        #   0   continue (Enter if E enabled; any key if A enabled; or allowed continue key)
        #   1   auto-continued (timeout reached)
        #   2   cancel
        #   3   redo
        #   4   quit
        #   10+ custom key index (first custom key = 10)
        #
        # Notes:
        #   - "A" acts as a fallback only after checking for reserved/custom handling.
        #   - The redraw assumes the block height equals:
        #       (optional message line) + (optional keymap line) + countdown line.
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
                if (( seconds <= 0 )); then
                    printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                    return 1
                fi
            fi
        done
    }

    # td_prompt_fromlist
        # Purpose:
        #   Prompt for a list of state/config entries described by "state spec" lines,
        #   assigning results directly to the variables named by each entry.
        #
        # Usage:
        #   td_prompt_fromlist [--labelwidth N] [--autoalign] [--colorize MODE] -- SPEC...
        #
        # Options:
        #   --labelwidth N     Pad labels to width N using td_fill_right (default: 0 = no padding).
        #   --autoalign        Compute label width from the longest label across SPEC lines
        #                      (only if labelwidth is 0/not provided).
        #   --colorize MODE    Passed through to ask --colorize (default: both).
        #   --                End of options; remaining args are SPEC lines.
        #
        # SPEC format:
        #   Each SPEC line is parsed by td_parse_statespec and is expected to yield:
        #     __statekey        variable name to assign
        #     __statelabel      display label (optional; defaults to key)
        #     __statedefault    default value (optional)
        #     __statevalidate   validator function name (optional)
        #
        # Behavior:
        #   - For each SPEC line:
        #       - Parses it via td_parse_statespec.
        #       - Skips invalid keys (must be a valid identifier; uses __td_is_ident).
        #       - Determines current value from the existing shell variable (if set),
        #         otherwise uses the default from the spec.
        #       - Calls ask() with --default and optional --validate.
        #       - Stores the accepted value into the variable named by the spec key.
        #   - If --autoalign is enabled, the function scans all SPEC lines first to
        #     compute a label width (based on label text or key fallback).
        #
        # Inputs (globals / dependencies):
        #   - td_parse_statespec (must set $__statekey, $__statelabel, $__statedefault, $__statevalidate)
        #   - __td_is_ident, td_trim, td_fill_right, ask
        #   - saywarning (optional)
        #
        # Outputs:
        #   None on stdout (interactive prompting happens on /dev/tty via ask()).
        #
        # Returns:
        #   0 always (prompt/orchestration helper; skips invalid entries).
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




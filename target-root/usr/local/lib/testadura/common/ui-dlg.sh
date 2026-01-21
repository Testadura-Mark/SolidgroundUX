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
# Rules / Contract:
#   - Library-only: must be sourced, never executed.
#   - Safe to source multiple times (must be guarded).
#   - Dialog helpers return status codes; callers decide what to do next.
#   - No logging policy decisions and no application-specific branching.
#   - Must not change global shell options (no set -euo pipefail, no stty side
#     effects left behind without restoration).
#
# Non-goals:
#   - General-purpose prompting (see ui-ask.sh)
#   - Typed/structured message output (see ui-say.sh)
#   - Full-screen UI frameworks (alternate screen, panes, widgets)
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_UIDLG_LOADED:-}" ]] && return 0
    TD_UIDLG_LOADED=1

# --- Internal helpers ------------------------------------------------------------
    __dlg_keymap(){
        local choices="$1"
        local keymap=""

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
    # --- td_dlg_autocontinue -----------------------------------------------------
        # Interactive auto-continue dialog with countdown and key controls.
        #
        # Usage:
        #   td_dlg_autocontinue [SECONDS] [MESSAGE] [CHOICES]
        #
        # Arguments:
        #   SECONDS   Seconds before auto-continue (default: 5)
        #   MESSAGE   Optional message shown above the prompt
        #   CHOICES   String of allowed actions:
        #             A = any key → continue
        #             E = Enter → continue
        #             R = R → redo
        #             C = C or Esc → cancel
        #             P = P or Space → pause/resume countdown
        #             Q = Q → quit
        #             H = hide keymap
        #
        # Returns:
        #   0 = continue (Enter / allowed key)
        #   1 = auto-continued (timeout)
        #   2 = cancel
        #   3 = redo
        #   4 = quit
        #
        # Notes:
        #   - Requires an interactive TTY.
        #   - Non-interactive sessions return immediately.
    td_dlg_autocontinue() {
        local seconds="${1:-5}"
        local msg="${2:-}"
        local dlgchoices="${3:-AERCPQ}"

        local tty="/dev/tty"
        [[ -e "$tty" ]] || return 0
        if [[ ! -t 0 && ! -t 1 ]]; then
            return 0
        fi

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

            # Status line (no newline; we keep cursor on this line)
            if (( paused )); then
                printf '\r\e[K%s' "${TUI_ITALIC}Paused... Press P or Space to resume countdown${RESET}" >"$tty"
            else
                printf '\r\e[K%s' "${TUI_ITALIC}Continuing in ${seconds}s...${RESET}" >"$tty"
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
            printf '\r' >"$tty"
            if (( lines == 3 )); then
                printf '\e[2A' >"$tty"
            else
                printf '\e[1A' >"$tty"
            fi

            if (( got )); then
                [[ -z "$key" ]] && key=$'\n'

                case "$key" in
                    p|P|" ")
                        [[ "$dlgchoices" == *"P"* ]] || continue
                        (( paused )) && paused=0 || paused=1
                        continue
                        ;;
                    r|R)
                        [[ "$dlgchoices" == *"R"* || "$dlgchoices" == *"A"* ]] || continue
                        printf '\n' >"$tty"
                        return 3
                        ;;
                    c|C|$'\e')
                        [[ "$dlgchoices" == *"C"* || "$dlgchoices" == *"A"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 2
                        ;;
                    q|Q)
                        [[ "$dlgchoices" == *"Q"* || "$dlgchoices" == *"A"* ]] || continue
                        printf '\n' >"$tty"
                        return 4
                        ;;
                    $'\n'|$'\r')
                        [[ "$dlgchoices" == *"E"* || "$dlgchoices" == *"A"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 0
                        ;;
                    *)
                        [[ "$dlgchoices" == *"A"* ]] || continue
                        printf '\r\e[%dB\n' "$((lines-1))" >"$tty"
                        return 0
                        ;;
                esac
            fi

            if (( ! paused )); then
                ((seconds--))
                if (( seconds <= 0 )); then
                    printf '\n' >"$tty"
                    return 1
                fi
            fi
        done
    }




# =================================================================================
# Testadura Consultancy — ui.sh
# ---------------------------------------------------------------------------------
# Purpose    : UI base layer and shared primitives
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides low-level UI infrastructure and shared helpers used by higher-level
#   UI modules (ui-say.sh, ui-ask.sh).
#
#   This file contains common primitives such as output routing, terminal helpers,
#   and compatibility overrides, but does not implement interaction or formatting
#   logic directly.
#
# Design rules:
#   - No high-level UI behavior (interaction or message formatting).
#   - No logging or policy decisions.
#   - Safe to source multiple times.
#
# Non-goals:
#   - User prompts or dialogs (see ui-ask.sh)
#   - Formatted message output (see ui-say.sh)
# =================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_UI_LOADED:-}" ]] && return 0
    TD_UI_LOADED=1

# --- Overrides -------------------------------------------------------------------
  # _sh_err override: use say --type FAIL if available
  _sh_err() 
  {
      if declare -f say >/dev/null 2>&1; then
          say --type FAIL "$*"
      else
          printf '%s\n' "${*:-(no message)}" >&2
      fi
  }

  # confirm override: use ask with yes/no validation if available
  confirm() 
  {
      if declare -f ask >/dev/null 2>&1; then
          local _ans

          ask \
              --label "${1:-Are you sure?}" \
              --var _ans \
              --default "N" \
              --validate validate_yesno \
              --colorize both \
              --echo

          [[ "$_ans" =~ ^[Yy]$ ]]
      else
          # fallback to the simple core behavior
          read -rp "${1:-Are you sure?} [y/N]: " _a
          [[ "$_a" =~ ^[Yy]$ ]]
      fi
  }

# --- Dialog helpers --------------------------------------------------------------
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

# --- Dialogs ---------------------------------------------------------------------
    # Arguments:
    #   $1 = seconds to wait before auto-continue (default: 5)
    #   $2 = message to display above prompt (default: none)
    #   $3 = allowed choices (string containing any of A,E,R,C,P,Q)
    #         A = any key to continue
    #         E = Enter to continue
    #         R = R to redo
    #         C = C or Esc to cancel
    #         P = P or Space to pause/resume countdown
    #         Q = Q to quit
    #         H = show keymap
    dlg_autocontinue() {
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
                printf '\r\e[K%s\n' "${CLR_TEXT}${msg}${RESET}" >"$tty"
            fi

            # Keymap line
            if (( ! hide_keymap )); then
                printf '\r\e[K%s\n' "${CLR_TEXT}${line_keymap}${RESET}" >"$tty"
            fi

            # Status line (no newline; we keep cursor on this line)
            if (( paused )); then
                printf '\r\e[K%s' "${CLR_TEXT}Paused... Press P or Space to resume countdown${RESET}" >"$tty"
            else
                printf '\r\e[K%s' "${CLR_TEXT}Continuing in ${seconds}s...${RESET}" >"$tty"
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


  


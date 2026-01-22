# =================================================================================
# Testadura Consultancy — ui.sh
# ---------------------------------------------------------------------------------
# Purpose    : Framework UI base layer (shared, low-level output primitives)
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Source this file to get the framework's low-level UI primitives that other
#   UI modules build on (e.g., ui-say.sh, ui-ask.sh). This layer provides:
#   - Output routing and terminal-safe printing helpers
#   - Small rendering utilities (aligned label/value, subheaders, rules)
#   - Compatibility overrides for common helpers (e.g., _sh_err, confirm)
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - Theme variables and RESET are available (e.g., TUI_LABEL, TUI_INPUT, RESET).
#   - core.sh utilities may be used (e.g., td_repeat).
#
# Rules / Contract:
#   - No high-level UI policy or behavior (no prompts, dialogs, workflows).
#   - No message semantics/formatting decisions beyond simple rendering helpers.
#   - No logging policy decisions (where/how to log is handled elsewhere).
#   - Safe to source multiple times (must be guarded).
#   - Library-only: must be sourced, never executed.
#
# Non-goals:
#   - User interaction and prompts (see ui-ask.sh)
#   - Dialogs (see ui-dlg.sh)
#   - Message formatting and typing rules (see ui-say.sh)
#   - Application-specific UI behavior or policy
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



# --- Public API ------------------------------------------------------------------
    # --- td_update_runmode
        # Update the global RUN_MODE label based on current execution mode.
        #
        # Derives a colorized, user-facing run mode indicator ("DRYRUN" or "COMMIT")
        # from FLAG_DRYRUN. Intended for UI display only; does not affect execution logic.
        # Usage:
        #   td_update_runmode
    td_update_runmode() {
        if (( FLAG_DRYRUN )); then
            RUN_MODE="$(td_runmode_color)DRYRUN${RESET}"
        else
            RUN_MODE="$(td_runmode_color)COMMIT${RESET}"
        fi
    }
    # --- td_runmode_color
        # Return the color sequence associated with the current run mode.
        #
        # Outputs the appropriate TUI color escape based on FLAG_DRYRUN.
        # Designed for composition in UI strings; does not include RESET.
        #
        # Usage:
        #   printf '%sRUNMODE%s\n' "$(td_runmode_color)" "$RESET"
    td_runmode_color() {
        (( FLAG_DRYRUN )) && printf '%s' "$TUI_DRYRUN" || printf '%s' "$TUI_COMMIT"
    }

    # --- td_print_globals 
        # Print framework globals (system/user/both/script) using TD_SYS_GLOBALS /
        # TD_USR_GLOBALS / TD_SCRIPT_GLOBALS.
        #
        # Usage:
        #   td_print_globals [sys|usr|both|script]
        #
    td_print_globals() {
        local which="${1:-both}"
        local name
        local -A usr_seen=()

        case "$which" in
            sys)
                for name in "${TD_SYS_GLOBALS[@]:-}"; do
                    __td_print_global "$name"
                done
                ;;

            usr)
                for name in "${TD_USR_GLOBALS[@]:-}"; do
                    __td_print_global "$name"
                done
                ;;

            script)
                for name in "${TD_SCRIPT_SETTINGS[@]:-}"; do
                    __td_print_global "$name"
                done
                ;;

            both)
                # Mark user globals
                for name in "${TD_USR_GLOBALS[@]:-}"; do
                    usr_seen["$name"]=1
                done

                # Print system globals EXCEPT those overridden by user
                for name in "${TD_SYS_GLOBALS[@]:-}"; do
                    [[ -n "${usr_seen[$name]:-}" ]] && continue
                    __td_print_global "$name"
                done

                # Then print user globals
                for name in "${TD_USR_GLOBALS[@]:-}"; do
                    __td_print_global "$name"
                done
                ;;

            *)
                printf 'td_print_globals: invalid selector: %s\n' "$which" >&2
                return 2
                ;;
        esac
    }

    # --- td_print_labeledvalue 
        # Print a single "label : value" line with optional width/sep/colors.
        # Usage:
        #   td_print_labeledvalue "Label" "Value"
        #   td_print_labeledvalue --label "Label" --value "Value" --sep ":" --width 22
    td_print_labeledvalue() {
        local label=""
        local value=""

        local sep=":"
        local width=22
        local labelclr="${TUI_LABEL}"
        local valueclr="${TUI_VALUE}"

        # --- Parse options
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label)
                    label="$2"
                    shift 2
                    ;;
                --value)
                    value="$2"
                    shift 2
                    ;;
                --sep)
                    sep="$2"
                    shift 2
                    ;;
                --width)
                    width="$2"
                    shift 2
                    ;;
                --labelclr)
                    labelclr="$2"
                    shift 2
                    ;;
                --valueclr)
                    valueclr="$2"
                    shift 2
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    # Allow positional fallback: label value
                    if [[ -z "$label" ]]; then
                        label="$1"
                    elif [[ -z "$value" ]]; then
                        value="$1"
                    fi
                    shift
                    ;;
            esac
        done

        [[ -z "$label" ]] && return 0

        # Width safety
        if [[ ! "$width" =~ ^[0-9]+$ ]]; then
            width=22
        fi

        printf ' %s %s %s\n' \
            "${labelclr}$(printf "%-*.*s" "$width" "$width" "$label")${RESET}" \
            "$sep" \
            "${valueclr}${value}${RESET}"
    }

    # --- td_print_fill
        # Print one line with left/right content separated by a fill region.
        # Fill width is computed using visible (ANSI-stripped) lengths.
        #
        # Usage:
        #   td_print_fill "Left" "Right"
        #   td_print_fill --left "Menu" --right "$RUN_MODE" --rightclr "$TUI_HIGHLIGHT"
        #   td_print_fill --fillchar "." --maxwidth 100
    td_print_fill() {
        local left="" right=""
        local padleft=2 padright=1 maxwidth=80
        local fillchar=" "
        local leftclr="${TUI_TEXT}"
        local rightclr=""

        # --- Parse options (with positional fallback)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --left)     left="$2"; shift 2 ;;
                --right)    right="$2"; shift 2 ;;
                --padleft)  padleft="$2"; shift 2 ;;
                --padright) padright="$2"; shift 2 ;;
                --maxwidth) maxwidth="$2"; shift 2 ;;
                --fillchar) fillchar="$2"; shift 2 ;;
                --leftclr)  leftclr="$2"; shift 2 ;;
                --rightclr) rightclr="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    if [[ -z "$left" ]]; then
                        left="$1"
                    elif [[ -z "$right" ]]; then
                        right="$1"
                    fi
                    shift
                    ;;
            esac
        done

        # --- Defaults / safety
        [[ "$padleft"  =~ ^[0-9]+$ ]] || padleft=2
        [[ "$padright" =~ ^[0-9]+$ ]] || padright=1
        [[ "$maxwidth" =~ ^[0-9]+$ ]] || maxwidth=80
        (( maxwidth < 10 )) && maxwidth=10

        # right color inherits left color
        [[ -z "$rightclr" ]] && rightclr="$leftclr"

        # fillchar: single visible char only
        [[ -n "$fillchar" ]] || fillchar=" "
        fillchar="${fillchar:0:1}"

        local fnl="" fill=0

        # --- Build plain layout
        fnl+="$(string_repeat "$fillchar" "$padleft")"

        fill=$(( maxwidth
                - padleft
                - $(visible_len "$left")
                - $(visible_len "$right")
                - padright ))

        (( fill < 0 )) && fill=0

        # --- Render (colors applied last)
        printf '%s%s%s%s%s%s\n' \
            "$(string_repeat "$fillchar" "$padleft")" \
            "${leftclr}${left}${RESET}" \
            "$(string_repeat "$fillchar" "$fill")" \
            "$(string_repeat "$fillchar" "$padright")" \
            "${rightclr}${right}${RESET}" \
            ""
    }

    # --- td_print_titlebar
        # Print a framed title bar with optional right-aligned status text.
        #
        # By default:
        #   - Left text  = script base name
        #   - Right text = RUN_MODE
        #   - Width      = 80 columns
        #
        # Layout and fill behavior are delegated to td_print_sectionheader()
        # and td_print_fill(); this function only wires options together.
    td_print_titlebar() {

        local left="${TD_SCRIPT_TITLE:-$TD_SCRIPT_BASE}"
        local right="${RUN_MODE:-}"
        local leftclr="${TUI_HIGHLIGHT}"
        local rightclr=""                 # let td_print_fill inherit
        local sub="${TD_SCRIPT_DESC:-""}"
        local subclr="${TUI_ITALIC}"
        local border="="
        local borderclr="${TUI_BORDER}"
        local padleft=4
        local maxwidth=80

        # -- Parse options
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --left)      left="$2"; shift 2 ;;
                --leftclr)   leftclr="$2"; shift 2 ;;
                --right)     right="$2"; shift 2 ;;
                --rightclr)  rightclr="$2"; shift 2 ;;
                --sub)       right="$2"; shift 2 ;;
                --subclr)    rightclr="$2"; shift 2 ;;
                --border)    border="$2"; shift 2 ;;
                --borderclr) borderclr="$2"; shift 2 ;;
                --padleft)   padleft="$2"; shift 2 ;;
                --maxwidth)  maxwidth="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    [[ -z "$left" ]] && left="$1"
                    shift
                    ;;
            esac
        done

        td_print
        # -- Numeric safety
        [[ "$padleft"  =~ ^[0-9]+$ ]] || padleft=4
        [[ "$maxwidth" =~ ^[0-9]+$ ]] || maxwidth=80
        (( maxwidth < 10 )) && maxwidth=10
        (( padleft < 0 )) && padleft=0

        td_print_sectionheader \
            --border "$border" \
            --borderclr "$borderclr" \
            --maxwidth "$maxwidth"

        td_print_fill \
            --left "$left" \
            --right "$right" \
            --padleft "$padleft" \
            --maxwidth "$maxwidth" \
            --leftclr "$leftclr" \
            ${rightclr:+--rightclr "$rightclr"}

        if [[ "${sub}" != "" ]]; then
            td_print --text "$sub" --justify "C" --textclr "$subclr"
        fi

        td_print_sectionheader \
            --border "$border" \
            --borderclr "$borderclr" \
            --maxwidth "$maxwidth"
    }

    # --- td_print_sectionheader
        # Print a full-width section header line.
        # Renders optional text with left padding and border fill up to max width.
        # ANSI-safe: visual width is computed after stripping color codes.
        #
        # Usage:
        #   td_print_sectionheader "Title"
        #   td_print_sectionheader --text "Framework info" --maxwidth 80
    td_print_sectionheader() {
        local text=""
        local textclr="${TUI_HIGHLIGHT}"
        local border="-"
        local borderclr="${TUI_BORDER}"
        local padleft=4
        local padend=1
        local maxwidth=80

        # -- Parse options
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --text)      text="$2"; shift 2 ;;
                --textclr)   textclr="$2"; shift 2 ;;
                --border)    border="$2"; shift 2 ;;
                --borderclr) borderclr="$2"; shift 2 ;;
                --padleft)   padleft="$2"; shift 2 ;;
                --padend)    padend="$2"; shift 2 ;;
                --maxwidth)  maxwidth="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    # positional fallback
                    [[ -z "$text" ]] && text="$1"
                    shift
                    ;;
            esac
        done

        # -- Numeric safety
        [[ "$padleft"  =~ ^[0-9]+$ ]] || padleft=4
        [[ "$padend"   =~ ^(0|1)$   ]] || padend=1
        [[ "$maxwidth" =~ ^[0-9]+$ ]] || maxwidth=80
        (( maxwidth < 10 )) && maxwidth=10
        (( padleft < 0 )) && padleft=0

        # -- Assemble line (PLAIN parts first; add color last)
        local left_plain="" mid_plain="" right_plain="" fnl=""
        local remaining=0

        # If no text: full-width border line
        if [[ -z "$text" ]]; then
            fnl="${borderclr}$(string_repeat "$border" "$maxwidth")${RESET}"
            printf '%s\n' "$fnl"
            return 0
        fi

        # Left: "---- " (padleft times border + a space)
        if [[ -n "$border" && $padleft -gt 0 ]]; then
            left_plain="$(string_repeat "$border" "$padleft") "
        fi

        # Middle: "Text"
        mid_plain="$(strip_ansi "$text")"

        if (( padend )); then
            # We will output: left_plain + mid_plain + space + right_plain
            # So count exactly those visible chars.
            local spent=0
            spent=$(( spent + ${#left_plain} ))
            spent=$(( spent + ${#mid_plain} ))
            spent=$(( spent + 1 ))   # space before right fill

            remaining=$(( maxwidth - spent ))
            (( remaining < 0 )) && remaining=0

            if [[ -n "$border" && $remaining -gt 0 ]]; then
                right_plain="$(string_repeat "$border" "$remaining")"
            fi

            if [[ -n "$right_plain" ]]; then
                fnl="${borderclr}${left_plain}${RESET}${textclr}${text}${RESET} ${borderclr}${right_plain}${RESET}"
            else
                fnl="${borderclr}${left_plain}${RESET}${textclr}${text}${RESET}"
            fi
        else
            fnl="${borderclr}${left_plain}${textclr}${text}${RESET}"
        fi

        printf '%s\n' "$fnl"
    }

    # --- td_print
        # Print formatted text with padding, justification, and optional word-wrapping.
        #
        # This is a high-level print helper that decides whether text should be rendered
        # as a single line or wrapped into multiple lines, and delegates the actual
        # rendering of each line to td_print_single().
        #
        # Wrapping behavior:
        # - If --wrap is explicitly specified, that value is always honored.
        # - If --wrap is NOT specified, wrapping is enabled automatically when the
        #   text length exceeds the available width:
        #
        #       available = maxwidth - (pad * 2) - rightmargin
        #
        # - In wrap (multi-line) mode:
        #   - Text is wrapped using td_wrap_words() with the available width.
        #   - Each wrapped line is rendered using td_print_single() with an effective
        #     maxwidth of (maxwidth - rightmargin), creating a visual right margin.
        #
        # - In non-wrapped (single-line) mode:
        #   - The full maxwidth is passed to td_print_single().
        #   - rightmargin has no effect.
        #
        # Parameters:
        #   --text <string>        Text to print (positional fallback supported)
        #   --textclr <ansi>       ANSI color sequence applied to the entire line
        #   --justify <L|C|R>      Text justification: Left (default), Center, Right
        #   --pad <n>              Padding added on both left and right sides (default: 4)
        #   --rightmargin <n>      Reserved margin on the right (wrap mode only)
        #   --maxwidth <n>         Total line width including padding (default: 80)
        #   --wrap <0|1>       Explicit wrap mode; overrides auto-wrap logic
        #
        # Behavior notes:
        # - An empty call prints a blank line.
        # - Text is assumed to be plain (no ANSI escapes); coloring is applied via --textclr.
        # - All layout decisions are made here; td_print_single() is purely a renderer.
        #
        # Examples:
        #   td_print "Hello world"
        #   td_print --text "Centered text" --justify C
        #   td_print --text "Long text" --rightmargin 4
        #   td_print --text "Force wrap" --wrap 1
    td_print() {
        local text=""
        local textclr="${TUI_TEXT:-}"
        local wrap=0
        local wrap_explicit=0
        local pad=4
        local rightmargin=0
        local justify="L"   # L = left, C = center, R = right
        local maxwidth=80

        # --- Parse options --------------------------------------------------------
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --text)         text="$2"; shift 2 ;;
                --textclr)      textclr="$2"; shift 2 ;;
                --justify)      justify="${2^^}"; shift 2 ;;
                --wrap)         wrap="$2"; wrap_explicit=1; shift 2 ;;
                --pad)          pad="$2"; shift 2 ;;
                --rightmargin)  rightmargin="$2"; shift 2 ;;
                --maxwidth)     maxwidth="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    [[ -z "$text" ]] && text="$1"
                    shift
                    ;;
            esac
        done

        # Empty call => newline
        if [[ -z "$text" ]]; then
            td_print_single
            return 0
        fi

        # --- Safety defaults ------------------------------------------------------
        (( pad < 0 )) && pad=0
        (( rightmargin < 0 )) && rightmargin=0
        (( maxwidth < 1 )) && maxwidth=80

        # --- Available width for auto-wrap decision -------------------------------
        local avail=$(( maxwidth - (pad * 2) - rightmargin ))
        (( avail < 1 )) && avail=1

        # --- Auto-wrap if not explicitly specified --------------------------------
        if (( ! wrap_explicit )); then
            (( ${#text} > avail )) && wrap=1 || wrap=0
        fi

        # --- Render ---------------------------------------------------------------
        if (( wrap )); then
            local mw_eff=$(( maxwidth - rightmargin ))
            (( mw_eff < 1 )) && mw_eff=1

            while IFS= read -r line; do
                td_print_single \
                    --text "$line" \
                    --textclr "$textclr" \
                    --pad "$pad" \
                    --justify "$justify" \
                    --maxwidth "$mw_eff"
            done < <(td_wrap_words --width "$avail" --text "$text")
        else
            td_print_single \
                --text "$text" \
                --textclr "$textclr" \
                --pad "$pad" \
                --justify "$justify" \
                --maxwidth "$maxwidth"
        fi
    }

    # --- td_print_single
        # Render a single formatted text line within a fixed width.
        #
        # This is a low-level rendering function used by td_print(). It formats and
        # outputs exactly one line of text, applying padding, justification, and
        # optional coloring. No wrapping or layout decisions are made here.
        #
        # Behavior:
        # - Renders exactly one output line per call.
        # - Text longer than the available width is truncated.
        # - Padding is applied symmetrically on both sides.
        # - Justification is applied within the padded area.
        # - Coloring is applied to the entire rendered line.
        #
        # Available width calculation:
        #   available = maxwidth - (pad * 2)
        #
        # Parameters:
        #   --text <string>        Text to render (positional fallback supported)
        #   --textclr <ansi>       ANSI color sequence applied to the entire line
        #   --justify <L|C|R>      Text justification: Left (default), Center, Right
        #   --pad <n>              Padding on both left and right sides (default: 4)
        #   --maxwidth <n>         Total line width including padding (default: 80)
        #
        # Notes:
        # - If called with no text, a blank line is printed.
        # - Text is assumed to be plain (no ANSI escape sequences).
        # - Width calculations are byte-based and assume a monospaced terminal.
        # - All layout policy (wrapping, margins) must be handled by the caller.
        #
        # Intended use:
        # - Call directly for precise single-line output.
        # - Used internally by td_print() for both single-line and wrapped output.
    td_print_single() {
        local text=""
        local textclr="${TUI_TEXT:-}"
        local pad=4
        local justify="L"
        local maxwidth=80

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --text)      text="$2"; shift 2 ;;
                --textclr)   textclr="$2"; shift 2 ;;
                --justify)   justify="${2^^}"; shift 2 ;;
                --pad)       pad="$2"; shift 2 ;;
                --maxwidth)  maxwidth="$2"; shift 2 ;;
                --) shift; break ;;
                *)
                    [[ -z "$text" ]] && text="$1"
                    shift
                    ;;
            esac
        done

        if [[ -z "$text" ]]; then
            printf "\n"
            return 0
        fi

        (( pad < 0 )) && pad=0
        (( maxwidth < 1 )) && maxwidth=80

        local textlen=${#text}

        local avail=$(( maxwidth - (pad * 2) ))
        (( avail < 1 )) && avail=1

        if (( textlen > avail )); then
            text="${text:0:avail}"
            textlen=${#text}
        fi

        local leftspace=0 rightspace=0
        case "$justify" in
            C)
                leftspace=$(( (avail - textlen) / 2 ))
                rightspace=$(( avail - textlen - leftspace ))
                ;;
            R)
                leftspace=$(( avail - textlen ))
                ;;
            *)
                rightspace=$(( avail - textlen ))
                ;;
        esac

        (( leftspace < 0 )) && leftspace=0
        (( rightspace < 0 )) && rightspace=0

        local line=""
        line+="$(printf '%*s' "$pad" "")"
        line+="$(printf '%*s' "$leftspace" "")"
        line+="$text"
        line+="$(printf '%*s' "$rightspace" "")"
        line+="$(printf '%*s' "$pad" "")"

        printf "%b\n" "${textclr}${line}${RESET}"
    }






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
#   - Core/string helpers exist: td_visible_len, strip_ansi, td_wrap_words, string_repeat.
#   - Theme variables and RESET are available (e.g., TUI_LABEL, TUI_INPUT, RESET).
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
#
# Dependencies / requirements:
#   - Bash (arrays, [[ ]], arithmetic).
#   - Core/string helpers exist: td_visible_len, strip_ansi, td_wrap_words, string_repeat.
#   - Theme variables and RESET are available (e.g., TUI_LABEL, TUI_INPUT, RESET).
#
# TTY note:
#   Output helpers emit ANSI styling if the theme variables include escapes.
#   Non-TTY consumers (pipes/logs) may see raw escapes unless upstream disables them.
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

# --- Compatibility overrides -----------------------------------------------------
    # Shims to integrate with legacy helpers if present (say/ask), with safe fallbacks.
    # These overrides are intentionally small and policy-free.

    # _sh_err
        # Purpose:
        #   Compatibility shim for legacy "_sh_err" error reporting.
        #
        # Usage:
        #   _sh_err "message..."
        #
        # Behavior:
        #   - If say() exists, emits a FAIL message via: say --type FAIL "$*"
        #   - Otherwise prints the message to stderr.
        #
        # Output:
        #   One line to stderr (directly or via say()).
        #
        # Returns:
        #   0 always.
  _sh_err() {
      if declare -f say >/dev/null 2>&1; then
          say --type FAIL "$*"
      else
          printf '%s\n' "${*:-(no message)}" >&2
      fi
  }

  # confirm
    #   Compatibility override for legacy "confirm" yes/no prompts.
    #
    # Behavior:
    #   - If ask() exists, uses it with yes/no validation (default: N).
    #   - Otherwise falls back to read -rp prompt [y/N].
    #
    # Returns:
    #   0 if user answered yes (Y/y), 1 otherwise.
    #
    # Notes:
    #   - This is intentionally minimal; higher-level prompt policy belongs in ui-ask.sh.
  confirm() {
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

# --- Helpers ---------------------------------------------------------------------
    # __td_ui_resolve_theme_file
        # Purpose:
        #   Resolve a palette/style spec into a readable .sh file path.
        #
        # Usage:
        #   __td_ui_resolve_theme_file KIND SPEC
        #
        # Arguments:
        #   $1  KIND : "palettes" | "styles"
        #   $2  SPEC : either:
        #       - explicit path (contains '/' or ends with .sh), OR
        #       - logical name (resolved as "$TD_UI_THEME_DIR/<KIND>/<SPEC>.sh")
        #
        # Output:
        #   Prints the resolved file path to stdout (no newline).
        #
        # Returns:
        #   0  resolved and readable
        #   2  missing SPEC
        #   3  explicit path provided but not readable
        #   4  theme base directory not set (TD_UI_THEME_DIR missing)
        #   5  named theme not found under theme directory
    __td_ui_resolve_theme_file() {
        local kind="$1"
        local spec="$2"
        local base
        local file

        if [[ -z "$spec" ]]; then
            printf '__td_ui_resolve_theme_file: missing %s spec\n' "$kind" >&2
            return 2
        fi

        # Treat as explicit file path if it looks like a path or ends with .sh
        if [[ "$spec" == */* || "$spec" == *.sh ]]; then
            file="$spec"
            [[ "$file" != *.sh ]] && file="${file}.sh"
            if [[ -r "$file" ]]; then
                printf '%s' "$file"
                return 0
            fi
            printf 'UI theme %s file not found/readable: %s\n' "$kind" "$file" >&2
            return 3
        fi

        # Name resolution under theme dir
        base="${TD_UI_THEME_DIR-}"
        if [[ -z "$base" ]]; then
            printf 'UI theme directory not set (TD_UI_THEME_DIR/TD_FRAMEWORK_ROOT missing)\n' >&2
            return 4
        fi

        file="${base%/}/${kind}/${spec}.sh"
        if [[ -r "$file" ]]; then
            printf '%s' "$file"
            return 0
        fi

        printf 'UI theme %s "%s" not found at: %s\n' "$kind" "$spec" "$file" >&2
        return 5
    }

# --- Public API ------------------------------------------------------------------
 # -- Public helpers --------------------------------------------------------------
    # td_strip_ansi
        # Purpose:
        #   Strip ANSI CSI escape sequences (sufficient for SGR styling) from a string.
        #
        # Usage:
        #   td_strip_ansi "text"
        #
        # Output:
        #   Prints the sanitized string to stdout.
        #
        # Notes:
        #   - Uses a regex that removes ESC[...<alpha> sequences.
        #   - Intended mainly for SGR (ESC[...m) and similar CSI codes used by the framework.
        #
        # Returns:
        #   0 always.
  td_strip_ansi() {
    sed -r $'s/\x1B\\[[0-9;?]*[[:alpha:]]//g' <<<"$1"
  }

  # td_visible_len
    # Purpose:
    #   Return the visible length (terminal columns) of a string after stripping ANSI.
    #
    # Usage:
    #   td_visible_len "text"
    #
    # Output:
    #   Prints an integer length to stdout (no newline).
    #
    # Notes:
    #   - Byte-count based; assumes monospaced terminal and no multi-column glyphs.
    #
    # Returns:
    #   0 always.
  td_visible_len() {
      local plain
      plain="$(td_strip_ansi "$1")"
      printf '%s' "${#plain}"
  }

 # -- Theme loading ---------------------------------------------------------------
    # td_ui_set_theme
        # Purpose:
        #   Load a UI palette and UI style (in that order) into the current shell.
        #
        # Usage:
        #   td_ui_set_theme --palette <file|name> --style <file|name>
        #   td_ui_set_theme --default
        #   td_ui_set_theme <palette> <style>         # shorthand positional form
        #
        # Resolution rules:
        #   - If a spec contains '/' or ends with .sh, it is treated as a file path.
        #   - Otherwise it is treated as a name and resolved under:
        #       $TD_UI_THEME_DIR/palettes/<name>.sh
        #       $TD_UI_THEME_DIR/styles/<name>.sh
        #
        # Theme dir:
        #   - If TD_UI_THEME_DIR is unset and TD_FRAMEWORK_ROOT is set, derives:
        #       TD_UI_THEME_DIR="$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common/ui"
        #   - If both are missing, name-based resolution will fail.
        #
        # Side effects (globals):
        #   TD_UI_THEME_DIR, TD_UI_PALETTE_FILE, TD_UI_STYLE_FILE, plus all variables
        #   defined by the sourced palette/style files.
        #
        # Returns:
        #   0  success (or --help)
        #   2  unexpected argument (too many positionals / unknown token)
        #   4/5/3  resolution failures from __td_ui_resolve_theme_file
        #   10 palette load failed
        #   11 palette did not define RESET
        #   12 style load failed
    td_ui_set_theme() {
        local palette_spec=""
        local style_spec=""
        local use_default=0

        local a
        while (($#)); do
            a="$1"
            case "$a" in
                --palette) palette_spec="${2-}"; shift 2 ;;
                --style)   style_spec="${2-}"; shift 2 ;;
                --default) use_default=1; shift ;;
                -h|--help)
                    printf '%s\n' \
                        "td_ui_set_theme --palette <file|name> --style <file|name>" \
                        "td_ui_set_theme --default"
                    return 0
                    ;;
                *)
                    # allow shorthand: td_ui_set_theme palette style
                    if [[ -z "$palette_spec" ]]; then
                        palette_spec="$a"
                    elif [[ -z "$style_spec" ]]; then
                        style_spec="$a"
                    else
                        printf 'td_ui_set_theme: unexpected argument: %s\n' "$a" >&2
                        return 2
                    fi
                    shift
                    ;;
            esac
        done

        if (( use_default )); then
            palette_spec="default-ui-palette"
            style_spec="default-ui-style"
        fi

        # Theme root (where palettes/ and styles/ live)
        if [[ -z "${TD_UI_THEME_DIR-}" ]]; then
            if [[ -n "${TD_FRAMEWORK_ROOT-}" ]]; then
                TD_UI_THEME_DIR="${TD_FRAMEWORK_ROOT%/}/usr/local/lib/testadura/common/ui"
            else
                # fallback: relative to this file if possible
                TD_UI_THEME_DIR=""
            fi
        fi

        # --- resolve palette/style -------------------------------------------------
        local palette_file
        local style_file

        palette_file="$(__td_ui_resolve_theme_file "palettes" "$palette_spec")" || return $?
        style_file="$(__td_ui_resolve_theme_file "styles"   "$style_spec")"   || return $?

        # --- load palette first, then style ---------------------------------------
        # shellcheck disable=SC1090
        source "$palette_file" || {
            printf 'td_ui_set_theme: failed to load palette: %s\n' "$palette_file" >&2
            return 10
        }

        # Minimal sanity: palette should define RESET
        if [[ -z "${RESET-}" ]]; then
            printf 'td_ui_set_theme: palette did not define RESET: %s\n' "$palette_file" >&2
            return 11
        fi

        # shellcheck disable=SC1090
        source "$style_file" || {
            printf 'td_ui_set_theme: failed to load style: %s\n' "$style_file" >&2
            return 12
        }

        TD_UI_PALETTE_FILE="$palette_file"
        TD_UI_STYLE_FILE="$style_file"

        return 0
    }

    # td_ui_set_default_theme
        # Purpose:
        #   Convenience wrapper to load the default palette + style.
        #
        # Usage:
        #   td_ui_set_default_theme
        #
        # Equivalent:
        #   td_ui_set_theme --default
        #
        # Returns:
        #   Whatever td_ui_set_theme returns.
    td_ui_set_default_theme() {
        td_ui_set_theme --default
    }

 # -- Styling helpers -------------------------------------------------------------
    # td_sgr
        # Purpose:
        #   Build ONE canonical ANSI SGR escape (ESC[...m) from mixed inputs.
        #
        # Usage:
        #   td_sgr <part...>
        #
        # Accepts:
        #   - Numeric SGR params (e.g. 1 bold, 4 underline, 7 reverse)
        #   - Full SGR escapes like: $'\e[38;5;46m'
        #
        # Behavior:
        #   - Extracts inner parameters from any ESC[...m input.
        #   - Merges all parts into a single ESC[<joined>m sequence.
        #   - Ignores empty/unrecognized parts.
        #
        # Output:
        #   Prints the SGR prefix to stdout (no newline).
        #
        # Returns:
        #   0 always (construction-only).
        #
        # Notes:
        #   - Does not validate terminal support.
        #   - If no valid parts are provided, prints "${RESET-}" (may be empty).
    td_sgr() {
        local -a parts=()
        local arg
        local inner

        for arg in "$@"; do
            [[ -z "${arg:-}" ]] && continue

            # Numeric: treat as SGR parameter
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                parts+=( "$arg" )
                continue
            fi

            # Escape: extract "38;5;46" from $'\e[38;5;46m'
            if [[ "$arg" == $'\e['*m ]]; then
                inner="${arg#$'\e['}"
                inner="${inner%m}"
                [[ -n "$inner" ]] && parts+=( "$inner" )
                continue
            fi
        done

        if (( ${#parts[@]} == 0 )); then
            printf '%s' "${RESET-}"
            return 0
        fi

        printf $'\e[%sm' "$(IFS=';'; echo "${parts[*]}")"
    }

    # td_fg
        # Purpose:
        #   Convenience wrapper to build a foreground SGR prefix (+ optional effects).
        #
        # Usage:
        #   td_fg <fg> [fx...]
        #
        # Output:
        #   Prints an SGR prefix to stdout (no newline).
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - This is syntactic sugar for: td_sgr "$fg" "" [fx...]
    td_fg() {  # td_fg <fg> [fx...]
        local fg="${1:-}"
        shift || true
        td_sgr "$fg" "" "$@"
    }

    # td_bg
        # Purpose:
        #   Convenience wrapper to build a background SGR prefix (+ optional effects).
        #
        # Usage:
        #   td_bg <bg> [fx...]
        #
        # Output:
        #   Prints an SGR prefix to stdout (no newline).
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - This is syntactic sugar for: td_sgr "" "$bg" [fx...]
    td_bg() {  # td_bg <bg> [fx...]
        local bg="${1:-}"
        shift || true
        td_sgr "" "$bg" "$@"
    }

 # -- Runmode indicators ----------------------------------------------------------
    # td_update_runmode
        # Purpose:
        #   Update the global RUN_MODE indicator ("DRYRUN" or "COMMIT") with styling.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN (0/1)
        #   RESET
        #   td_runmode_color() (uses TUI_DRYRUN / TUI_COMMIT)
        #
        # Outputs (globals):
        #   RUN_MODE  Styled string ending with RESET (suitable for title bars).
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - UI-only indicator; does not affect execution logic.
    td_update_runmode() {
        if (( FLAG_DRYRUN )); then
            RUN_MODE="$(td_runmode_color)DRYRUN${RESET}"
        else
            RUN_MODE="$(td_runmode_color)COMMIT${RESET}"
        fi
    }

    # td_runmode_color
        # Purpose:
        #   Return the ANSI prefix associated with the current run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #   TUI_DRYRUN, TUI_COMMIT
        #
        # Output:
        #   Prints an ANSI prefix (no newline, no RESET).
        #
        # Returns:
        #   0 always.
    td_runmode_color() {
        (( FLAG_DRYRUN )) && printf '%s' "$TUI_DRYRUN" || printf '%s' "$TUI_COMMIT"
    }

 # -- Rendering primitives --------------------------------------------------------
    # td_print_labeledvalue
        # Purpose:
        #   Print one aligned "Label : Value" line with optional coloring.
        #
        # Usage:
        #   td_print_labeledvalue "Label" "Value"
        #   td_print_labeledvalue --label "Label" --value "Value" [opts]
        #
        # Options:
        #   --sep <text>         Separator token (default ":")
        #   --width <n>          Fixed label width (default 25)
        #   --pad <n>            Left indentation (default 0)
        #   --labelclr <ansi>    Label color prefix (default TUI_LABEL)
        #   --valueclr <ansi>    Value color prefix (default TUI_VALUE)
        #
        # Output:
        #   Writes one line to stdout.
        #
        # Returns:
        #   0 always (no-op if label missing).
        #
        # Notes:
        #   - Only the label is width-clamped; the value is not truncated.
        #   - Always appends RESET after colored segments.
    td_print_labeledvalue() {
        local label=""
        local value=""

        local sep=":"
        local width=25
        local pad=0
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
                --pad)
                    pad="$2"
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

        # Width / pad safety
        [[ "$width" =~ ^[0-9]+$ ]] || width=22
        [[ "$pad"   =~ ^[0-9]+$ ]] || pad=4

        printf '%*s%s %s %s\n' \
            "$pad" "" \
            "${labelclr}$(printf "%-*.*s" "$width" "$width" "$label")${RESET}" \
            "$sep" \
            "${valueclr}${value}${RESET}"
    }

    # td_print_fill
        # Purpose:
        #   Print one line with left/right content separated by a fill region.
        #
        # Usage:
        #   td_print_fill "Left" "Right"
        #   td_print_fill --left "Menu" --right "$RUN_MODE" [opts]
        #
        # Options:
        #   --padleft/--padright <n>   Fill padding counts (default 2 / 1)
        #   --maxwidth <n>             Total width (default 80)
        #   --fillchar <c>             Single visible fill character (default space)
        #   --leftclr/--rightclr <ansi> ANSI prefixes (right defaults to left)
        #
        # Output:
        #   Writes one line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Uses td_visible_len (ANSI-safe) for alignment.
        #   - fillchar is truncated to one character.
        #   - Always appends RESET after colored segments.
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

        fill=$(( maxwidth
                - padleft
                - $(td_visible_len "$left")
                - $(td_visible_len "$right")
                - padright ))

        (( fill < 0 )) && fill=0

        # --- Render (colors applied last)
        printf '%s%s%s%s%s%s\n' \
            "$(td_string_repeat "$fillchar" "$padleft")" \
            "${leftclr}${left}${RESET}" \
            "$(td_string_repeat "$fillchar" "$fill")" \
            "$(td_string_repeat "$fillchar" "$padright")" \
            "${rightclr}${right}${RESET}" \
            ""
    }

    # td_print_titlebar
        # Purpose:
        #   Print a framed title bar: border, header line (left/right), optional subtitle, border.
        #
        # Usage:
        #   td_print_titlebar [opts]
        #
        # Defaults:
        #   --left     = TD_SCRIPT_TITLE (or TD_SCRIPT_BASE)
        #   --right    = RUN_MODE
        #   --sub      = TD_SCRIPT_DESC (if non-empty)
        #   --maxwidth = 80
        #
        # Options:
        #   --left/--right <text>
        #   --leftclr/--rightclr <ansi>
        #   --sub <text>              Subtitle line (optional)
        #   --subclr <ansi>
        #   --subjust <L|C|R>         Subtitle justification (default C)
        #   --border <char>           Border character (default "=")
        #   --borderclr <ansi>        Border color (default TUI_BORDER)
        #   --padleft <n>             Left indentation for fill layout (default 4)
        #   --maxwidth <n>            Total width (default 80)
        #
        # Output:
        #   Writes multiple lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Delegates to td_print_sectionheader, td_print_fill, td_print.
    td_print_titlebar() {

        local left="${TD_SCRIPT_TITLE:-$TD_SCRIPT_BASE}"
        local right="${RUN_MODE:-}"
        local leftclr="$(td_sgr "$WHITE" "" "$FX_BOLD")"
        local rightclr=""                 # let td_print_fill inherit
        local sub="${TD_SCRIPT_DESC:-""}"
        local subclr="$(td_sgr "$WHITE" "" "$FX_ITALIC")"
        local subjust="C"
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
                --sub)       sub="$2"; shift 2 ;;
                --subclr)    subclr="$2"; shift 2 ;;
                --subjust)   subjust="$2"; shift 2 ;;
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
           td_print \
            --text "$sub" \
            --justify "$subjust" \
            --textclr "$subclr" \
            --rightmargin "$(td_visible_len "$right")"
        fi

        td_print_sectionheader \
            --border "$border" \
            --borderclr "$borderclr" \
            --maxwidth "$maxwidth"
    }

    # td_print_sectionheader
        # Purpose:
        #   Print a divider line with optional title text.
        #
        # Usage:
        #   td_print_sectionheader
        #   td_print_sectionheader "Title"
        #   td_print_sectionheader --text "Title" [opts]
        #
        # Options:
        #   --text <text>          Title text (positional fallback supported)
        #   --textclr <ansi>       Title color (default bold white)
        #   --border <char>        Border character (default "-")
        #   --borderclr <ansi>     Border color (default TUI_BORDER)
        #   --padleft <n>          Border count before title (default 4)
        #   --padend <0|1>         Fill to maxwidth after title (default 1)
        #   --maxwidth <n>         Total width (default 80)
        #
        # Output:
        #   Writes one line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - ANSI-safe: width calculations are based on td_strip_ansi(text).
    td_print_sectionheader() {
        local text=""
        local textclr="$(td_sgr "$WHITE" "" "$FX_BOLD")"
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
            fnl="${borderclr}$(td_string_repeat "$border" "$maxwidth")${RESET}"
            printf '%s\n' "$fnl"
            return 0
        fi

        # Left: "---- " (padleft times border + a space)
        if [[ -n "$border" && $padleft -gt 0 ]]; then
            left_plain="$(td_string_repeat "$border" "$padleft") "
        fi

        # Middle: "Text"
        mid_plain="$(td_strip_ansi "$text")"

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
                right_plain="$(td_string_repeat "$border" "$remaining")"
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

    # td_print
        # Purpose:
        #   Print formatted text with padding, justification, and optional word-wrapping.
        #
        # Usage:
        #   td_print
        #   td_print "Text"
        #   td_print --text "Text" [opts]
        #
        # Options:
        #   --text <string>        Text to print (positional fallback supported)
        #   --textclr <ansi>       ANSI color prefix (applied to the full rendered line)
        #   --justify <L|C|R>      Justification (default L)
        #   --pad <n>              Left/right padding (default 0)
        #   --rightmargin <n>      Reserved right margin (wrap mode only; default 0)
        #   --maxwidth <n>         Total width including padding (default 80)
        #   --wrap <0|1>           Explicit wrap mode; overrides auto-wrap
        #
        # Behavior:
        #   - Empty call prints a blank line.
        #   - If --wrap is not specified, auto-wrap is enabled when text exceeds:
        #       maxwidth - (pad * 2) - rightmargin
        #   - In wrap mode, wraps using td_wrap_words and prints multiple lines,
        #     using (maxwidth - rightmargin) as the effective width for rendering.
        #
        # Output:
        #   Writes one or more lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Dependencies:
        #   - td_wrap_words (external to this file)
    td_print() {
        local text=""
        local textclr="${TUI_TEXT:-}"
        local wrap=0
        local wrap_explicit=0
        local pad=0
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

    # td_print_single
        # Purpose:
        #   Render exactly one formatted line within a fixed width (no wrapping).
        #
        # Usage:
        #   td_print_single
        #   td_print_single "Text"
        #   td_print_single --text "Text" [opts]
        #
        # Options:
        #   --text <string>        Text to render (positional fallback supported)
        #   --textclr <ansi>       ANSI color prefix for the entire rendered line
        #   --justify <L|C|R>      Justification (default L)
        #   --pad <n>              Left/right padding (default 0)
        #   --maxwidth <n>         Total width including padding (default 80)
        #
        # Behavior:
        #   - Empty call prints a blank line.
        #   - If text exceeds available width (maxwidth - pad*2), it is truncated.
        #   - Width math is byte-based (monospace assumptions).
        #
        # Output:
        #   Writes one line to stdout.
        #
        # Returns:
        #   0 always.
    td_print_single() {
        local text=""
        local textclr="${TUI_TEXT:-}"
        local pad=0
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

    # td_print_file
        # Purpose:
        #   Print a text file to stdout, paging when interactive.
        #
        # Usage:
        #   td_print_file <path>
        #
        # Behavior:
        #   - If stdout is a TTY and "less" exists, pages output using: less -FRSX
        #   - For Markdown (*.md), tries richer viewers in this order:
        #       glow (pager mode), mdcat, bat, pandoc->plain, then plain
        #   - For non-TTY output (pipes/redirects), prints without paging.
        #
        # Returns:
        #   0 on success (viewer return code)
        #   2 on missing/unreadable file
        #
        # Notes:
        #   - Viewer availability is runtime-dependent (command -v checks).
        #   - Assumes text input (no encoding detection).
    td_print_file() {
        local file="$1"
        
        [[ -n "${file:-}" ]] || { printf "ERROR: td_print_file: missing file\n" >&2; return 2; }
        [[ -r "$file" ]]      || { printf "ERROR: td_print_file: not readable: %s\n" "$file" >&2; return 2; }

        
        local ext="${file##*.}"
        local is_tty=0
        [[ -t 1 ]] && is_tty=1

        # Pager (only if interactive)
        local pager_cmd=()
        if (( is_tty )); then
            if command -v less >/dev/null 2>&1; then
                pager_cmd=( less -FRSX )
            fi
        fi

        # Markdown render if possible
        if [[ "${ext,,}" == "md" ]]; then
            if command -v glow >/dev/null 2>&1; then
                # glow pages itself; use -p for pager mode
                glow -p "$file"
                return $?
            fi

            if command -v mdcat >/dev/null 2>&1; then
                if (( is_tty )) && ((${#pager_cmd[@]})); then
                    mdcat "$file" | "${pager_cmd[@]}"
                else
                    mdcat "$file"
                fi
                return $?
            fi

            if command -v bat >/dev/null 2>&1; then
                # bat handles paging/highlighting nicely
                bat --language=md --style=plain --paging=auto "$file"
                return $?
            fi

            if command -v pandoc >/dev/null 2>&1; then
                # Render to plain text
                if (( is_tty )) && ((${#pager_cmd[@]})); then
                    pandoc -t plain "$file" | "${pager_cmd[@]}"
                else
                    pandoc -t plain "$file"
                fi
                return $?
            fi
        fi

        # Plain text fallback
        if (( is_tty )) && ((${#pager_cmd[@]})); then
            "${pager_cmd[@]}" "$file"
        else
            cat -- "$file"
        fi
    }
    
    # td_print_cell
        # Purpose:
        #   Print a fixed-width “cell” that may contain ANSI CSI sequences (SGR colors/effects).
        #
        # Usage:
        #   td_print_cell <width> <text_with_ansi>
        #
        # Output:
        #   Writes the padded cell to stdout (no newline).
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Pads based on visible length after stripping CSI sequences.
        #   - Does not truncate: if visible text is longer than width, prints as-is.
    td_print_cell() {
        local width="$1"
        local s="$2"

        # Strip ANSI CSI sequences for visible length calculation
        local plain
        plain="$(printf '%s' "$s" | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g')"

        local vislen="${#plain}"
        local pad=$(( width - vislen ))
        (( pad < 0 )) && pad=0

        printf '%s%*s' "$s" "$pad" ""
    }

 # -- Externals -------------------------------------------------------------------
 # -- Sample/demo renderers -------------------------------------------------------
    # td_color_samples
        # Purpose:
        #   Print a demo table of available palette colors and common effects.
        #
        # Usage:
        #   td_color_samples
        #
        # Output:
        #   Writes a formatted demo to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Intended for palette/style development and sanity checks.
    td_color_samples()
    {
        printf '\n%s\n\n' "---- Available foreground colors & effects in SolidgroundUX ----"

        td_sample_row	BLUE	BRIGHT_BLUE	    DARK_BLUE	    BG_BLUE	    BG_DARK_BLUE
        td_sample_row	BROWN	BRIGHT_BROWN	DARK_BROWN      BG_BROWN	BG_DARK_BROWN
        td_sample_row	CYAN	BRIGHT_CYAN	    DARK_CYAN	    BG_CYAN	    BG_DARK_CYAN
        td_sample_row	GOLD	BRIGHT_GOLD	    DARK_GOLD	    BG_GOLD	    BG_DARK_GOLD
        td_sample_row	GREEN	BRIGHT_GREEN	DARK_GREEN	    BG_GREEN	BG_DARK_GREEN
        td_sample_row	MAGENTA	BRIGHT_MAGENTA	DARK_MAGENTA	BG_MAGENTA	BG_DARK_MAGENTA
        td_sample_row	ORANGE	BRIGHT_ORANGE	DARK_ORANGE	    BG_ORANGE	BG_DARK_ORANGE
        td_sample_row	PINK	BRIGHT_PINK	    DARK_PINK	    BG_PINK	    BG_DARK_PINK
        td_sample_row	PURPLE	BRIGHT_PURPLE	DARK_PURPLE	    BG_PURPLE	BG_DARK_PURPLE
        td_sample_row	RED	    BRIGHT_RED	    DARK_RED	    BG_RED	    BG_DARK_RED
        td_sample_row	TEAL	BRIGHT_TEAL	    DARK_TEAL	    BG_TEAL	    BG_DARK_TEAL
        td_sample_row	WHITE	BRIGHT_WHITE	DARK_WHITE	    BG_WHITE	BG_DARK_WHITE
        td_sample_row	YELLOW	BRIGHT_YELLOW	DARK_YELLOW	    BG_YELLOW	BG_DARK_YELLOW

    }

    # td_sample_row
        # Purpose:
        #   Internal helper used by td_color_samples to render one row of samples.
        #
        # Usage:
        #   td_sample_row <NAME> [NAME...]
        #
        # Arguments:
        #   NAME is the variable name holding an ANSI escape (e.g. BLUE=$'\e[34m').
        #
        # Behavior:
        #   - Uses eval to retrieve the value of each named color variable.
        #   - Prints a fixed-width cell containing the variable name in that style.
        #   - Prints multiple effect samples (bold/faint/italic/underline/reverse/strike).
        #
        # Output:
        #   Writes one line per NAME to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Uses eval; safe here because NAME tokens come from the framework palette list.
    td_sample_row(){
        local clr name val

        for clr in "$@"; do
            eval "val=\${$clr}"

            td_print_cell 20 "$val$clr$RESET"

            # Bold
            printf "%sBOLD%s\t" \
                "$(td_sgr "$val" "" "$FX_BOLD")" \
                "$RESET"

            # Faint / Dim
            printf "%sFAINT%s\t" \
                "$(td_sgr "$val" "" "$FX_FAINT")" \
                "$RESET"

            # Italic
            printf "%sITALIC%s\t" \
                "$(td_sgr "$val" "" "$FX_ITALIC")" \
                "$RESET"

            # Underline
            printf "%sUNDER%s\t" \
                "$(td_sgr "$val" "" "$FX_UNDERLINE")" \
                "$RESET"

            # Reverse
            printf "%sREVERSE%s\t" \
                "$(td_sgr "$val" "" "$FX_REVERSE")" \
                "$RESET"

            # Strikethrough
            printf "%sSTRIKE%s\t" \
                "$(td_sgr "$val" "" "$FX_STRIKE")" \
                "$RESET"

            printf "\n"    
        done

        printf "\n"
    }

    # td_style_samples
        # Purpose:
        #   Print a demo of semantic UI/style variables (message colors + UI element colors).
        #
        # Usage:
        #   td_style_samples
        #
        # Output:
        #   Writes a formatted list to stdout showing:
        #     - MSG_CLR_* (say/info/warn/fail/etc.)
        #     - TUI_* semantic UI colors (labels, borders, run mode, prompt/input, etc.)
        #
        # Returns:
        #   0 always.
        #
        # Notes:
        #   - Useful for verifying that palette/style files were loaded correctly.
    td_style_samples(){
        printf '\n%s\n\n' "---- Message colors (Say) ----"
       
        printf '%s\n' "${MSG_CLR_INFO}MSG_CLR_INFO${RESET}"
        printf '%s\n' "${MSG_CLR_STRT}MSG_CLR_STRT${RESET}"
        printf '%s\n' "${MSG_CLR_OK}MSG_CLR_OK${RESET}"
        printf '%s\n' "${MSG_CLR_WARN}MSG_CLR_WARN${RESET}"
        printf '%s\n' "${MSG_CLR_FAIL}MSG_CLR_FAIL${RESET}"
        printf '%s\n' "${MSG_CLR_CNCL}MSG_CLR_CNCL${RESET}"
        printf '%s\n' "${MSG_CLR_END}MSG_CLR_END${RESET}"
        printf '%s\n' "${MSG_CLR_EMPTY}MSG_CLR_EMPTY${RESET}"
        printf '%s\n' "${MSG_CLR_DEBUG}MSG_CLR_DEBUG${RESET}"

        printf '\n%s\n\n' "---- Ui element color ----"
        printf '%s\n' "${TUI_BORDER}TUI_BORDER${RESET}"

        printf '%s\n' "${TUI_LABEL}TUI_LABEL${RESET} : ${TUI_VALUE}TUI_VALUE${RESET}"

        printf '%s\n' "${TUI_COMMIT}TUI_COMMIT${RESET}/${TUI_DRYRUN}TUI_DRYRUN${RESET}"
        printf '%s\n' "${TUI_ENABLED}TUI_ENABLED${RESET}/${TUI_DISABLED}TUI_DISABLED${RESET}"
        printf '%s\n' "${TUI_PROMPT}TUI_PROMPT${RESET} : ${TUI_INPUT}TUI_INPUT${RESET}"

        printf '%s\n' "${TUI_INVALID}TUI_INVALID${RESET}/${TUI_VALID}TUI_VALID${RESET}"
        
        printf '%s\n' "${TUI_SUCCESS}TUI_SUCCESS${RESET}"
        printf '%s\n' "${TUI_ERROR}TUI_ERROR${RESET}"

        printf '%s\n' "${TUI_TEXT}TUI_TEXT${RESET}"

        printf '%s\n' "${TUI_DEFAULT}TUI_DEFAULT${RESET}"

    }






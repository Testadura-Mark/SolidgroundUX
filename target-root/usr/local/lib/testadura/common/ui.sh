# =================================================================================
# Testadura Consultancy — Terminal UI Rendering Module
# ---------------------------------------------------------------------------------
# Module     : ui.sh
# Purpose    : Core terminal UI rendering utilities (colors, formatting, output)
#
# Description:
#   Provides a consistent abstraction layer for rendering styled output in the
#   terminal. Wraps ANSI escape sequences and centralizes visual behavior such as:
#     - colors and text attributes
#     - message formatting (info, warning, error, debug, etc.)
#     - standardized console output conventions
#
#   Ensures consistent look-and-feel across all Testadura / SolidGround scripts.
#
# Core capabilities:
#   - ANSI color and style handling via td_sgr
#   - Predefined message helpers (say, sayinfo, saywarn, sayfail, etc.)
#   - Conditional output (verbosity, debug, dry-run awareness)
#   - Formatting helpers for emphasis and readability
#
# Design principles:
#   - Centralized styling (no inline ANSI codes in modules)
#   - Readability over visual complexity
#   - Graceful degradation when styling is disabled
#   - Consistent message semantics across the framework
#
# Typical usage:
#   sayinfo "Starting process..."
#   saywarn "Configuration missing, using defaults"
#   sayfail "Operation failed"
#
#   clr="$(td_sgr "$BRIGHT_GREEN" "" "$FX_BOLD")"
#   printf "%sSuccess%s\n" "$clr" "$(td_sgr_reset)"
#
# Role in framework:
#   - Forms the visual layer of the framework
#   - Used by all modules for user interaction and feedback
#   - Supports higher-level UI modules (console menus, dialogs, etc.)
#
# Non-goals:
#   - No layout engine (handled by higher-level modules)
#   - No input handling (handled by dialog/console modules)
#   - No terminal capability detection beyond basic needs
#
# Author     : Mark Fieten
# Copyright  : © 2025 Mark Fieten — Testadura Consultancy
# License    : Testadura Non-Commercial License (TD-NC) v1.0
# =================================================================================
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

# --- Compatibility overrides -----------------------------------------------------
    # Shims to integrate with legacy helpers if present (say/ask), with safe fallbacks.
    # These overrides are intentionally small and policy-free.

    # _sh_err
        # Purpose:
        #   Compatibility shim for legacy "_sh_err" error reporting.
        #
        # Behavior:
        #   - If say() exists, emits a FAIL message via say --type FAIL.
        #   - Otherwise prints the message directly to stderr.
        #
        # Arguments:
        #   $*  MESSAGE
        #       Error text to report.
        #
        # Side effects:
        #   - Writes one error line to stderr, directly or via say().
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   _sh_err "Something went wrong"
        #
        # Examples:
        #   _sh_err "Palette file missing"
    _sh_err() {
        if declare -f say >/dev/null 2>&1; then
            say --type FAIL "$*"
        else
            printf '%s\n' "${*:-(no message)}" >&2
        fi
    }

    # confirm
        # Purpose:
        #   Compatibility override for legacy yes/no confirmation prompts.
        #
        # Behavior:
        #   - If ask() exists, delegates to ask() using yes/no validation.
        #   - Otherwise falls back to a minimal read -rp prompt.
        #   - Treats Y/y as confirmation and all other responses as no.
        #
        # Arguments:
        #   $1  PROMPT
        #       Optional confirmation prompt text.
        #
        # Returns:
        #   0 if the user answered yes.
        #   1 otherwise.
        #
        # Usage:
        #   confirm "Are you sure?"
        #
        # Examples:
        #   if confirm "Delete existing config?"; then
        #       td_cfg_reset
        #   fi
        #
        # Notes:
        #   - Higher-level prompt policy belongs in ui-ask.sh.
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
        #   Resolve a palette or style specification into a readable .sh file path.
        #
        # Behavior:
        #   - Treats values containing "/" or ending in ".sh" as explicit paths.
        #   - Otherwise resolves logical names under:
        #       $TD_UI_THEME_DIR/<kind>/<name>.sh
        #   - Verifies readability before returning success.
        #
        # Arguments:
        #   $1  KIND
        #       Theme kind: palettes | styles
        #   $2  SPEC
        #       Explicit path or logical theme name.
        #
        # Inputs (globals):
        #   TD_UI_THEME_DIR
        #
        # Output:
        #   Prints the resolved readable file path to stdout.
        #
        # Returns:
        #   0  resolved and readable
        #   2  missing spec
        #   3  explicit path unreadable
        #   4  TD_UI_THEME_DIR missing for named lookup
        #   5  named theme not found
        #
        # Usage:
        #   __td_ui_resolve_theme_file palettes default-ui-palette
        #
        # Examples:
        #   palette_file="$(__td_ui_resolve_theme_file "palettes" "$palette_spec")" || return $?
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
        #   Strip ANSI CSI escape sequences from a string.
        #
        # Behavior:
        #   - Removes ESC[...<alpha> sequences from the supplied text.
        #   - Intended primarily for SGR styling sequences used by the framework.
        #
        # Arguments:
        #   $1  TEXT
        #       Text that may contain ANSI escape sequences.
        #
        # Output:
        #   Prints the sanitized string to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_strip_ansi "$text"
        #
        # Examples:
        #   plain="$(td_strip_ansi "$colored_text")"
    td_strip_ansi() {
        sed -r $'s/\x1B\\[[0-9;?]*[[:alpha:]]//g' <<<"$1"
    }

    # td_visible_len
        # Purpose:
        #   Return the visible character length of a string after stripping ANSI.
        #
        # Behavior:
        #   - Strips ANSI sequences using td_strip_ansi().
        #   - Returns the remaining string length.
        #
        # Arguments:
        #   $1  TEXT
        #       Text whose visible length should be measured.
        #
        # Output:
        #   Prints the visible length to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_visible_len "$text"
        #
        # Examples:
        #   width="$(td_visible_len "$RUN_MODE")"
        #
        # Notes:
        #   - Length is byte-based and assumes monospaced terminal rendering.
    td_visible_len() {
        local plain
        plain="$(td_strip_ansi "$1")"
        printf '%s' "${#plain}"
    }

 # -- Theme loading ---------------------------------------------------------------
    # td_ui_set_theme
        # Purpose:
        #   Load a UI palette and style into the current shell.
        #
        # Behavior:
        #   - Accepts palette and style as explicit paths or logical names.
        #   - Resolves logical names under TD_UI_THEME_DIR.
        #   - Derives TD_UI_THEME_DIR from TD_FRAMEWORK_ROOT when unset.
        #   - Loads palette first, then style.
        #   - Records the resolved files in TD_UI_PALETTE_FILE and TD_UI_STYLE_FILE.
        #
        # Arguments:
        #   --palette SPEC
        #       Palette file path or logical name.
        #   --style SPEC
        #       Style file path or logical name.
        #   --default
        #       Load default-ui-palette and default-ui-style.
        #   -h | --help
        #       Print usage help.
        #
        # Inputs (globals):
        #   TD_UI_THEME_DIR
        #   TD_FRAMEWORK_ROOT
        #
        # Outputs (globals):
        #   TD_UI_THEME_DIR
        #   TD_UI_PALETTE_FILE
        #   TD_UI_STYLE_FILE
        #   Variables defined by the sourced palette and style files
        #
        # Side effects:
        #   - Sources palette and style files into the current shell.
        #
        # Returns:
        #   0   success or help shown
        #   2   unexpected argument
        #   3   explicit file unreadable
        #   4   theme directory missing
        #   5   named theme not found
        #   10  palette load failed
        #   11  palette did not define RESET
        #   12  style load failed
        #
        # Usage:
        #   td_ui_set_theme --palette <file|name> --style <file|name>
        #   td_ui_set_theme --default
        #   td_ui_set_theme <palette> <style>
        #
        # Examples:
        #   td_ui_set_theme --default
        #
        #   td_ui_set_theme "default-ui-palette" "default-ui-style"
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
        #   Convenience wrapper to load the default UI palette and style.
        #
        # Behavior:
        #   - Delegates directly to td_ui_set_theme --default.
        #
        # Returns:
        #   Whatever td_ui_set_theme returns.
        #
        # Usage:
        #   td_ui_set_default_theme
        #
        # Examples:
        #   td_ui_set_default_theme || return 1
    td_ui_set_default_theme() {
        td_ui_set_theme --default
    }

 # -- Styling helpers -------------------------------------------------------------
    # td_sgr
        # Purpose:
        #   Build one canonical ANSI SGR escape sequence from mixed inputs.
        #
        # Behavior:
        #   - Accepts numeric SGR params, numeric param lists, and full ESC[...m sequences.
        #   - Extracts and normalizes parameters into one combined SGR escape.
        #   - Ignores empty or unsupported inputs.
        #   - Returns RESET when no valid parts are supplied.
        #
        # Arguments:
        #   $@  PARTS
        #       Mixed SGR parts such as:
        #       - numeric params: 1
        #       - param lists: "1,4" or "1;4"
        #       - full escapes: $'\e[38;5;46m'
        #
        # Inputs (globals):
        #   RESET
        #
        # Output:
        #   Prints one SGR prefix to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_sgr "$WHITE" "" "$FX_BOLD"
        #
        # Examples:
        #   clr="$(td_sgr "$GREEN" "" "$FX_BOLD")"
        #
        #   printf '%sHello%s\n' "$(td_sgr 1 4)" "$RESET"
    td_sgr() {
        local -a parts=()
        local -a subparts=()
        local arg=""
        local inner=""
        local sub=""

        for arg in "$@"; do
            [[ -z "${arg:-}" ]] && continue

            # Numeric: treat as single SGR parameter
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                parts+=( "$arg" )
                continue
            fi

            # Numeric list: allow comma or semicolon separated params
            if [[ "$arg" =~ ^[0-9]+([,;][0-9]+)+$ ]]; then
                inner="${arg//,/;}"
                IFS=';' read -r -a subparts <<< "$inner"

                for sub in "${subparts[@]}"; do
                    [[ -n "$sub" ]] && parts+=( "$sub" )
                done
                continue
            fi

            # Escape: extract inner params from $'\e[...m'
            if [[ "$arg" == $'\e['*m ]]; then
                inner="${arg#$'\e['}"
                inner="${inner%m}"

                if [[ "$inner" =~ ^[0-9]+([;][0-9]+)*$ ]]; then
                    IFS=';' read -r -a subparts <<< "$inner"

                    for sub in "${subparts[@]}"; do
                        [[ -n "$sub" ]] && parts+=( "$sub" )
                    done
                fi
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
        #   Convenience wrapper to build a foreground-color SGR prefix.
        #
        # Arguments:
        #   $1  FG
        #       Foreground color escape or SGR fragment.
        #   $@  FX
        #       Optional effect fragments.
        #
        # Output:
        #   Prints an SGR prefix to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_fg "$GREEN" "$FX_BOLD"
        #
        # Examples:
        #   printf '%sText%s\n' "$(td_fg "$WHITE" "$FX_ITALIC")" "$RESET"
    td_fg() {  # td_fg <fg> [fx...]
        local fg="${1:-}"
        shift || true
        td_sgr "$fg" "" "$@"
    }

    # td_bg
        # Purpose:
        #   Convenience wrapper to build a background-color SGR prefix.
        #
        # Arguments:
        #   $1  BG
        #       Background color escape or SGR fragment.
        #   $@  FX
        #       Optional effect fragments.
        #
        # Output:
        #   Prints an SGR prefix to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_bg "$BG_BLUE"
        #
        # Examples:
        #   printf '%sText%s\n' "$(td_bg "$BG_RED" "$FX_BOLD")" "$RESET"
    td_bg() {  # td_bg <bg> [fx...]
        local bg="${1:-}"
        shift || true
        td_sgr "" "$bg" "$@"
    }

 # -- Runmode indicators ----------------------------------------------------------
    # td_update_runmode
        # Purpose:
        #   Update the styled global RUN_MODE indicator from the current dry-run state.
        #
        # Behavior:
        #   - Sets RUN_MODE to DRYRUN or COMMIT.
        #   - Uses td_runmode_color() for the prefix.
        #   - Appends RESET so the string is safe for inline rendering.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #   RESET
        #
        # Outputs (globals):
        #   RUN_MODE
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_update_runmode
        #
        # Examples:
        #   FLAG_DRYRUN=1
        #   td_update_runmode
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
        #   TUI_DRYRUN
        #   TUI_COMMIT
        #
        # Output:
        #   Prints the active run-mode color prefix to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_runmode_color
        #
        # Examples:
        #   printf '%s%s%s\n' "$(td_runmode_color)" "COMMIT" "$RESET"
    td_runmode_color() {
        (( FLAG_DRYRUN )) && printf '%s' "$TUI_DRYRUN" || printf '%s' "$TUI_COMMIT"
    }

 # -- Rendering primitives --------------------------------------------------------
    # td_print_labeledvalue
        # Purpose:
        #   Print one aligned "Label : Value" line with optional styling.
        #
        # Behavior:
        #   - Accepts positional or named arguments.
        #   - Applies a fixed-width label column.
        #   - Prints the value without truncation.
        #   - Appends RESET after colored segments.
        #
        # Arguments:
        #   --label TEXT
        #       Label text.
        #   --value TEXT
        #       Value text.
        #   --sep TEXT
        #       Separator token. Default: :
        #   --width N
        #       Label width. Default: 25
        #   --pad N
        #       Left indentation. Default: 0
        #   --labelclr ANSI
        #       Label color prefix.
        #   --valueclr ANSI
        #       Value color prefix.
        #
        # Output:
        #   Writes one formatted line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_labeledvalue "Label" "Value"
        #   td_print_labeledvalue --label "Label" --value "Value" [opts]
        #
        # Examples:
        #   td_print_labeledvalue "Version" "$TD_VERSION"
        #
        #   td_print_labeledvalue --label "Mode" --value "$RUN_MODE" --pad 4
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
        #   Print one line with left and right content separated by a fill region.
        #
        # Behavior:
        #   - Accepts positional or named arguments.
        #   - Computes fill width using ANSI-safe visible lengths.
        #   - Applies optional left and right colors.
        #   - Uses a single visible fill character across the gap.
        #
        # Arguments:
        #   --left TEXT
        #       Left-side content.
        #   --right TEXT
        #       Right-side content.
        #   --padleft N
        #       Left fill padding. Default: 2
        #   --padright N
        #       Right fill padding. Default: 1
        #   --maxwidth N
        #       Total width. Default: 80
        #   --fillchar C
        #       Fill character. Default: space
        #   --leftclr ANSI
        #       Left color prefix.
        #   --rightclr ANSI
        #       Right color prefix.
        #
        # Output:
        #   Writes one formatted line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_fill "Left" "Right"
        #   td_print_fill --left "Menu" --right "$RUN_MODE" [opts]
        #
        # Examples:
        #   td_print_fill --left "$TD_SCRIPT_TITLE" --right "$RUN_MODE" --maxwidth 100
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
        #   Print a framed title bar with left/right header text and optional subtitle.
        #
        # Behavior:
        #   - Prints a border line, one header line, an optional subtitle line,
        #     and a closing border line.
        #   - Uses TD_SCRIPT_TITLE or TD_SCRIPT_BASE as the default left title.
        #   - Uses RUN_MODE as the default right-side text.
        #   - Uses TD_SCRIPT_DESC as the default subtitle.
        #
        # Inputs (globals):
        #   TD_SCRIPT_TITLE
        #   TD_SCRIPT_BASE
        #   TD_SCRIPT_DESC
        #   RUN_MODE
        #
        # Output:
        #   Writes multiple formatted lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_titlebar [opts]
        #
        # Examples:
        #   td_print_titlebar
        #
        #   td_print_titlebar --left "SolidGround Console" --right "$RUN_MODE" --sub "$TD_SCRIPT_DESC"
    td_print_titlebar() {

        local left="${TD_SCRIPT_TITLE:-$TD_SCRIPT_BASE}"
        local right="${RUN_MODE:-}"
        local leftclr="$(td_sgr "$WHITE" "" "$FX_BOLD")"
        local rightclr=""                 # let td_print_fill inherit
        local sub="${TD_SCRIPT_DESC:-""}"
        local subclr="$(td_sgr "$WHITE" "" "$FX_ITALIC")"
        local subjust="C"
        local border="$DL_H"
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
        # Behavior:
        #   - Prints a full-width border when no title text is given.
        #   - Prints a titled divider when text is supplied.
        #   - Uses ANSI-safe width calculations for visible alignment.
        #
        # Arguments:
        #   --text TEXT
        #       Section title.
        #   --textclr ANSI
        #       Title color prefix.
        #   --border C
        #       Border character. Default: -
        #   --borderclr ANSI
        #       Border color prefix.
        #   --padleft N
        #       Border count before title. Default: 4
        #   --padend 0|1
        #       Fill remainder after title. Default: 1
        #   --maxwidth N
        #       Total width. Default: 80
        #
        # Output:
        #   Writes one formatted divider line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_sectionheader
        #   td_print_sectionheader "Title"
        #   td_print_sectionheader --text "Title" [opts]
        #
        # Examples:
        #   td_print_sectionheader --text "Framework metadata"
        #
        #   td_print_sectionheader --border "=" --maxwidth 100
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
        #   Print formatted text with padding, justification, and optional wrapping.
        #
        # Behavior:
        #   - Empty call prints a blank line.
        #   - Auto-wraps when text exceeds the available width unless wrap mode is forced.
        #   - Delegates single-line rendering to td_print_single().
        #   - Delegates wrapping to td_wrap_words().
        #
        # Arguments:
        #   --text TEXT
        #       Text to print.
        #   --textclr ANSI
        #       Text color prefix.
        #   --justify L|C|R
        #       Justification. Default: L
        #   --wrap 0|1
        #       Explicit wrap mode.
        #   --pad N
        #       Left and right padding. Default: 0
        #   --rightmargin N
        #       Reserved right margin in wrap mode. Default: 0
        #   --maxwidth N
        #       Total width. Default: 80
        #
        # Output:
        #   Writes one or more formatted lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print
        #   td_print "Text"
        #   td_print --text "Text" [opts]
        #
        # Examples:
        #   td_print --text "$TD_SCRIPT_DESC" --justify C --pad 4
        #
        #   td_print --text "$long_text" --wrap 1 --maxwidth 100
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
        #   Render exactly one formatted line within a fixed width.
        #
        # Behavior:
        #   - Empty call prints a blank line.
        #   - Applies justification and padding.
        #   - Truncates text when it exceeds the available width.
        #   - Does not perform wrapping.
        #
        # Arguments:
        #   --text TEXT
        #       Text to render.
        #   --textclr ANSI
        #       Text color prefix.
        #   --justify L|C|R
        #       Justification. Default: L
        #   --pad N
        #       Left and right padding. Default: 0
        #   --maxwidth N
        #       Total width. Default: 80
        #
        # Output:
        #   Writes one formatted line to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_single
        #   td_print_single "Text"
        #   td_print_single --text "Text" [opts]
        #
        # Examples:
        #   td_print_single --text "Done" --justify R --maxwidth 40
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
        # Behavior:
        #   - Uses less for paging when stdout is a TTY and less is available.
        #   - For Markdown files, tries richer renderers before falling back to plain output.
        #   - Prints without paging for non-interactive output.
        #
        # Arguments:
        #   $1  FILE
        #       Readable text file path.
        #
        # Side effects:
        #   - May invoke external viewers such as less, glow, mdcat, bat, or pandoc.
        #
        # Returns:
        #   0 on success
        #   2 on missing or unreadable file
        #
        # Usage:
        #   td_print_file <path>
        #
        # Examples:
        #   td_print_file "$TD_DOCS_DIR/README.md"
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
        #   Print a fixed-width cell that may contain ANSI styling sequences.
        #
        # Behavior:
        #   - Computes visible width after stripping ANSI CSI sequences.
        #   - Pads with spaces to the requested width.
        #   - Does not truncate when text exceeds the target width.
        #
        # Arguments:
        #   $1  WIDTH
        #       Target visible width.
        #   $2  TEXT
        #       Cell content, optionally containing ANSI styling.
        #
        # Output:
        #   Writes the padded cell to stdout without a newline.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_print_cell 20 "$text"
        #
        # Examples:
        #   td_print_cell 20 "${GREEN}OK${RESET}"
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
        # Behavior:
        #   - Renders sample rows for the framework palette color variables.
        #   - Delegates row rendering to td_sample_row().
        #
        # Output:
        #   Writes a formatted color demo to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_color_samples
        #
        # Examples:
        #   td_color_samples
    td_color_samples(){
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
        #   Render one sample row for one or more named palette variables.
        #
        # Behavior:
        #   - Resolves each supplied variable name using eval.
        #   - Prints the variable name in its own style.
        #   - Prints samples for common text effects.
        #
        # Arguments:
        #   $@  NAMES
        #       Variable names holding ANSI escape values.
        #
        # Output:
        #   Writes one or more formatted sample lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_sample_row BLUE BRIGHT_BLUE
        #
        # Examples:
        #   td_sample_row GREEN BRIGHT_GREEN DARK_GREEN
        #
        # Notes:
        #   - Uses eval and expects trusted framework palette variable names.
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
        #   Print a demo of semantic message and UI style variables.
        #
        # Behavior:
        #   - Prints sample output for MSG_CLR_* message colors.
        #   - Prints sample output for TUI_* semantic UI colors.
        #
        # Output:
        #   Writes a formatted style demo to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_style_samples
        #
        # Examples:
        #   td_style_samples
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






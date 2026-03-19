# ==================================================================================
# Testadura Consultancy — SolidGround Console Menu Engine
# ----------------------------------------------------------------------------------
# Module  : sgnd-console-menu.sh
# Purpose : Interactive menu rendering and navigation engine for sgnd-console.
#
# Scope   :
#   - Menu rendering (titles, groups, items, layout)
#   - Pagination (previous/next navigation)
#   - Input handling and dispatch
#   - Toggle-aware item presentation
#
# Design  :
#   - Driven by registered menu items (data → rendering)
#   - Stateless rendering based on current flags and page index
#   - Integrates with sgnd-console core for execution and state
#
# Notes   :
#   - This module controls the full TUI lifecycle (render → input → dispatch)
#   - Relies on shared UI helpers and toggle infrastructure
#   - Assumes terminal-based interactive environment
#
# Author  : Mark Fieten
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


# --- Label and status formatting --------------------------------------------------
    # __sgnd_console_toggleword
        # Purpose:
        #   Render a toggle label (e.g. DEBUG, DRYRUN) with color and hotkey styling.
        #
        # Arguments:
        #   $1  Word (e.g. "DEBUG")
        #   $2  Hotkey (single character)
        #   $3  State (0=off, 1=on)
        #   $4  Optional ON color
        #   $5  Optional OFF color
        #
        # Behavior:
        #   - Highlights hotkey with underline.
        #   - Applies color and bold styling depending on state.
        #   - Supports special-case transformations (e.g. DRYRUN → COMMIT).
        #
        # Outputs:
        #   Prints formatted toggle text.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_toggleword "DEBUG" "B" 1
        #   __sgnd_console_toggleword "DRYRUN" "D" 0
    __sgnd_console_toggleword() {
        local word="${1:?missing word}"
        local hotkey="${2:?missing hotkey}"
        local state="${3:-0}"

        local onclr="${4:-$GREEN}"
        local offclr="${5:-$DARK_SILVER}"

        local word_style=""
        local key_style=""
        local prefix=""
        local suffix=""

        if (( state )); then
            word_style="$(td_sgr "$onclr" "$FX_BOLD")"
            key_style="$(td_sgr "$onclr" "$FX_BOLD" "$FX_UNDERLINE")"
        else
            if [[ "$word" == "DRYRUN" ]]; then
                word="COMMIT(D)"
            fi
            word_style="$(td_sgr "$offclr")"
            key_style="$(td_sgr "$offclr" "$FX_BOLD" "$FX_UNDERLINE")"
        fi

        prefix="${word%%"$hotkey"*}"
        suffix="${word#*"$hotkey"}"

        if [[ "$word" == "$prefix" ]]; then
            printf '%s%s%s' "$word_style" "$word" "$RESET"
            return 0
        fi

        printf '%s%s%s%s%s%s%s' \
            "$word_style" "$prefix" \
            "$key_style" "$hotkey" \
            "$RESET" \
            "$word_style" "$suffix" \
            "$RESET"
    }

    # __sgnd_console_onoff
        # Purpose:
        #   Render a colored "On" or "Off" state fragment.
        #
        # Arguments:
        #   $1  VALUE    Truthy numeric state.
        #   $2  ONCLR    Optional color for the On state.
        #   $3  OFFCLR   Optional color for the Off state.
        #
        # Output:
        #   Prints the styled state text to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_onoff() {
        local value="${1:-0}"
        local onclr="${2:-$BRIGHT_GREEN}"
        local offclr="${3:-$DARK_SILVER}"

        if (( value )); then
            printf '%sOn%s' "$(td_sgr "$onclr")" "$RESET"
        else
            printf '%sOff%s' "$(td_sgr "$offclr")" "$RESET"
        fi
    }

    # __sgnd_console_label_clearonrender
        # Purpose:
        #   Build the current label text for the clear-on-render builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_clearonrender() {
        : "${SGND_CLEAR_ONRENDER:=1}"
        printf 'Clear screen: %s' "$(__sgnd_console_onoff "$SGND_CLEAR_ONRENDER")"
    }

    # __sgnd_console_label_dryrun
        # Purpose:
        #   Build the current label text for the dry-run builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_dryrun() {
        : "${FLAG_DRYRUN:=0}"
        printf 'Dry-run: %s' "$(__sgnd_console_onoff "$FLAG_DRYRUN" "$TUI_DRYRUN" "$TUI_COMMIT")"
    }

    # __sgnd_console_label_debug
        # Purpose:
        #   Build the current label text for the debug builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_debug() {
        : "${FLAG_DEBUG:=0}"
        printf 'Debug: %s' "$(__sgnd_console_onoff "$FLAG_DEBUG")"
    }

    # __sgnd_console_label_verbose
        # Purpose:
        #   Build the current label text for the verbose builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_verbose() {
        : "${FLAG_VERBOSE:=0}"
        printf 'Verbose: %s' "$(__sgnd_console_onoff "$FLAG_VERBOSE")"
    }

    # __sgnd_console_label_logfile
        # Purpose:
        #   Build the current label text for the logfile builtin item.
        #
        # Output:
        #   Prints the label to stdout (no newline).
        #
        # Returns:
        #   0 always
    __sgnd_console_label_logfile() {
        : "${TD_LOGFILE_ENABLED:=0}"
        printf 'Logfile: %s' "$(__sgnd_console_onoff "$TD_LOGFILE_ENABLED")"
    }

# --- Builtin actions --------------------------------------------------------------
     # __sgnd_console_toggle_clearonrender
        # Purpose:
        #   Toggle whether the console clears the screen before each render.
        #
        # Behavior:
        #   - Flips SGND_CLEAR_ONRENDER between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
    __sgnd_console_toggle_clearonrender() {
        : "${SGND_CLEAR_ONRENDER:=1}"

        if (( SGND_CLEAR_ONRENDER )); then
            SGND_CLEAR_ONRENDER=0
            sayinfo "Clear-on-render disabled"
        else
            SGND_CLEAR_ONRENDER=1
            sayinfo "Clear-on-render enabled"
        fi
    }

    # __sgnd_console_toggle_dryrun
        # Purpose:
        #   Toggle dry-run mode for the current session.
        #
        # Behavior:
        #   - Flips FLAG_DRYRUN between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
    __sgnd_console_toggle_dryrun() {
        : "${FLAG_DRYRUN:=0}"

        if (( FLAG_DRYRUN )); then
            FLAG_DRYRUN=0
            sayinfo "Dry-run disabled"
        else
            FLAG_DRYRUN=1
            sayinfo "Dry-run enabled"
        fi
        
    }

    # __sgnd_console_toggle_debug
        # Purpose:
        #   Toggle debug output for the current session.
        #
        # Behavior:
        #   - Flips FLAG_DEBUG between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #   - Calls td_update_runmode so framework UI/debug state stays synchronized.
        #
        # Returns:
        #   0 always
    __sgnd_console_toggle_debug() {
        : "${FLAG_DEBUG:=0}"

        if (( FLAG_DEBUG )); then
            FLAG_DEBUG=0
            sayinfo "Debug disabled"
        else
            FLAG_DEBUG=1
            sayinfo "Debug enabled"
        fi
        td_update_runmode
    }

    # __sgnd_console_toggle_verbose
        # Purpose:
        #   Toggle verbose output for the current session.
        #
        # Behavior:
        #   - Flips FLAG_VERBOSE between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
    __sgnd_console_toggle_verbose() {
        : "${FLAG_VERBOSE:=0}"

        if (( FLAG_VERBOSE )); then
            FLAG_VERBOSE=0
            sayinfo "Verbose disabled"
        else
            FLAG_VERBOSE=1
            sayinfo "Verbose enabled"
        fi
    }

    # __sgnd_console_toggle_logfile
        # Purpose:
        #   Toggle logfile output for the current session.
        #
        # Behavior:
        #   - Flips TD_LOGFILE_ENABLED between 0 and 1.
        #   - Emits an informational message reflecting the new state.
        #
        # Returns:
        #   0 always
    __sgnd_console_toggle_logfile() {
        : "${TD_LOGFILE_ENABLED:=0}"

        if (( TD_LOGFILE_ENABLED )); then
            TD_LOGFILE_ENABLED=0
            sayinfo "Logfile disabled"
        else
            TD_LOGFILE_ENABLED=1
            sayinfo "Logfile enabled"
        fi
    }

    # __sgnd_console_redraw
        # Purpose:
        #   No-op action used to force a menu redraw cycle.
        #
        # Returns:
        #   0 always
    __sgnd_console_redraw() {
        return 0
    }

    # __sgnd_console_quit
        # Purpose:
        #   Signal the console loop to terminate.
        #
        # Returns:
        #   200 as a sentinel value consumed by __sgnd_console_run
    __sgnd_console_quit() {
        return 200
    }

    # __sgnd_console_nextpage
        # Purpose:
        #   Advance to the next rendered menu page when available.
        #
        # Returns:
        #   0 always
    __sgnd_console_nextpage() {
        __sgnd_console_build_pages

        if (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )); then
            SGND_PAGE_INDEX=$(( SGND_PAGE_INDEX + 1 ))
        fi

        return 0
    }

    # __sgnd_console_prevpage
        # Purpose:
        #   Return to the previous rendered menu page when available.
        #
        # Returns:
        #   0 always

    __sgnd_console_prevpage() {
        if (( SGND_PAGE_INDEX > 0 )); then
            SGND_PAGE_INDEX=$(( SGND_PAGE_INDEX - 1 ))
        fi

        return 0
    }

# --- Menu layout ------------------------------------------------------------------
    # __sgnd_console_build_pages
        # Purpose:
        #   Simulate pagination and determine the start item of each page.
        #
        # Output:
        #   Populates SGND_PAGE_STARTS with visible item indexes.
        #
        # Returns:
        #   0 always
    __sgnd_console_build_pages() {
        local body_height=0
        local used_lines=0
        local visible_count=0
        local visible_i=0
        local row_index=0
        local group_key=""
        local current_group=""
        local item_lines=0
        local header_lines=0
        local needed_lines=0

        SGND_PAGE_STARTS=()

        __sgnd_console_collect_group_render_indexes
        __sgnd_console_collect_visible_item_indexes

        visible_count="${#SGND_VISIBLE_ITEM_INDEXES[@]}"
        body_height="$(__sgnd_console_body_height)"

        (( visible_count == 0 )) && return 0

        SGND_PAGE_STARTS+=(0)

        for (( visible_i=0; visible_i<visible_count; visible_i++ )); do
            row_index="${SGND_VISIBLE_ITEM_INDEXES[$visible_i]}"
            group_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
            item_lines="$(__sgnd_console_measure_item_lines "$row_index")"

            needed_lines="$item_lines"

            if [[ "$group_key" != "$current_group" ]]; then
                header_lines="$(__sgnd_console_measure_group_header_lines)"
                needed_lines=$(( needed_lines + header_lines ))
            fi

            if (( used_lines + needed_lines > body_height )); then
                SGND_PAGE_STARTS+=("$visible_i")
                used_lines=0
                current_group=""
            fi

            if [[ "$group_key" != "$current_group" ]]; then
                header_lines="$(__sgnd_console_measure_group_header_lines)"
                used_lines=$(( used_lines + header_lines ))
                current_group="$group_key"
            fi

            used_lines=$(( used_lines + item_lines ))
        done
    }

    # __sgnd_console_body_height
        # Purpose:
        #   Return the maximum number of body rows to render on one page.
        #
        # Output:
        #   Prints the configured maximum body row count.
        #
        # Returns:
        #   0 always
    __sgnd_console_body_height() {
        local body_height="${SGND_PAGE_MAX_ROWS:-20}"

        (( body_height < 5 )) && body_height=5
        printf '%s\n' "$body_height"
    }

    # __sgnd_console_measure_item_lines
        # Purpose:
        #   Measure how many screen lines a menu item will occupy when rendered.
        #
        # Arguments:
        #   $1  ROW_INDEX   Row index in SGND_ITEM_ROWS
        #
        # Output:
        #   Prints the rendered line count.
        #
        # Returns:
        #   0 always
    __sgnd_console_measure_item_lines() {
        local row_index="${1:?missing row index}"
        local desc=""
        local term_width=80
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local gap=3
        local tpad=3
        local desc_width=0
        local wrapped_count=0
        local line=""

        desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" desc)"

        if [[ -z "$desc" ]]; then
            printf '1\n'
            return 0
        fi

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        while IFS= read -r line; do
            wrapped_count=$(( wrapped_count + 1 ))
        done < <(td_wrap_words --width "$desc_width" --text "$desc")

        (( wrapped_count < 1 )) && wrapped_count=1
        printf '%s\n' "$wrapped_count"
    }

    # __sgnd_console_measure_group_header_lines
    __sgnd_console_measure_group_header_lines() {
        # group label + underline
        printf '2\n'
    }

    # __sgnd_console_visible_item_count
    __sgnd_console_visible_item_count() {
        printf '%s\n' "${#SGND_VISIBLE_ITEM_INDEXES[@]}"
    }

    # __sgnd_console_get_visible_row_index
    __sgnd_console_get_visible_row_index() {
        local visible_index="${1:?missing visible index}"

        if (( visible_index < 0 || visible_index >= ${#SGND_VISIBLE_ITEM_INDEXES[@]} )); then
            return 1
        fi

        printf '%s\n' "${SGND_VISIBLE_ITEM_INDEXES[$visible_index]}"
    }

    # __sgnd_console_collect_visible_item_indexes
        # Purpose:
        #   Build the canonical visible numeric menu order for non-builtin items.
        #
        # Behavior:
        #   - Traverses groups in canonical render order.
        #   - Includes only non-builtin items.
        #   - Within each group, preserves item registration order.
        #   - Includes only items whose visible state is:
        #       1 = visible/enabled
        #       2 = visible/disabled
        #   - Excludes hidden items (state 0).
        #
        # Output:
        #   Populates SGND_VISIBLE_ITEM_INDEXES with SGND_ITEM_ROWS row indexes.
        #
        # Returns:
        #   0 always
    __sgnd_console_collect_visible_item_indexes() {
        local gi
        local ii
        local item_row_count=0
        local group_key=""
        local group_builtin="0"
        local item_group=""
        local item_builtin="0"
        local item_state="1"

        SGND_VISIBLE_ITEM_INDEXES=()

        __sgnd_console_collect_group_render_indexes
        item_row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for gi in "${SGND_GROUP_RENDER_INDEXES[@]}"; do
            group_builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" builtin)"
            (( group_builtin )) && continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)"

            for (( ii=0; ii<item_row_count; ii++ )); do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
                [[ "$item_group" == "$group_key" ]] || continue

                item_builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" builtin)"
                (( item_builtin )) && continue

                item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
                case "$item_state" in
                    1|2)
                        SGND_VISIBLE_ITEM_INDEXES+=("$ii")
                        ;;
                esac
            done
        done
    }

    # __sgnd_console_calc_label_width
        # Purpose:
        #   Calculate the left-column width needed for rendered menu items.
        #
        # Behavior:
        #   - Includes builtin items.
        #   - Includes non-builtin items present in the canonical visible order.
        #   - Caps the final width at 35 characters.
        #
        # Output:
        #   Prints the calculated width to stdout.
        #
        # Returns:
        #   0 always
    __sgnd_console_calc_label_width() {
        local i
        local row_count=0
        local builtin="0"
        local display_key=""
        local label=""
        local left_text=""
        local width=0
        local max_width=0

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            else
                display_key="$(__sgnd_console_get_visible_display_number "$i" 2>/dev/null)" || continue
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label)"
            left_text="${display_key}) ${label}"
            width="$(td_visible_length "$left_text")"

            (( width > max_width )) && max_width="$width"
        done

        (( max_width > 35 )) && max_width=35
        printf '%s\n' "$max_width"
    }

    # __sgnd_console_find_visible_pos_for_row
        # Purpose:
        #   Find the visible-order position for a row index in SGND_ITEM_ROWS.
        #
        # Arguments:
        #   $1  ROW_INDEX
        #
        # Output:
        #   Prints the 0-based visible position.
        #
        # Returns:
        #   0 if found
        #   1 otherwise
    __sgnd_console_find_visible_pos_for_row() {
        local row_index="${1:?missing row index}"
        local i

        for (( i=0; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            if [[ "${SGND_VISIBLE_ITEM_INDEXES[$i]}" == "$row_index" ]]; then
                printf '%s\n' "$i"
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_group_continues_after_visible_pos
        # Purpose:
        #   Determine whether a group has more visible items after a given visible
        #   position in the canonical visible item order.
        #
        # Arguments:
        #   $1  GROUP_KEY
        #   $2  LAST_VISIBLE_POS
        #
        # Returns:
        #   0 if the group continues on a later page
        #   1 otherwise
    __sgnd_console_group_continues_after_visible_pos() {
        local group_key="${1:?missing group key}"
        local last_visible_pos="${2:?missing visible position}"
        local i
        local row_index=0
        local item_group=""

        for (( i=last_visible_pos + 1; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            row_index="${SGND_VISIBLE_ITEM_INDEXES[$i]}"
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"

            if [[ "$item_group" == "$group_key" ]]; then
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_get_visible_display_number
        # Purpose:
        #   Resolve the visible numeric display number for an item row index.
        #
        # Arguments:
        #   $1  ROW_INDEX   Index in SGND_ITEM_ROWS
        #
        # Output:
        #   Prints the 1-based display number, or nothing if not visible.
        #
        # Returns:
        #   0 if the item is in the visible numeric order
        #   1 otherwise
    __sgnd_console_get_visible_display_number() {
        local row_index="${1:?missing row index}"
        local i

        for (( i=0; i<${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            if [[ "${SGND_VISIBLE_ITEM_INDEXES[$i]}" == "$row_index" ]]; then
                printf '%s\n' "$((i + 1))"
                return 0
            fi
        done

        return 1
    }

    # __sgnd_console_collect_group_render_indexes
        # Purpose:
        #   Build the canonical render order for menu groups.
        #
        # Behavior:
        #   - Includes all registered groups.
        #   - Sorts non-builtin groups before builtin groups.
        #   - Within each bucket, sorts by ascending ord.
        #   - For equal ord values, preserves registration order.
        #
        # Output:
        #   Populates SGND_GROUP_RENDER_INDEXES with SGND_GROUP_ROWS row indexes
        #   in render order.
        #
        # Returns:
        #   0 always
    __sgnd_console_collect_group_render_indexes() {
        local i
        local row_count=0
        local builtin="0"
        local ord="1000"

        local -a sortable_rows=()
        local -a sorted_rows=()

        SGND_GROUP_RENDER_INDEXES=()

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$i" builtin)"
            ord="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$i" ord)"
            : "${ord:=1000}"

            # sort key = builtin bucket | ord | original row index
            # non-builtin first, builtin last
            sortable_rows+=("$(printf '%d|%08d|%08d' "$builtin" "$ord" "$i")")
        done

        if (( ${#sortable_rows[@]} == 0 )); then
            return 0
        fi

        mapfile -t sorted_rows < <(printf '%s\n' "${sortable_rows[@]}" | sort -t '|' -k1,1n -k2,2n -k3,3n)

        for i in "${!sorted_rows[@]}"; do
            SGND_GROUP_RENDER_INDEXES+=("${sorted_rows[$i]##*|}")
        done
    }

# --- Menu rendering ---------------------------------------------------------------
    # __sgnd_console_render_menu
        # Purpose:
        #   Render the complete console menu for the current state.
        #
        # Behavior:
        #   - Refreshes builtin labels so toggle-driven labels stay current.
        #   - Builds the canonical group render order.
        #   - Builds the canonical visible item order.
        #   - Calculates the left-column render width.
        #   - Renders the menu title, paged non-builtin body, builtin groups,
        #     and bottom toggle bar.
        #
        # Inputs (globals):
        #   SGND_GROUP_ROWS
        #   SGND_ITEM_ROWS
        #   SGND_GROUP_SCHEMA
        #   SGND_ITEM_SCHEMA
        #   SGND_RENDER_LABEL_WIDTH
        #
        # Outputs (globals):
        #   SGND_RENDER_LABEL_WIDTH
        #
        # Side effects:
        #   - Writes the full menu render to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_render_menu
        #
        # Examples:
        #   __sgnd_console_render_menu
    __sgnd_console_render_menu() {
        local idx=""
        local group_key=""
        local builtin="0"

        __sgnd_console_refresh_builtin_labels
        __sgnd_console_collect_group_render_indexes
        __sgnd_console_collect_visible_item_indexes
        SGND_RENDER_LABEL_WIDTH="$(__sgnd_console_calc_label_width)"

        __sgnd_console_render_menu_title
        __sgnd_console_render_menu_body_paged

        for idx in "${SGND_GROUP_RENDER_INDEXES[@]}"; do
            builtin="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$idx" builtin)"
            (( builtin )) || continue

            group_key="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$idx" key)"
            __sgnd_console_render_group "$group_key"
        done

        __sgnd_console_render_togglebar
    }

    # __sgnd_console_render_menu_title
        # Purpose:
        #   Render the console title and description banner.
        #
        # Behavior:
        #   - Clears the screen first when SGND_CLEAR_ONRENDER is enabled.
        #   - Prints the console title and description with section borders.
        #
        # Returns:
        #   0 always
    __sgnd_console_render_menu_title() {
        (( ! SGND_CLEAR_ONRENDER )) || clear
        
        local width=80
        width="$(td_terminal_width)"

        td_print_sectionheader --border "$DL_H" --maxwidth "$width"
        td_print --pad 4 "$(td_sgr "$WHITE" "" "$FX_BOLD")${SGND_CONSOLE_TITLE}${RESET}"
        td_print --pad 4 "$(td_sgr "$SILVER" "" "$FX_ITALIC")${SGND_CONSOLE_DESC}"
        td_print_sectionheader --border "$LN_H" --maxwidth "$width"
        td_print
    }

    # __sgnd_console_render_menu_body_paged
        # Purpose:
        #   Render the current non-builtin menu page using the computed paging model.
        #
        # Behavior:
        #   - Rebuilds visible item order and page starts.
        #   - Normalizes SGND_PAGE_INDEX to a valid page.
        #   - Determines whether previous and next pages are available.
        #   - Selects the visible row indexes that belong to the current page.
        #   - Delegates final row rendering to __sgnd_console_render_page_rows.
        #
        # Inputs (globals):
        #   SGND_VISIBLE_ITEM_INDEXES
        #   SGND_PAGE_STARTS
        #   SGND_PAGE_INDEX
        #   SGND_PAGE_MAX_ROWS
        #   SGND_GROUP_ROWS
        #   SGND_ITEM_ROWS
        #   SGND_GROUP_SCHEMA
        #   SGND_ITEM_SCHEMA
        #
        # Outputs (globals):
        #   SGND_PAGE_HAS_PREV
        #   SGND_PAGE_HAS_NEXT
        #   SGND_PAGE_INDEX
        #
        # Side effects:
        #   - Writes the paged menu body to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_render_menu_body_paged
        #
        # Examples:
        #   __sgnd_console_render_menu_body_paged
    __sgnd_console_render_menu_body_paged() {
        local body_height=0
        local used_lines=0

        local visible_count=0
        local visible_i=0
        local row_index=0
        local group_key=""
        local current_group=""
        local item_lines=0
        local header_lines=0
        local needed_lines=0

        local pending_group=""
        local -a page_rows=()
        local -a page_groups=()

        __sgnd_console_collect_group_render_indexes
        __sgnd_console_collect_visible_item_indexes
        __sgnd_console_build_pages

        visible_count="${#SGND_VISIBLE_ITEM_INDEXES[@]}"
        body_height="$(__sgnd_console_body_height)"

                    SGND_PAGE_HAS_PREV=0
        SGND_PAGE_HAS_NEXT=0

        if (( visible_count == 0 )); then
            return 0
        fi

        if (( SGND_PAGE_INDEX < 0 )); then
            SGND_PAGE_INDEX=0
        fi

        if (( SGND_PAGE_INDEX >= ${#SGND_PAGE_STARTS[@]} )); then
            SGND_PAGE_INDEX=0
        fi

        (( SGND_PAGE_INDEX > 0 )) && SGND_PAGE_HAS_PREV=1
        (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )) && SGND_PAGE_HAS_NEXT=1

        local page_start_item=0
        local page_end_item="$visible_count"

        page_start_item="${SGND_PAGE_STARTS[$SGND_PAGE_INDEX]}"

        if (( SGND_PAGE_INDEX < ${#SGND_PAGE_STARTS[@]} - 1 )); then
            page_end_item="${SGND_PAGE_STARTS[$((SGND_PAGE_INDEX + 1))]}"
        fi

        for (( visible_i=page_start_item; visible_i<page_end_item; visible_i++ )); do
            row_index="${SGND_VISIBLE_ITEM_INDEXES[$visible_i]}"
            group_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
            item_lines="$(__sgnd_console_measure_item_lines "$row_index")"

            needed_lines="$item_lines"

            if [[ "$group_key" != "$current_group" ]]; then
                header_lines="$(__sgnd_console_measure_group_header_lines)"
                needed_lines=$(( needed_lines + header_lines ))
            fi

            if [[ "$group_key" != "$current_group" ]]; then
                page_groups+=("$group_key")
                current_group="$group_key"
                used_lines=$(( used_lines + header_lines ))
            fi

            page_rows+=("$row_index")
            used_lines=$(( used_lines + item_lines ))
        done

        __sgnd_console_render_page_rows page_groups page_rows
    }

    # __sgnd_console_render_page_rows
        # Purpose:
        #   Render a prepared set of ordered groups and item rows for one menu page.
        #
        # Arguments:
        #   $1  PAGE_GROUPS_VAR
        #       Name of the array variable containing ordered group keys.
        #   $2  PAGE_ROWS_VAR
        #       Name of the array variable containing ordered item row indexes.
        #
        # Behavior:
        #   - Resolves group labels from SGND_GROUP_ROWS.
        #   - Renders each group header once.
        #   - Renders enabled items normally and disabled items faint.
        #   - Wraps descriptions to the available right-column width.
        #   - Appends " ....." to a group title when that group continues
        #     on a later page.
        #
        # Inputs (globals):
        #   SGND_GROUP_ROWS
        #   SGND_ITEM_ROWS
        #   SGND_GROUP_SCHEMA
        #   SGND_ITEM_SCHEMA
        #   SGND_RENDER_LABEL_WIDTH
        #
        # Side effects:
        #   - Writes rendered groups and item rows to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_render_page_rows page_groups page_rows
        #
        # Examples:
        #   __sgnd_console_render_page_rows page_groups page_rows
        #
        # Notes:
        #   - Requires bash 4.3+ (nameref).
    __sgnd_console_render_page_rows() {
        local -n _page_groups="$1"
        local -n _page_rows="$2"

        local group_key=""
        local row_index=0
        local label=""
        local desc=""
        local display_key=""
        local item_group=""
        local item_state="1"

        local left_text=""
        local left_width=0
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local desc_width=0
        local term_width=80
        local gap=3
        local tpad=3

        local label_style=""
        local value_style=""
        local normal_label_style="$(td_sgr "$SILVER")"
        local normal_value_style="$(td_sgr "$SILVER" "" "$FX_ITALIC")"
        local disabled_label_style="$(td_sgr "$DARK_SILVER" "" "$FX_FAINT")"
        local disabled_value_style="$(td_sgr "$DARK_SILVER" "" "$FX_FAINT" "$FX_ITALIC")"

        local wrapped_line=""
        local first_line=1
        local group_label=""
        local group_label_display=""
        local gi

        local group_last_row_index=-1
        local group_last_visible_pos=-1

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        for group_key in "${_page_groups[@]}"; do
            group_label=""
            group_last_row_index=-1
            group_last_visible_pos=-1

            for (( gi=0; gi<$(td_dt_row_count SGND_GROUP_ROWS); gi++ )); do
                if [[ "$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)" == "$group_key" ]]; then
                    group_label="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" label)"
                    break
                fi
            done

            [[ -n "$group_label" ]] || continue

            for row_index in "${_page_rows[@]}"; do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
                [[ "$item_group" == "$group_key" ]] || continue
                group_last_row_index="$row_index"
            done

            group_label_display="$group_label"

            if (( group_last_row_index >= 0 )); then
                group_last_visible_pos="$(__sgnd_console_find_visible_pos_for_row "$group_last_row_index" 2>/dev/null || printf '%s' '-1')"

                if (( group_last_visible_pos >= 0 )); then
                    if __sgnd_console_group_continues_after_visible_pos "$group_key" "$group_last_visible_pos"; then
                        group_label_display="${group_label} ....."
                    fi
                fi
            fi

            td_print --text "$group_label_display"
            left_width="$(td_visible_length "$group_label_display")"
            td_print_sectionheader --border "$LN_H" --maxwidth "$left_width"

            for row_index in "${_page_rows[@]}"; do
                item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" group)"
                [[ "$item_group" == "$group_key" ]] || continue

                item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" visible)"
                case "$item_state" in
                    1|2) ;;
                    *) continue ;;
                esac

                display_key="$(__sgnd_console_get_visible_display_number "$row_index")" || continue

                if (( item_state == 2 )); then
                    label_style="$disabled_label_style"
                    value_style="$disabled_value_style"
                else
                    label_style="$normal_label_style"
                    value_style="$normal_value_style"
                fi

                label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" label)"
                desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" desc)"
                left_text="${display_key}) ${label}"

                if [[ -z "$desc" ]]; then
                    printf '%*s%s' "$tpad" "" "$label_style"
                    td_padded_visible "$left_text" "$left_width_max"
                    printf '%s\n' "$RESET"
                    continue
                fi

                first_line=1
                while IFS= read -r wrapped_line; do
                    if (( first_line )); then
                        printf '%*s%s' "$tpad" "" "$label_style"
                        td_padded_visible "$left_text" "$left_width_max"
                        printf '%s%*s%s%s%s\n' \
                            "$RESET" \
                            "$gap" "" \
                            "$value_style" "$wrapped_line" "$RESET"
                        first_line=0
                    else
                        printf '%*s%*s%*s%s%s%s\n' \
                            "$tpad" "" \
                            "$left_width_max" "" \
                            "$gap" "" \
                            "$value_style" "$wrapped_line" "$RESET"
                    fi
                done < <(td_wrap_words --width "$desc_width" --text "$desc")
            done

            td_print
        done
    }

    # __sgnd_console_render_group
        # Purpose:
        #   Render one complete menu group and its currently renderable items.
        #
        # Arguments:
        #   $1  GROUP_KEY
        #       Registered group key to render.
        #
        # Behavior:
        #   - Skips missing or hidden groups.
        #   - Skips groups with no visible or disabled items.
        #   - Renders builtin items by key and non-builtin items by visible number.
        #   - Renders disabled items faint.
        #   - Wraps descriptions to the available right-column width.
        #
        # Inputs (globals):
        #   SGND_GROUP_ROWS
        #   SGND_ITEM_ROWS
        #   SGND_GROUP_SCHEMA
        #   SGND_ITEM_SCHEMA
        #   SGND_RENDER_LABEL_WIDTH
        #
        # Side effects:
        #   - Writes the rendered group to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_render_group "$group_key"
        #
        # Examples:
        #   __sgnd_console_render_group "builtin"
    __sgnd_console_render_group() {
        local group_key="${1:?missing group key}"
        local _tpad=3

        local gi
        local ii
        local row_count=0
        local label=""
        local desc=""
        local group_label=""
        local found_group=0
        local group_state=1
        local display_key=""
        local item_group=""
        local builtin="0"
        local item_state="1"
        local has_renderable_items=0

        local left_text=""
        local left_width=0
        local left_width_max="${SGND_RENDER_LABEL_WIDTH:-28}"
        local desc_width=0
        local term_width=80
        local gap=3

        local label_style=""
        local value_style=""
        local normal_label_style="$(td_sgr "$SILVER")"
        local normal_value_style="$(td_sgr "$SILVER" "$FX_ITALIC")"
        local disabled_label_style="$(td_sgr "$DARK_SILVER" "$FX_FAINT")"
        local disabled_value_style="$(td_sgr "$DARK_SILVER" "$FX_FAINT" "$FX_ITALIC")"

        row_count="$(td_dt_row_count SGND_GROUP_ROWS)"

        for (( gi=0; gi<row_count; gi++ )); do
            if [[ "$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" key)" == "$group_key" ]]; then
                group_label="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" label)"
                group_state="$(td_dt_get "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS "$gi" visible)"
                found_group=1
                break
            fi
        done

        (( found_group )) || return 0
        (( group_state != 0 )) || return 0

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( ii=0; ii<row_count; ii++ )); do
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
            [[ "$item_group" == "$group_key" ]] || continue

            item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
            case "$item_state" in
                1|2)
                    has_renderable_items=1
                    break
                    ;;
            esac
        done

        (( has_renderable_items )) || return 0

        term_width="$(td_terminal_width)"
        desc_width=$(( term_width - _tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        td_print --text "$group_label"
        left_width="$(td_visible_length "$group_label")"
        td_print_sectionheader --border "$LN_H" --maxwidth "$left_width"

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( ii=0; ii<row_count; ii++ )); do
            item_group="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" group)"
            [[ "$item_group" == "$group_key" ]] || continue

            item_state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" visible)"
            case "$item_state" in
                1|2) ;;
                *) continue ;;
            esac

            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" builtin)"

            if (( builtin )); then
                display_key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" key)"
            else
                display_key="$(__sgnd_console_get_visible_display_number "$ii")" || continue
            fi

            if (( item_state == 2 )); then
                label_style="$disabled_label_style"
                value_style="$disabled_value_style"
            else
                label_style="$normal_label_style"
                value_style="$normal_value_style"
            fi

            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" label)"
            desc="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$ii" desc)"
            left_text="${display_key}) ${label}"

            if [[ -z "$desc" ]]; then
                printf '%*s%s' "$_tpad" "" "$label_style"
                td_padded_visible "$left_text" "$left_width_max"
                printf '%s\n' "$RESET"
                continue
            fi

            local first_line=1
            local wrapped_line=""

            while IFS= read -r wrapped_line; do
                if (( first_line )); then
                    printf '%*s%s' "$_tpad" "" "$label_style"
                    td_padded_visible "$left_text" "$left_width_max"
                    printf '%s%*s%s%s%s\n' \
                        "$RESET" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                    first_line=0
                else
                    printf '%*s%*s%*s%s%s%s\n' \
                        "$_tpad" "" \
                        "$left_width_max" "" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                fi
            done < <(td_wrap_words --width "$desc_width" --text "$desc")
        done

        td_print
    }

    # __sgnd_console_render_togglebar
        # Purpose:
        #   Render the bottom console status and navigation bar.
        #
        # Behavior:
        #   - Builds styled status words for runtime toggles.
        #   - Shows previous and next page indicators only when paging is active.
        #   - Shows the current page indicator when more than one page exists.
        #   - Centers the composed bar within the current terminal width.
        #   - Prints a bottom border before the bar.
        #
        # Inputs (globals):
        #   FLAG_DEBUG
        #   FLAG_DRYRUN
        #   TD_LOGFILE_ENABLED
        #   FLAG_VERBOSE
        #   SGND_CLEAR_ONRENDER
        #   SGND_PAGE_INDEX
        #   SGND_PAGE_STARTS
        #
        # Side effects:
        #   - Writes the rendered toggle bar to stdout.
        #   - Emits debug output for page count and page index.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_render_togglebar
        #
        # Examples:
        #   __sgnd_console_render_togglebar
    __sgnd_console_render_togglebar() {
        local render_width=80
        local pad=3
        local gap=3

        local debug_text=""
        local dryrun_text=""
        local logfile_text=""
        local verbose_text=""
        local clearscr_text=""
        local prevtext=""
        local nexttext=""

        local bar_text=""
        local visible_len=0
        local left_pad=0

        local prev_enabled=0
        local next_enabled=0

        render_width="$(td_terminal_width)"

        debug_text="$(__sgnd_console_toggleword "DEBUG"   "B" "${FLAG_DEBUG:-0}")"
        dryrun_text="$(__sgnd_console_toggleword "DRYRUN" "D" "${FLAG_DRYRUN:-0}" "${TUI_DRYRUN}" "${TUI_COMMIT}")"
        logfile_text="$(__sgnd_console_toggleword "LOG"   "L" "${TD_LOGFILE_ENABLED:-0}")"
        verbose_text="$(__sgnd_console_toggleword "VERBOSE" "V" "${FLAG_VERBOSE:-0}")"
        clearscr_text="$(__sgnd_console_toggleword "CLRSCR" "C" "${SGND_CLEAR_ONRENDER:-0}")"

        (( SGND_PAGE_INDEX > 0 )) && prev_enabled=1
        (( SGND_PAGE_INDEX + 1 < ${#SGND_PAGE_STARTS[@]} )) && next_enabled=1

        prevtext="$(__sgnd_console_toggleword "<<PREV" "<" "$prev_enabled")"
        nexttext="$(__sgnd_console_toggleword "NEXT>>" ">" "$next_enabled")"

        local page_text=""
        local page_count="${#SGND_PAGE_STARTS[@]}"
        local -a segments=()

        saydebug "Pagecount: ${page_count}"
        saydebug "Page index: ${SGND_PAGE_INDEX}"

        if (( page_count > 1 )); then
            page_text="Page $((SGND_PAGE_INDEX + 1))/$page_count"
            page_text="$(td_sgr "$SILVER" "" "$FX_ITALIC")${page_text}${RESET}"

            segments+=("$prevtext")
            segments+=("$debug_text")
            segments+=("$dryrun_text")
            segments+=("$page_text")
            segments+=("$logfile_text")
            segments+=("$verbose_text")
            segments+=("$clearscr_text")
            segments+=("$nexttext")
        else
            segments+=("$debug_text")
            segments+=("$dryrun_text")
            segments+=("$logfile_text")
            segments+=("$verbose_text")
            segments+=("$clearscr_text")
        fi

        # Join with gaps
        bar_text=""
        local seg
        for seg in "${segments[@]}"; do
            if [[ -n "$bar_text" ]]; then
                bar_text+="$(td_string_repeat ' ' "$gap")"
            fi
            bar_text+="$seg"
        done
        visible_len="$(td_visible_length "$bar_text")"
        left_pad=$(( (render_width - visible_len) / 2 ))
        (( left_pad < pad )) && left_pad="$pad"

        td_print_sectionheader --border "$DL_H" --maxwidth "$render_width"
        printf '%*s%s\n' "$left_pad" "" "$bar_text"
    }

# --- Menu dispatch ----------------------------------------------------------------
    # __sgnd_console_valid_choices_csv
        # Purpose:
        #   Build the current valid choice list for immediate console input.
        #
        # Behavior:
        #   - Includes numbered choices for visible non-builtin items.
        #   - Includes builtin item keys directly, even when hidden from the menu body.
        #   - Returns the result as a comma-separated list.
        #
        # Inputs (globals):
        #   SGND_VISIBLE_ITEM_INDEXES
        #   SGND_ITEM_ROWS
        #   SGND_ITEM_SCHEMA
        #
        # Output:
        #   Prints a comma-separated choice list to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __sgnd_console_valid_choices_csv
        #
        # Examples:
        #   choices="$(__sgnd_console_valid_choices_csv)"
    __sgnd_console_valid_choices_csv() {
        local i
        local out=""
        local row_count=0
        local builtin="0"
        local key=""

        __sgnd_console_collect_visible_item_indexes

        for (( i=1; i<=${#SGND_VISIBLE_ITEM_INDEXES[@]}; i++ )); do
            [[ -n "$out" ]] && out+=","
            out+="$i"
        done

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            builtin="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
            (( builtin )) || continue

            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            [[ -n "$out" ]] && out+=","
            out+="$key"
        done

        printf '%s' "$out"
    }

    # __sgnd_console_dispatch
        # Purpose:
        #   Dispatch a user menu choice to the matching registered handler.
        #
        # Arguments:
        #   $1  CHOICE
        #       Numeric menu selection or registered builtin item key.
        #
        # Behavior:
        #   - Numeric choices resolve against the canonical visible non-builtin order.
        #   - Hidden non-builtin items are excluded from numbering and dispatch.
        #   - Disabled items are recognized but not executed.
        #   - Builtin item keys remain dispatchable directly.
        #   - Stores the selected item's waitsecs in SGND_LAST_WAITSECS before execution.
        #
        # Inputs (globals):
        #   SGND_VISIBLE_ITEM_INDEXES
        #   SGND_ITEM_ROWS
        #   SGND_ITEM_SCHEMA
        #
        # Outputs (globals):
        #   SGND_LAST_WAITSECS
        #
        # Side effects:
        #   - Executes the matched handler function.
        #   - May emit warnings for invalid or disabled selections.
        #
        # Returns:
        #   Handler return code when dispatched successfully.
        #   1 when the choice is invalid or disabled.
        #
        # Usage:
        #   __sgnd_console_dispatch "$choice"
        #
        # Examples:
        #   __sgnd_console_dispatch "1"
        #
        #   __sgnd_console_dispatch "Q"
    __sgnd_console_dispatch() {
        local choice="${1:?missing choice}"
        local handler=""
        local label=""
        local state="1"
        local row_index=0
        local i
        local row_count=0
        local key=""

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            __sgnd_console_collect_visible_item_indexes

            if (( choice < 1 || choice > ${#SGND_VISIBLE_ITEM_INDEXES[@]} )); then
                saywarning "Invalid selection: $choice"
                return 1
            fi

            row_index="${SGND_VISIBLE_ITEM_INDEXES[$((choice - 1))]}"
            label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" label)"
            state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" visible)"

            if (( state == 2 )); then
                saywarning "Option disabled: $label"
                return 1
            fi

            handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" handler)"
            SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$row_index" waitsecs)"
            "$handler"
            return $?
        fi

        row_count="$(td_dt_row_count SGND_ITEM_ROWS)"

        for (( i=0; i<row_count; i++ )); do
            key="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"

            if [[ "${choice^^}" == "${key^^}" ]]; then
                state="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" visible)"
                label="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" label)"

                if (( state == 2 )); then
                    saywarning "Option disabled: $label"
                    return 1
                fi

                handler="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" handler)"
                SGND_LAST_WAITSECS="$(td_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" waitsecs)"
                "$handler"
                return $?
            fi
        done

        saywarning "Invalid selection: $choice"
        return 1
    }



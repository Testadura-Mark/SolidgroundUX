# ==================================================================================
# Testadura Consultancy — Typed Message Output Engine
# ----------------------------------------------------------------------------------
# Module     : ui-say.sh
# Purpose    : Typed console output and logging framework (say* API)
#
# Description:
#   Provides a unified messaging system for terminal-based applications using
#   typed output categories such as INFO, WARN, FAIL, DEBUG, etc.
#
#   The module standardizes:
#     - message formatting (label/icon/symbol composition)
#     - optional timestamping
#     - selective colorization (label/message/date)
#     - console output policy (verbosity, filtering, debug gating)
#     - best-effort logfile routing with rotation support
#
# Message model:
#   - All output flows through say() or its convenience wrappers (sayinfo, sayfail, etc.)
#   - Message types are normalized and mapped to style tokens (LBL_*, ICO_*, SYM_*)
#   - Console visibility is controlled centrally via policy flags
#
# Design principles:
#   - Single entry point for all user-facing output
#   - Separate rendering, policy, and logging concerns
#   - Never let logging or formatting failures break execution
#   - Keep calling code clean and intention-driven
#
# Role in framework:
#   - Core UI output layer used by all modules and scripts
#   - Complements ui-ask.sh (input) and ui.sh (styling)
#   - Provides consistent UX across all SolidGround tools
#
# Non-goals:
#   - Interactive prompting (see ui-ask.sh)
#   - Application-specific logging policies beyond type filtering
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

# --- Global defaults -------------------------------------------------------------
    # Can be overridden in:
    #   - environment
    #   - styles/*.sh
    SAY_DATE_DEFAULT="${SAY_DATE_DEFAULT:-0}"              # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="${SAY_SHOW_DEFAULT:-label}"         # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT="${SAY_COLORIZE_DEFAULT:-label}" # none|label|msg|both|all|date
    SAY_WRITELOG_DEFAULT="${SAY_WRITELOG_DEFAULT:-0}"     # 0 = no log, 1 = log
    SAY_DATE_FORMAT="${SAY_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"  # date format for --date

# --- Helpers ---------------------------------------------------------------------
    # __say_should_print_console
        # Purpose:
        #   Determine whether a message TYPE should be printed to the console
        #   according to the current output policy.
        #
        # Behavior:
        #   - FLAG_VERBOSE=1 overrides all filters (always prints).
        #   - TD_LOG_TO_CONSOLE=0 suppresses all console output.
        #   - DEBUG messages require FLAG_DEBUG=1 unless verbose.
        #   - Other types must be present in TD_CONSOLE_MSGTYPES.
        #
        # Arguments:
        #   $1  TYPE
        #       Message type token (case-insensitive).
        #
        # Inputs (globals):
        #   FLAG_VERBOSE, TD_LOG_TO_CONSOLE, FLAG_DEBUG, TD_CONSOLE_MSGTYPES
        #
        # Returns:
        #   0 if the message should be printed
        #   1 otherwise
        #
        # Usage:
        #   if __say_should_print_console "INFO"; then
        #       printf "...\n"
        #   fi
        #
        # Examples:
        #   __say_should_print_console "DEBUG" || return
    __say_should_print_console() {
        local type="${1^^}"
        local list="${TD_CONSOLE_MSGTYPES:-INFO|STRT|WARN|FAIL|CNCL|OK|END|EMPTY}"
        list="${list^^}"

        [[ "${FLAG_VERBOSE:-0}" -eq 1 ]] && return 0
        [[ "${TD_LOG_TO_CONSOLE:-1}" -eq 0 ]] && return 1
        [[ "$type" == "DEBUG" && "${FLAG_DEBUG:-0}" -eq 1 ]] && return 0

        [[ "|$list|" == *"|$type|"* ]]
    }

    # __td_logfile
        # Purpose:
        #   Resolve the effective logfile path based on configured priorities.
        #
        # Behavior:
        #   - Checks TD_LOG_PATH first, then TD_ALT_LOGPATH.
        #   - Uses td_can_append to validate write capability.
        #   - Returns the first usable path.
        #
        # Outputs:
        #   Prints the resolved logfile path (no newline).
        #
        # Returns:
        #   0 if a usable path is found
        #   1 otherwise
        #
        # Usage:
        #   logfile="$(__td_logfile)" || return
        #
        # Examples:
        #   if logfile="$(__td_logfile)"; then
        #       echo "Logging to $logfile"
        #   fi
    __td_logfile() {
        
        # Determine logfile path according to priority:
        # 1. TD_LOG_PATH if set and usable
        if [[ -n "${TD_LOG_PATH:-}" ]] && td_can_append "$TD_LOG_PATH"; then
            printf '%s' "$TD_LOG_PATH"
            return 0
        fi

        # 2. TD_ALT_LOGPATH if set and usable
        if [[ -n "${TD_ALT_LOGPATH:-}" ]] && td_can_append "$TD_ALT_LOGPATH"; then
            printf '%s' "$TD_ALT_LOGPATH"
            return 0
        fi

        return 1
    }

    # __say_caller
        # Purpose:
        #   Resolve the originating caller location for logging purposes.
        #
        # Behavior:
        #   - Traverses the call stack.
        #   - Skips internal say* wrappers.
        #   - Returns the first non-wrapper frame.
        #
        # Outputs:
        #   Prints:
        #     <function>\t<file>\t<line>
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   IFS=$'\t' read -r func file line <<< "$(__say_caller)"
        #
        # Examples:
        #   caller="$(__say_caller)"
    __say_caller() {
        local i
        for ((i=1; i<${#FUNCNAME[@]}; i++)); do
            case "${FUNCNAME[$i]}" in
                say|sayinfo|saywarning|sayfail|saydebug|justsay)
                    continue
                    ;;
                *)
                    printf '%s\t%s\t%s' \
                        "${FUNCNAME[$i]}" \
                        "${BASH_SOURCE[$i]}" \
                        "${BASH_LINENO[$((i-1))]}"
                    return
                    ;;
            esac
        done
        printf '<main>\t<unknown>\t?'
    }

    # __say_write_log
        # Purpose:
        #   Append a formatted log record to the logfile with optional rotation.
        #
        # Behavior:
        #   - No-op when logging is disabled or no valid logfile is available.
        #   - Sanitizes message (removes ANSI, normalizes whitespace).
        #   - Adds timestamp, user, type, and caller metadata.
        #   - Rotates logfile when size exceeds TD_LOG_MAX_BYTES.
        #   - Never fails the caller (best-effort).
        #
        # Arguments:
        #   $1  TYPE
        #   $2  MSG
        #   $3  DATE_STR (optional)
        #
        # Inputs (globals):
        #   TD_LOGFILE_ENABLED, TD_LOG_MAX_BYTES, TD_LOG_KEEP, TD_LOG_COMPRESS
        #   SAY_DATE_FORMAT
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __say_write_log "INFO" "Starting process" ""
        #
        # Examples:
        #   __say_write_log "FAIL" "Connection error" "$(date)"
    __say_write_log() {
        local type="${1^^}"
        local msg="$2"
        local date_str="$3"

        : "${TD_LOGFILE_ENABLED:=0}"
        : "${TD_LOG_MAX_BYTES:=$((25 * 1024 * 1024))}"
        : "${TD_LOG_KEEP:=5}"
        : "${TD_LOG_COMPRESS:=0}"

        # Looks backwards at first glance: logging OFF → exit successfully (=no-op)
        (( TD_LOGFILE_ENABLED )) || return 0

        local logfile
        logfile="$(__td_logfile)" || return 0
        [[ -n "$logfile" ]] || return 0

        local log_ts log_user caller_func caller_file caller_line clean_msg log_line

        if [[ -n "$date_str" ]]; then
            log_ts="$date_str"
        else
            log_ts="$(date "+${SAY_DATE_FORMAT}")"
        fi

        log_user="$(id -un 2>/dev/null || printf '%s' "${USER:-unknown}")"
        IFS=$'\t' read -r caller_func caller_file caller_line <<< "$(__say_caller)"

        clean_msg="$msg"
        clean_msg="$(printf '%s' "$clean_msg" | sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g')"
        clean_msg="${clean_msg//$'\r'/}"
        clean_msg="${clean_msg//$'\n'/\\n}"
        clean_msg="${clean_msg//$'\t'/\\t}"

        log_line="${log_ts} user=${log_user} type=${type} caller=${caller_func}:${caller_file}:${caller_line} msg=${clean_msg}"

        local size add_bytes
        size=$(stat -c %s "$logfile" 2>/dev/null || echo 0)
        add_bytes=$(( ${#log_line} + 1 ))   # +1 for '\n'

        if (( size + add_bytes >= TD_LOG_MAX_BYTES )); then
            __td_rotate_logs "$logfile"
        fi

        printf '%s\n' "$log_line" >>"$logfile" 2>/dev/null || true
    }

    # __td_rotate_logs
        # Purpose:
        #   Perform size-based rotation of a logfile.
        #
        # Behavior:
        #   - Renames logfile to logfile.1, shifts older files upward.
        #   - Keeps up to TD_LOG_KEEP rotated files.
        #   - Optionally compresses rotated files.
        #   - Recreates the active logfile.
        #
        # Arguments:
        #   $1  LOGFILE
        #
        # Inputs (globals):
        #   TD_LOG_MAX_BYTES, TD_LOG_KEEP, TD_LOG_COMPRESS
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __td_rotate_logs "/var/log/app.log"
        #
        # Examples:
        #   __td_rotate_logs "$logfile"
    __td_rotate_logs() {
            # Usage: __td_rotate_logs "/path/to/logfile"
            local logfile="$1"
            [[ -n "$logfile" ]] || return 0
            [[ -f "$logfile" ]] || return 0

            # If not exceeding, do nothing (caller can pre-check; keep safe here too)
            local size
            size="$(wc -c < "$logfile" 2>/dev/null)" || return 0
            (( size >= TD_LOG_MAX_BYTES )) || return 0

            local i src dst
            # Shift: logfile.N(.gz) -> logfile.(N+1)(.gz)
            for (( i=TD_LOG_KEEP; i>=1; i-- )); do
                src="${logfile}.${i}"
                dst="${logfile}.$((i+1))"
                [[ -f "$src" ]] && mv -f -- "$src" "$dst" 2>/dev/null || true
                [[ -f "${src}.gz" ]] && mv -f -- "${src}.gz" "${dst}.gz" 2>/dev/null || true
            done

            # Move current to .1
            mv -f -- "$logfile" "${logfile}.1" 2>/dev/null || true

            # Recreate (keep perms reasonable; adjust if you manage perms elsewhere)
            : > "$logfile" 2>/dev/null || true

            # Compress rotated file
            if (( TD_LOG_COMPRESS )) && [[ -f "${logfile}.1" ]]; then
                gzip -f "${logfile}.1" 2>/dev/null || true
            fi

            # Trim oldest beyond keep
            rm -f -- "${logfile}.$((TD_LOG_KEEP+1))" "${logfile}.$((TD_LOG_KEEP+1)).gz" 2>/dev/null || true
    }

# --- Public API ------------------------------------------------------------------
    # say
        # Purpose:
        #   Emit a typed message with formatting, colorization, and optional logging.
        #
        # Behavior:
        #   - Supports message types: INFO, STRT, WARN, FAIL, CNCL, OK, END, DEBUG, EMPTY
        #   - Builds prefix using label/icon/symbol based on configuration
        #   - Applies colorization rules
        #   - Honors console output policy
        #   - Logs message if enabled
        #
        # Usage:
        #   say INFO "Starting process"
        #   say --type WARN "Low disk space"
        #   say --date --show all --colorize both INFO "Message"
        #
        # Examples:
        #   say STRT "Initializing..."
        #
        #   say --date --type FAIL "Connection failed"
        #
        #   say DEBUG "Value = $value"
        #
        # Returns:
        #   0 always.
    say() {
      # -- Declarations
        local type="EMPTY"
        local add_date="${SAY_DATE_DEFAULT:-0}"
        local show="${SAY_SHOW_DEFAULT:-label}"
        local colorize="${SAY_COLORIZE_DEFAULT:-label}"

        local writelog="${SAY_WRITELOG_DEFAULT:-0}"
        local logfile="${LOG_FILE:-}"

        local explicit_type=0
        local msg=""
        local s_label=0 s_icon=0 s_symbol=0
        local prefixlength=0

      # -- Parse options
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --type)
                    type="${2^^}"
                    explicit_type=1
                    shift 2
                    ;;
                --date)
                    add_date=1
                    prefixlength=$((prefixlength + 19))
                    shift
                    ;;
                --show)
                    show="$2"
                    shift 2
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
                    # Positional TYPE: say STRT "message"
                    if (( ! explicit_type )); then
                        local maybe="${1^^}"
                        case "$maybe" in
                            INFO|STRT|WARN|FAIL|CNCL|OK|END|DEBUG|EMPTY)
                                type="$maybe"
                                explicit_type=1
                                shift
                                continue
                                ;;
                        esac
                    fi
                    break
                    ;;
            esac
        done

        msg="${*:-}"

        # Normalize TYPE
        type="${type^^}"
        case "$type" in
            INFO|STRT|WARN|FAIL|CNCL|OK|END|DEBUG|EMPTY) ;;
            *) type="EMPTY" ;;
        esac

        # EMPTY = print message only (no prefix), still eligible for logging
        if [[ "$type" == "EMPTY" ]]; then
            if __say_should_print_console "EMPTY"; then
                printf '%s\n' "$msg"
            fi
            __say_write_log "EMPTY" "$msg" ""
            return 0
        fi

      # -- Resolve style tokens for this TYPE via maps (LBL_*, ICO_*, SYM_*, MSG_CLR_*)
        local lbl icn smb clr
        local w

        w="LBL_${type}";     lbl="${!w:-$type}"
        w="ICO_${type}";     icn="${!w:-}"
        w="SYM_${type}";     smb="${!w:-}"
        w="MSG_CLR_${type}"; clr="${!w:-}"

      # -- Decode --show (supports "label,icon", "label+symbol", "all")
        local sel p
        IFS=',+' read -r -a sel <<<"$show"
        if [[ "${#sel[@]}" -eq 0 ]]; then
            sel=(label)
        fi

        for p in "${sel[@]}"; do
            case "${p,,}" in
                label)  s_label=1;  prefixlength=$((prefixlength + 8)) ;;
                icon)   s_icon=1;   prefixlength=$((prefixlength + 1)) ;;
                symbol) s_symbol=1; prefixlength=$((prefixlength + 3)) ;;
                all)
                    s_label=1; s_icon=1; s_symbol=1
                    prefixlength=$((prefixlength + 16))
                    ;;
            esac
        done

        if (( s_label + s_icon + s_symbol == 0 )); then
            s_label=1
            prefixlength=$((prefixlength + 8))
        fi

      # -- Decode colorize: none|label|msg|date|both|all
        local c_label=0 c_msg=0 c_date=0
        case "${colorize,,}" in
            none) ;;
            label) c_label=1 ;;
            msg)   c_msg=1 ;;
            date)  c_date=1 ;;
            both|all) c_label=1; c_msg=1; c_date=1 ;;
            *) c_label=1 ;;
        esac

      # -- Build final output line and print
        local fnl=""
        local date_str=""
        local rst="${RESET:-}"
        local prefix_parts=()

        if (( add_date )); then
            date_str="$(date "+${SAY_DATE_FORMAT}")"
            if (( c_date )); then
                prefix_parts+=("${clr}${date_str}${rst}")
            else
                prefix_parts+=("$date_str")
            fi
        fi

        local l_len pad_lbl
        l_len=$(td_visible_len "$lbl")
        pad_lbl=""
        if (( l_len < 8 )); then
            printf -v pad_lbl '%*s' $((8 - l_len)) ''
        fi
        lbl="${lbl}${pad_lbl}"

        if (( s_label )); then
            if (( c_label )); then
                prefix_parts+=("${clr}${lbl}${rst}")
            else
                prefix_parts+=("$lbl")
            fi
        fi

        if (( s_icon )); then
            if (( c_label )); then
                prefix_parts+=("${clr}${icn}${rst}")
            else
                prefix_parts+=("$icn")
            fi
        fi

        if (( s_symbol )); then
            if (( c_label )); then
                prefix_parts+=("${clr}${smb}${rst}")
            else
                prefix_parts+=("$smb")
            fi
        fi

        if ((${#prefix_parts[@]} > 0)); then
            fnl+="${prefix_parts[*]} "
            prefixlength=$((prefixlength + 1))
        fi

        local v_len
        v_len=$(td_visible_len "$fnl")

        local pad_col=""
        if (( v_len < prefixlength )); then
            printf -v pad_col '%*s' $((prefixlength - v_len)) ''
        else
            pad_col=" "
        fi
        fnl+="$pad_col"

        if (( c_msg )); then
            fnl+="${clr}${msg}${rst}"
        else
            fnl+="$msg"
        fi

        if __say_should_print_console "$type"; then
            printf '%s\n' "$fnl $RESET"
        fi

        __say_write_log "$type" "$msg" "$date_str"
    }

    # -- Convenience wrappers for say() with a fixed TYPE.
        # sayinfo
            # Purpose:
            #   Emit an INFO message.
            #
            # Behavior:
            #   - Delegates to say INFO.
            #   - Only emits when FLAG_VERBOSE=1.
            #   - Always returns 0, even when suppressed.
            #
            # Inputs (globals):
            #   FLAG_VERBOSE
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   sayinfo "Loading optional libraries..."
            #
            # Examples:
            #   sayinfo "Using default configuration"
        sayinfo() {
            if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                say INFO "$@"
            fi
            return 0
        }

        # saystart
            # Purpose:
            #   Emit a STRT message.
            #
            # Behavior:
            #   - Delegates to say STRT.
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   saystart "Initializing framework"
            #
            # Examples:
            #   saystart "Starting installation"
        saystart() {
            say STRT "$@"
        }

        # saywarning
            # Purpose:
            #   Emit a WARN message.
            #
            # Behavior:
            #   - Delegates to say WARN.
            #
            # Usage:
            #   saywarning "Disk space low"
            #
            # Examples:
            #   saywarning "Configuration missing"
        saywarning() {
            say WARN "$@"
        }

        # sayfail
            # Purpose:
            #   Emit a FAIL message.
            #
            # Behavior:
            #   - Delegates to say FAIL.
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   sayfail "Cannot create directory: $dir"
            #
            # Examples:
            #   sayfail "Bootstrap failed"
        sayfail() {
            say FAIL "$@"
        }

        # saycancel
            # Purpose:
            #   Emit a CNCL message.
            #
            # Behavior:
            #   - Delegates to say CNCL.
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   saycancel "Cancelled by user"
            #
            # Examples:
            #   saycancel "Operation aborted"
        saycancel() {
            say CNCL "$@"
        }

        # sayok
            # Purpose:
            #   Emit an OK message.
            #
            # Behavior:
            #   - Delegates to say OK.
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   sayok "Configuration written successfully"
            #
            # Examples:
            #   sayok "Validation passed"
        sayok() {
            say OK "$@"
        }

        # sayend
            # Purpose:
            #   Emit an END message.
            #
            # Behavior:
            #   - Delegates to say END.
            #
            # Returns:
            #   0 always.
            #
            # Usage:
            #   sayend "Process completed"
            #
            # Examples:
            #   sayend "Finished successfully"
        sayend() {
            say END "$@"
        }

        # justsay
            # Purpose:
            #   Emit plain text without formatting or logging.
            #
            # Behavior:
            #   - Prints directly to stdout.
            #
            # Usage:
            #   justsay "Hello world"
            #
            # Examples:
            #   justsay "Raw output"
        justsay() {
            printf '%s\n' "$@"
        }

        # saydebug
            # Purpose:
            #   Emit a DEBUG message with optional caller context.
            #
            # Behavior:
            #   - Only active when FLAG_DEBUG=1.
            #   - Adds caller info when FLAG_VERBOSE=1.
            #   - Delegates to say DEBUG.
            #
            # Usage:
            #   saydebug "Value = $x"
            #
            # Examples:
            #   saydebug "Entering function"
        saydebug() {
            if [[ ${FLAG_DEBUG:-0} -eq 1 ]]; then

                if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                    # Stack level 1 = caller of saydebug
                    local src="${BASH_SOURCE[1]##*/}"
                    local func="${FUNCNAME[1]}"
                    local line="${BASH_LINENO[0]}"

                    say DEBUG "$@" "[$src:$func:$line]"
                else
                    say DEBUG "$@"
                fi
            fi
            return 0
        }
    # -- Sample/demo renderers
    say_test(){
        sayinfo "Info message"
        saystart "Start message"
        saywarning "Warning message"
        sayfail "Failure message"
        saycancel "Cancellation message"
        sayok "All is well"
        sayend "Ended gracefully"
        saydebug "Debug message"
        justsay "Just saying"
    }
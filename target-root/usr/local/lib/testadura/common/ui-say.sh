# =================================================================================
# Testadura Consultancy — ui-say.sh
# ---------------------------------------------------------------------------------
# Purpose    : Typed message output (say*) with optional logfile routing
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Description:
#   Provides the say() API and say* shorthands for consistent, typed console output:
#     INFO, STRT, WARN, FAIL, CNCL, OK, END, DEBUG, EMPTY
#
#   Features:
#   - Prefix composition (label/icon/symbol) via style maps (LBL_*, ICO_*, SYM_*)
#   - Optional timestamp prefix (SAY_DATE_FORMAT)
#   - Selective colorization (label/msg/date) via MSG_CLR_<TYPE>* and RESET
#   - Optional logfile output with ANSI stripping and log rotation
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - Theme/style variables exist (CLR_*, RESET, LBL_*, ICO_*, SYM_*).
#   - Core/UI primitives are available when used (e.g., visible_len, td_repeat).
#   - Logging globals may exist (TD_LOGFILE_ENABLED, TD_LOG_MAX_BYTES, TD_LOG_KEEP,
#     TD_LOG_COMPRESS, TD_CONSOLE_MSGTYPES, FLAG_VERBOSE).
#
# Rules / Contract:
#   - Implements message formatting and rendering for the say* family only.
#   - No interactive prompting (confirmation/input belongs in ui-ask.sh).
#   - Safe to source multiple times (must be guarded).
#   - Library-only: must be sourced, never executed.
#
# Non-goals:
#   - User input or dialogs (see ui-ask.sh)
#   - Application-specific message policy beyond type filtering
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
        # __say_should_print_console TYPE
            #   Returns 0 if TYPE should be printed to console under current policy.
            #   Policy order:
            #     1) FLAG_VERBOSE forces output
            #     2) TD_LOG_TO_CONSOLE=0 disables output
            #     3) DEBUG requires FLAG_DEBUG=1
            #     4) TYPE must appear in TD_CONSOLE_MSGTYPES (pipe-separated list)
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
            #   Prints the resolved logfile path to stdout.
            #   Resolution order:
            #     1) TD_LOG_PATH (if writable/creatable)
            #     2) TD_ALT_LOGPATH (if writable/creatable)
            #   Returns non-zero if no usable path is available.
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
            #   Returns a tab-separated triple:
            #     <func>\t<file>\t<line>
            #   Skips internal say* wrappers so logs point at the real caller.
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

        # __say_write_log TYPE MSG DATE_STR
            #   Appends a single-line, ANSI-stripped record to the resolved logfile.
            #   - DATE_STR may be empty (then a timestamp is generated).
            #   - Respects TD_LOGFILE_ENABLED and rotation settings.
            #   - Never fails the caller (best-effort logging).
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

         # __td_rotate_logs LOGFILE
            #   Performs size-based rotation:
            #     LOGFILE     -> LOGFILE.1(.gz)
            #     LOGFILE.1   -> LOGFILE.2, ... up to TD_LOG_KEEP
            #   Compression is controlled by TD_LOG_COMPRESS.
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
        # Typed message output with optional timestamp, selective prefix parts, and logging.
        #
        # Usage:
        #   say [TYPE] [message...]
        #   say [opts] [TYPE] [message...]
        #
        # Types:
        #   INFO STRT WARN FAIL CNCL OK END DEBUG EMPTY
        #
        # Options:
        #   --type TYPE           Explicit message type (else: first positional TYPE)
        #   --date                Prefix timestamp (SAY_DATE_FORMAT)
        #   --show PATTERN        Prefix parts: label|icon|symbol|all (comma/+ separated)
        #   --colorize MODE       none|label|msg|date|both|all
        #   --                    End options; rest is message
        #
        # Logging:
        #   - Controlled globally via TD_LOGFILE_ENABLED and TD_LOG_PATH/TD_ALT_LOGPATH.
        #   - Log output is plain text (ANSI stripped) with optional rotation.
        #
        # TODO:
        #   - Per-call logfile override and per-call log enable/disable are not implemented yet.
        #
        # Defaults (env/style):
        #   SAY_DATE_DEFAULT, SAY_SHOW_DEFAULT, SAY_COLORIZE_DEFAULT, SAY_WRITELOG_DEFAULT,
        #   SAY_DATE_FORMAT
        #
        # Examples:
        #   say INFO "Starting"
        #   say --date WARN "Low disk space"
        #   say --show=all --colorize=both OK "All good"

        # -----------------------------------------------------------------------------
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
        sayinfo() {
            if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                say INFO "$@"
            fi
            return 0
        }

        saystart() {
            say STRT "$@"
        }

        saywarning() {
            say WARN "$@"
        }

        sayfail() {
            say FAIL "$@"
        }

        saycancel() {
            say CNCL "$@"
        }

        sayok() {
            say OK "$@"
        }

        sayend() {
            say END "$@"
        }

        justsay() {
            printf '%s\n' "$@"
        }

        saydebug() {
            if [[ ${FLAG_DEBUG:-0} -eq 1 ]]; then
                say DEBUG "$@"
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
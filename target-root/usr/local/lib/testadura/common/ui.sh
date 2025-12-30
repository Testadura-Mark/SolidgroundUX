#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — ui.sh
# -------------------------------------------------------------------------------
# Purpose : Easy user interaction functions
# Author  : Mark Fieten
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description :
#   User interaction functions. 
# ===============================================================================

# --- Overrides ----------------------------------------------------------
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

# --- UI functions -------------------------------------------------------
  # --- say() global defaults ----------------------------------------------------
  
  # Can be overridden in:
  #   - environment
  #   - styles/*.sh
  SAY_DATE_DEFAULT="${SAY_DATE_DEFAULT:-0}"              # 0 = no date, 1 = add date
  SAY_SHOW_DEFAULT="${SAY_SHOW_DEFAULT:-label}"         # label|icon|symbol|all|label,icon|...
  SAY_COLORIZE_DEFAULT="${SAY_COLORIZE_DEFAULT:-label}" # none|label|msg|both|all|date
  SAY_WRITELOG_DEFAULT="${SAY_WRITELOG_DEFAULT:-0}"     # 0 = no log, 1 = log
  SAY_DATE_FORMAT="${SAY_DATE_FORMAT:-%Y-%m-%d %H:%M:%S}"  # date format for --date

  # --- Say -----------------------------------------------------------------------
    # Options supported by say():
      #
      #   - --type <TYPE>
      #       Explicitly set message type.
      #       Valid: INFO, STRT, WARN, FAIL, CNCL, OK, END, DEBUG, EMPTY
      #
      #   - --date
      #       Add timestamp prefix using SAY_DATE_FORMAT.
      #
      #   - --show <pattern>
      #       Control which parts of the prefix to display.
      #       Patterns (comma or + separated):
      #         label      → e.g. [INFO]
      #         icon       → e.g. ℹ️
      #         symbol     → e.g. >
      #         all        → label + icon + symbol
      #       Examples:
      #         --show=label
      #         --show=icon
      #         --show=label,icon
      #         --show=all
      #
      #   - --colorize <mode>
      #       Control which elements receive color.
      #       Modes:
      #         none       → no color
      #         label      → colorize label/icon/symbol only
      #         msg        → colorize message text only
      #         date       → colorize timestamp
      #         both|all   → colorize label + message + date
      #
      #   - --writelog
      #       Write the message to a logfile (plain text, no ANSI).
      #       Uses LOG_FILE unless overridden by --logfile.
      #
      #   - --logfile <path>
      #       Override the logfile for this invocation only.
      #
      #   - --
      #       End option processing; treat remaining tokens as the message.
      #
      #   Positional type:
      #       You may specify TYPE as the first argument instead of using --type:
      #         say INFO "Message"
      #         say WARN "Something happened"
      #
      #   Defaults (overridable via environment or style files):
      #       SAY_DATE_DEFAULT       → 0 or 1
      #       SAY_SHOW_DEFAULT       → label|icon|symbol|all|label,icon|…
      #       SAY_COLORIZE_DEFAULT   → none|label|msg|both|all|date
      #       SAY_WRITELOG_DEFAULT   → 0 or 1
      #       SAY_DATE_FORMAT        → strftime pattern
    # Usage examples:
      #   - Simplest usage: INFO with label only
      #     say INFO "Starting deployment"
      #
      #   - Let say() infer the type from first argument (same effect)
      #     say STRT "Initializing workspace"
      #
      #   - Explicit type using --type
      #     say --type warn "Low disk space on /data"
      #
      #   - Show date + label (colorization uses defaults)
      #     say --date INFO "Backup completed"
      #
      #   - Show label + icon + symbol (style maps: LBL_*, ICO_*, SYM_*)
      #     say --show=all WARN "Configuration file missing; using defaults"
      #
      #   - Only show icon + message, no label
      #     say --show=icon --colorize=msg OK "All services are up"
      #
      #   - Colorize only the label (default behavior)
      #     say --colorize=label FAIL "Deployment failed; see log for details"
      #
      #   - Colorize date + label + message
      #     say --date --colorize=all INFO "System update finished"
      #
      #   - Log to default logfile (LOG_FILE)
      #     say --writelog INFO "Scheduled job executed successfully"
      #
      #   - Log to an explicit logfile (overrides LOG_FILE)
      #     say --writelog --logfile "/var/log/testadura/custom.log" \
      #         WARN "Manual override applied"
      #
      #   - DEBUG messages (when DEBUG style is defined)
      #     say DEBUG "Checking configuration before deploy"
      #
      #   - Plain message without prefix (EMPTY type)
      #     say EMPTY "----------------------------------------"
      #
      #   - Change defaults for the entire script
      #       export SAY_DATE_DEFAULT=1
      #       export SAY_SHOW_DEFAULT="label,icon"
      #       export SAY_COLORIZE_DEFAULT="both"
      #       say INFO "These settings apply to all subsequent calls"
      #
      #   - Colorize only the date, leave label/msg plain
      #     say --date --colorize=date INFO "Daily maintenance window started"
     # ---------------------------------------------------------------------------
  say() {
    local type="EMPTY"
    local add_date="${SAY_DATE_DEFAULT:-0}"
    local show="${SAY_SHOW_DEFAULT:-label}"
    local colorize="${SAY_COLORIZE_DEFAULT:-label}"
    local writelog="${SAY_WRITELOG_DEFAULT:-0}"
    local logfile="${LOG_FILE:-}"

    local explicit_type=0
    local msg
    local s_label=0 s_icon=0 s_symbol=0

    # --- Parse options
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)
          type="${2^^}"
          explicit_type=1
          shift 2
          ;;
        --date)
          add_date=1
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
        --writelog)
          writelog=1
          shift
          ;;
        --logfile)
          logfile="$2"
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
      # First non-option, non-type token -> start of message
      break
      ;;
      esac
    done

    msg="${*:-}"

    # Normalize TYPE
    type="${type^^}"
    case "$type" in
      INFO|STRT|WARN|FAIL|CNCL|OK|END|DEBUG|EMPTY) ;;
      "") type="ËMPTY" ;;
      *) type="EMPTY" ;;
    esac
    
    if [[ "$type" != "EMPTY" ]]; then
      
      # Resolve maps via namerefs
      #   Expects LBL_<TYPE>, ICO_<TYPE>, SYM_<TYPE>, CLR_<TYPE>
      wrk="LBL_${type}"
      declare -n lbl="$wrk"
      wrk="ICO_${type}"
      declare -n icn="$wrk"
      wrk="SYM_${type}"
      declare -n smb="$wrk"
      wrk="CLR_${type}"
    
      declare -n clr="$wrk"
     
      # Decode --show (supports "label,icon", "label+symbol", "all")
      local sel p
      IFS=',+' read -r -a sel <<<"$show"
      if [[ "${#sel[@]}" -eq 0 ]]; then sel=(label); fi

      for p in "${sel[@]}"; do
        case "${p,,}" in
          label)  s_label=1 ;;
          icon)   s_icon=1  ;;
          symbol) s_symbol=1 ;;
          all)
            s_label=1
            s_icon=1
            s_symbol=1
            ;;
        esac
      done

      # default: at least label
      if (( s_label + s_icon + s_symbol == 0 )); then
        s_label=1
      fi

      # Decode colorize: none|label|msg|date|both|all
      local c_label=0 c_msg=0 c_date=0

      case "${colorize,,}" in
        none)
          # all stay 0
          ;;
        label)
          c_label=1
          ;;
        msg)
          c_msg=1
          ;;
        date)
          c_date=1
          ;;
        both|all)
          c_label=1
          c_msg=1
          c_date=1
          ;;
        *)
          # default to 'label'
          c_label=1
          ;;
      esac

      # Build final line
      local fnl=""
      local date_str=""
      local prefix_parts=()
      local rst="${RESET:-}"


      # timestamp
      if (( add_date )); then
        date_str="$(date "+${SAY_DATE_FORMAT}")"
        if (( c_date )); then
          prefix_parts+=("${clr}${date_str}${rst}")
        else
          prefix_parts+=("$date_str")
        fi
      fi

      # label / icon / symbol
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

      # join prefix with spaces
      if ((${#prefix_parts[@]} > 0)); then
        fnl+="${prefix_parts[*]} "
      fi

      # message text
      if (( c_msg )); then
        fnl+="${clr}${msg}${rst}"
      else
        fnl+="$msg"
      fi

      printf '%s\n' "$fnl $RESET"
    else
      # EMPTY type: just print message (no prefix) 
      printf '%s\n' "$msg"
    fi


    # Optional log (plain; no ANSI)
    # Always include date+type in logs for clarity
    if (( writelog )) && [[ -n "$logfile" ]]; then
      local log_ts log_line
      if [[ -n "$date_str" ]]; then
        log_ts="$date_str"
      else
        log_ts="$(date "+${SAY_DATE_FORMAT}")"
      fi

      # lbl is typically "[INFO]" / "[WARN]" etc. If you prefer raw type, use "$type".
      log_line="$log_ts $lbl $msg"

      printf '%s\n' "$log_line" >>"$logfile" 2>/dev/null || true
    fi
    
  }
  # --- say shorthand ------------------------------------------------------------
    sayinfo() {
        say INFO "$@"
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
       say --date DEBUG "$@" 
    }
  
  # --- ask ---------------------------------------------------------------------
    #   Prompt user for input with optional:
    #     --label TEXT       Display label
    #     --var NAME         Store result in variable NAME
    #     --default VALUE    Pre-filled editable default
    #     --colorize MODE    none|label|input|both  (default: none)
    #     --validate FUNC    Validation function FUNC "$value"
    #     --echo             Echo value with ✓ / ✗
    #
    #   Validation functions
          #	Filesystem validations
            #	validate_file_exists()
            #	validate_path_exists()
            #	validate_dir_exists()
            #	validate_executable()
            #	validate_file_not_exists()

          #	Type validations
            #	validate_int() {
            #	validate_numeric() 
            #	validate_text() 
            #	validate_bool() 
            #	validate_date() 
            #	validate_ip() 
            #	validate_slug() 
            #	validate_fs_name() 
    #   Usage examples:
      #   Ask for filename with exists validation
      #     ask --label "Template script file" 
      #         --default "$default_template" 
      #         --validate validate_file_exists 
      #         --var TEMPLATE_SCRIPT
      #
      #   Ask for an ip address with validation 
      #     ask --label "Bind IP address" 
      #         --default "127.0.0.1" 
      #         --validate validate_ip 
      #         --var BIND_IP
      #
      #   Retry-loop
      #     while true; do
      #       __collect_settings
      #
      #       ask_ok_retry_quit "Proceed with these settings?"
      #       choice=$?
      #
      #       case $choice in
      #         0)  break ;;               # OK
      #        10) continue ;;            # Retry
      #        20) say WARN "Aborted." ; exit 1 ;;
      #       esac
      #    done
      #
      #   Ask with different color settings
      #     ask --label "Service name" 
      #         --default "my-service" 
      #         --colorize input 
      #         --var SERVICE_NAME
      #   
      #     ask --label "Owner" 
      #         --default "$USER" 
      #         --colorize label 
      #         --var SERVICE_OWNER
      #   
      #     ask --label "Description" 
      #         --default "" 
      #         --colorize both 
      #         --var SERVICE_DESC
      #
      #   Press Enter to continue
      #     ask_continue "Review the settings above"
      #   
      #   Alternative syntax
      #     USER_EMAIL=$(ask --label "Email address" --default "user@example.com")
    #
    #   Coloring stored in active style,(when empty default)
    #     CLR_LABEL
    #     CLR_INPUT
    #     CLR_TEXT
    #     CLR_DEFAULT
    #     CLR_VALID
    #     CLR_INVALID
  ask(){
    local label="" var_name="" colorize="both"
    local validate_fn="" def_value="" echo_input=0

    # ---- parse options ------------------------------------------------------
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --label)    label="$2"; shift 2 ;;
            --var)      var_name="$2"; shift 2 ;;
            --colorize) colorize="$2"; shift 2 ;;
            --validate) validate_fn="$2"; shift 2 ;;
            --default)  def_value="$2"; shift 2 ;;
            --echo)     echo_input=1; shift ;;
            --)         shift; break ;;
            *)          [[ -z "$label" ]] && label="$1"; shift ;;
        esac
    done

    # ---- resolve color mode -------------------------------------------------
      
    local label_color="$CLR_LABEL"
    local input_color="$CLR_INPUT"
    local default_color="$CLR_DEFAULT"

    case "$colorize" in
        label)
            label_color="$CLR_LABEL"
            ;;
        input)
            input_color="$CLR_INPUT"
            ;;
        both)
            label_color="$CLR_LABEL"
            input_color="$CLR_INPUT"
            ;;
        none|*) ;;
    esac
    
    # ---- build prompt -------------------------------------------------------
    local prompt=""
    if [[ -n "$label" ]]; then
        # label in label_color, then ": ", then switch to input_color for typing
        prompt+="${label_color}${label}${RESET}: ${input_color}"
    fi

    # ---- use bash readline pre-fill (-i) -----------------------------------
    local value ok
    if [[ -n "$def_value" ]]; then
        # LABEL is a real prompt (not editable), def_value is editable
        IFS= read -e -p "$prompt" -i "$def_value" value
        [[ -z "$value" ]] && value="$def_value"
    else
        # no default — simple prompt
        IFS= read -e -p "$prompt" value
    fi

    # reset color after the line, so the rest of the script isn't tinted
    printf "%b\n" "$RESET"


    # ---- validation ---------------------------------------------------------
    ok=1
    if [[ -n "$validate_fn" ]]; then
        if "$validate_fn" "$value"; then
            ok=1
        else
            ok=0
        fi
    fi

    # ---- echo with ✓ / ✗ ----------------------------------------------------
    if (( echo_input )); then
        if (( ok )); then
            printf "  %b%s%b %b✓%b\n" \
                "$input_color" "$value" "$RESET" \
                "$CLR_VALID" "$RESET"
        else
            printf "  %b%s%b %b✗%b\n" \
                "$CLR_INPUT" "$value" "$RESET" \
                "$CLR_INVALID" "$RESET"
        fi
    fi

    # Re-prompt on validation failure
    if (( !ok )); then
        printf "%bInvalid value. Please try again.%b\n" "$CLR_INVALID" "$RESET"
        ask "$@"   # recursive retry
        return
    fi

    # ---- return value -------------------------------------------------------
    if [[ -n "$var_name" ]]; then
        printf -v "$var_name" '%s' "$value"
    elif [[ "$echo_input" -eq 1 ]]; then
        printf "%s\n" "$value"
    fi
  }
  # --- Ask shorthand
      ask_yesno(){
        local prompt="$1"
        local yn_response

        ask --label "$prompt [Y/n]" --default "Y" --var yn_response

        case "${yn_response^^}" in
            Y|YES) return 0 ;;
            N|NO)  return 1 ;;
            *)     return 1 ;; # fallback to No
        esac
      }
      ask_noyes() {
          local prompt="$1"
          local ny_response

          ask --label "$prompt [y/N]" --default "N" --var ny_response

          case "${ny_response^^}" in
              Y|YES) return 0 ;;
              N|NO)  return 1 ;;
              *)     return 1 ;;
          esac
      }
      ask_okcancel() {
        local prompt="$1"
        local oc_response

        ask --label "$prompt [OK/Cancel]" --default "OK" --var oc_response

        case "${oc_response^^}" in
            OK)     return 0 ;;
            CANCEL) return 1 ;;
            *)      return 1 ;;
        esac
      }
      ask_ok_redo_quit() {
          local prompt="$1"
          local orq_response=""

          ask --label "$prompt [OK/Redo/Quit]" --default "OK" --var orq_response

          # Trim whitespace (left + right)
          orq_response="${orq_response#"${orq_response%%[![:space:]]*}"}"
          orq_response="${orq_response%"${orq_response##*[![:space:]]}"}"

          local upper="${orq_response^^}"

          case "$upper" in
              ""|OK|O)        return 0  ;;  # Enter defaults to OK
              REDO|R)         return 1 ;;
              QUIT|Q|EXIT)    return 2 ;;
              *)              return 3 ;;
          esac
    }
  # --- File system validations
      validate_file_exists() {
          local path="$1"

          [[ -f "$path" ]] && return 0    # valid
          return 1                        # invalid
      }
      validate_path_exists() {
          [[ -e "$1" ]] && return 0
          return 1
      }
      validate_dir_exists() {
          [[ -d "$1" ]] && return 0
          return 1
      }
      validate_executable() {
          [[ -x "$1" ]] && return 0
          return 1
      }
      validate_file_not_exists() {
          [[ ! -f "$1" ]] && return 0
          return 1
      }

  # --- Type validations
    validate_int() {
        [[ "$1" =~ ^-?[0-9]+$ ]] && return 0
        return 1
    }
    validate_numeric() {
        [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && return 0
        return 1
    }
    validate_text() {
        [[ -n "$1" ]] && return 0
        return 1
    }
    validate_bool() {
        case "${1,,}" in
            y|yes|n|no|true|false|1|0)
                return 0 ;;
            *)
                return 1 ;;
        esac
    }
    validate_date() {
        [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && return 0
        return 1
    }
    validate_ip() {
        local ip="$1"
        local IFS='.'
        local -a octets

        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

        read -r -a octets <<< "$ip"

        for o in "${octets[@]}"; do
            (( o >= 0 && o <= 255 )) || return 1
        done

        return 0
    }
    validate_slug() {
        [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] && return 0
        return 1
    }
    validate_fs_name() {
        [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && return 0
      return 1
    }









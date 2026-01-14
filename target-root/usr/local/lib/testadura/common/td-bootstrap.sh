# Framwork root
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-/}"
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-/}" # Application root (where this script is deployed)
    
    TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}"
    TD_SYSCFG_DIR="${TD_SYSCFG_DIR:-$TD_APPLICATION_ROOT/etc/testadura}" # Sys config directory path
   
    TD_USRCFG_DIR="${TD_USRCFG_DIR:-$HOME/.config}/testadura" # Usr config directory path
    

# --- Minimal fallback UI (overridden by ui.sh when sourced) ----------------------
    saystart()   { printf 'START  \t%s\n' "$*" >&2; }
    saywarning() { printf 'WARNING \t%s\n' "$*" >&2; }
    sayfail()    { printf 'FAIL    \t%s\n' "$*" >&2; }
    saycancel()  { printf 'CANCEL  \t%s\n' "$*" >&2; }
    sayend()     { printf 'END     \t%s\n' "$*" >&2; }
    sayok()      { printf 'OK      \t%s\n' "$*" >&2; }
    sayinfo()    { printf 'INFO    \t%s\n' "$*" >&2; }
    sayerror()   { printf 'ERR     \t%s\n' "$*" >&2; }

# --- Loading libraries from TD_COMMON_LIB ---------------------------------------------    
    td_source_libs() {
        local lib path
        saystart "Sourcing libraries from: $TD_COMMON_LIB" 

        for lib in "${TD_USING[@]}"; do
            path="$TD_COMMON_LIB/$lib"

            if [[ -f "$path" ]]; then
                #sayinfo "Using library: $path" >&2
                # shellcheck source=/dev/null
                source "$path"
                continue
            fi

            # core.sh is required
            if [[ "$lib" == "core.sh" ]]; then
                sayfail "Required library not found: $path" 
                echo "Cannot continue without core library." >&2
                exit 2
            fi

            saywarning "Library not found (optional): $path" 
        done

        sayend "All libraries sourced." 
    }

# --- Initialize framework
    # -- Framwork metadata
        TD_SYS_GLOBALS=(
            TD_STATE_DIR
            TD_LOGFILE_ENABLED
            TD_CONSOLE_MSGTYPES
            TD_LOG_PATH
            TD_ALTLOG_PATH
            TD_LOG_MAX_BYTES
            TD_LOG_KEEP
            TD_LOG_COMPRESS
            SAY_COLORIZE_DEFAULT
            SAY_DATE_DEFAULT
            SAY_SHOW_DEFAULT
            SAY_DATE_FORMAT
        )
        TD_USR_GLOBALS=(
            TD_STATE_DIR
            TD_CONSOLE_MSGTYPES

            SAY_COLORIZE_DEFAULT
            SAY_DATE_DEFAULT
            SAY_SHOW_DEFAULT
            SAY_DATE_FORMAT
        )
        TD_CORE_LIBS=(
            args.sh
            cfg.sh
            core.sh
            ui.sh
            default-colors.sh
            default-styles.sh
        )
    # -- Helpers
        __create_cfg_template() {
            local dir="$1"
            local filename="$2"
            local template_fn="$3"
            local dirmode="${4:-0755}"
            local filemode="${5:-0644}"

            if [[ -z "$dir" || -z "$filename" || -z "$template_fn" ]]; then
                sayerror "__create_cfg_template: missing arguments" >&2
                return 1
            fi

            if ! declare -F "$template_fn" >/dev/null; then
                sayerror "__create_cfg_template: template not found: $template_fn" >&2
                return 2
            fi

            install -d -m "$dirmode" "$dir" || return 3

            local path="$dir/$filename"

            "$template_fn" > "$path" || return 4
            chmod "$filemode" "$path" || return 5

            sayok "Wrote config: $path"
            return 0
        }

        __source_systemoruser() {
            local cfg_file="$1"          # e.g. solidgroundux.cfg
            local cfg_create="${2:-0}"   # 0/1
            local template_fn="${3:-}"   # e.g. __create_cfg_template

            local cfg_source=0
            local user_cfg=""

            # --- system cfg ---
            if [[ -r "$TD_SYSCFG_DIR/$cfg_file" ]]; then
                # shellcheck disable=SC1090
                source "$TD_SYSCFG_DIR/$cfg_file"
                cfg_source=1
            fi

            # --- optional user cfg (dev override) ---
            if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
                user_cfg="$TD_USRCFG_DIR/$cfg_file"
                if [[ -r "$user_cfg" ]]; then
                    # shellcheck disable=SC1090
                    source "$user_cfg"
                    cfg_source=2
                fi
            fi

            # --- create if requested and none found ---
            if (( cfg_create == 1 )) && (( cfg_source == 0 )); then
                if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
                    __create_cfg_template \
                        "$TD_SYSCFG_DIR" \
                        "$cfg_file" \
                        "$template_fn"
                else
                    __create_cfg_template \
                        "$TD_USRCFG_DIR" \
                        "$cfg_file" \
                        "$template_fn"
                fi
            fi

            # return source indicator if you want
            # echo "$cfg_source"
            return 0
        }

    # -- Template cfg files   
            __print_sysglobals_cfg(){
                local var
                printf '%s\n' "# Framework globals system only globals and settings"
                
                # Build lookup table for user globals
                local -A _usr
                for var in "${TD_USR_GLOBALS[@]}"; do
                    _usr["$var"]=1
                done

                # Emit only SYS globals not present in USR globals
                for var in "${TD_SYS_GLOBALS[@]}"; do
                    [[ -n "${_usr[$var]:-}" ]] && continue

                    if [[ -v "$var" ]]; then
                        printf '%s=%q\n' "$var" "${!var}"
                    else
                        printf '# %s is unset\n' "$var"
                    fi
                done
                printf "\n"
                __print_usrglobals_cfg
            }
            __print_usrglobals_cfg(){
                local var
                printf '%s\n' "# User overridable globals and settings"
                for var in "${TD_USR_GLOBALS[@]}"; do
                    if [[ -v "$var" ]]; then
                        printf '%s=%q\n' "$var" "${!var}"
                    else
                        printf '# %s is unset\n' "$var"
                    fi
                done
            }
            __print_bootstrap_cfg() {
                printf "%s\n" "# SolidgroundUX bootstrap configuration"
                printf "%s\n" "# Purpose: allow locating the framework + application roots."
                printf "%s\n" "# Values below mirror derived defaults at source-time."
                printf "%s\n" "# Override by editing this file if needed."
                printf "%s\n" ""

                printf 'TD_FRAMEWORK_ROOT=%q\n' "$TD_FRAMEWORK_ROOT"
                printf 'TD_APPLICATION_ROOT=%q\n' "$TD_APPLICATION_ROOT"
                printf "%s\n" ""

                printf 'TD_USRCFG_DIR=%q\n' "$TD_USRCFG_DIR"
                printf "%s\n" ""

                printf "%s\n" "# Initially derived, but overridable here"
                printf 'TD_COMMON_LIB=%q\n' "$TD_COMMON_LIB"
                printf 'TD_SYSCFG_DIR=%q\n' "$TD_SYSCFG_DIR"
            }      

    # -- Main sequence        
        __parse_bootstrap_args() {
            exe_ui=0
            exe_libs=1
            exe_state=0
            exe_cfg=0
            exe_args=1
            exe_root=0

            TD_BOOTSTRAP_REST=()

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --ui)        exe_ui=1; shift ;;
                    --state)     exe_state=1; shift ;;
                    --cfg)       exe_cfg=1; shift ;;
                    --needroot)  exe_root=1; shift ;;
                    --cannotroot)exe_root=2; shift ;;
                    --args)      exe_args=1; shift ;;
                    --init-config)
                        FLAG_INIT_CONFIG=1; shift ;;
                    --) shift; TD_BOOTSTRAP_REST=("$@"); return 0 ;;
                    *) TD_BOOTSTRAP_REST=("$@"); return 0 ;;
                esac
            done

            TD_BOOTSTRAP_REST=()
        }

        __init_bootstrap() {
            cfg_source=0  # 0 defaults, 1 system, 2 user
            cfg_file="solidgroundux.cfg"
            __source_systemoruser "$cfg_file" 1 "__print_bootstrap_cfg"
            
            TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}" # Reset if root has changed AND isn't set by cfg load

            if [[ ! -r "$TD_COMMON_LIB/core.sh" ]]; then
                echo "Invalid TD_FRAMEWORK_ROOT: $TD_FRAMEWORK_ROOT (missing $TD_COMMON_LIB/core.sh)" >&2
                exit 2
            fi
        }

        __source_globals(){
            cfg_source=0  # 0 defaults, 1 system, 2 user
            cfg_file="td-globals.cfg"

            if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
                __source_systemoruser "$cfg_file" 1 "__print_sysglobals_cfg"
            else
                __source_systemoruser "$cfg_file" 1 "__print_usrglobals_cfg"
            fi

        }
        __source_corelibs(){
            local lib path
            for lib in "${TD_CORE_LIBS[@]}"; do
                path="$TD_COMMON_LIB/$lib"
                # shellcheck source=/dev/null
                source "$path"
            done
        }

        __finalize_bootstrap() {       
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   
            FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
            FLAG_STATERESET="${FLAG_STATERESET:-0}"
            if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
                td_state_reset
                sayinfo "State file reset as requested."
            fi

            RUN_MODE=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_ORANGE}DRYRUN${RESET}" || echo "${BOLD_GREEN}COMMIT${RESET}")

            TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)" # User home directory
            
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Running in Dry-Run mode (no changes will be made)."
            else
                saywarning "Running in Normal mode (changes will be applied)."
            fi

            if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
                __td_showarguments
            fi
        }    

        td_bootstrap() {
            __init_bootstrap
            __source_corelibs
            __source_globals

            FLAG_INIT_CONFIG=0;
            __parse_bootstrap_args "$@"

            # If you want ui, init after libs (unless ui_init is dependency-free)
            (( exe_ui )) && ui_init

            # Root checks (after libs so need_root exists)
            if (( exe_root == 1 )); then
                need_root "${TD_BOOTSTRAP_REST[@]}"
            fi
            if (( exe_root == 2 )); then
                cannot_root "${TD_BOOTSTRAP_REST[@]}"
            fi

            # Load state/cfg and parse *script* args (not bootstrap args)
             TD_STATE_FILE="${TD_STATE_FILE:-"$TD_STATE_DIR/$TD_SCRIPT_NAME.state"}" # State file path
             TD_SYSCFG_FILE="${TD_SYSCFG_FILE:-"$TD_SYSCFG_DIR/$TD_SCRIPT_NAME.cfg"}" # Config file path
             TD_USRCFG_FILE="${TD_USRCFG_FILE:-"$TD_USRCFG_DIR/$TD_SCRIPT_NAME.cfg"}" # Config file path

            (( exe_state )) && td_state_load
            (( exe_cfg ))   && td_cfg_load

            td_parse_args "${TD_BOOTSTRAP_REST[@]}"

            __finalize_bootstrap

            return 0
        }



         
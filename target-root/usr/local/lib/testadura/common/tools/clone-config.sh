#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — clone-config.sh
# ------------------------------------------------------------------------------
# Purpose : Menu application for cloned VM configuration management
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design:
#   - Executable scripts are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (templating, not inheritance).
#   - Args parsing and config loading are opt-in by defining ARGS_SPEC and/or CFG_*.
# ==============================================================================

set -euo pipefail

# --- Script metadata ----------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_VERSION_STATUS="beta"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Framework roots (explicit) ----------------------------------------------
    # Override from environment if desired:
    # Directory where Testadura framework is installed
    TD_FRAMEWORK_ROOT="${TD_FRAMEWORK_ROOT:-/}"
    # Application root (where this script is deployed)
    TD_APPLICATION_ROOT="${TD_APPLICATION_ROOT:-/}"
    # Common libraries path
    TD_COMMON_LIB="${TD_COMMON_LIB:-$TD_FRAMEWORK_ROOT/usr/local/lib/testadura/common}"
    # State and config files
    TD_STATE_FILE="${TD_STATE_FILE:-"$TD_APPLICATION_ROOT/var/testadura/$TD_SCRIPT_NAME.state"}"
    TD_CFG_FILE="${TD_CFG_FILE:-"$TD_APPLICATION_ROOT/etc/testadura/$TD_SCRIPT_NAME.cfg"}"
    # User home directory
    TD_USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"

# --- Minimal fallback UI (overridden by ui.sh when sourced) -------------------
    saystart()   { printf '[STRT] %s\n' "$*" >&2; }
    saywarning() { printf '[WARN] %s\n' "$*" >&2; }
    sayfail()    { printf '[FAIL] %s\n' "$*" >&2; }
    saycancel()  { printf '[CNCL] %s\n' "$*" >&2; }
    sayend()     { printf '[END ] %s\n' "$*" >&2; }
    sayok()      { printf '[OK  ] %s\n' "$*" >&2; }
    sayinfo()    { printf '[INFO] %s\n' "$*" >&2; }

# --- Using / imports ----------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    "core.sh"   # td_die/td_warn/td_info, need_root, etc. (you decide contents)
    "args.sh"   # td_parse_args, td_show_help
    "default-colors.sh" # color definitions for terminal output
    "default-styles.sh" # text styles for terminal output
    "ui.sh"     # user inetractive helpers
    "cfg.sh"    # td_cfg_load, config discovery + source, td_state_set/load
    )

    td_source_libs() {
        local lib path
        saystart "Sourcing libraries from: $TD_COMMON_LIB" >&2

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
                sayfail "Required library not found: $path" >&2
                td_die "Cannot continue without core library."
            fi

            saywarning "Library not found (optional): $path" >&2``
        done

        sayend "All libraries sourced." >&2
    }


# --- Example: Arguments -------------------------------------------------------
    # Each entry:
    #   "name|short|type|var|help|choices"
    #
    #   name    = long option name WITHOUT leading --
    #   short   - short option name WITHOUT leading -
    #   type    = flag | value | enum
    #   var     = shell variable that will be set
    #   help    = help string for auto-generated --help output
    #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
    #             for flag/value: leave empty
    #
    # Notes:
    #   - -h / --help is built in, you don't need to define it here.
    #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    # ------------------------------------------------------------------------
    TD_ARGS_SPEC=(
        "dryrun|d|flag|FLAG_DRYRUN|Just list the files don't do any work|"
        "verbose|v|flag|FLAG_VERBOSE|Verbose output, show arguments|"
    )

    TD_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $TD_SCRIPT_NAME --dryrun"
        "  $TD_SCRIPT_NAME -d"
        ""
        "Show arguments:"
        "  $TD_SCRIPT_NAME --verbose"
        "  $TD_SCRIPT_NAME -v"
    ) 


# --- local script functions -------------------------------------------------
__showmenu() {
    _barcolor="${CLI_BORDER}"
    _titelecolor="${CLI_TEXT}"
    _itemcolor="${CLI_TEXT}"

    _verb=$([ "${FLAG_VERBOSE:-0}" -eq 1 ] && echo "${BOLD_SILVER}ON${RESET}" || echo "${FAINT_SILVER}OFF${RESET}")
    _dry=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_GREEN}ON${RESET}" || echo "${BOLD_ORANGE}OFF${RESET}")

    cat << EOF
${_barcolor}==================================================
${_titelecolor}   Clone Configuration Menu
${_barcolor}==================================================
${_itemcolor}    1) Setup Machine ID
    2) Configure Hostname and Network   
    3) Enable SSH and set authorized keys
    4) Join Domain (optional)
    5) Prepare template for next clone
    6) Toggle Verbose mode ($_verb)
    7) Toggle Dry-Run mode ($_dry)
    8) Exit
${_barcolor}==================================================${RESET}
EOF
}

__setup_machine_id() {
    saystart "Setting up Machine ID..."
    
    # 1) machine-id
    if [[ ! -s /etc/machine-id || "$(cat /etc/machine-id)" == "00000000000000000000000000000000" ]]; then
        if [[ FLAG_DRYRUN -eq 1 ]]; then
            saydebug "Would have generated a machine-id"
        fi
        if [[ FLAG_VERBOSE -eq 1 ]]; then
          saydebug "Generating machine-id"
        fi
        truncate -s 0 /etc/machine-id
        systemd-machine-id-setup
    fi

    # keep D-Bus in sync
    if [[ -e /var/lib/dbus/machine-id ]]; then
        if [[ FLAG_DRYRUN -eq 1 ]]; then
            saydebug "Would have linked D-Bus machine-id"
        fi
        if [[ FLAG_VERBOSE -eq 1 ]]; then
          saydebug "Linking D-Bus machine-id"
        fi
        ln -sf /etc/machine-id /var/lib/dbus/machine-id
    fi

    local id
    id=$(cat /etc/machine-id)
    sayend "Machine ID setup complete. (ID: $id)"
}

__enable_shh(){
    saystart "Enabling SSH and setting authorized keys..."

    if [[ FLAG_DRYRUN -eq 1 ]]; then
        saydebug "Would have generated SSH host keys"
    else
        if [[ FLAG_VERBOSE -eq 1 ]]; then
            saydebug "Generating SSH host keys"
        fi

        # Generate any missing keys
        ssh-keygen -A
    fi

    if [[ FLAG_DRYRUN -eq 1 ]]; then
        saydebug "Would have unmasked and enabled SSH service"
    else
        if [[ FLAG_VERBOSE -eq 1 ]]; then
            saydebug "Unmasking and enabling SSH service"
        fi

        # Make sure the service isn't masked and is enabled for future boots
        systemctl unmask ssh 2>/dev/null || true
        systemctl enable ssh 2>/dev/null || true
    fi

    if [[ FLAG_DRYRUN -eq 1 ]]; then
        saydebug "Would have restarted SSH service"
    else
        if [[ FLAG_VERBOSE -eq 1 ]]; then
            saydebug "Restarting SSH service"
        fi

        # Start (or restart) sshd now; it will listen as soon as NICs are up
        systemctl restart ssh || systemctl start ssh || true
    fi

    sayend "SSH enabled and authorized keys set."
}

__save_settings(){
    td_state_set "HOST" "$HOST"
    td_state_set "USE_DHCP" "$USE_DHCP"
    td_state_set "IP" "$IP"
    td_state_set "CIDR" "$CIDR"
    td_state_set "GW" "$GW"
    td_state_set "DNS" "$DNS"
    td_state_set "NIC" "$NIC"
    td_state_set "NETPLAN_FILE" "$NETPLAN_FILE"
}
__collect_settings(){
    saystart "Collecting settings for Hostname and Network configuration..."
    printf '\n'
    # Configuration variables
    RENDERER="networkd"

    # Defaults (only if not already loaded)
    : "${HOST:=td-clone}"
    : "${USE_DHCP:=1}"
    : "${IP:=192.168.0.98}"
    : "${CIDR:=24}"
    : "${GW:=192.168.0.1}"
    : "${DNS:=192.168.0.1,1.1.1.1}"
    : "${NETPLAN_FILE:=/etc/netplan/10-netplan.yaml}"

    # NIC detection (only if not already loaded)
    if [[ -z "${NIC:-}" ]]; then
        NIC="$(get_primary_nic)"
        if [[ -z "$NIC" ]]; then
            saywarn "No primary NIC detected, falling back to eth0"
            NIC="eth0"
        fi
    fi

    # ---- prompts ----
    while true; do
        printf "${CLI_BORDER}==================================================\n"
        printf "${CLI_TEXT}   Host & IPv4 setup\n"
        printf "${CLI_BORDER}==================================================\n"
        
        ask --label "Hostname" --var HOST --default "$HOST" --colorize both
        SHORT="${HOST%%.*}"
        ask --label "Network interface" --var NIC --default "$NIC" --colorize both  
        ask --label "Netplan filename" --var NETPLAN_FILE --default "$NETPLAN_FILE" --colorize=both
        ask --label "Use DHCP for IPv4?" --var USE_DHCP --default "$USE_DHCP" --colorize=both
       
        if ! $USE_DHCP; then
            ask --label "Static IPv4" --var IP --default "$IP" --colorize=both --validate_fn=validate_ip
            ask --label "CIDR prefix (e.g. 24)" --var CIDR --default "$CIDR" --colorize=both --validate_fn=validate_cidr 
            ask --label "Gateway IPv4" --var GW --default "$GW" --colorize=both --validate_fn=validate_ip
            ask --label "Extra routes (CIDR:via, comma-separated; blank = none)" --var ROUTES --default "" --colorize=both
            ask --label "DNS servers (comma-separated)" --var DNS --default "$DNS" --colorize=both
        fi
        printf "${CLI_BORDER}==================================================\n"

        if ask_yesno "Ok to apply?"; then
            break
        fi
    done

    __save_settings

    sayend "Settings collection complete."
}
__set_hostname(){
    # ---- set hostname (short only) ----
    say "Setting hostname (short): $SHORT"
    hostnamectl set-hostname "$SHORT"

    # ---- rebuild /etc/hosts atomically ----
    tmp_hosts="$(mktemp)"
    {
    echo "127.0.0.1 localhost"
    echo "127.0.1.1 ${SHORT} ${SHORT}"
    if [[ ${USE_DHCP:-0} == 0 && -n "${IP:-}" ]]; then
        echo "${IP} ${SHORT}"
    fi
    } >"$tmp_hosts"
    install -m 0644 "$tmp_hosts" /etc/hosts

    say "Hosts updated:"
    cat "$tmp_hosts" | sed 's/^/  /'

    rm -f "$tmp_hosts"
}

__configure_network_settings(){
    saystart "Configuring Network Settings"

   __collect_settings

    sayend "Hostname and Network configuration complete."
}

# --- main() must be the last function in the script -------------------------
    __td_showarguments() {
        printf "File                : %s\n" "$TD_SCRIPT_FILE"
        printf "Script              : %s\n" "$TD_SCRIPT_NAME"
        printf "Script description  : %s\n" "$TD_SCRIPT_DESC"
        printf "Script dir          : %s\n" "$TD_SCRIPT_DIR"
        printf "Script version      : %s (build %s)\n" "$TD_SCRIPT_VERSION" "$TD_SCRIPT_BUILD"
        printf "TD_APPLICATION_ROOT : %s\n" "${TD_APPLICATION_ROOT:-<none>}"
        printf "TD_FRAMEWORK_ROOT   : %s\n" "${TD_FRAMEWORK_ROOT:-<none>}"
        printf "TD_COMMON_LIB       : %s\n" "${TD_COMMON_LIB:-<none>}"

        printf "TD_STATE_FILE       : %s\n" "${TD_STATE_FILE:-<none>}"
        printf "TD_CFG_FILE         : %s\n" "${TD_CFG_FILE:-<none>}"

        printf -- "Arguments / Flags:\n"

        local entry varname
        for entry in "${TD_ARGS_SPEC[@]:-}"; do
            IFS='|' read -r name short type var help choices <<< "$entry"
            varname="${var}"
            printf "  --%s (-%s) : %s = %s\n" "$name" "$short" "$varname" "${!varname:-<unset>}"
        done

        printf -- "Positional args:\n"
        for arg in "${TD_POSITIONAL[@]:-}"; do
            printf "  %s\n" "$arg"
        done
    }

    main() {
        # --- Source libraries ------------------c------------------------------------
        td_source_libs
        
        # --- Ensure sudo or non-sudo as desired ---------------------------
            need_root "$@"
            #cannot_root "$@"

        # --- Load previous state and config
            # enable if desired:
            td_state_load
            #td_cfg_load

        # --- Parse arguments
            td_parse_args "$@"
            FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   

            if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
                __td_showarguments
            fi
        
        # --- Main script logic ---------------------------------------------------
        wait_after=0
        while true; do
            clear
            __showmenu

            read -rp "${BOLD_SILVER}Select an option [1-8]: ${BOLD_YELLOW}" choice

            printf "\n"

            case $choice in
                1)
                    wait_after=8
                    __setup_machine_id  
                    ;;
                2)
                    wait_after=5
                   __configure_network_settings
                    ;;
                3)
                    wait_after=5
                    __enable_shh
                    ;;
                4)
                    wait_after=10
                    sayinfo "Joining Domain..."
                    # Placeholder for actual implementation
                    ;;
                5)
                    wait_after=10
                    sayinfo "Preparing template for next clone..."
                    # Placeholder for actual implementation
                    ;;
                6)
                    wait_after=0.5
                    if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
                        FLAG_VERBOSE=0
                        sayinfo "Verbose mode disabled."
                    else
                        FLAG_VERBOSE=1
                        sayinfo "Verbose mode enabled."
                    fi
                    ;;
                7)
                    wait_after=0.5
                    if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                        FLAG_DRYRUN=0
                        saywarning "Dry-Run mode disabled."
                    else
                        FLAG_DRYRUN=1
                        sayinfo "Dry-Run mode enabled."
                    fi
                    ;;
                8)
                    sayinfo "Exiting..."
                    break
                    ;;
                *)
                    saywarning "Invalid option. Please select a valid option."
                    ;;
            esac
            if [[ $wait_after > 1 ]]; then
                ask_autocontinue $wait_after 
            else
                sleep $wait_after
            fi
        done
    }

    # Run main with positional args only (not the options)
    main "$@"

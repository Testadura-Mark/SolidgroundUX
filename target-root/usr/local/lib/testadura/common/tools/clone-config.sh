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

# --- Script metadata -------------------------------------------------------------
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

# --- Framework roots (explicit) --------------------------------------------------
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

# --- Minimal fallback UI (overridden by ui.sh when sourced) ----------------------
    saystart()   { printf '[STRT] %s\n' "$*" >&2; }
    saywarning() { printf '[WARN] %s\n' "$*" >&2; }
    sayfail()    { printf '[FAIL] %s\n' "$*" >&2; }
    saycancel()  { printf '[CNCL] %s\n' "$*" >&2; }
    sayend()     { printf '[END ] %s\n' "$*" >&2; }
    sayok()      { printf '[OK  ] %s\n' "$*" >&2; }
    sayinfo()    { printf '[INFO] %s\n' "$*" >&2; }

# --- Using / imports -------------------------------------------------------------
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

# --- Argument specification and processing ---------------------------------------
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
        "statereset|r|flag|FLAG_STATERESET|Reset the state file|"
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

    __set_runmodes(){
        RUN_MODE=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_ORANGE}DRYRUN${RESET}" || echo "${BOLD_GREEN}COMMIT${RESET}")

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            sayinfo "Running in Dry-Run mode (no changes will be made)."
        else
            saywarning "Running in Normal mode (changes will be applied)."
        fi

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi

        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi
    }

# --- local script functions ------------------------------------------------------
    __menuline() { printf "%b\n" "$*"; }
    __show_mainmenu() {
        _barcolor="${CLI_BORDER}"
        _titlecolor="${CLI_HIGHLIGHT}"
        _itemcolor="${CLI_TEXT}"

        _verb=$([ "${FLAG_VERBOSE:-0}" -eq 1 ] && echo "${BOLD_YELLOW}ON${RESET}" || echo "${BOLD_YELLOW}OFF${RESET}")
        _dry=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${BOLD_YELLOW}ON${RESET}" || echo "${BOLD_YELLOW}OFF${RESET}")

        __menuline "${_barcolor}====================================================="
        __menuline "${_titlecolor}   Clone Configuration Menu                    ${RUN_MODE}"
        __menuline "${_barcolor}====================================================="
        __menuline "${_titlecolor}    --- Basic configuration tasks ---${_itemcolor}"
        __menuline "    1) Setup Machine ID"
        __menuline "    2) Configure Hostname and Network"
        __menuline "    3) Enable SSH and set authorized keys"
        __menuline ""
        __menuline "${_titlecolor}     --- Additional tasks ---${_itemcolor}"
        __menuline "    4) Join Domain (optional)"
        __menuline "    5) Prepare template for next clone"
        __menuline ""
        __menuline "${_titlecolor}    --- Modes ---${_itemcolor}"
        __menuline "    6) Toggle Verbose mode ($_verb)"
        __menuline "    7) Toggle Dry-Run mode ($_dry)"
        __menuline ""
        __menuline "    8) Exit"
        __menuline "${_barcolor}===================================================${RESET}"
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

    # --- Menu actions ------------------------------------------------------------
        # 1) Setup Machine ID
        __setup_machine_id() {

            saydebug "Setting up Machine ID..."
            
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
        
        # 2) Configure Hostname and Network
        __configure_network(){
            saystart "Configuring Network Settings"

            __get_network_settings
            __set_hostname
            __create_netplan
            __apply_netplan

            sayend "Hostname and Network configuration complete."
        }

       # 3) Enable SSH and set authorized keys
        __enable_shh(){
            saydebug "Enabling SSH and setting authorized keys..."

            if [[ FLAG_DRYRUN -eq 1 ]]; then
                sayinfo "Would have generated SSH host keys"
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

            sayok "SSH enabled and authorized keys set."
        }
       
       # 4) Join Domain (optional)
        __join_domain(){
            saystart "Joining domain"

            __get_domain_settings
            __install_samba_client
            __write_smbconf
            __finalize_domain_join

            sayend "Joined to ${DOMAIN}"
        }
      # 5) Prepare template for next clone
        __prepare_template(){
            saystart "Preparing template for next clone"

            __get_clone_defaults

            # Clear machine-id
            #__clear_machine_id

            # Remove SSH host keys
            #__remove_ssh_host_keys

            # Clear temporary and transient directories
            #__clear_temp_and_caches

            # Clear DHCP leases
            #__clear_dhcp_leases

            # Trim logs
            #__trim_logs

            # Ensure first-boot service is present and enabled
            #__enable_firstboot_service

            sayend "Template preparation complete."
        }
    # --- Network config ----------------------------------------------------------
        __get_network_settings(){
            saystart "Collecting settings for Hostname and Network configuration..."
            printf '\n'
            # Configuration variables
            RENDERER="networkd"

            # Defaults (only if not already loaded)
            : "${HOST:=td-clone}"
            : "${USE_DHCP:=Yes}"
            : "${IP:=192.168.0.98}"
            : "${CIDR:=24}"
            : "${GW:=192.168.0.1}"
            : "${DNS:=192.168.0.1,1.1.1.1}"
            : "${NETPLAN_FILE:=/etc/netplan/10-netplan.yaml}"

            # NIC detection (only if not already loaded)
            if [[ -z "${NIC:-}" ]]; then
                NIC="$(get_primary_nic)"
                if [[ -z "$NIC" ]]; then
                    saywarning "No primary NIC detected, falling back to eth0"
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
            
                if ! is_true "$USE_DHCP"; then
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
            if [[ "${FLAG_DRYRUN:-0}" -eq 0 ]]; then
                saydebug "Setting hostname (short): $SHORT"
                hostnamectl set-hostname "$SHORT"
            else
                sayinfo "Would have set hostname to : $SHORT"
            fi

            if [[ "${FLAG_DRYRUN:-0}" -eq 0 ]]; then
                saydebug "Rebuilding /etc/hosts"
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

                sayok "Hosts updated:"
                cat "$tmp_hosts" | sed 's/^/  /'

                rm -f "$tmp_hosts"
            else
                sayinfo "Would have updated /etc/hosts"
            fi
        }

        __author_netplan(){
            echo "# Generated by clone-config.sh"
            echo "network:"
            echo "  version: 2"
            echo "  renderer: $RENDERER"
            echo "  ethernets:"
            echo "    $NIC:"
            if is_true $USE_DHCP; then
                echo "      dhcp4: true"
            else
                echo "      dhcp4: false"
                
                echo "      addresses:"
                echo "        - $IP/$CIDR"

                if [[ -n "${GW:-}" || -n "${ROUTES:-}" || -n "${DNS:-}" ]]; then
                echo "      routes:"
                if [[ -n "${GW:-}" ]]; then
                    echo "        - to: 0.0.0.0/0"
                    echo "          via: $GW"
                fi
                if [[ -n "${ROUTES:-}" ]]; then
                    IFS=',' read -r -a arr <<<"$ROUTES"
                    for r in "${arr[@]}"; do
                    r="$(echo "$r" | xargs)"; [[ -z "$r" ]] && continue
                    dest="${r%%:*}"; via="${r#*:}"
                    [[ "$dest" == */* ]] && validate_ip "$via" || { say "Skip bad route: $r"; continue; }
                    echo "        - to: $dest"
                    echo "          via: $via"
                    done
                fi
                fi
                if [[ -n "${DNS:-}" ]]; then
                echo "      nameservers:"
                echo "        addresses:"
                IFS=',' read -r -a dnsarr <<<"$DNS"
                for d in "${dnsarr[@]}"; do
                    d="$(echo "$d" | tr -d '\r' | xargs)"
                    validate_ip "$d" || { say "Skip invalid DNS: $d"; continue; }
                    # Print the literal value (no shell interpolation into YAML)
                    printf '          - "%s"\n' "$d"
                done
                fi
            fi
        }
        __create_netplan(){
            saystart "Writing $NETPLAN_FILE"
            mkdir -p /etc/netplan

            if is_true "$FLAG_DRYRUN"; then
                NETPLAN_PREVIEW="$(__author_netplan)"
                sayinfo "Netplan config would be:"
                echo
                echo "$NETPLAN_PREVIEW"
            else
                __author_netplan > "$NETPLAN_FILE"
                sayok "Netplan written to $NETPLAN_FILE"
            fi
            if ! is_true "$FLAG_DRYRUN"; then
                saydebug "Setting access"
                chmod 0600 "$NETPLAN_FILE"
                cat "$NETPLAN_FILE" | sed 's/^/  /'

                # Disable all existing netplans (except the one we're about to write)
                saydebug "Disabling other netplan configs"
                for f in /etc/netplan/*.yaml; do
                if [ "$f" != "$NETPLAN_FILE" ]; then
                    mv "$f" "${f}.disabled"
                fi
                done
            else
                sayinfo "Would have set access to netplan and disabled others"
            fi
        }
        __apply_netplan(){
            if ! is_true "$FLAG_DRYRUN"; then
                if ask_yesno "Apply netplan now?"; then
                    have netplan || { sayfail "netplan not found (install netplan.io)"; exit 1; }
                    saywarning "Applying netplan (brief disruption possible)"
                    netplan generate
                    netplan apply
                    sayinfo "IPv4 on $NIC:"; ip -4 addr show "$NIC" | sed 's/^/  /'
                    sayinfo "Default route:"; ip route show default | sed 's/^/  /'
                else
                    saywarning "Skipped apply. Later: sudo netplan generate && sudo netplan apply"
                fi
            else
                sayinfo "Would have applied newly created netplan"
            fi
        }

    # --- Domain join -------------------------------------------------------------
        __get_domain_settings(){
            saydebug "Collecting settings for Domain Join..."
            printf '\n' 

            # Defaults (only if not already loaded)
            : "${DOMAIN:=example.com}"
            : "${ADM_USR:=administrator}"

            # ---- prompts ----
            while true; do
                printf "${CLI_BORDER}==================================================\n"
                printf "${CLI_TEXT}   Join domain                              ${RUN_MODE}\n"                        
                printf "${CLI_BORDER}==================================================\n"

                ask --label "Hostname" --var HOST --default "$HOST" --colorize both 
                ask --label "Domain" --var DOMAIN --default "$DOMAIN" --colorize both
                ask --label "Authorized user" --var ADM_USR --default "$ADM_USR" --colorize both
                
                # Normalize to lowercase (for smb.conf)
                DOMAIN_LC="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
                # Derive realm in uppercase (for Kerberos)
                REALM_UC="$(printf '%s' "$DOMAIN_LC" | tr '[:lower:]' '[:upper:]')"
                WORKGROUP="${REALM_UC%%.*}"   # keep only first label; remove this line if you want EXAMPLE.COM


                # Show derived values (don’t let user overwrite them unless you truly want that)
                printf "%sDerived domain   : %s\n" "${CLI_ITALIC}" "${DOMAIN_LC:-<none>}"
                printf "%sKerberos realm   : %s\n" "${CLI_ITALIC}" "${REALM_UC:-<none>}"                      
                printf "${CLI_BORDER}==================================================\n"

                decision=0
                ask_ok_redo_quit "Continue with domain join?" || decision=$?
                
                saydebug "Decision: ${decision}"

                case "$decision" in
                        0)  saydebug "Proceding"
                            break ;;
                        1)  saydebug "Redo" 
                            continue ;;
                        2)  saycancel "Cancelled as per user request"
                            exit 1 ;;
                        *)  sayfail "Unexpected response: $decision" 
                            exit 2 ;;
                esac
            done
            __save_domain_settings
        }
        __save_domain_settings(){
            td_state_set "DOMAIN" "$DOMAIN"
            td_state_set "ADM_USR" "$ADM_USR"
        }

        __write_smbconf(){
            saydebug "Writing smb.conf for domain join..."
            if [ "${FLAG_DRYRUN:-0}" -eq 1 ]; then
                sayinfo "Would have written /etc/samba/smb.conf as:"
                TARGET="/dev/stdout"
            else
                TARGET="/etc/samba/smb.conf"
            fi
            {
                printf "%s\n" "[global]"
                printf "%s\n" "   workgroup = ${WORKGROUP:-${REALM_UC%%.*}}"
                printf "%s\n" "   realm = ${REALM_UC}"
                printf "%s\n" "   security = ADS"
                printf "%s\n" "   server role = member server"
                printf "%s\n" ""
                printf "%s\n" "   dedicated keytab file = /etc/krb5.keytab"
                printf "%s\n" "   kerberos method = secrets and keytab"
                printf "%s\n" "   allow dns updates = secure only"
                printf "%s\n" ""
                printf "%s\n" "   # Pre-join: single idmap so winbind can start"
                printf "%s\n" "   idmap config * : backend = tdb"
                printf "%s\n" "   idmap config * : range   = 10000-999999"
                printf "%s\n" ""
                printf "%s\n" "   winbind use default domain = yes"
                printf "%s\n" "   winbind nss info = rfc2307"
                printf "%s\n" "   winbind offline logon = yes"
                printf "%s\n" ""
                printf "%s\n" "   vfs objects = acl_xattr"
                printf "%s\n" "   map acl inherit = yes"
                printf "%s\n" "   store dos attributes = yes"
                printf "%s\n" "   ea support = yes"
                printf "%s\n" "   template shell = /bin/bash"
            } > "$TARGET"
            sayok "smb.conf written to $TARGET"
        }

        __install_samba_client(){
            if is_true "$FLAG_DRYRUN"; then
                sayinfo "Would have installed Samba AD client stack"
            else
                saydebug "Installing Samba AD client stack"
                apt update -y
                apt install -y samba winbind libnss-winbind libpam-winbind libwbclient0 dnsutils acl attr krb5-user
                sayok "Samba AD client stack installed"
            fi
        }

        __finalize_domain_join(){
            # -- NSS update
                if is_true "$FLAG_DRYRUN"; then
                    sayinfo "Would have updated NSS for domain users"
                else
                    saydebug "Updating NSS for domain users"

                    # Safer: ensure winbind is present on passwd/group lines (append if missing)
                    if grep -qE '^[[:space:]]*passwd:.*\bwinbind\b' /etc/nsswitch.conf; then
                        saydebug "nsswitch.conf passwd line already includes winbind"
                    else
                        sed -i -E 's/^([[:space:]]*passwd:[[:space:]]*.*)$/\1 winbind/' /etc/nsswitch.conf
                    fi

                    if grep -qE '^[[:space:]]*group:.*\bwinbind\b' /etc/nsswitch.conf; then
                        saydebug "nsswitch.conf group line already includes winbind"
                    else
                        sed -i -E 's/^([[:space:]]*group:[[:space:]]*.*)$/\1 winbind/' /etc/nsswitch.conf
                    fi

                    sayok "NSS updated for domain users"
                fi
            # -- Restart Samba and join domain
                if is_true "$FLAG_DRYRUN"; then
                    sayinfo "Would have restarted Samba services"
                else
                    saydebug "Restarting Samba services"
                    systemctl restart smbd nmbd winbind
                    sayok "Samba services restarted"
                fi

                if is_true "$FLAG_DRYRUN"; then
                    sayinfo "Would have joined domain ${DOMAIN} as user ${ADM_USR}"
                else
                    saydebug "Joining domain ${DOMAIN} as user ${ADM_USR_NORM}"
                    kinit "${ADM_USR_NORM}@${REALM_UC}" || { sayfail "kinit failed"; return 1; }
                    net ads join -U "${ADM_USR_NORM}"    || { sayfail "net ads join failed"; return 1; }
                    net ads testjoin                     || { sayfail "net ads testjoin failed"; return 1; }
                    sayok "Joined domain ${DOMAIN} as user ${ADM_USR_NORM}"
                fi
            # -- Switch to RID idmap mapping
                if is_true "$FLAG_DRYRUN"; then
                    sayinfo "Would have switched to RID idmap mapping"
                else
                    saydebug "Switching to RID idmap mapping"

                    [ -n "$WORKGROUP" ] || { sayfail "WORKGROUP is empty"; return 1; }

                    # If it's already RID, skip
                    if grep -qE "^[[:space:]]*idmap config[[:space:]]+$WORKGROUP[[:space:]]*:[[:space:]]*backend[[:space:]]*=[[:space:]]*rid" /etc/samba/smb.conf; then
                        sayinfo "RID idmap already configured for $WORKGROUP (skipping)"
                        return 0
                    fi

                    tmp="$(mktemp /tmp/smb.conf.XXXXXX)" || { sayfail "mktemp failed"; return 1; }

                    # preserve perms/owner from existing file
                    chmod --reference=/etc/samba/smb.conf "$tmp" 2>/dev/null || true
                    chown --reference=/etc/samba/smb.conf "$tmp" 2>/dev/null || true

                    awk -v WG="$WORKGROUP" '
                        { print }
                        /kerberos method/ && !x {
                            x=1
                            print ""
                            print "   idmap config *          : backend = tdb"
                            print "   idmap config *          : range   = 10000-19999"
                            print "   idmap config " WG "          : backend = rid"
                            print "   idmap config " WG "          : range   = 20000-999999"
                        }
                    ' /etc/samba/smb.conf > "$tmp" && mv "$tmp" /etc/samba/smb.conf || {
                        rc=$?
                        rm -f "$tmp"
                        sayfail "Failed to update smb.conf (rc=$rc)"
                        return "$rc"
                    }

                    sayok "Switched to RID idmap mapping"
                fi
            # -- Restart services and verify
            if is_true "$FLAG_DRYRUN"; then
                sayinfo "Would have restarted winbind and Samba services"
            else
                saydebug "Restarting winbind and Samba services"
                systemctl restart winbind smbd nmbd
                sayok "winbind and Samba services restarted"
            fi

            if wbinfo -p && getent passwd "${WORKGROUP}\\${ADM_USR}" >/dev/null; then
                sayok "Joined and domain users resolvable."
            else
                sayfail "Domain join verification failed"
            fi
        }



    # --- Prepare for next clone ---------------------------------------------------
        __get_clone_defaults(){
            : "${CLONE_NIC:=${NIC:-eth0}}"
            : "${CLONE_NETPLAN_FILE:=/etc/netplan/10-netplan-clone.yaml}"
            : "${CLONE_HOST:=${HOST:-td-ubuntu-template}}"
            : "${CLONE_IP:=${IP:-192.168.0.200}}"
            : "${CLONE_CIDR:=${CIDR:-24}}"
            : "${CLONE_GW:=${GW:-192.168.0.1}}"
            : "${CLONE_DNS:=${DNS:-192.168.0.1}}"


            while true; do
                printf "${CLI_BORDER}==================================================\n"
                printf "${CLI_TEXT}   Prepare template for next clone settings\n"
                printf "${CLI_BORDER}==================================================\n"

                ask --label "Hostname for template" --var CLONE_HOST --default "$CLONE_HOST" --colorize both 
                ask --label "Network interface for template" --var CLONE_NIC --default "$CLONE_NIC" --colorize both  
                ask --label "Static IPv4 for template" --var CLONE_IP --default "$CLONE_IP" --colorize=both --validate_fn=validate_ip
                ask --label "CIDR prefix for template (e.g. 24)" --var CLONE_CIDR --default "$CLONE_CIDR" --colorize=both --validate_fn=validate_cidr 
                ask --label "Gateway IPv4 for template" --var CLONE_GW --default "$CLONE_GW" --colorize=both --validate_fn=validate_ip
                ask --label "DNS servers for template (comma-separated)" --var CLONE_DNS --default "$CLONE_DNS" --colorize=both 
                ask --label "Netplan filename for template" --var CLONE_NETPLAN_FILE --default "$CLONE_NETPLAN_FILE" --colorize=both

                printf "${CLI_BORDER}==================================================\n"

                ask_autocontinue 15 
                rc=$?
                printf "shoudlve printed something"
                printf "Decision: %d\n" "$rc"
                case "$rc" in
                    0)  saydebug "Proceding"
                        break ;;
                    1)  saydebug "Redo" 
                        continue ;;
                    2)  saycancel "Cancelled as per user request"
                        exit 1 ;;
                    *)  sayfail "Unexpected response: $rc" 
                        exit 2 ;;
                esac
            done
            __save_clone_defaults

        }
        __save_clone_defaults(){
            td_state_set "CLONE_NIC" "$CLONE_NIC"
            td_state_set "CLONE_HOST" "$CLONE_HOST"
            td_state_set "CLONE_IP" "$CLONE_IP"
            td_state_set "CLONE_CIDR" "$CLONE_CIDR"
            td_state_set "CLONE_GW" "$CLONE_GW"
            td_state_set "CLONE_DNS" "$CLONE_DNS"
            td_state_set "CLONE_NETPLAN_FILE" "$CLONE_NETPLAN_FILE"
        }

        __clear_machine_id(){
            saydebug "Clearing machine-id..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared /etc/machine-id"
            else
                truncate -s 0 /etc/machine-id
                sayok "/etc/machine-id cleared"
            fi
        }

        __remove_ssh_host_keys(){
            saydebug "Removing SSH host keys..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have removed SSH host keys in /etc/ssh/"
            else
                rm -f /etc/ssh/ssh_host_*
                sayok "SSH host keys removed"
            fi
        }

        __clear_temp_and_caches(){
            saydebug "Clearing temporary files and caches..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared /tmp and /var/tmp"
            else
                rm -rf /tmp/* /var/tmp/*
                sayok "Temporary files and caches cleared"
            fi
        }

        __clear_dhcp_leases(){
            saydebug "Clearing DHCP leases..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared DHCP leases in /var/lib/dhcp/"
            else
                rm -f /var/lib/dhcp/dhclient*.leases
                sayok "DHCP leases cleared"
            fi
        }

        __trim_logs(){
            saydebug "Trimming log files..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have trimmed log files in /var/log/"
            else
                find /var/log -type f -exec truncate -s 0 {} \;
                sayok "Log files trimmed"
            fi
        }

        __cleanup_netplans(){
            saydebug "Cleaning up netplan configurations..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have removed existing netplan configurations except the active one"
            else
                for f in /etc/netplan/*.yaml; do
                    if [ "$f" != "$NETPLAN_FILE" ]; then
                        rm -f "$f"
                    fi
                done
                sayok "Netplan configurations cleaned up"
            fi
        }

        __create_netplan(){
            saydebug "Creating minimal netplan configuration..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                NETPLAN_PREVIEW="$(__minimal_netplan)"
                sayinfo "Netplan config would be:"
                echo
                echo "$NETPLAN_PREVIEW"
            else
                __minimal_netplan > "$CLONE_NETPLAN_FILE"
                chmod 0600 "$CLONE_NETPLAN_FILE"
                sayok "Minimal netplan written to $CLONE_NETPLAN_FILE"
            fi
        }
        __enable_firstboot_service(){
            saydebug "Enabling first-boot service..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have ensured first-boot service is enabled"
            else
                # Placeholder: Implement enabling first-boot service as needed
                sayok "First-boot service enabled (placeholder)"
            fi
        }

        __minimal_netplan(){
            echo "# Minimal netplan generated by clone-config.sh"
            echo "network:"
            echo "  version: 2"
            echo "  renderer: networkd"
            echo "  ethernets:"
            echo "    $CLONE_NIC:"
            echo "      dhcp4: no"
            echo "      addresses:"
            echo "        - {$CLONE_IP}/$CLONE_CIDR"
            echo "      routes:"
            echo "        - to: default"
            echo "          via: $CLONE_GW"
            echo "      nameservers:"
            echo "        addresses:"
            echo "          - $CLONE_DNS"
        }

# === main() must be the last function in the script ==============================
    main() {
        # --- Bootstrap -----------------------------------------------------------
            # -- Source libraries
                td_source_libs
            
            # -- Ensure sudo or non-sudo as desired 
                need_root "$@"
                #cannot_root "$@"

            # -- Load previous state and config
                # enable if desired:
                td_state_load
                #td_cfg_load

            # -- Parse arguments
                td_parse_args "$@"
                FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   
                FLAG_VERBOSE="${FLAG_VERBOSE:-0}"
                FLAG_STATERESET="${FLAG_STATERESET:-0}"
                __set_runmodes
            
        # --- Main script logic ---------------------------------------------------
            wait_after=0
            while true; do
                clear
                __show_mainmenu

                read -rp "${BOLD_SILVER}Select an option [1-8]: ${BOLD_YELLOW}" choice

                printf "\n"

                case $choice in
                    1)
                        wait_after=8
                        __setup_machine_id  
                        ;;
                    2)
                        wait_after=5
                        __configure_network
                        ;;
                    3)
                        wait_after=5
                        __enable_shh
                        ;;
                    4)
                        wait_after=10
                        __join_domain
                        ;;
                    5)
                        wait_after=10
                        __prepare_template
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
                        __set_runmodes
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
                        __set_runmodes
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

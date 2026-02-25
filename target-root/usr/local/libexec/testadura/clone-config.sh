#!/usr/bin/env bash
# ==============================================================================
# Testadura Consultancy — clone-config.sh
# ------------------------------------------------------------------------------
# Purpose    : Interactive menu for cloned VM configuration
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ------------------------------------------------------------------------------
# Description:
#   Interactive menu application used after cloning a VM to apply machine-specific
#   configuration (identity, network, SSH, domain join, etc.).
#
# Assumptions:
#   - Requires an interactive TTY
#   - Some actions may require root privileges
#
# Effects:
#   - May modify system configuration files and network settings
#   - May enable/disable services (e.g., SSH) depending on selected actions
#
# Design notes:
#   - Executables are explicit: set paths, import libs, then run.
#   - Libraries never auto-run (composition, not inheritance).
#   - Args parsing and config/state loading are opt-in via ARGS_SPEC and/or CFG_*.
# ==============================================================================

set -uo pipefail
# -- Find bootstrapper
    BOOTSTRAP="/usr/local/lib/testadura/common/td-bootstrap.sh"

    if [[ -r "$BOOTSTRAP" ]]; then
        # shellcheck disable=SC1091
        source "$BOOTSTRAP"
    else
        # Only prompt if interactive
        if [[ -t 0 ]]; then
            printf "\n"
            printf "Framework not installed in the default location."
            printf "Are you developing the framework or using a custom install path?\n\n"

            read -r -p "Enter framework root path (or leave empty to abort): " _root
            [[ -n "$_root" ]] || exit 127

            BOOTSTRAP="$_root/usr/local/lib/testadura/common/td-bootstrap.sh"
            if [[ ! -r "$BOOTSTRAP" ]]; then
                printf "FATAL: No td-bootstrap.sh found at provided location: $BOOTSTRAP"
                exit 127
            fi

            # Persist for next runs
            CFG="$HOME/.config/testadura/bootstrap.conf"
            mkdir -p "$(dirname "$CFG")"
            printf 'TD_FRAMEWORK_ROOT=%q\n' "$_root" > "$CFG"

            # shellcheck disable=SC1091
            source "$CFG"
            # shellcheck disable=SC1091
            source "$BOOTSTRAP"
        else
            printf "FATAL: Testadura framework not installed ($BOOTSTRAP missing)" >&2
            exit 127
        fi
    fi

# --- Script metadata -------------------------------------------------------------
    TD_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    TD_SCRIPT_DIR="$(cd -- "$(dirname -- "$TD_SCRIPT_FILE")" && pwd)"
    TD_SCRIPT_BASE="$(basename -- "$TD_SCRIPT_FILE")"
    TD_SCRIPT_NAME="${TD_SCRIPT_BASE%.sh}"
    TD_SCRIPT_TITLE="Clone configurator"
    TD_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    TD_SCRIPT_VERSION="1.0"
    TD_SCRIPT_BUILD="20250110"    
    TD_SCRIPT_DEVELOPERS="Mark Fieten"
    TD_SCRIPT_COMPANY="Testadura Consultancy"
    TD_SCRIPT_COPYRIGHT="© 2025 Mark Fieten — Testadura Consultancy"
    TD_SCRIPT_LICENSE="Testadura Non-Commercial License (TD-NC) v1.0"

# --- Using / imports -------------------------------------------------------------
    # Libraries to source from TD_COMMON_LIB
    TD_USING=(
    )

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

# --- local script functions ------------------------------------------------------
    __show_mainmenu() {
        local _barcolor="${TUI_BORDER}"
        local _titlecolor="$(td_color "$WHITE" "" "$FX_BOLD")"
        local _itemcolor="${TUI_TEXT}"
        local _pad=2
        local _tpad=$((_pad + 3))
        local _rcolor="$( (( FLAG_DRYRUN )) && printf '%s' "$TUI_DISABLED" || printf '%s' "$TUI_ENABLED" )"

        local _verb=$([ "${FLAG_VERBOSE:-0}" -eq 1 ] && echo "${TUI_ENABLED}ON${RESET}" || echo "${TUI_DISABLED}OFF${RESET}")
        local _dry=$([ "${FLAG_DRYRUN:-0}" -eq 1 ] && echo "${TUI_ENABLED}ON${RESET}" || echo "${TUI_DISABLED}OFF${RESET}")
    
        td_print_titlebar --text "Clone configuration menu" --textclr "$_titlecolor"

        td_print_sectionheader --text "Core setup" --padend 1 --padleft "$_pad" --prefix 2
        td_print --text "1) Setup Machine ID" --padleft "$_tpad" 
        td_print --text "2) Configure Hostname and Network" --padleft "$_tpad"
        td_print --text "3) Enable SSH and set authorized keys" --padleft "$_tpad"
        td_print

        td_print_sectionheader --text "Operations" --textclr "$_itemcolor" --padend 0 --padleft "$_pad"
        td_print --text "4) Download and Install SolidgroundUX" --padleft "$_tpad"
        td_print --text "5) Join Domain" --padleft "$_tpad"
        td_print_fill --left "6) Prepare template for next clone" --padleft "$_tpad"\
                      --right "State Altering" --rightclr "$_rcolor"
        td_print

        td_print_sectionheader --text "Server roles" --textclr "$_itemcolor" --padend 0 --padleft "$_pad"
        td_print --text "7) Provision Samba AD DC" --padleft "$_tpad"
        td_print --text "8) Provision Samba SMB Fileserver" --padleft "$_tpad"
        td_print

        td_print_sectionheader --text "Run modes" --textclr "$_itemcolor" --padend 0 --padleft "$_pad"
        td_print --text "V) Toggle Verbose mode ($_verb)" --padleft "$_tpad"
        td_print --text "D) Toggle Dry-Run mode ($_dry)" --padleft "$_tpad"
        td_print

        td_print --text "X) Exit" --padleft "$_tpad"
        td_print_sectionheader --borderclr $_barcolor
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
                if [[ ${FLAG_DRYRUN:-0} -eq 1 ]]; then
                    sayinfo "Would have generated a machine-id"
                else
                    saydebug "Generating machine-id"
                
                    truncate -s 0 /etc/machine-id
                    systemd-machine-id-setup
                fi
            fi

            # keep D-Bus in sync
            if [[ -e /var/lib/dbus/machine-id ]]; then
                if [[ ${FLAG_DRYRUN:-0} -eq 1 ]]; then
                    sayinfo "Would have linked D-Bus machine-id"
                else
                    saydebug "Linking D-Bus machine-id"
                    ln -sf /etc/machine-id /var/lib/dbus/machine-id
                fi
            fi

            local id
            id=$(cat /etc/machine-id)
            sayend "Machine ID setup complete. (ID: $id)"
        }
        
        # 2) Configure Hostname and Network
        __configure_network(){
            saystart "Configuring Network Settings"

            __get_network_settings
            __set_hostname --host "$HOST" --use-dhcp "$USE_DHCP" --ip "${IP:-}"
            __create_runtime_netplan
            __apply_netplan
            

            sayend "Hostname and Network configuration complete."
        }

       # 3) Enable SSH and set authorized keys
        __enable_ssh(){
            saydebug "Enabling SSH and setting authorized keys..."

            if [[ ${FLAG_DRYRUN:-0} -eq 1 ]]; then
                sayinfo "Would have generated SSH host keys"
            else
                if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                    saydebug "Generating SSH host keys"
                fi

                # Generate any missing keys
                ssh-keygen -A
            fi

            if [[ ${FLAG_DRYRUN:-0} -eq 1 ]]; then
                saydebug "Would have unmasked and enabled SSH service"
            else
                if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                    saydebug "Unmasking and enabling SSH service"
                fi

                # Make sure the service isn't masked and is enabled for future boots
                systemctl unmask ssh 2>/dev/null || true
                systemctl enable ssh 2>/dev/null || true
            fi

            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                saydebug "Would have restarted SSH service"
            else
                if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
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
        # --- __prepare_template ----------------------------------------------------------
            # Prepare the system to be used as a clone template.
            #
            # This function removes machine-specific identity and transient state so that
            # newly cloned machines will regenerate unique identifiers on first boot.
            #
            # Actions performed:
            #   - Collect and confirm template defaults (hostname, IP, netplan file, etc.)
            #   - Clear system machine-id
            #   - Remove SSH host keys
            #   - Clear temporary directories and caches
            #   - Remove DHCP lease state
            #   - Trim logs (journald + rotated logs)
            #   - Ensure first-boot service is enabled
            #
            # Notes:
            #   - Does NOT reboot or shut down the system
            #   - Intended to be run once, just before converting VM to template
            #   - Network identity is finalized via __create_tmpl_netplan (caller responsibility)
        __prepare_template(){
            saystart "Preparing template for next clone"

            __get_clone_defaults

            # Write a minimal netplan
            __create_tmpl_netplan

            # Write cleanup old netplans
            __cleanup_netplans

            # Set hostname
            __set_hostname --host "$CLONE_HOST" --use-dhcp "No" --ip "${CLONE_IP:-192.168.0.254}"

            # Clear machine-id
            __clear_machine_id

            # Remove SSH host keys
            __remove_ssh_host_keys

            # Clear DHCP leases
            __clear_dhcp_leases

            # Clear temporary and transient directories
            __clear_temp_and_caches

            # Clear leftovers
            __clear_leftovers
  
            # Trim logs
            __trim_logs

            # Ensure first-boot service is present and enabled
            __enable_firstboot_service

            sayend "Template preparation complete."
        }
    # --- Network config ----------------------------------------------------------
        # --- __get_network_settings ------------------------------------------------------
            # Collect interactive hostname + IPv4 settings and persist them to state.
            #
            # This function prompts the user for the machine's hostname and network settings,
            # validates inputs, and stores the resulting values for reuse.
            #
            # Collected values:
            #   - HOST           : hostname (short name derived as SHORT)
            #   - NIC            : primary network interface
            #   - NETPLAN_FILE   : target netplan YAML file to generate
            #   - USE_DHCP       : Yes/No toggle for IPv4 DHCP
            #   - If static IPv4:
            #       - IP, CIDR, GW, ROUTES (optional), DNS
            #
            # Persists:
            #   - Uses __save_settings (td_state_set) to store runtime values
            #
            # Notes:
            #   - Repeats until the user confirms "Ok to apply?"
            #   - Does not write/apply netplan; callers handle __create_runtime_netplan/__apply_netplan
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
                printf "${TUI_BORDER}==================================================\n"
                printf "${TUI_TEXT}   Host & IPv4 setup\n"
                printf "${TUI_BORDER}==================================================\n"
                
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
                printf "${TUI_BORDER}==================================================\n"

                if ask_yesno "Ok to apply?"; then
                    break
                fi
            done

            __save_settings

            sayend "Settings collection complete."
        }
        # --- __set_hostname --------------------------------------------------------------
            # Set system hostname (short) and rebuild /etc/hosts.
            #
            # Usage:
            #   __set_hostname --host "$HOST" [--ip "$IP"] [--use-dhcp "$USE_DHCP"]
            #                 [--short "$SHORT"] [--hosts-file /etc/hosts]
            #
            # Notes:
            # - If --short is not provided, it is derived from --host (split at first '.')
            # - If use-dhcp is true, the IP line in /etc/hosts is omitted
            # - If --ip is empty, the IP line is omitted
        __set_hostname() {
            local host=""
            local short=""
            local ip=""
            local use_dhcp="Yes"
            local hosts_file="/etc/hosts"

            local tmp_hosts=""

            # --- Parse options
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --host)       host="$2"; shift 2 ;;
                    --short)      short="$2"; shift 2 ;;
                    --ip)         ip="$2"; shift 2 ;;
                    --use-dhcp)   use_dhcp="$2"; shift 2 ;;
                    --hosts-file) hosts_file="$2"; shift 2 ;;
                    --) shift; break ;;
                    *)
                        sayfail "__set_hostname: Unknown option: $1"
                        return 2
                        ;;
                esac
            done

            # --- Validate
            if [[ -z "$host" ]]; then
                sayfail "__set_hostname: --host is required"
                return 2
            fi

            if [[ -z "$short" ]]; then
                short="${host%%.*}"
            fi

            # ---- set hostname (short only) ----
            if [[ "${FLAG_DRYRUN:-0}" -eq 0 ]]; then
                saydebug "Setting hostname (short): $short"
                hostnamectl set-hostname "$short"
            else
                sayinfo "Would have set hostname to : $short"
            fi

            # ---- rebuild /etc/hosts atomically ----
            if [[ "${FLAG_DRYRUN:-0}" -eq 0 ]]; then
                saydebug "Rebuilding $hosts_file"

                tmp_hosts="$(mktemp)"
                {
                    echo "127.0.0.1 localhost"
                    echo "127.0.1.1 ${short} ${short}"

                    # Only add IP line when NOT using DHCP and IP is provided
                    if ! is_true "$use_dhcp" && [[ -n "$ip" ]]; then
                        echo "${ip} ${short}"
                    fi
                } >"$tmp_hosts"

                install -m 0644 "$tmp_hosts" "$hosts_file"

                sayok "Hosts updated:"
                cat "$tmp_hosts" | sed 's/^/  /'

                rm -f "$tmp_hosts"
            else
                sayinfo "Would have updated $hosts_file"
            fi
        }

        # --- __author_netplan -------------------------------------------------------------
            # Emit a complete netplan YAML configuration to stdout based on current
            # runtime network settings.
            #
            # This function does not write to disk or apply the configuration.
            # It is intended to be used by callers that want to:
            #   - Preview the generated netplan
            #   - Write it to a specific file
            #
            # Uses runtime variables:
            #   - NIC
            #   - USE_DHCP
            #   - IP, CIDR
            #   - GW
            #   - ROUTES (optional)
            #   - DNS
            #
            # Notes:
            #   - Supports both DHCP and static IPv4 configurations
            #   - DNS and routes are validated and rendered explicitly
            #   - Output is valid netplan YAML
        __author_netplan(){
            echo "# Generated by clone-config.sh"
            echo "network:"
            echo "  version: 2"
            echo "  renderer: $RENDERER"
            echo "  ethernets:"
            echo "    $NIC:"
            if is_true "$USE_DHCP"; then
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

        # --- __create_runtime_netplan -----------------------------------------------------
            # Generate and write the runtime netplan configuration for the current machine.
            #
            # Behavior:
            #   - Uses __author_netplan to generate YAML
            #   - Writes configuration to NETPLAN_FILE
            #   - Sets restrictive permissions (0600)
            #   - Disables other existing netplan YAML files to avoid conflicts
            #
            # Notes:
            #   - Does NOT apply the netplan (see __apply_netplan)
            #   - Intended for configuring an already-cloned machine
            #   - Assumes NETPLAN_FILE refers to the active runtime configuration
        __create_runtime_netplan(){
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

        # --- __apply_netplan --------------------------------------------------------------
            # Apply the currently written netplan configuration to the system.
            #
            # Behavior:
            #   - Prompts the user for confirmation before applying
            #   - Runs `netplan generate` and `netplan apply`
            #   - Displays resulting IPv4 address and default route
            #   - Ensures SSH is enabled and running after network changes
            #
            # Notes:
            #   - Applying netplan may cause brief network disruption
            #   - SSH is explicitly restarted/enabled to avoid loss of access
            #   - Safe to skip and apply manually later if desired
        __apply_netplan(){
            if ! is_true "$FLAG_DRYRUN"; then
                if ask_yesno "Apply netplan now?"; then
                    have netplan || { sayfail "netplan not found (install netplan.io)"; exit 1; }
                    saywarning "Applying netplan (brief disruption possible)"
                    netplan generate
                    netplan apply
                    sayinfo "IPv4 on $NIC:"; ip -4 addr show "$NIC" | sed 's/^/  /'
                    sayinfo "Default route:"; ip route show default | sed 's/^/  /'
                    sudo systemctl enable --now ssh
                else
                    saywarning "Skipped apply. Later: sudo netplan generate && sudo netplan apply"
                fi
            else
                sayinfo "Would have applied newly created netplan"
            fi
        }

    # --- Domain join -------------------------------------------------------------
        # --- __get_domain_settings -------------------------------------------------------
            # Collect interactive domain join settings and derive WORKGROUP/REALM values.
            #
            # This function prompts for the AD domain and the authorized join user, then derives
            # normalized values needed by Samba/Kerberos:
            #   - DOMAIN_LC : lowercase DNS domain (for smb.conf conventions)
            #   - REALM_UC  : uppercase Kerberos realm
            #   - WORKGROUP : first label of the realm (e.g. EXAMPLE from EXAMPLE.COM)
            #
            # Persists:
            #   - Uses __save_domain_settings to store DOMAIN and ADM_USR for reuse
            #
            # Flow:
            #   - Presents derived values for confirmation
            #   - Uses ask_ok_redo_quit to continue, redo, or abort
            #
            # Notes:
            #   - This function collects/derives settings only; join work happens in
            #     __install_samba_client, __write_smbconf, and __finalize_domain_join.
        __get_domain_settings(){
            saydebug "Collecting settings for Domain Join..."
            printf '\n' 

            # Defaults (only if not already loaded)
            : "${DOMAIN:=example.com}"
            : "${ADM_USR:=administrator}"

            # ---- prompts ----
            while true; do
                printf "${TUI_BORDER}==================================================\n"
                printf "${TUI_TEXT}   Join domain                              ${RUN_MODE}\n"                        
                printf "${TUI_BORDER}==================================================\n"

                ask --label "Hostname" --var HOST --default "$HOST" --colorize both 
                ask --label "Domain" --var DOMAIN --default "$DOMAIN" --colorize both
                ask --label "Authorized user" --var ADM_USR --default "$ADM_USR" --colorize both
                
                # Normalize to lowercase (for smb.conf)
                DOMAIN_LC="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
                # Derive realm in uppercase (for Kerberos)
                REALM_UC="$(printf '%s' "$DOMAIN_LC" | tr '[:lower:]' '[:upper:]')"
                WORKGROUP="${REALM_UC%%.*}"   # keep only first label; remove this line if you want EXAMPLE.COM


                # Show derived values (don’t let user overwrite them unless you truly want that)
                printf "%sDerived domain   : %s\n" "$(td_color "$WHITE" "" "$FX_ITALIC")" "${DOMAIN_LC:-<none>}"
                printf "%sKerberos realm   : %s\n" "$(td_color "$WHITE" "" "$FX_ITALIC")" "${REALM_UC:-<none>}"                      
                printf "${TUI_BORDER}==================================================\n"

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

        # --- __save_domain_settings ------------------------------------------------------
            # Persist domain join settings to the state store.
            #
            # Saves the values collected in __get_domain_settings so subsequent runs can reuse
            # defaults without prompting again.
            #
            # Persists:
            #   - DOMAIN  : DNS domain name (e.g. example.com)
            #   - ADM_USR : authorized account name (e.g. administrator)
            #
            # Notes:
            #   - Derived values (DOMAIN_LC, REALM_UC, WORKGROUP) are recomputed at runtime and
            #     are intentionally not persisted here.
        __save_domain_settings(){
            td_state_set "DOMAIN" "$DOMAIN"
            td_state_set "ADM_USR" "$ADM_USR"
        }
        # --- __write_smbconf -------------------------------------------------------------
            # Write a minimal Samba smb.conf suitable for joining an AD domain as a member server.
            #
            # Generates /etc/samba/smb.conf with the required global settings for:
            #   - security = ADS
            #   - realm/workgroup
            #   - winbind defaults
            #   - idmap pre-join defaults (tdb) so winbind can start
            #
            # Behavior:
            #   - In dry-run mode, prints the generated smb.conf to stdout
            #   - Otherwise writes to /etc/samba/smb.conf
            #
            # Inputs (expected to be set by __get_domain_settings):
            #   - WORKGROUP, REALM_UC
            #
            # Notes:
            #   - This is the "pre-join" smb.conf; __finalize_domain_join may later inject
            #     a WORKGROUP-specific RID idmap mapping after a successful join.
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
        # --- __install_samba_client ------------------------------------------------------
            # Install the Samba AD member-server client stack required for domain join.
            #
            # Installs packages needed for:
            #   - Samba member server services (samba)
            #   - Winbind + NSS/PAM integration
            #   - Kerberos client tools (krb5-user)
            #   - Basic DNS utilities and ACL/attr helpers used by Samba
            #
            # Behavior:
            #   - In dry-run mode, only reports intended actions
            #   - Otherwise runs apt update and apt install
            #
            # Notes:
            #   - Intended for Ubuntu/Debian systems (apt-based).
            #   - Call before __write_smbconf / __finalize_domain_join.
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

        # --- __finalize_domain_join ------------------------------------------------------
            # Perform the domain join, configure NSS, switch idmap strategy, and verify.
            #
            # This function completes the AD member join process:
            #   1) Ensure NSS is configured to resolve domain users via winbind
            #   2) Restart Samba services (smbd/nmbd/winbind)
            #   3) Acquire Kerberos ticket (kinit) and join AD (net ads join)
            #   4) Switch from generic pre-join idmap (tdb) to WORKGROUP RID mapping
            #   5) Restart services again and validate resolution (wbinfo/getent)
            #
            # Inputs (expected):
            #   - DOMAIN, REALM_UC, WORKGROUP
            #   - ADM_USR (and any normalized form, if you define ADM_USR_NORM upstream)
            #
            # Behavior:
            #   - Honors FLAG_DRYRUN by printing intended actions without changing the system
            #   - Fails (non-zero) when join/verification steps fail (non-dry-run)
            #
            # Notes:
            #   - If RID idmap is already present for the WORKGROUP, the switch step is skipped.
            #   - Verification checks:
            #       wbinfo -p
            #       getent passwd "${WORKGROUP}\\${ADM_USR}"
            #   - Requires working DNS and time sync for Kerberos to succeed.
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
        # --- __get_clone_defaults ---------------------------------------------------------
            # Collect and confirm default settings that the template should use when cloned.
            #
            # These values define the *initial identity* of a newly cloned machine before
            # first-boot reconfiguration takes place.
            #
            # Collected settings:
            #   - Template hostname
            #   - Network interface
            #   - Static IPv4 address (typically staging IP, e.g. .254)
            #   - CIDR prefix
            #   - Gateway
            #   - DNS servers
            #   - Netplan filename to generate
            #
            # Behavior:
            #   - Existing values are used as defaults
            #   - User is prompted to confirm or modify
            #   - Values are persisted to state via __save_clone_defaults
        __get_clone_defaults(){
            : "${CLONE_NIC:=${NIC:-eth0}}"
            : "${CLONE_NETPLAN_FILE:=/etc/netplan/10-netplan-clone.yaml}"
            : "${CLONE_HOST:=${HOST:-td-ubuntu-template}}"
            : "${CLONE_IP:=${IP:-192.168.0.200}}"
            : "${CLONE_CIDR:=${CIDR:-24}}"
            : "${CLONE_GW:=${GW:-192.168.0.1}}"
            : "${CLONE_DNS:=${DNS:-192.168.0.1}}"


            while true; do
                printf "${TUI_BORDER}==================================================\n"
                printf "${TUI_TEXT}   Prepare template for next clone settings\n"
                printf "${TUI_BORDER}==================================================\n"

                ask --label "Hostname for template" --var CLONE_HOST --default "$CLONE_HOST" --colorize both 
                ask --label "Network interface for template" --var CLONE_NIC --default "$CLONE_NIC" --colorize both  
                ask --label "Static IPv4 for template" --var CLONE_IP --default "$CLONE_IP" --colorize=both --validate_fn=validate_ip
                ask --label "CIDR prefix for template (e.g. 24)" --var CLONE_CIDR --default "$CLONE_CIDR" --colorize=both --validate_fn=validate_cidr 
                ask --label "Gateway IPv4 for template" --var CLONE_GW --default "$CLONE_GW" --colorize=both --validate_fn=validate_ip
                ask --label "DNS servers for template (comma-separated)" --var CLONE_DNS --default "$CLONE_DNS" --colorize=both 
                ask --label "Netplan filename for template" --var CLONE_NETPLAN_FILE --default "$CLONE_NETPLAN_FILE" --colorize=both

                printf "${TUI_BORDER}==================================================\n"

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

        # --- __save_clone_defaults --------------------------------------------------------
            # Persist clone template default settings to the state store.
            #
            # Saves the values collected in __get_clone_defaults so they can be reused
            # across runs without prompting again.
            #
            # Persisted values:
            #   - CLONE_NIC
            #   - CLONE_HOST
            #   - CLONE_IP
            #   - CLONE_CIDR
            #   - CLONE_GW
            #   - CLONE_DNS
            #   - CLONE_NETPLAN_FILE
            #
            # Notes:
            #   - State persistence allows idempotent template preparation
            #   - Caller is responsible for loading state on next run
        __save_clone_defaults(){
            td_state_set "CLONE_NIC" "$CLONE_NIC"
            td_state_set "CLONE_HOST" "$CLONE_HOST"
            td_state_set "CLONE_IP" "$CLONE_IP"
            td_state_set "CLONE_CIDR" "$CLONE_CIDR"
            td_state_set "CLONE_GW" "$CLONE_GW"
            td_state_set "CLONE_DNS" "$CLONE_DNS"
            td_state_set "CLONE_NETPLAN_FILE" "$CLONE_NETPLAN_FILE"
        }
        # --- __clear_machine_id -----------------------------------------------------------
            # Remove the system machine-id so it will be regenerated on next boot.
            #
            # Required for cloning to ensure each VM gets a unique system identity.
            #
            # Notes:
            #   - systemd will regenerate /etc/machine-id automatically
            #   - Should only be done when preparing a template
        __clear_machine_id(){
            saydebug "Clearing machine-id..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared /etc/machine-id"
            else
                truncate -s 0 /etc/machine-id
                sayok "/etc/machine-id cleared"
            fi
        }

        # --- __remove_ssh_host_keys -------------------------------------------------------
            # Remove existing SSH host keys from the system.
            #
            # This ensures that cloned machines generate unique SSH host keys
            # on first boot, preventing key collisions and client warnings.
            #
            # Notes:
            #   - SSH service will regenerate keys automatically when started
        __remove_ssh_host_keys(){
            saydebug "Removing SSH host keys..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have removed SSH host keys in /etc/ssh/"
            else
                rm -f /etc/ssh/ssh_host_*
                sayok "SSH host keys removed"
            fi
        }

        # --- __clear_temp_and_caches ------------------------------------------------------
            # Remove temporary files and transient cache data from the system.
            #
            # Actions:
            #   - Clears /tmp
            #   - Clears /var/tmp
            #
            # Notes:
            #   - Safe to run when preparing a template
            #   - Does not affect persistent application data
            #   - Helps reduce template size and leftover runtime state
        __clear_temp_and_caches(){
            saydebug "Clearing temporary files and caches..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared /tmp and /var/tmp"
            else
                rm -rf /tmp/* /var/tmp/*
                sayok "Temporary files and caches cleared"
            fi
        }

        # --- __clear_leftovers ------------------------------------------------------------
            # Remove miscellaneous machine-specific leftovers before converting the system
            # into a clone template.
            #
            # Actions:
            #   - Remove root user's bash history
            #   - Remove current user's bash history (if present)
            #   - Remove systemd random seed so entropy is regenerated on first boot
            #
            # Notes:
            #   - Prevents sensitive or identifying data from leaking into clones
            #   - random-seed removal ensures better entropy uniqueness per clone
            #   - Safe to run multiple times
        __clear_leftovers(){
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared shell histories and systemd random-seed"
                return 0
            fi

            rm -f /root/.bash_history
            rm -f "$HOME/.bash_history" 2>/dev/null || true
            rm -f /var/lib/systemd/random-seed

            sayok "Leftover identity artifacts cleared."
        }
        # --- __trim_logs ------------------------------------------------------------------
            # Clean system logs to reduce template size and remove historical noise.
            #
            # Actions:
            #   - Rotate and vacuum systemd journal
            #   - Remove rotated/compressed log files under /var/log
            #
            # Notes:
            #   - Active log files are left intact
            #   - Safer than truncating all files under /var/log
        __trim_logs(){
            saydebug "Clearing journald and removing rotated logs..."

            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have rotated/vacuumed journald and deleted rotated logs under /var/log"
                return 0
            fi

            # Clear systemd journal (Ubuntu often stores most logs here)
            journalctl --rotate || true
            journalctl --vacuum-time=1s || true

            # Remove rotated/compressed logs; leave active logs intact
            find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" -o -name "*.[0-9]" \) -delete || true

            sayok "Logs cleaned (journal vacuum + rotated logs removed)."
        }

        # --- __clear_dhcp_leases ----------------------------------------------------------
            # Remove stored DHCP lease information from the system.
            #
            # Actions:
            #   - Deletes dhclient lease files under /var/lib/dhcp
            #
            # Notes:
            #   - Prevents cloned machines from reusing stale DHCP leases
            #   - Safe even when static networking is used
            #   - Particularly useful if DHCP was used earlier in the VM lifecycle
        __clear_dhcp_leases(){
            saydebug "Clearing DHCP leases..."
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have cleared DHCP leases in /var/lib/dhcp/"
            else
                rm -f /var/lib/dhcp/dhclient*.leases
                sayok "DHCP leases cleared"
            fi
        }

        # --- __cleanup_netplans -----------------------------------------------------------
            # Remove or disable netplan configuration files that should no longer be active.
            #
            # Behavior:
            #   - Iterates over existing netplan YAML files
            #   - Removes or disables all except the intended active configuration
            #
            # Notes:
            #   - Must be used carefully: caller must ensure the correct netplan file
            #     (runtime or template) is preserved
            #   - For template preparation, prefer a CLONE-specific cleanup variant
        __cleanup_netplans(){
            saydebug "Cleaning up netplan configurations..."
            local keep="$CLONE_NETPLAN_FILE"
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would have removed existing netplan configurations except the active one"
            else
                 for f in /etc/netplan/*.yaml; do
                    [[ -e "$f" ]] || continue
                    if [[ "$f" != "$keep" ]]; then
                        rm -f "$f"
                    fi
                done
                sayok "Netplan configurations cleaned up"
            fi
        }

        # --- __create_tmpl_netplan --------------------------------------------------------
            # Generate and write a minimal netplan configuration for the clone template.
            #
            # This netplan defines the *initial* network identity of a freshly cloned VM,
            # typically using a fixed staging IP to allow immediate SSH access.
            #
            # Behavior:
            #   - Uses CLONE_* variables collected via __get_clone_defaults
            #   - Writes a minimal, deterministic netplan configuration
            #   - Does NOT apply the netplan
            #
            # Notes:
            #   - Intended for template state only
            #   - First-boot logic may later replace this netplan dynamically
        __create_tmpl_netplan(){
            __get_clone_defaults
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

        # --- __minimal_netplan ------------------------------------------------------------
            # Emit a minimal static netplan YAML configuration to stdout.
            #
            # This configuration is intended for use on clone templates and provides:
            #   - A fixed IPv4 address (staging IP)
            #   - Default route
            #   - Explicit DNS servers
            #
            # Output:
            #   - Valid netplan YAML written to stdout
            #
            # Notes:
            #   - DNS servers are split from CLONE_DNS (comma-separated)
            #   - No DHCP is enabled
            #   - Caller is responsible for writing to disk and applying if desired
        __minimal_netplan(){
            echo "# Minimal netplan generated by clone-config.sh"
            echo "network:"
            echo "  version: 2"
            echo "  renderer: networkd"
            echo "  ethernets:"
            echo "    ${CLONE_NIC:-ens99}:"
            echo "      dhcp4: no"
            echo "      addresses:"
            echo "        - ${CLONE_IP:-192.168.0.254}/${CLONE_CIDR:-24}"
            echo "      routes:"
            echo "        - to: 0.0.0.0/0"
            echo "          via: ${CLONE_GW:-192.168.0.1}"
            echo "      nameservers:"
            echo "        addresses:"

            IFS=',' read -r -a dnsarr <<<"${CLONE_DNS:-1.1.1.1}"
            for d in "${dnsarr[@]}"; do
                d="$(echo "$d" | tr -d '\r' | xargs)"
                validate_ip "$d" || { say "Skip invalid DNS: $d"; continue; }
                printf '          - "%s"\n' "$d"
            done
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

# === main() must be the last function in the script ==============================
    main() {
    # --- Bootstrap ---------------------------------------------------------------
        td_bootstrap --state --needroot -- "$@"

        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi
            
    # --- Main script logic ---------------------------------------------------
        wait_after=0
        while true; do
            clear
            if [[ ${FLAG_VERBOSE:-0} -eq 1 ]]; then
                td_showarguments
            fi
            __show_mainmenu

            td_choose --label "Select option" --choices "1-8,D,V,X" --var choice

            case "${choice^^}" in
                1) wait_after=8  ; __setup_machine_id ;;
                2) wait_after=5  ; __configure_network ;;
                3) wait_after=5  ; __enable_ssh ;;
                4) wait_after=10 ; __join_domain ;;
                5) wait_after=10 ; __prepare_template ;;

                V)
                    wait_after=3
                    if (( FLAG_VERBOSE )); then
                        FLAG_VERBOSE=0
                        sayinfo "Verbose mode disabled."
                    else
                        FLAG_VERBOSE=1
                        sayinfo "Verbose mode enabled."
                    fi
                    ;;

                D)
                    wait_after=3
                    if (( FLAG_DRYRUN )); then
                        FLAG_DRYRUN=0
                        saywarning "DryRun mode disabled."
                        td_update_runmode
                    else
                        FLAG_DRYRUN=1
                        saywarning "DryRun mode enabled."
                        td_update_runmode
                    fi
                    ;;

                X)
                    sayinfo "Exiting..."
                    break
                    ;;

                *)
                    saywarning "Invalid option. Please select a valid option."
                    ;;
            esac
            
            if (( wait_after > 1 )); then
                ask_autocontinue "$wait_after"
            else
                sleep "$wait_after"
            fi
        done
    }

    # Run main with positional args only (not the options)
    main "$@"

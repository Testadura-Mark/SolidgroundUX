#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — core.sh
# -------------------------------------------------------------------------------
# Purpose : Common Bash helper one-liners for reusable scripts
# Author  : Mark Fieten
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description :
#   Source this file to get small, focused utilities:
#   - Privilege & command checks
#   - Filesystem helpers
#   - Network helpers
#   - Arg/env validators
#   - Process helpers
#   - Version/OS helpers
#   - Misc utilities
# ===============================================================================

# --- Script metadata ----------------------------------------------------------
    SCRIPT_FILE="${BASH_SOURCE[0]}"
    SCRIPT_NAME=""
    SCRIPT_DESC="Short description of what this script does."
    SCRIPT_VERSION="1.0"
    SCRIPT_VERSION_STATUS="alpha"
    SCRIPT_BUILD="20250110"

# --- Internals ---------------------------------------------------------------
  # _sh_err -- print an error message to stderr (internal, minimal).
  _sh_err(){ printf '%s\n' "${*:-(no message)}" >&2; }


# --- Privilege & Command Checks ----------------------------------------------
  # have -- test if a command exists in PATH.
  have(){ command -v "$1" >/dev/null 2>&1; }

  # need_cmd -- require a command to exist or exit with error.
  need_cmd(){ have "$1" || { _sh_err "Missing required command: $1"; exit 1; }; }

  # need_root -- require the script to run as root (EUID=0) or exit.
  need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { _sh_err "Run as root (sudo)."; exit 1; }; }

  # cannot_root -- require normal session
  cannot_root() {
      if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
          _sh_err "Do not run this script as root."
          exit 1
      fi
  }

  # need_bash -- require Bash (optionally minimum major version) or exit.
  need_bash(){ (( BASH_VERSINFO[0] >= ${1:-4} )) || { _sh_err "Bash ${1:-4}+ required."; exit 1; }; }

  # need_tty -- require an attached TTY on stdout, return 1 otherwise.
  need_tty(){ [[ -t 1 ]] || { _sh_err "No TTY attached."; return 1; }; }

  # is_active -- check if a systemd unit is active.
  is_active(){ systemctl is-active --quiet "$1"; }

  # need_systemd -- require systemd (systemctl available) or exit.
  need_systemd(){ have systemctl || { _sh_err "Systemd not available."; exit 1; }; }

# --- Filesystem Helpers ------------------------------------------------------
  # ensure_dir -- create directory (including parents) if it does not exist.
  ensure_dir(){ [[ -d "$1" ]] || mkdir -p "$1"; }

  # exists -- test if a regular file exists.
  exists(){ [[ -f "$1" ]]; }

  # is_dir -- test if a directory exists.
  is_dir(){ [[ -d "$1" ]]; }

  # is_nonempty -- test if a file exists and is non-empty.
  is_nonempty(){ [[ -s "$1" ]]; }

  # need_writable -- require a path to be writable or exit.
  need_writable(){ [[ -w "$1" ]] || { _sh_err "Not writable: $1"; exit 1; }; }

  # abs_path -- resolve an absolute canonical path using readlink/realpath.
  abs_path(){ readlink -f "$1" 2>/dev/null || realpath "$1"; }

  # mktemp_dir -- create a temporary directory, return its path.
  mktemp_dir(){ mktemp -d 2>/dev/null || TMPDIR=${TMPDIR:-/tmp} mktemp -d "${TMPDIR%/}/XXXXXX"; }

  # mktemp_file -- create a temporary file, return its path.
  mktemp_file(){ TMPDIR=${TMPDIR:-/tmp} mktemp "${TMPDIR%/}/XXXXXX"; }

# --- Network Helpers ---------------------------------------------------------
  # ping_ok -- return 0 if host responds to a single ping.
  ping_ok(){ ping -c1 -W1 "$1" &>/dev/null; }

  # port_open -- test if TCP port on host is open (nc preferred, /dev/tcp fallback).
  port_open(){
    local h="$1" p="$2"
    if have nc; then nc -z "$h" "$p" &>/dev/null; else
      (exec 3<>"/dev/tcp/$h/$p") &>/dev/null
    fi
  }

  # get_ip -- return first non-loopback IP address of this host.
  get_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }

# --- Argument & Environment Helpers-------------------------------------------
  # is_set -- test if a variable name is defined (set) in the environment.
  is_set(){ [[ -v "$1" ]]; }

  # need_env -- require a named environment variable to be non-empty or exit.
  need_env(){ [[ -n "${!1:-}" ]] || { _sh_err "Missing env var: $1"; exit 1; }; }

  # default -- set VAR to VALUE if VAR is unset or empty.
  default(){ eval "${1}=\${${1}:-$2}"; }

  # is_number -- test if value consists only of digits.
  is_number(){ [[ "$1" =~ ^[0-9]+$ ]]; }

  # is_bool -- test if value is a common boolean-like token.
  is_bool(){ [[ "$1" =~ ^(true|false|yes|no|on|off|1|0)$ ]]; }

  # confirm -- ask a yes/no question, return 0 on [Yy].
  confirm(){ read -rp "${1:-Are you sure?} [y/N]: " _a; [[ "$_a" =~ ^[Yy]$ ]]; }

# --- Process & State Helpers -------------------------------------------------
  # proc_exists -- check if a process with given name is running.
  proc_exists(){ pgrep -x "$1" &>/dev/null; }

  # wait_for_exit -- block until a named process is no longer running.
  wait_for_exit(){ while proc_exists "$1"; do sleep 0.5; done; }

  # kill_if_running -- terminate processes by name if they are running.
  kill_if_running(){ pkill -x "$1" &>/dev/null || true; }


# --- Version & OS Helpers ----------------------------------------------------
  # get_os -- return OS ID from /etc/os-release (e.g. ubuntu, debian).
  get_os(){ grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # get_os_version -- return OS VERSION_ID from /etc/os-release.
  get_os_version(){ grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # version_ge -- return 0 if version A >= version B (natural sort -V).
  # usage: version_ge "1.4" "1.3"
  version_ge(){ [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

  show_version() {
    justsay "SoluxGround Framework : $SOLUXGROUND_VERSION ($SOLUXGROUND_VERSION_DATE)"
    justsay "Script                 : ${SCRIPT_VERSION:-<none>} ${SCRIPT_VERSION_STATUS:-}"
    [[ -n "$SCRIPT_VERSION_DATE" ]] && justsay "Script Date            : $SCRIPT_VERSION_DATE"
}


# --- Misc Utilities ----------------------------------------------------------
  # join_by -- join arguments with a separator.
  join_by(){ local IFS="$1"; shift; echo "$*"; }

  # trim -- remove leading/trailing whitespace.
  trim(){ local v="${*:-}"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }

  # timestamp -- return current time as "YYYY-MM-DD HH:MM:SS".
  timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }

  # retry -- retry command N times with DELAY seconds between attempts.
  # usage: retry 5 2 cmd arg1 arg2
  retry(){
    local n="$1" d="$2"; shift 2
    local i
    for ((i=1;i<=n;i++)); do
      "$@" && return 0
      (( i < n )) && sleep "$d"
    done
    return 1
  }

# --- Die and exit  handlers --------------------------------------------------
    die(){ local code="${2:-1}"; _sh_err "${1:-fatal error}"; exit "$code"; }

    # on_exit -- append command to existing EXIT trap if set.
    on_exit(){
      local new="$1" old
      old="$(trap -p EXIT | sed -n "s/^trap -- '\(.*\)' EXIT$/\1/p")"
      if [[ -n "$old" ]]; then
        trap "$old; $new" EXIT
      else
        trap "$new" EXIT
      fi
    }

# --- Argument & Environment Validators ---------------------------------------
  # validate_int -- return 0 if value is an integer (optional +/- sign).
  validate_int() 
  {
    [[ "$1" =~ ^[+-]?[0-9]+$ ]]
  }

  # validate_decimal -- return 0 if value is a decimal number (int or int.frac, optional +/-).
  validate_decimal() 
  {

    [[ "$1" =~ ^[+-]?[0-9]+(\.[0-9]+)?$ ]]
  }

  # validate_ipv4 -- return 0 if value is a valid IPv4 address (0–255 per octet).
  validate_ipv4() 
  {
    local ip="$1" IFS='.' octets o
    IFS='.' read -r -a octets <<<"$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for o in "${octets[@]}"; do
      [[ "$o" =~ ^[0-9]+$ ]] || return 1
      (( o >= 0 && o <= 255 )) || return 1
    done
    return 0
  }

  # validate_yesno -- return 0 if value is single-char Y/y/N/n.
  validate_yesno() 
  {
    [[ "$1" =~ ^[YyNn]$ ]]
  }

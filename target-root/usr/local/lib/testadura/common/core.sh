# =================================================================================
# Testadura Consultancy — core.sh
# ---------------------------------------------------------------------------------
# Purpose    : Minimal, UI-free Bash helpers for reusable scripts
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ---------------------------------------------------------------------------------
# Assumptions:
#   - Core helpers (NO framework or UI dependencies)
#
# Description:
#   Source this file to get small, focused utilities:
#   - Privilege & command checks
#   - Filesystem helpers
#   - Networking convenience helpers
#   - Arg/env validators
#   - Process helpers
#   - OS/version detection helpers
#   - Misc utilities
#
# Rules / Contract:
#   - No UI formatting or rendering
#   - No colors, themes, or terminal assumptions
#   - No logging, prompts, or interactive behavior
#   - No dependency on framework state or globals
#   - Safe to use during early bootstrap and in isolation
# 
# =================================================================================
# --- Library guard ---------------------------------------------------------------
    # Derive a unique per-library guard variable from the filename:
    #   ui.sh        -> TD_UI_LOADED
    #   ui-sgr.sh    -> TD_UI_SGR_LOADED
    #   foo-bar.sh   -> TD_FOO_BAR_LOADED
    # Note:
    #   Guard variables (__lib_*) are internal globals by convention; they are not part
    #   of the public API and may change without notice.
    __lib_base="$(basename "${BASH_SOURCE[0]}")"
    __lib_base="${__lib_base%.sh}"
    __lib_base="${__lib_base//-/_}"
    __lib_guard="TD_${__lib_base^^}_LOADED"

    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
        echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
        exit 2
    }

    # Load guard (safe under set -u)
    [[ -n "${!__lib_guard-}" ]] && return 0
    printf -v "$__lib_guard" '1'

# --- Internals -------------------------------------------------------------------
  # _sh_err -- print an error message to stderr (internal, minimal).
  _sh_err(){ printf '%s\n' "${*:-(no message)}" >&2; }

# --- Requirement checks ----------------------------------------------------------
  # td_have
    # Test if a command exists in PATH.
  td_have(){ command -v "$1" >/dev/null 2>&1; }

 # -- Possibly exiting requirement checks -----------------------------------------
  # td_need_cmd
    # Require a command to exist or exit with error.
  td_need_cmd(){ td_have "$1" || { _sh_err "Missing required command: $1"; exit 1; }; }

  # td_need_root 
    # Require the script to run as root, re-exec with sudo if not.
  td_need_root() {
      if [[ ${EUID:-$(id -u)} -ne 0 && -z "${TD_ALREADY_ROOT:-}" ]]; then
          exec sudo \
              --preserve-env=TD_FRAMEWORK_ROOT,TD_APPLICATION_ROOT,PATH \
              -- env TD_ALREADY_ROOT=1 "$0" "$@"
      fi
  }

  # td_cannot_root
    # require normal session
  td_cannot_root() {
      if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
          _sh_err "Do not run this script as root."
          exit 1
      fi
  }

  # td_need_bash
    # require Bash (optionally minimum major version) or exit.
  td_need_bash(){ (( BASH_VERSINFO[0] >= ${1:-4} )) || { _sh_err "Bash ${1:-4}+ required."; exit 1; }; }

  # td_need_env
    # Require a named environment variable to be non-empty or exit.
  td_need_env(){ [[ -n "${!1:-}" ]] || { _sh_err "Missing env var: $1"; exit 1; }; }

  # td_need_systemd
    # Require systemd (systemctl available) or exit.
  td_need_systemd(){ td_have systemctl || { _sh_err "Systemd not available."; exit 1; }; }

  # td_need_writable
    # Require a path to be writable or exit.
  td_need_writable(){ [[ -w "$1" ]] || { _sh_err "Not writable: $1"; exit 1; }; }

 # -- Non lethal requirement checks (return 1 on failure, do not exit) ------------
  # td_need_tty
    # Require an attached TTY on stdout, return 1 otherwise.
  td_need_tty(){ [[ -t 1 ]] || { _sh_err "No TTY attached."; return 1; }; }

  # td_is_active
    # Check if a systemd unit is active.
  td_is_active(){ systemctl is-active --quiet "$1"; }

# --- Filesystem Helpers ----------------------------------------------------------
  # td_can_append PATH
      #   Returns 0 if PATH can be appended to.
      #   Conditions:
      #     - If file exists: must be regular file and writable.
      #     - If file does not exist: parent directory must be writable
      #       or creatable via mkdir -p.
      #   Does not create the file; only ensures writability conditions.
  td_can_append() {
      # Returns 0 if we can append to $1 (file exists and writable, or dir writable to create)
      local f="$1"
      local d

      [[ -n "$f" ]] || return 1
      d="$(dirname -- "$f")"

      # Existing file must be writable
      if [[ -e "$f" ]]; then
          [[ -f "$f" && -w "$f" ]] || return 1
          return 0
      fi

      # Non-existing file: directory must exist and be writable, OR be creatable (mkdir -p)
      if [[ -d "$d" ]]; then
          [[ -w "$d" ]] || return 1
          return 0
      fi

      # Try to create directory path (silently)
      mkdir -p -- "$d" 2>/dev/null || return 1
      [[ -w "$d" ]] || return 1
      return 0
  }
  # td_ensure_dir
    # Create directory (including parents) if it does not exist.
  td_ensure_dir() {
      local dir="${1:-}"
      [[ -n "$dir" ]] || return 2
      [[ -d "$dir" ]] || mkdir -p -- "$dir"
  }

  # td_ensure_writable_dir
    # Create directory (including parents) if it does not exist.
    # If running via sudo, assign ownership to the invoking user (dev convenience).
  td_ensure_writable_dir() {
      local dir="${1:-}"
      [[ -n "$dir" ]] || return 2

      local created=0
      if [[ ! -d "$dir" ]]; then
          mkdir -p -- "$dir" || return 3
          created=1
      fi

      # If running under sudo, ensure user-owned directory for user-scoped paths
      if [[ -n "${SUDO_USER:-}" ]]; then
          local grp
          grp="$(id -gn "$SUDO_USER" 2>/dev/null || printf '%s' "$SUDO_USER")"

          if (( created )); then
              chown "$SUDO_USER:$grp" "$dir" 2>/dev/null || true
          fi
      fi

      [[ -d "$dir" ]] || return 4
      return 0
  }

  # td_exists
    # Test if a regular file exists.
  td_exists(){ [[ -f "$1" ]]; }

  # td_is_dir
    # Test if a directory exists.
  td_is_dir(){ [[ -d "$1" ]]; }

  # td_is_nonempty 
    # Test if a file exists and is non-empty.
  td_is_nonempty(){ [[ -s "$1" ]]; }

  # td_abs_path
    # Resolve an absolute canonical path using readlink/realpath.
  td_abs_path(){ readlink -f "$1" 2>/dev/null || realpath "$1"; }

  # td_mktemp_dir
    # Create a temporary directory, return its path.
  td_mktemp_dir(){ mktemp -d 2>/dev/null || TMPDIR=${TMPDIR:-/tmp} mktemp -d "${TMPDIR%/}/XXXXXX"; }

  # td_mktemp_file
    # Create a temporary file, return its path.
  td_mktemp_file(){ TMPDIR=${TMPDIR:-/tmp} mktemp "${TMPDIR%/}/XXXXXX"; }

  # td_slugify
    # Sanitize a string into a filename-safe "slug".
  td_slugify() {
      # Usage: td_slugify "Some Title!!"
      # Output: some-title
      local s="${1:-}"

      # Lowercase (bash 4+)
      s="${s,,}"

      # Replace whitespace with dash
      s="$(printf '%s' "$s" | tr -s '[:space:]' '-')"

      # Remove anything not [a-z0-9-_.]
      s="$(printf '%s' "$s" | tr -cd 'a-z0-9-_.')"

      # Collapse multiple dashes
      while [[ "$s" == *--* ]]; do s="${s//--/-}"; done

      # Trim leading/trailing dashes
      s="${s#-}"
      s="${s%-}"

      [[ -n "$s" ]] || s="hub"
      printf '%s' "$s"
  }

  # td_hash_sha256_file
    #   Print SHA256 hash of a file to stdout.
    #   Returns non-zero if no hashing tool is available.
  td_hash_sha256_file() {
      local file="$1"

      [[ -r "$file" ]] || return 2

      if command -v sha256sum >/dev/null 2>&1; then
          # sha256sum prints: "<hash>  filename"
          local out
          out="$(sha256sum "$file")" || return 3
          printf '%s\n' "${out%% *}"
          return 0
      fi

      if command -v shasum >/dev/null 2>&1; then
          local out
          out="$(shasum -a 256 "$file")" || return 3
          printf '%s\n' "${out%% *}"
          return 0
      fi

      return 127
  }

# --- Systeminfo ------------------------------------------------------------------
  td_get_primary_nic() {
      ip route show default 2>/dev/null | awk 'NR==1 {print $5}'
  }
# --- Network Helpers -------------------------------------------------------------
  # td_ping_ok
    # Return 0 if host responds to a single ping.
  td_ping_ok(){ ping -c1 -W1 "$1" &>/dev/null; }

  # td_port_open
    # Test if TCP port on host is open (nc preferred, /dev/tcp fallback).
  td_port_open(){
    local h="$1" p="$2"
    if td_have nc; then nc -z "$h" "$p" &>/dev/null; else
      (exec 3<>"/dev/tcp/$h/$p") &>/dev/null
    fi
  }

  # td_get_ip
    # Return first non-loopback IP address of this host.
  td_get_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }

# --- Argument & Environment Helpers-----------------------------------------------
  # td_is_set
    # Test if a variable name is defined (set) in the environment.
  td_is_set(){ [[ -v "$1" ]]; }

  # td_default
    # Set VAR to VALUE if VAR is unset or empty.
  td_default(){ eval "${1}=\${${1}:-$2}"; }

  # td_is_number
    # Test if value consists only of digits.
  td_is_number(){ [[ "$1" =~ ^[0-9]+$ ]]; }

  # td_is_bool
    # Test if value is a common boolean-like token.
  td_is_bool(){ [[ "$1" =~ ^(true|false|yes|no|on|off|1|0)$ ]]; }

  # td_array_has_items
    # Test if an array variable has any items.
  td_array_has_items(){
    declare -p "$1" &>/dev/null || return 1
    local -n _arr="$1"
    (( ${#_arr[@]} > 0 ))
  }

  # td_is_true
    # Test if value is a common "true" token (case-insensitive).
  td_is_true() {
    case "${1,,}" in
        y|yes|1|true) return 0 ;;
        *)            return 1 ;;
    esac
  }

# --- Process & State Helpers -----------------------------------------------------
  # td_proc_exists
    # Check if a process with given name is running.
  td_proc_exists(){ pgrep -x "$1" &>/dev/null; }

  # td_wait_for_exit
    # Block until a named process is no longer running.
  td_wait_for_exit(){ while td_proc_exists "$1"; do sleep 0.5; done; }

  # td_kill_if_running
    # Terminate processes by name if they are running.
  td_kill_if_running(){ pkill -x "$1" &>/dev/null || true; }

# --- Version & OS Helpers --------------------------------------------------------
  # td_get_os
    # Return OS ID from /etc/os-release (e.g. ubuntu, debian).
  td_get_os(){ grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # td_get_os_version
    # Return OS VERSION_ID from /etc/os-release.
  td_get_os_version(){ grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # td_version_ge
    # Return 0 if version A >= version B (natural sort -V).
    # usage: version_ge "1.4" "1.3"
  td_version_ge(){ [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# --- Misc Utilities --------------------------------------------------------------
  # td_join_by
    # Join arguments with a separator.
  td_join_by(){ local IFS="$1"; shift; echo "$*"; }

  # td_timestamp
    # Return current time as "YYYY-MM-DD HH:MM:SS".
  td_timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }

  # td_retry
    # Retry command N times with DELAY seconds between attempts.
    # usage: retry 5 2 cmd arg1 arg2
  td_retry(){
    local n="$1" d="$2"; shift 2
    local i
    for ((i=1;i<=n;i++)); do
      "$@" && return 0
      (( i < n )) && sleep "$d"
    done
    return 1
  }
# --- Text functions --------------------------------------------------------------
  # td_trim
    # Remove leading/trailing whitespace.
  td_trim(){ local v="${*:-}"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }

  # td_string_repeat
     # Repeat a string N times.
     # Usage: td_string_repeat "abc" 3  # outputs "abcabcabc"
   td_string_repeat() {
        local s="$1"
        local n="$2"
        local out=""
        local i=0

        (( n <= 0 )) && { printf '%s' ""; return 0; }

        for (( i=0; i<n; i++ )); do
            out+="$s"
        done
        printf '%s' "$out"
  }

  # td_wrap_words
    # Wrap a text to a given width (word-boundary wrap).
    # Usage: td_wrap_words --width 60 --text "hello world ..."
  td_wrap_words() {
        local width=80 text=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --width) width="$2"; shift 2 ;;
                --text)  text="$2";  shift 2 ;;
                --) shift; break ;;
                *) return 2 ;;
            esac
        done

        [[ -z "$text" ]] && return 0
        (( width < 1 )) && printf '%s\n' "$text" && return 0

        local line="" word=""

        # Split into words on whitespace (same semantics as your array approach),
        # but without building an array.
        while read -r word; do
            if [[ -z "$line" ]]; then
                line="$word"
            elif (( ${#line} + 1 + ${#word} <= width )); then
                line+=" $word"
            else
                printf '%s\n' "$line"
                line="$word"
            fi
        done < <(printf '%s\n' "$text" | tr -s '[:space:]' '\n')

        [[ -n "$line" ]] && printf '%s\n' "$line"
    }
# --- Die and exit handlers ------------------------------------------------------
    td_die(){ local code="${2:-1}"; _sh_err "${1:-fatal error}"; exit "$code"; }

    # td_on_exit
      # Append command to existing EXIT trap if set.
    td_on_exit(){
      local new="$1" old
      old="$(trap -p EXIT | sed -n "s/^trap -- '\(.*\)' EXIT$/\1/p")"
      if [[ -n "$old" ]]; then
        trap "$old; $new" EXIT
      else
        trap "$new" EXIT
      fi
    }

# --- Argument & Environment Validators -------------------------------------------
  # td_validate_int
    # Return 0 if value is an integer (optional +/- sign).
  td_validate_int() 
  {
    [[ "$1" =~ ^[+-]?[0-9]+$ ]]
  }

  # td_validate_decimal
    # Return 0 if value is a decimal number (int or int.frac, optional +/-).
  td_validate_decimal() 
  {

    [[ "$1" =~ ^[+-]?[0-9]+(\.[0-9]+)?$ ]]
  }

  # td_validate_ipv4
    # Return 0 if value is a valid IPv4 address (0–255 per octet).
  td_validate_ipv4() 
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

  # td_validate_yesno
    # Return 0 if value is single-char Y/y/N/n.
  td_validate_yesno() 
  {
    [[ "$1" =~ ^[YyNn]$ ]]
  }

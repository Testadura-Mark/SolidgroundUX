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

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
      echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
      exit 2
    }

    # Load guard
    [[ -n "${TD_CORE_LOADED:-}" ]] && return 0
    TD_CORE_LOADED=1

# --- Internals -------------------------------------------------------------------
  # _sh_err -- print an error message to stderr (internal, minimal).
  _sh_err(){ printf '%s\n' "${*:-(no message)}" >&2; }


# --- Privilege & Command Checks --------------------------------------------------
  # have -- test if a command exists in PATH.
  have(){ command -v "$1" >/dev/null 2>&1; }

  # need_cmd -- require a command to exist or exit with error.
  need_cmd(){ have "$1" || { _sh_err "Missing required command: $1"; exit 1; }; }

  # need_root -- require the script to run as root, re-exec with sudo if not.
  need_root() {
      if [[ ${EUID:-$(id -u)} -ne 0 && -z "${TD_ALREADY_ROOT:-}" ]]; then
          exec sudo \
              --preserve-env=TD_FRAMEWORK_ROOT,TD_APPLICATION_ROOT,PATH \
              -- env TD_ALREADY_ROOT=1 "$0" "$@"
      fi
  }


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

# --- Filesystem Helpers ----------------------------------------------------------
  # ensure_dir -- create directory (including parents) if it does not exist.
  ensure_dir() {
      local dir="${1:-}"
      [[ -n "$dir" ]] || return 2
      [[ -d "$dir" ]] || mkdir -p -- "$dir"
  }

  # ensure_writable_dir
    # Create directory (including parents) if it does not exist.
    # If running via sudo, assign ownership to the invoking user (dev convenience).
  ensure_writable_dir() {
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

  # td_slugify -- sanitize filenames
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

  # __td_hash_sha256_file
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
  get_primary_nic() {
      ip route show default 2>/dev/null | awk 'NR==1 {print $5}'
  }
# --- Network Helpers -------------------------------------------------------------
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

# --- Argument & Environment Helpers-----------------------------------------------
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

# --- Process & State Helpers -----------------------------------------------------
  # proc_exists -- check if a process with given name is running.
  proc_exists(){ pgrep -x "$1" &>/dev/null; }

  # wait_for_exit -- block until a named process is no longer running.
  wait_for_exit(){ while proc_exists "$1"; do sleep 0.5; done; }

  # kill_if_running -- terminate processes by name if they are running.
  kill_if_running(){ pkill -x "$1" &>/dev/null || true; }


# --- Version & OS Helpers --------------------------------------------------------
  # get_os -- return OS ID from /etc/os-release (e.g. ubuntu, debian).
  get_os(){ grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # get_os_version -- return OS VERSION_ID from /etc/os-release.
  get_os_version(){ grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # version_ge -- return 0 if version A >= version B (natural sort -V).
  # usage: version_ge "1.4" "1.3"
  version_ge(){ [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

  show_script_version() {
    printf '%s\n' "SolidgroundUX : $SGND_VERSION ($SGND_VERSION_DATE)"
    printf '%s\n' "Script        : ${SCRIPT_VERSION:-<none>} ${SCRIPT_VERSION_STATUS:-}"
    [[ -n "$SCRIPT_VERSION_DATE" ]] && justsay "Script Date            : $SCRIPT_VERSION_DATE"
  }

# --- Misc Utilities --------------------------------------------------------------
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
  
  # Strip ANSI SGR color sequences (ESC[...m)
  strip_ansi() {
    sed -r $'s/\x1B\\[[0-9;?]*[[:alpha:]]//g' <<<"$1"
  }
  # Visible length of a string (after stripping ANSI SGR codes)
  # Usage: VisibleLen "text"
  visible_len() {

      local plain
      plain="$(strip_ansi "$1")"
      printf '%s' "${#plain}"
  }
  array_has_items(){
    declare -p "$1" &>/dev/null || return 1
    local -n _arr="$1"
    (( ${#_arr[@]} > 0 ))
  }
  is_true() {
    case "${1,,}" in
        y|yes|1|true) return 0 ;;
        *)            return 1 ;;
    esac
  }
  string_repeat() {
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

    # td_open_editor
      # Open a file for editing using the user's preferred editor.
      # Uses sudo only if the file is not writable.
    td_open_editor() {
        local file="$1"
        [[ -n "$file" ]] || return 1

        local editor=""

        if [[ -n "${EDITOR:-}" ]]; then
            editor="$EDITOR"
        elif [[ -n "${VISUAL:-}" ]]; then
            editor="$VISUAL"
        else
            editor="nano"
        fi

        if [[ -w "$file" ]]; then
            $editor "$file"
        else
            sudo $editor "$file"
        fi
    }
# --- Die and exit  handlers ------------------------------------------------------
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


# --- Argument & Environment Validators -------------------------------------------
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

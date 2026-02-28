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
# Design rules:
#   - Libraries define functions and constants only.
#   - No auto-execution (must be sourced).
#   - Avoids changing shell options beyond strict-unset/pipefail (set -u -o pipefail).
#     (No set -e; no shopt.)
#   - No path detection or root resolution (bootstrap owns path resolution).
#   - No global behavior changes (UI routing, logging policy, shell options).
#   - Safe to source multiple times (idempotent load guard).
# 
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

# --- Internals -------------------------------------------------------------------
  # _sh_err
      # Purpose:
      #   Print an error message to stderr (internal helper).
      #
      # Arguments:
      #   $@  Message tokens. If none given, prints "(no message)".
      #
      # Outputs:
      #   Writes to stderr.
      #
      # Returns:
      #   0 always.
      #
      # Notes:
      #   - Intended for internal use only (minimal; no UI formatting).
  _sh_err(){ printf '%s\n' "${*:-(no message)}" >&2; }

# --- Requirement checks ----------------------------------------------------------
 # -- Possibly exiting requirement checks -----------------------------------------
  # td_need_cmd
      # Purpose:
      #   Require a command to be available on PATH; exit on failure.
      #
      # Arguments:
      #   $1  Command name to check.
      #
      # Behavior:
      #   - Calls td_have "$1".
      #   - Exits the process with rc=1 if missing.
      #
      # Outputs:
      #   Writes an error to stderr on failure.
      #
      # Returns:
      #   Does not return on failure (exits).
  td_need_cmd(){ td_have "$1" || { _sh_err "Missing required command: $1"; exit 1; }; }

  # td_need_root
      # Purpose:
      #   Require the script to run as root; re-exec via sudo if not.
      #
      # Arguments:
      #   $@  Arguments forwarded to the re-exec call.
      #
      # Inputs (env):
      #   TD_ALREADY_ROOT (internal guard to prevent loops)
      #   TD_FRAMEWORK_ROOT, TD_APPLICATION_ROOT, PATH (preserved through sudo)
      #
      # Behavior:
      #   - If not root and TD_ALREADY_ROOT is unset:
      #       exec sudo --preserve-env=... env TD_ALREADY_ROOT=1 "$0" "$@"
      #   - Otherwise continues.
      #
      # Outputs:
      #   Uses sayinfo/saydebug for diagnostics.
      #
      # Returns:
      #   0 when already root (continues).
      #   Does not return when re-exec occurs.
  td_need_root() {
    sayinfo "Script requires root permissions"
    if [[ ${EUID:-$(id -u)} -ne 0 && -z "${TD_ALREADY_ROOT:-}" ]]; then
      exec sudo \
          --preserve-env=TD_FRAMEWORK_ROOT,TD_APPLICATION_ROOT,PATH \
          -- env TD_ALREADY_ROOT=1 "$0" "$@"
      saydebug "Restarting as root"
    else
      saydebug "Already root, no restart required"
    fi
  }

  # td_cannot_root
      # Purpose:
      #   Require the script to NOT run as root; exit if root.
      #
      # Behavior:
      #   - If EUID == 0: prints failure via sayfail and exits rc=1.
      #   - Otherwise continues.
      #
      # Outputs:
      #   Uses sayinfo/sayfail.
      #
      # Returns:
      #   0 when not root; does not return when root (exits).
  td_cannot_root() {
    sayinfo "Script requires NOT having root permissions"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        sayfail "Do not run this script as root. Exiting..."
        exit 1
    fi
  }

  # td_need_bash
      # Purpose:
      #   Require Bash and (optionally) a minimum major version; exit on failure.
      #
      # Arguments:
      #   $1  Minimum major version (default: 4).
      #
      # Inputs:
      #   BASH_VERSINFO
      #
      # Outputs:
      #   Writes an error to stderr on failure.
      #
      # Returns:
      #   Does not return on failure (exits rc=1).
  td_need_bash(){ (( BASH_VERSINFO[0] >= ${1:-4} )) || { _sh_err "Bash ${1:-4}+ required."; exit 1; }; }

  # td_need_systemd
      # Purpose:
      #   Require systemd tooling (systemctl); exit on failure.
      #
      # Behavior:
      #   - Calls td_have systemctl.
      #
      # Outputs:
      #   Writes an error to stderr on failure.
      #
      # Returns:
      #   Does not return on failure (exits rc=1).
  td_need_systemd(){ td_have systemctl || { _sh_err "Systemd not available."; exit 1; }; }

  # td_need_writable
      # Purpose:
      #   Require a path to be writable; exit on failure.
      #
      # Arguments:
      #   $1  Path to test with [[ -w ]].
      #
      # Outputs:
      #   Writes an error to stderr on failure.
      #
      # Returns:
      #   Does not return on failure (exits rc=1).
  td_need_writable(){ [[ -w "$1" ]] || { _sh_err "Not writable: $1"; exit 1; }; }

 # -- Non lethal requirement checks (return 1 on failure, do not exit) ------------
  # td_need_tty
      # Purpose:
      #   Require stdout to be a TTY; return non-zero if not.
      #
      # Behavior:
      #   - Tests [[ -t 1 ]].
      #
      # Outputs:
      #   Writes an error to stderr on failure.
      #
      # Returns:
      #   0 if stdout is a TTY; 1 otherwise.
  td_need_tty(){ [[ -t 1 ]] || { _sh_err "No TTY attached."; return 1; }; }

  # td_is_active
      # Purpose:
      #   Test whether a systemd unit is active.
      #
      # Arguments:
      #   $1  Unit name (e.g. ssh.service).
      #
      # Returns:
      #   0 if active; non-zero otherwise (as per systemctl).
  td_is_active(){ systemctl is-active --quiet "$1"; }

# --- Filesystem Helpers ----------------------------------------------------------
  # td_can_append
      # Purpose:
      #   Test whether a path can be appended to (or created for appending).
      #
      # Arguments:
      #   $1  File path.
      #
      # Behavior:
      #   - If file exists: requires regular file and writable.
      #   - If file does not exist:
      #       - If parent dir exists: requires writable.
      #       - Else attempts mkdir -p on parent dir and then requires writable.
      #
      # Returns:
      #   0 if appendable/creatable for append; 1 otherwise.
      #
      # Notes:
      #   - May create the parent directory (mkdir -p), but does not create the file.
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
      # Purpose:
      #   Ensure a directory exists (mkdir -p if needed).
      #
      # Arguments:
      #   $1  Directory path.
      #
      # Behavior:
      #   - If dir is empty => returns 2.
      #   - If dir does not exist => mkdir -p.
      #
      # Returns:
      #   0 on success; 2 on missing argument; otherwise mkdir's rc.
  td_ensure_dir() {
      local dir="${1:-}"
      [[ -n "$dir" ]] || return 2
      [[ -d "$dir" ]] || mkdir -p -- "$dir"
  }

  # td_ensure_writable_dir
    # Purpose:
    #   Ensure a directory exists, optionally making it user-owned when running via sudo.
    #
    # Arguments:
    #   $1  Directory path.
    #
    # Inputs (env):
    #   SUDO_USER (optional)
    #
    # Behavior:
    #   - Creates the directory if missing (mkdir -p).
    #   - If created and SUDO_USER is set, attempts to chown dir to SUDO_USER:<primary-group>.
    #
    # Returns:
    #   0 on success
    #   2 if directory argument is missing/empty
    #   3 if mkdir -p fails
    #   4 if directory still not present after attempts
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
    # Purpose:
    #   Test whether a regular file exists.
    #
    # Arguments:
    #   $1  File path.
    #
    # Returns:
    #   0 if exists and is a regular file; non-zero otherwise.
  td_exists(){ [[ -f "$1" ]]; }

  # td_is_dir
    # Purpose:
    #   Test whether a directory exists.
    #
    # Arguments:
    #   $1  Directory path.
    #
    # Returns:
    #   0 if exists and is a directory; non-zero otherwise.
  td_is_dir(){ [[ -d "$1" ]]; }

  # td_is_nonempty
    # Purpose:
    #   Test whether a file exists and is non-empty.
    #
    # Arguments:
    #   $1  File path.
    #
    # Returns:
    #   0 if file exists and size > 0; non-zero otherwise.
  td_is_nonempty(){ [[ -s "$1" ]]; }

  # td_abs_path
      # Purpose:
      #   Resolve an absolute canonical path.
      #
      # Arguments:
      #   $1  Path to resolve.
      #
      # Behavior:
      #   - Uses readlink -f when available; falls back to realpath.
      #
      # Outputs:
      #   Prints resolved path to stdout.
      #
      # Returns:
      #   0 on success; non-zero if both resolvers fail.
  td_abs_path(){ readlink -f "$1" 2>/dev/null || realpath "$1"; }

  # td_mktemp_dir
    # Purpose:
    #   Create a temporary directory and print its path.
    #
    # Outputs:
    #   Prints directory path to stdout.
    #
    # Returns:
    #   0 on success; non-zero on failure.
    #
    # Notes:
    #   - Uses mktemp -d; falls back to TMPDIR-based template.
  td_mktemp_dir(){ mktemp -d 2>/dev/null || TMPDIR=${TMPDIR:-/tmp} mktemp -d "${TMPDIR%/}/XXXXXX"; }

  # td_mktemp_file
      # Purpose:
      #   Create a temporary file and print its path.
      #
      # Outputs:
      #   Prints file path to stdout.
      #
      # Returns:
      #   0 on success; non-zero on failure.
  td_mktemp_file(){ ... }
    td_mktemp_file(){ TMPDIR=${TMPDIR:-/tmp} mktemp "${TMPDIR%/}/XXXXXX"; }

  # td_slugify
      # Purpose:
      #   Convert an arbitrary string into a filename-safe "slug".
      #
      # Arguments:
      #   $1  Source string.
      #
      # Behavior:
      #   - Lowercases.
      #   - Converts whitespace runs to a single dash.
      #   - Removes all chars except [a-z0-9-_.].
      #   - Collapses multiple dashes and trims leading/trailing dashes.
      #   - If result is empty, returns "hub".
      #
      # Outputs:
      #   Prints slug to stdout.
      #
      # Returns:
      #   0 always.
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
      # Purpose:
      #   Print the SHA-256 hash of a file (hex) to stdout.
      #
      # Arguments:
      #   $1  File path.
      #
      # Behavior:
      #   - Uses sha256sum if available, otherwise shasum -a 256.
      #
      # Outputs:
      #   Prints hash to stdout.
      #
      # Returns:
      #   0 on success
      #   2 if file is not readable
      #   3 if hashing tool fails
      #   127 if no supported hashing tool exists
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
  # td_get_primary_nic
    # Purpose:
    #   Return the interface name for the default route (best-effort).
    #
    # Behavior:
    #   - Parses `ip route show default` and prints column 5 of the first line.
    #
    # Outputs:
    #   Prints interface name to stdout (may be empty).
    #
    # Returns:
    #   0 always (awk/ip failures may result in empty output).
  td_get_primary_nic() {
      ip route show default 2>/dev/null | awk 'NR==1 {print $5}'
  }
# --- Network Helpers -------------------------------------------------------------
  # td_ping_ok
      # Purpose:
      #   Test whether a host responds to a single ICMP ping.
      #
      # Arguments:
      #   $1  Hostname or IP.
      #
      # Returns:
      #   0 if ping succeeds; non-zero otherwise.
  td_ping_ok(){ ping -c1 -W1 "$1" &>/dev/null; }

  # td_port_open
    # Purpose:
    #   Test whether a TCP port on a host appears open.
    #
    # Arguments:
    #   $1  Hostname or IP.
    #   $2  TCP port number.
    #
    # Behavior:
    #   - Prefers nc -z when available.
    #   - Falls back to bash /dev/tcp.
    #
    # Returns:
    #   0 if connection succeeds; non-zero otherwise.
  td_port_open(){
    local h="$1" p="$2"
    if td_have nc; then nc -z "$h" "$p" &>/dev/null; else
      (exec 3<>"/dev/tcp/$h/$p") &>/dev/null
    fi
  }

  # td_get_ip
    # Purpose:
    #   Return the first non-loopback IP from hostname -I (best-effort).
    #
    # Outputs:
    #   Prints IP to stdout (may be empty).
    #
    # Returns:
    #   0 always (command failures may result in empty output).
  td_get_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }

# --- Argument & Environment Helpers-----------------------------------------------
  # td_is_set
    # Purpose:
    #   Test whether a variable name is set/defined in the shell.
    #
    # Arguments:
    #   $1  Variable name.
    #
    # Returns:
    #   0 if defined; non-zero otherwise.
  td_is_set(){ [[ -v "$1" ]]; }

  # td_default
    # Purpose:
    #   Set a variable to a default value if it is unset or empty.
    #
    # Arguments:
    #   $1  Variable name.
    #   $2  Default value expression.
    #
    # Behavior:
    #   - Uses eval: VAR=${VAR:-DEFAULT}.
    #
    # Returns:
    #   0 always.
    #
    # Notes:
    #   - Because this uses eval, callers must ensure $1 and $2 are trusted.
  td_default(){ eval "${1}=\${${1}:-$2}"; }

  # td_is_number
    # Purpose:
    #   Test whether a value contains only digits (0-9).
    #
    # Arguments:
    #   $1  Value to test.
    #
    # Returns:
    #   0 if digits-only; non-zero otherwise.
  td_is_number(){ [[ "$1" =~ ^[0-9]+$ ]]; }

  # td_is_bool
    # Purpose:
    #   Test whether a value is a common boolean-like token.
    #
    # Arguments:
    #   $1  Token to test.
    #
    # Returns:
    #   0 if matches (true|false|yes|no|on|off|1|0); non-zero otherwise.
  td_is_bool(){ [[ "$1" =~ ^(true|false|yes|no|on|off|1|0)$ ]]; }

  # td_array_has_items
    # Purpose:
    #   Test whether a named array variable exists and contains at least one element.
    #
    # Arguments:
    #   $1  Array variable name.
    #
    # Returns:
    #   0 if array exists and length > 0; non-zero otherwise.
    #
    # Requires:
    #   bash 4.3+ (nameref).
  td_array_has_items(){
    declare -p "$1" &>/dev/null || return 1
    local -n _arr="$1"
    (( ${#_arr[@]} > 0 ))
  }

  # td_is_true
      # Purpose:
      #   Test whether a value represents "true" (case-insensitive).
      #
      # Arguments:
      #   $1  Token to test.
      #
      # Returns:
      #   0 if token is one of: y, yes, 1, true; non-zero otherwise.
  td_is_true() {
    case "${1,,}" in
        y|yes|1|true) return 0 ;;
        *)            return 1 ;;
    esac
  }

# --- Process & State Helpers -----------------------------------------------------
  # td_proc_exists
    # Purpose:
    #   Test whether a process with an exact name is running.
    #
    # Arguments:
    #   $1  Process name (exact match; pgrep -x).
    #
    # Returns:
    #   0 if found; non-zero otherwise.
  td_proc_exists(){ pgrep -x "$1" &>/dev/null; }

   # td_wait_for_exit
    # Purpose:
    #   Block until a named process is no longer running.
    #
    # Arguments:
    #   $1  Process name.
    #
    # Behavior:
    #   - Polls every 0.5 seconds.
    #
    # Returns:
    #   0 always (terminates when process is gone).
  td_wait_for_exit(){ while td_proc_exists "$1"; do sleep 0.5; done; }

  # td_kill_if_running
    # Purpose:
    #   Terminate all processes with an exact name if running.
    #
    # Arguments:
    #   $1  Process name (exact match; pkill -x).
    #
    # Returns:
    #   0 always (pkill failures suppressed).
  td_kill_if_running(){ pkill -x "$1" &>/dev/null || true; }

  # td_caller_id
    # Purpose:
    #   Return a compact caller identifier string: "file:line (function)".
    #
    # Arguments:
    #   $1  Stack depth (default: 1 = direct caller of td_caller_id).
    #
    # Outputs:
    #   Prints identifier to stdout.
    #
    # Returns:
    #   0 always.
    #
    # Notes:
    #   - Uses BASH_SOURCE/FUNCNAME/BASH_LINENO.
  td_caller_id() {
      local depth="${1:-1}"

      local file="${BASH_SOURCE[$depth]}"
      local func="${FUNCNAME[$depth]}"
      local line="${BASH_LINENO[$((depth-1))]}"

      printf '%s:%s (%s)' "${file##*/}" "$line" "$func"
  }
  
  # td_stack_trace
      # Purpose:
      #   Print a stack trace (most-recent call first, excluding this function).
      #
      # Outputs:
      #   Prints stack trace lines to stdout.
      #
      # Returns:
      #   0 always.
  td_stack_trace() {
      local i
      for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
          printf '  at %s:%s (%s)\n' \
              "${BASH_SOURCE[$i]##*/}" \
              "${BASH_LINENO[$((i-1))]}" \
              "${FUNCNAME[$i]}"
      done
  }
# --- Version & OS Helpers --------------------------------------------------------
  # td_get_os
    # Purpose:
    #   Return OS ID from /etc/os-release (e.g., ubuntu, debian).
    #
    # Outputs:
    #   Prints ID value to stdout.
    #
    # Returns:
    #   0 on success; non-zero if /etc/os-release is missing/unreadable.
  td_get_os(){ grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # td_get_os_version
    # Purpose:
    #   Return OS VERSION_ID from /etc/os-release.
    #
    # Outputs:
    #   Prints VERSION_ID to stdout.
    #
    # Returns:
    #   0 on success; non-zero if /etc/os-release is missing/unreadable.
  td_get_os_version(){ grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' ; }

  # td_version_ge
      # Purpose:
      #   Compare two version strings using sort -V (A >= B).
      #
      # Arguments:
      #   $1  Version A.
      #   $2  Version B.
      #
      # Returns:
      #   0 if A >= B; 1 otherwise.
  td_version_ge(){ [[ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# --- Misc Utilities --------------------------------------------------------------
  # td_timestamp
      # Purpose:
      #   Return current local timestamp in "YYYY-MM-DD HH:MM:SS".
      #
      # Outputs:
      #   Prints timestamp to stdout.
      #
      # Returns:
      #   0 always.
  td_timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }

  # td_retry
    # Purpose:
    #   Retry a command up to N times with a delay between attempts.
    #
    # Arguments:
    #   $1  N attempts (integer >= 1).
    #   $2  Delay in seconds between attempts.
    #   $@  Command to execute (after shifting N and delay).
    #
    # Returns:
    #   0 if the command succeeds within N attempts; 1 otherwise.
  td_retry(){
    local n="$1" d="$2"; shift 2
    local i
    for ((i=1;i<=n;i++)); do
      "$@" && return 0
      (( i < n )) && sleep "$d"
    done
    return 1
  }

  # td_join
    # Purpose:
    #   Join arguments into a single string using a separator.
    #
    # Arguments:
    #   $1  Separator string (assigned to IFS).
    #   $@  Items to join.
    #
    # Outputs:
    #   Prints joined string to stdout (with echo).
    #
    # Returns:
    #   0 always.
    #
    # Notes:
    #   - Uses echo "$*"; this preserves spaces via IFS join semantics.
    #   - Not safe for binary data; intended for display/logging.
  td_join(){ local IFS="$1"; shift; echo "$*"; }
  
  # td_array_union
    # Purpose:
    #   Build a stable union of one or more source arrays into a destination array.
    #
    # Arguments:
    #   $1  DEST_ARRAY name (will be overwritten).
    #   $@  One or more SRC_ARRAY names.
    #
    # Behavior:
    #   - Preserves order (SRC1 first, then SRC2, ...).
    #   - Removes duplicates.
    #   - Ignores empty items.
    #   - Skips non-existent source arrays silently.
    #
    # Outputs (globals):
    #   Writes the destination array via nameref.
    #
    # Returns:
    #   0 on success; 1 on invalid args.
    #
    # Requires:
    #   bash 4.3+ (nameref) and associative arrays.
  td_array_union() {
      local dest_name="$1"
      shift || true

      [[ -n "${dest_name:-}" && $# -ge 1 ]] || return 1

      local -n __dest="$dest_name"
      local -A __seen=()
      __dest=()

      local src_name
      local item

      for src_name in "$@"; do
          [[ -n "${src_name:-}" ]] || continue

          # If source array doesn't exist, skip it quietly
          declare -p "$src_name" >/dev/null 2>&1 || continue

          local -n __src="$src_name"
          for item in "${__src[@]:-}"; do
              [[ -n "${item:-}" ]] || continue
              if [[ -z "${__seen[$item]+x}" ]]; then
                  __dest+=( "$item" )
                  __seen["$item"]=1
              fi
          done
      done

      return 0
  }

# --- Text functions --------------------------------------------------------------
  # td_trim
      # Purpose:
      #   Trim leading and trailing whitespace from a string.
      #
      # Arguments:
      #   $@  String tokens (treated as a single string).
      #
      # Outputs:
      #   Prints trimmed string to stdout.
      #
      # Returns:
      #   0 always.
  td_trim(){ local v="${*:-}"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }

  # td_string_repeat
      # Purpose:
      #   Repeat a string N times.
      #
      # Arguments:
      #   $1  String to repeat (default: single space).
      #   $2  Repeat count (default: 0).
      #
      # Outputs:
      #   Prints repeated string to stdout.
      #
      # Returns:
      #   0 always.
  td_string_repeat() {
      local s="${1- }"
      local n="${2-0}"

      local out=""
      local i=0

      (( n > 0 )) || { printf '%s' ""; return 0; }

      for (( i=0; i<n; i++ )); do
          out+="$s"
      done

      printf '%s' "$out"
  }

  # td_fill_left
      # Purpose:
      #   Left-pad a string to a given total length using a fill character.
      #
      # Arguments:
      #   $1  Source string.
      #   $2  Total width (default: 20).
      #   $3  Fill character/string (default: space).
      #
      # Outputs:
      #   Prints padded string to stdout.
      #
      # Returns:
      #   0 always.
  td_fill_left() {
      local source="${1-}"
      local maxlength="${2-20}"
      local char="${3- }"

      local padcount=$(( maxlength - ${#source} ))
      (( padcount > 0 )) || { printf '%s' "$source"; return 0; }

      local pad
      pad="$(td_string_repeat "$char" "$padcount")"

      printf '%s%s' "$pad" "$source"
  }

  # td_fill_right
    # Purpose:
    #   Right-pad a string to a given total length using a fill character.
    #
    # Arguments:
    #   $1  Source string.
    #   $2  Total width (default: 20).
    #   $3  Fill character/string (default: space).
    #
    # Outputs:
    #   Prints padded string to stdout.
    #
    # Returns:
    #   0 always.
  td_fill_right() {
      local source="${1-}"
      local maxlength="${2-20}"
      local char="${3- }"

      local padcount=$(( maxlength - ${#source} ))
      (( padcount > 0 )) || { printf '%s' "$source"; return 0; }

      local pad
      pad="$(td_string_repeat "$char" "$padcount")"

      printf '%s%s' "$source" "$pad"
  }

  # td_fill_center
    # Purpose:
    #   Center-pad a string to a given total length using a fill character.
    #
    # Arguments:
    #   $1  Source string.
    #   $2  Total width (default: 20).
    #   $3  Fill character/string (default: space).
    #
    # Outputs:
    #   Prints padded string to stdout.
    #
    # Returns:
    #   0 always.
  td_fill_center() {
      local source="${1-}"
      local maxlength="${2-20}"
      local char="${3- }"

      local padcount=$(( maxlength - ${#source} ))
      (( padcount > 0 )) || { printf '%s' "$source"; return 0; }

      local left=$(( padcount / 2 ))
      local right=$(( padcount - left ))

      local pad_left pad_right
      pad_left="$(td_string_repeat "$char" "$left")"
      pad_right="$(td_string_repeat "$char" "$right")"

      printf '%s%s%s' "$pad_left" "$source" "$pad_right"
  }

  # td_wrap_words
      # Purpose:
      #   Word-wrap a text string to a given width.
      #
      # Arguments:
      #   --width N   Wrap width (default: 80).
      #   --text STR  Text to wrap.
      #
      # Outputs:
      #   Prints wrapped lines to stdout.
      #
      # Returns:
      #   0 on success (or if text empty)
      #   2 on invalid arguments.
      #
      # Notes:
      #   - Collapses whitespace for wrapping by splitting on whitespace.
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

# --- Error handlers --------------------------------------------------------------
  # td_die
    # Purpose:
    #   Terminate the process with an error message and rc.
    #
    # Arguments:
    #   $1  Message (optional; defaults to "Fatal error").
    #   $2  Exit code (optional; default: 1).
    #
    # Inputs (globals):
    #   FLAG_VERBOSE (optional)
    #
    # Behavior:
    #   - If FLAG_VERBOSE is non-zero: includes td_stack_trace output.
    #   - Otherwise includes td_caller_id (depth=2).
    #   - Calls sayfail then exits with rc.
    #
    # Outputs:
    #   Uses sayfail. Exits process.
    #
    # Returns:
    #   Does not return.
  td_die() {
      local msg="${1-}"
      local rc="${2-1}"

      local ci=""
      if (( ${FLAG_VERBOSE:-0} )); then
          # td_stack_trace should PRINT the trace to stdout
          ci="$(td_stack_trace)"
      else
          ci="$(td_caller_id 2)"
      fi

      sayfail "$rc ${msg:-Fatal error} ($ci)"
      exit "$rc"
  }

  # td_require
    # Purpose:
    #   Run a command; on failure print a diagnostic and return the command rc.
    #
    # Arguments:
    #   $@  Command and args.
    #
    # Behavior:
    #   - Executes "$@".
    #   - If rc != 0: prints sayfail including caller id.
    #
    # Returns:
    #   The command's exit code.
  td_require() {
      "$@"
      local rc=$?

      if (( rc != 0 )); then
          # script -> td_require -> td_caller_id
          sayfail "Command failed (rc=$rc): $* ($(td_caller_id 2))"
      fi

      return "$rc"
  }

  # td_must
    # Purpose:
    #   Run a command; on failure terminate via td_die.
    #
    # Arguments:
    #   $@  Command and args.
    #
    # Behavior:
    #   - Executes "$@".
    #   - If rc != 0: calls td_die with a fatal message and rc.
    #
    # Returns:
    #   0 if command succeeds; does not return on failure.
  td_must() {
      "$@"
      local rc=$?

      (( rc == 0 )) && return 0

      # Do NOT add caller-id here; td_die will do that (and optional stack trace)
      td_die "Fatal: $* (rc=$rc)" "$rc"
  }

# --- Argument & Environment Validators -------------------------------------------
  # td_validate_int
    # Purpose:
    #   Validate whether a value is an integer (optional leading +/-).
    #
    # Arguments:
    #   $1  Value to test.
    #
    # Returns:
    #   0 if valid integer; non-zero otherwise.
  td_validate_int(){
    [[ "$1" =~ ^[+-]?[0-9]+$ ]]
  }

  # td_validate_decimal
    # Purpose:
    #   Validate whether a value is a decimal number (int or int.frac, optional leading +/-).
    #
    # Arguments:
    #   $1  Value to test.
    #
    # Returns:
    #   0 if valid decimal; non-zero otherwise.
  td_validate_decimal(){
    [[ "$1" =~ ^[+-]?[0-9]+(\.[0-9]+)?$ ]]
  }

  # td_validate_ipv4
    # Purpose:
    #   Validate whether a value is a syntactically valid IPv4 address.
    #
    # Arguments:
    #   $1  IP string.
    #
    # Behavior:
    #   - Splits on '.' and requires 4 octets.
    #   - Each octet must be digits and within 0..255.
    #
    # Returns:
    #   0 if valid; 1 otherwise.
  td_validate_ipv4(){
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
    # Purpose:
    #   Validate whether a value is a single-char Y/y/N/n token.
    #
    # Arguments:
    #   $1  Value to test.
    #
    # Returns:
    #   0 if matches ^[YyNn]$; non-zero otherwise.
  td_validate_yesno(){
    [[ "$1" =~ ^[YyNn]$ ]]
  }

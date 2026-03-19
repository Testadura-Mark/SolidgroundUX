# ==================================================================================
# Testadura Consultancy — SolidGround Core Library
# ----------------------------------------------------------------------------------
# Module  : core.sh
# Purpose : Foundational helpers and shared primitives used across SolidGround
#           scripts and modules.
#
# Scope   :
#   - Lightweight, dependency-free utilities
#   - Safe shell abstractions (validation, guards, common patterns)
#   - Internal helpers not tied to UI or application state
#
# Design  :
#   - Functions are intentionally small and composable
#   - No side effects unless explicitly documented
#   - Suitable for sourcing in any SolidGround-compatible script
#
# Notes   :
#   - This module forms part of the SolidGround runtime layer
#   - Keep dependencies minimal to avoid bootstrap coupling
#
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================
set -uo pipefail
# --- Library guard ---------------------------------------------------------------
    # __td_lib_guard
        # Purpose:
        #   Ensure the file is sourced as a library and only initialized once.
        #
        # Behavior:
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution if the file is executed instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Skips initialization if the library was already loaded.
        #
        # Inputs:
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals):
        #   TD_<MODULE>_LOADED
        #
        # Returns:
        #   0 if already loaded or successfully initialized.
        #   Exits with code 2 if executed instead of sourced.
        #
        # Usage:
        #   __td_lib_guard
        #
        # Examples:
        #   # Typical usage at top of library file
        #   __td_lib_guard
        #   unset -f __td_lib_guard
        #
        # Notes:
        #   - Guard variable is derived dynamically (e.g. ui-glyphs.sh → TD_UI_GLYPHS_LOADED).
        #   - Safe under `set -u` due to indirect expansion with default.
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
        #   Require the script to run as root, re-executing through sudo when needed.
        #
        # Behavior:
        #   - Detects whether the current process already runs with effective UID 0.
        #   - If not root and TD_ALREADY_ROOT is unset, re-executes the current script via sudo.
        #   - Preserves selected environment variables across the sudo boundary.
        #   - Uses TD_ALREADY_ROOT as a loop guard to prevent repeated elevation attempts.
        #
        # Arguments:
        #   $@  ARGS
        #       Original script arguments forwarded to the re-exec call.
        #
        # Inputs (globals):
        #   TD_ALREADY_ROOT
        #   TD_FRAMEWORK_ROOT
        #   TD_APPLICATION_ROOT
        #   PATH
        #
        # Side effects:
        #   - May replace the current process via exec sudo.
        #   - Writes informational/debug output through sayinfo/saydebug.
        #
        # Returns:
        #   0 when already running as root and execution may continue.
        #   Does not return when re-exec succeeds.
        #
        # Usage:
        #   td_need_root "$@"
        #
        # Examples:
        #   td_need_root "$@"
        #
        #   td_need_root "$@" || exit 1
        #
        # Notes:
        #   - Intended as a guard near the top of privileged scripts.
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
        #   Test whether a file can be appended to, or created for later appending.
        #
        # Behavior:
        #   - If the target file exists, requires it to be a writable regular file.
        #   - If the target file does not exist, checks whether the parent directory is writable.
        #   - If the parent directory does not exist, attempts to create it with mkdir -p.
        #   - Does not create the target file itself.
        #
        # Arguments:
        #   $1  FILE
        #       File path to test.
        #
        # Side effects:
        #   - May create the parent directory path using mkdir -p.
        #
        # Returns:
        #   0 if the file is appendable or creatable for append.
        #   1 otherwise.
        #
        # Usage:
        #   td_can_append FILE
        #
        # Examples:
        #   if td_can_append "$TD_LOG_PATH"; then
        #       printf 'log target ok\n'
        #   fi
        #
        #   td_can_append "/var/log/testadura/app.log" || return 1
        #
        # Notes:
        #   - Does not verify available disk space or future write success.
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
        #   Ensure a directory exists and is suitable for user-scoped writing.
        #
        # Behavior:
        #   - Validates that a directory argument was supplied.
        #   - Creates the directory path when missing.
        #   - When running via sudo and the directory was newly created, attempts to chown it to SUDO_USER and that user's primary group.
        #   - Verifies that the directory exists before returning success.
        #
        # Arguments:
        #   $1  DIR
        #       Directory path to ensure.
        #
        # Inputs (globals):
        #   SUDO_USER
        #
        # Side effects:
        #   - May create directories with mkdir -p.
        #   - May change ownership with chown.
        #
        # Returns:
        #   0 on success.
        #   2 if DIR is missing or empty.
        #   3 if mkdir -p fails.
        #   4 if the directory still does not exist afterward.
        #
        # Usage:
        #   td_ensure_writable_dir DIR
        #
        # Examples:
        #   td_ensure_writable_dir "$TD_USRCFG_DIR" || return 1
        #
        #   td_ensure_writable_dir "$(td_real_home)/.config/testadura"
        #
        # Notes:
        #   - Ownership correction is only attempted for newly created directories.
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
    td_mktemp_file(){ TMPDIR=${TMPDIR:-/tmp} mktemp "${TMPDIR%/}/XXXXXX"; }

    # td_slugify
        # Purpose:
        #   Convert arbitrary text into a lowercase, filename-safe slug.
        #
        # Behavior:
        #   - Lowercases the input text.
        #   - Replaces whitespace runs with a single dash.
        #   - Removes characters outside [a-z0-9-_.].
        #   - Collapses repeated dashes and trims leading/trailing dashes.
        #   - Falls back to "hub" when the resulting slug would otherwise be empty.
        #
        # Arguments:
        #   $1  TEXT
        #       Source text to normalize.
        #
        # Output:
        #   Prints the slug to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_slugify TEXT
        #
        # Examples:
        #   td_slugify "Some Title!!"
        #
        #   slug="$(td_slugify "$menu_title")"
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
        #   Compute and print the SHA-256 hash of a readable file.
        #
        # Behavior:
        #   - Validates that the target file is readable.
        #   - Uses sha256sum when available.
        #   - Falls back to shasum -a 256 when sha256sum is unavailable.
        #   - Prints only the hexadecimal hash value, not the filename.
        #
        # Arguments:
        #   $1  FILE
        #       File path to hash.
        #
        # Output:
        #   Prints the SHA-256 hash to stdout.
        #
        # Returns:
        #   0 on success.
        #   2 if FILE is not readable.
        #   3 if the hashing tool fails.
        #   127 if no supported hashing tool is available.
        #
        # Usage:
        #   td_hash_sha256_file FILE
        #
        # Examples:
        #   hash="$(td_hash_sha256_file "$archive")" || return 1
        #
        #   td_hash_sha256_file "./release.tar.gz"
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
        #   Assign a default value to a variable when it is unset or empty.
        #
        # Behavior:
        #   - Uses shell parameter expansion in an eval expression.
        #   - Leaves the variable unchanged when it already has a non-empty value.
        #   - Assigns the supplied default expression otherwise.
        #
        # Arguments:
        #   $1  VAR_NAME
        #       Variable name to initialize.
        #   $2  DEFAULT
        #       Default value expression.
        #
        # Side effects:
        #   - Sets the target variable in the current shell.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_default VAR_NAME DEFAULT
        #
        # Examples:
        #   td_default TD_UI_STYLE "default"
        #
        #   td_default FLAG_VERBOSE "0"
        #
        # Notes:
        #   - Uses eval, so both arguments must be trusted.
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

    # td_real_user
        # Purpose:
        #   Resolve the real invoking user, even when the current process runs under sudo.
        #
        # Behavior:
        #   - Returns SUDO_USER when it is set and not equal to root.
        #   - Otherwise returns the current effective username via id -un.
        #
        # Inputs (globals):
        #   SUDO_USER
        #
        # Output:
        #   Prints the resolved username to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_real_user
        #
        # Examples:
        #   user="$(td_real_user)"
        #
        #   printf 'real user: %s\n' "$(td_real_user)"
    td_real_user() {
        if [[ -n "${SUDO_USER-}" && "${SUDO_USER}" != "root" ]]; then
            printf '%s\n' "${SUDO_USER}"
        else
            id -un
        fi
    }

    # td_real_home
        # Purpose:
        #   Resolve the home directory of the real invoking user.
        #
        # Behavior:
        #   - Determines the effective invoking user through td_real_user().
        #   - Looks up that user in the system account database using getent passwd.
        #   - Prints the home directory field from the passwd entry.
        #
        # Output:
        #   Prints the absolute home directory path to stdout.
        #
        # Returns:
        #   0 on success.
        #   Non-zero if the user lookup fails.
        #
        # Usage:
        #   td_real_home
        #
        # Examples:
        #   home_dir="$(td_real_home)"
        #
        #   td_ensure_writable_dir "$(td_real_home)/workspace"
        #
        # Notes:
        #   - Avoids relying on HOME, which may point to /root under sudo.
    td_real_home() {
        local user
        user="$(td_real_user)"
        getent passwd "${user}" | cut -d: -f6
    }

    # td_run_as_real_user
        # Purpose:
        #   Execute a command as the invoking non-root user when currently running as root.
        #
        # Behavior:
        #   - Resolves the real user via td_real_user().
        #   - If the current process runs as root and the real user is not root, executes the command through sudo -u <user> -H.
        #   - Otherwise executes the command directly in the current context.
        #
        # Arguments:
        #   $@  COMMAND
        #       Command and arguments to execute.
        #
        # Side effects:
        #   - May launch a subprocess under a different user context.
        #
        # Returns:
        #   Returns the exit status of the executed command.
        #
        # Usage:
        #   td_run_as_real_user COMMAND [ARG ...]
        #
        # Examples:
        #   td_run_as_real_user mkdir -p "$(td_real_home)/workspace"
        #
        #   td_run_as_real_user cp template.txt "$target_dir/"
        #
        # Notes:
        #   - The -H flag ensures HOME is set correctly for the target user.
    td_run_as_real_user() {
        local user
        user="$(td_real_user)"

        if (( EUID == 0 )) && [[ "${user}" != "root" ]]; then
            sudo -u "${user}" -H -- "$@"
        else
            "$@"
        fi
    }

    # td_fix_ownership
        # Purpose:
        #   Recursively change ownership of a path to the real invoking user.
        #
        # Behavior:
        #   - Resolves the real user via td_real_user().
        #   - Resolves that user's primary group via id -gn.
        #   - Applies chown -R to the requested path.
        #
        # Arguments:
        #   $1  PATH
        #       Path whose ownership should be corrected.
        #
        # Side effects:
        #   - Recursively changes ownership on disk.
        #
        # Returns:
        #   0 on success.
        #   Non-zero if chown fails.
        #
        # Usage:
        #   td_fix_ownership PATH
        #
        # Examples:
        #   td_fix_ownership "$workspace_dir"
        #
        #   td_fix_ownership "$(td_real_home)/.config/testadura"
    td_fix_ownership() {
        local path="$1"
        local user group
        user="$(td_real_user)"
        group="$(id -gn "${user}")"

        chown -R "${user}:${group}" "${path}"
    }
  
    # td_fix_permissions
        # Purpose:
        #   Normalize directory and file permissions under a path.
        #
        # Behavior:
        #   - Sets directories to mode 755.
        #   - Sets regular files to mode 644.
        #   - Processes the target path recursively using find.
        #
        # Arguments:
        #   $1  PATH
        #       Root path whose permissions should be normalized.
        #
        # Side effects:
        #   - Recursively changes file and directory permissions on disk.
        #
        # Returns:
        #   0 on success.
        #   Non-zero if any chmod operation fails.
        #
        # Usage:
        #   td_fix_permissions PATH
        #
        # Examples:
        #   td_fix_permissions "$publish_root"
        #
        #   td_fix_permissions "./target-root"
        #
        # Notes:
        #   - Executable bits are not preserved for regular files.
    td_fix_permissions() {
        local path="$1"

        # Directories: 755, files: 644 (tweak if you want executable scripts kept executable)
        find "${path}" -type d -exec chmod 755 {} +
        find "${path}" -type f -exec chmod 644 {} +
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
        #   Build a compact caller identifier string for diagnostics.
        #
        # Behavior:
        #   - Reads file, function, and line information from the Bash call stack.
        #   - Uses the requested stack depth to select the caller frame.
        #   - Formats the result as: file:line (function)
        #
        # Arguments:
        #   $1  DEPTH
        #       Optional stack depth.
        #       Default: 1
        #
        # Output:
        #   Prints the caller identifier to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_caller_id [DEPTH]
        #
        # Examples:
        #   td_caller_id
        #
        #   saydebug "Called from $(td_caller_id 2)"
    td_caller_id() {
        local depth="${1:-1}"

        local file="${BASH_SOURCE[$depth]}"
        local func="${FUNCNAME[$depth]}"
        local line="${BASH_LINENO[$((depth-1))]}"

        printf '%s:%s (%s)' "${file##*/}" "$line" "$func"
    }
  
    # td_stack_trace
        # Purpose:
        #   Print a simple stack trace with the most recent caller first.
        #
        # Behavior:
        #   - Iterates over the Bash call stack arrays.
        #   - Skips the td_stack_trace frame itself.
        #   - Prints one formatted line per caller frame.
        #
        # Output:
        #   Prints stack trace lines to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_stack_trace
        #
        # Examples:
        #   td_stack_trace
    td_stack_trace() {
        local i
        for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
            printf '  at %s:%s (%s)\n' \
                "${BASH_SOURCE[$i]##*/}" \
                "${BASH_LINENO[$((i-1))]}" \
                "${FUNCNAME[$i]}"
        done
    }

    # td_has_tty
        # Purpose:
        #   Test whether /dev/tty is available for reading and writing.
        #
        # Returns:
        #   0 if /dev/tty is readable and writable.
        #   1 otherwise.
        #
        # Usage:
        #   td_has_tty
        #
        # Examples:
        #   td_has_tty || return 1
    td_has_tty() {
        [[ -r /dev/tty && -w /dev/tty ]]
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

    # td_visible_length
        # Purpose:
        #   Measure the visible character length of a string, ignoring ANSI escape sequences.
        #
        # Behavior:
        #   - Strips ANSI SGR-style escape codes from the input text.
        #   - Counts the remaining visible characters.
        #
        # Arguments:
        #   $1  TEXT
        #       Text whose visible width should be measured.
        #
        # Output:
        #   Prints the visible character count to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_visible_length TEXT
        #
        # Examples:
        #   td_visible_length "$colored_text"
    td_visible_length() {
        local text="${1-}"

        text="$(printf '%s' "$text" | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g')"
        printf '%s' "$text" | wc -m
    }

    # td_terminal_width
        # Purpose:
        #   Determine the effective terminal render width within configured limits.
        #
        # Behavior:
        #   - Reads the terminal width through tput cols when available.
        #   - Falls back to 80 columns on failure.
        #   - Caps the width at SGND_MAX_RENDER_WIDTH.
        #   - Enforces a minimum width of 40.
        #
        # Inputs (globals):
        #   SGND_MAX_RENDER_WIDTH
        #
        # Output:
        #   Prints the effective terminal width to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_terminal_width
        #
        # Examples:
        #   render_width="$(td_terminal_width)"
    td_terminal_width() {
        local term_width=80
        local max_render_width="${SGND_MAX_RENDER_WIDTH:-140}"

        if command -v tput >/dev/null 2>&1; then
            term_width="$(tput cols 2>/dev/null || printf '80')"
        fi
        [[ "$term_width" =~ ^[0-9]+$ ]] || term_width=80

        (( term_width > max_render_width )) && term_width="$max_render_width"
        (( term_width < 40 )) && term_width=40

        printf '%s\n' "$term_width"
    }

    # td_padded_visible
        # Purpose:
        #   Pad a string to a target visible width while accounting for ANSI escape sequences.
        #
        # Behavior:
        #   - Measures visible length through td_visible_length().
        #   - Appends the required number of trailing spaces.
        #   - Never truncates the input text.
        #
        # Arguments:
        #   $1  TEXT
        #       Text to pad.
        #   $2  WIDTH
        #       Target visible width.
        #
        # Output:
        #   Prints the padded string to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_padded_visible TEXT WIDTH
        #
        # Examples:
        #   td_padded_visible "$label" 20
    td_padded_visible() {
        local text="${1-}"
        local width="${2:-0}"
        local visible_len=0
        local pad_len=0

        visible_len="$(td_visible_length "$text")"
        pad_len=$(( width - visible_len ))
        (( pad_len < 0 )) && pad_len=0

        printf '%s%*s' "$text" "$pad_len" ""
    }

    # td_wrap_words
        # Purpose:
        #   Wrap a text string to a fixed width on word boundaries.
        #
        # Behavior:
        #   - Accepts --width and --text named arguments.
        #   - Splits the input text on collapsed whitespace.
        #   - Builds output lines without exceeding the requested width where possible.
        #   - Prints each wrapped line separately.
        #
        # Arguments:
        #   --width N
        #       Wrap width. Default: 80
        #   --text STR
        #       Text to wrap.
        #
        # Output:
        #   Prints wrapped text to stdout.
        #
        # Returns:
        #   0 on success, including empty text.
        #   2 on invalid arguments.
        #
        # Usage:
        #   td_wrap_words --width N --text STR
        #
        # Examples:
        #   td_wrap_words --width 60 --text "$long_text"
        #
        #   td_wrap_words --width "$render_width" --text "This is a wrapped sentence."
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
        #   Terminate the script with a formatted fatal error message.
        #
        # Behavior:
        #   - Uses the supplied message and exit code, or defaults when omitted.
        #   - When FLAG_VERBOSE is non-zero, prints a stack trace.
        #   - Otherwise appends a compact caller identifier.
        #   - Exits the process with the requested return code.
        #
        # Arguments:
        #   $1  MESSAGE
        #       Optional fatal error message.
        #   $2  RC
        #       Optional exit code. Default: 1
        #
        # Inputs (globals):
        #   FLAG_VERBOSE
        #
        # Side effects:
        #   - Writes failure output through sayfail.
        #   - May print a stack trace.
        #   - Terminates the current process.
        #
        # Returns:
        #   Does not return.
        #
        # Usage:
        #   td_die [MESSAGE] [RC]
        #
        # Examples:
        #   td_die "Configuration invalid"
        #
        #   td_die "Unable to continue" 2
    td_die() {
      local msg="${1-}"
      local rc="${2-1}"

      local ci=""
      if (( ${FLAG_VERBOSE:-0} )); then
          sayfail "$rc ${msg:-Fatal error}"
          td_stack_trace
      else
          sayfail "$rc ${msg:-Fatal error} ($(td_caller_id 2))"
      fi
      exit "$rc"
    }

    # td_require
        # Purpose:
        #   Execute a command and report failure without terminating the script.
        #
        # Behavior:
        #   - Runs the supplied command.
        #   - Captures its return code.
        #   - When the command fails, emits a diagnostic including the caller location.
        #   - Returns the original command exit code unchanged.
        #
        # Arguments:
        #   $@  COMMAND
        #       Command and arguments to execute.
        #
        # Side effects:
        #   - May write failure output through sayfail.
        #
        # Returns:
        #   Returns the executed command's exit code.
        #
        # Usage:
        #   td_require COMMAND [ARG ...]
        #
        # Examples:
        #   td_require cp "$src" "$dst" || return 1
        #
        #   td_require systemctl restart ssh
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
        #   Execute a command and terminate the script when it fails.
        #
        # Behavior:
        #   - Runs the supplied command.
        #   - Returns immediately when the command succeeds.
        #   - On failure, delegates to td_die with the original exit code.
        #
        # Arguments:
        #   $@  COMMAND
        #       Command and arguments to execute.
        #
        # Side effects:
        #   - May terminate the current process through td_die.
        #
        # Returns:
        #   0 if the command succeeds.
        #   Does not return on failure.
        #
        # Usage:
        #   td_must COMMAND [ARG ...]
        #
        # Examples:
        #   td_must mkdir -p "$target_dir"
        #
        #   td_must cp "$source" "$target"
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
          #   Validate whether a string is a syntactically valid IPv4 address.
          #
          # Behavior:
          #   - Splits the input on dots into four octets.
          #   - Requires exactly four octets.
          #   - Requires each octet to contain only digits.
          #   - Requires each octet value to be in the range 0..255.
          #
          # Arguments:
          #   $1  IP
          #       Candidate IPv4 address.
          #
          # Returns:
          #   0 if IP is valid.
          #   1 otherwise.
          #
          # Usage:
          #   td_validate_ipv4 IP
          #
          # Examples:
          #   if td_validate_ipv4 "$server_ip"; then
          #       printf 'ok\n'
          #   fi
          #
          #   td_validate_ipv4 "192.168.1.10"
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

# ==================================================================================
# Testadura Consultancy — SolidGround Configuration Library
# ----------------------------------------------------------------------------------
# Module  : cfg.sh
# Purpose : Lightweight KEY=VALUE configuration and state file handling.
#
# Scope   :
#   - Load, read, write, and remove configuration entries
#   - Support for application config, user config, and state files
#   - Minimal parsing without external dependencies
#
# Design  :
#   - Simple, predictable file format (KEY=VALUE)
#   - No implicit transformations (values treated as literal)
#   - Safe updates with minimal file mutation
#
# Notes   :
#   - Used by both runtime configuration and persisted state
#   - Complements environment-based configuration
#
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ==================================================================================
set -uo pipefail
# --- Library guard ----------------------------------------------------------------
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

# --- Internal: file and value manipulation ----------------------------------------
    # - Ignores empty lines and comments
    # - Accepts only names: [A-Za-z_][A-Za-z0-9_]*
    # - Loads via printf -v assignment (value preserved as-is)

    # __td_is_ident
        # Purpose:
        #   Test whether a string is a valid shell identifier.
        #
        # Behavior:
        #   - Validates the input against shell variable naming rules.
        #   - Accepts names starting with a letter or underscore.
        #   - Allows alphanumeric characters and underscores thereafter.
        #
        # Arguments:
        #   $1  NAME
        #       Candidate identifier.
        #
        # Returns:
        #   0 if NAME is a valid identifier.
        #   1 otherwise.
        #
        # Usage:
        #   __td_is_ident NAME
        #
        # Examples:
        #   if __td_is_ident "APP_TITLE"; then
        #       printf 'valid\n'
        #   fi
    __td_is_ident() {
            [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
        }
   
    # __td_kv_load_file
        # Purpose:
        #   Load KEY=VALUE pairs from a file into shell variables.
        #
        # Behavior:
        #   - Reads plain KEY=VALUE lines from the target file.
        #   - Ignores blank lines and comment lines.
        #   - Validates keys as shell identifiers.
        #   - Assigns values literally without unquoting or escape processing.
        #
        # Arguments:
        #   $1  FILE
        #       Path to the KEY=VALUE file.
        #
        # Outputs (globals):
        #   Sets variables defined in the file.
        #
        # Side effects:
        #   - May emit warnings for invalid keys.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   __td_kv_load_file FILE
        #
        # Examples:
        #   __td_kv_load_file "$TD_CFG_FILE"
        #
        #   [[ -r "$file" ]] && __td_kv_load_file "$file"
    __td_kv_load_file() {
        local file="$1"
        [[ -f "$file" ]] || return 0

        local line key val
        while IFS= read -r line || [[ -n "$line" ]]; do
            # strip leading/trailing whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"

            # skip blanks / comments
            [[ -z "$line" ]] && continue
            [[ "$line" == \#* ]] && continue

            # accept KEY=VALUE only
            [[ "$line" == *"="* ]] || continue

            key="${line%%=*}"
            val="${line#*=}"

            # trim whitespace around key only
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"

            # validate key name
            if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                continue
            fi

            # If value starts with a space, keep it; we store exactly after '='.
            printf -v "$key" '%s' "$val"
        done < "$file"
    }

    # __td_kv_set
        # Purpose:
        #   Write or update a KEY=VALUE entry in a file.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Replaces an existing KEY=VALUE entry when present.
        #   - Appends a new entry when the key does not exist.
        #   - Preserves the rest of the file content.
        #
        # Arguments:
        #   $1  FILE
        #       Path to the KEY=VALUE file.
        #   $2  KEY
        #       Key to write.
        #   $3  VALUE
        #       Value to assign.
        #
        # Side effects:
        #   - Modifies the target file.
        #   - May emit warnings for invalid keys.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   __td_kv_set FILE KEY VALUE
        #
        # Examples:
        #   __td_kv_set "$TD_CFG_FILE" "APP_TITLE" "SolidGround"
        #
        #   __td_kv_set "$TD_STATE_FILE" "CURRENT_PAGE" "2"
    __td_kv_set() {
        local file="$1" key="$2" val="$3"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

        local dir
        dir="$(dirname -- "$file")" || return 1

        # Decide who should own the file
        local uid gid
        if [[ ${EUID:-0} -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
            uid="$SUDO_UID"
            gid="$SUDO_GID"
        else
            uid="$(id -u)"
            gid="$(id -g)"
        fi

        # Ensure directory exists (state dir should typically be private)
        mkdir -p -- "$dir" || return 1

        local tmp
        tmp="$(mktemp)" || return 1

        if [[ -f "$file" ]]; then
            grep -v -E "^[[:space:]]*${key}[[:space:]]*=" -- "$file" > "$tmp" || true
        fi

        printf "%s=%s\n" "$key" "$val" >> "$tmp" || { rm -f -- "$tmp"; return 1; }

        if [[ ${EUID:-0} -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
            # Create final file with correct owner/group/mode immediately
            install -o "$uid" -g "$gid" -m 600 -T -- "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
            # Also ensure directory is owned by the user (optional but usually desired)
            chown "$uid:$gid" -- "$dir" || true
            chmod 700 -- "$dir" || true
        else
            # Normal user path
            install -m 600 -T -- "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
            chmod 700 -- "$dir" || true
        fi

        rm -f -- "$tmp"
        return 0
    }

    # __td_kv_unset
        # Purpose:
        #   Remove a KEY=VALUE entry from a file.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Removes matching KEY=VALUE lines from the file.
        #   - Leaves the rest of the file unchanged.
        #
        # Arguments:
        #   $1  FILE
        #       Path to the KEY=VALUE file.
        #   $2  KEY
        #       Key to remove.
        #
        # Side effects:
        #   - Modifies the target file.
        #   - May emit warnings for invalid keys.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   __td_kv_unset FILE KEY
        #
        # Examples:
        #   __td_kv_unset "$TD_CFG_FILE" "APP_TITLE"
        #
        #   __td_kv_unset "$TD_STATE_FILE" "CURRENT_PAGE"
    __td_kv_unset() {
        local file="$1" key="$2"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
        [[ -f "$file" ]] || return 0

        local tmp
        tmp="$(mktemp)"
        grep -v -E "^[[:space:]]*${key}[[:space:]]*=" "$file" > "$tmp" || true

        # If file becomes empty (or only whitespace/comments were removed earlier), keep it simple:
        if [[ ! -s "$tmp" ]]; then
            rm -f "$tmp"
            rm -f "$file"
            return 0
        fi

        cat -- "$tmp" > "$file"
        rm -f -- "$tmp"
    }

    # __td_kv_reset_file
        # Purpose:
        #   Hard-delete a KEY=VALUE file.
        #
        # Arguments:
        #   $1  File path.
        #
        # Side effects:
        #   Removes the file if present.
        #
        # Returns:
        #   0 always (rm -f semantics).
    __td_kv_reset_file() {
        local file="$1"
        rm -f "$file"
    }

    # __td_kv_get
        # Purpose:
        #   Read a value for a key from a KEY=VALUE file.
        #
        # Behavior:
        #   - Searches the file for a matching KEY=VALUE entry.
        #   - Returns the last matching occurrence when duplicates exist.
        #   - Does not read from the current shell variable.
        #
        # Arguments:
        #   $1  FILE
        #       Path to the KEY=VALUE file.
        #   $2  KEY
        #       Key to retrieve.
        #
        # Output:
        #   Prints the value to stdout without a trailing newline.
        #
        # Returns:
        #   0 if the key is found.
        #   1 if the key is not present.
        #
        # Usage:
        #   __td_kv_get FILE KEY
        #
        # Examples:
        #   value="$(__td_kv_get "$TD_CFG_FILE" "APP_TITLE")" || value=""
        #
        #   __td_kv_get "$TD_STATE_FILE" "CURRENT_PAGE"
    __td_kv_get() {
        local file="$1" key="$2"

        [[ -n "$file" && -n "$key" ]] || return 2
        __td_is_ident "$key"        || return 2
        [[ -r "$file" ]]            || return 2

        local line
        line="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" -- "$file" 2>/dev/null)" || true
        [[ -n "$line" ]] || return 1

        printf '%s' "${line#*=}"
        return 0
    }

    # __td_kv_has
        # Purpose:
        #   Test whether a KEY exists in a KEY=VALUE file (even if empty).
        #
        # Arguments:
        #   $1  File path.
        #   $2  Key (must be a valid identifier).
        #
        # Returns:
        #   0 if present,
        #   1 if not present,
        #   2 on argument/read error.
    __td_kv_has() {
        local file="$1" key="$2"

        [[ -n "$file" && -n "$key" ]] || return 2
        __td_is_ident "$key" || return 2
        [[ -r "$file" ]] || return 2

        grep -q -E "^[[:space:]]*${key}[[:space:]]*=" -- "$file" 2>/dev/null
    }

    # __td_kv_list_keys
        # Purpose:
        #   Emit file contents as 'key|value' lines (order preserved).
        #
        # Arguments:
        #   $1  File path.
        #
        # Output:
        #   Prints one line per KEY=VALUE entry as: key|value
        #
        # Returns:
        #   0 on success; non-zero if file is unreadable.
        #
        # Notes:
        #   - Intended for display/debug; not a stable interchange format.
    __td_kv_list_keys() {
        local file="$1"
        [[ -r "$file" ]] || return 1

        local line key val

        while IFS= read -r line || [[ -n "$line" ]]; do
            # skip blanks and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # split on first '=' only
            key="${line%%=*}"
            val="${line#*=}"

            # trim surrounding whitespace from key
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"

            # basic identifier sanity (optional but recommended)
            [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

            printf '%s|%s\n' "$key" "$val"
        done < "$file"
    }

# --- Public API: Config management ------------------------------------------------
    # td_cfg_load
        # Purpose:
        #   Load a config file into shell variables.
        #
        # Behavior:
        #   - Loads KEY=VALUE pairs from the selected config file.
        #   - Ignores missing files.
        #   - Accepts only valid shell identifiers as keys.
        #
        # Arguments:
        #   $1  FILE
        #       Optional config file path.
        #       Defaults to TD_CFG_FILE when omitted.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Outputs (globals):
        #   Sets variables defined in the loaded file.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_cfg_load
        #
        # Examples:
        #   td_cfg_load
        #
        #   td_cfg_load "/etc/testadura/myapp.cfg"
        #
        # Notes:
        #   - Missing files are not treated as an error.
    td_cfg_load() {
        local file="${1:-$TD_CFG_FILE}"
        __td_kv_load_file "$file"
    }

    # td_cfg_set
        # Purpose:
        #   Persist a config KEY=VALUE pair and update the current shell variable.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Writes or replaces the KEY=VALUE entry in TD_CFG_FILE.
        #   - Updates the in-memory shell variable to the same value.
        #
        # Arguments:
        #   $1  KEY
        #       Config variable name.
        #   $2  VALUE
        #       Value to persist.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Outputs (globals):
        #   Sets $KEY in the current shell.
        #
        # Side effects:
        #   - Updates TD_CFG_FILE on disk.
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   td_cfg_set KEY VALUE
        #
        # Examples:
        #   td_cfg_set "APP_TITLE" "SolidGround Console"
        #
        #   td_cfg_set "SGND_PAGE_MAX_ROWS" "15"
    td_cfg_set() {
        local key="$1" val="$2"
        __td_is_ident "$key" || { saywarning "Skipping invalid cfg key: '$key'"; return 1; }
        local file
        file="${TD_CFG_FILE}"
        __td_kv_set "$file" "$key" "$val"
        printf -v "$key" '%s' "$val"
    }

    # td_cfg_unset
        # Purpose:
        #   Remove a config key from the file and unset it in the current shell.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Removes the KEY=VALUE entry from TD_CFG_FILE.
        #   - Unsets the variable in the current shell (best effort).
        #
        # Arguments:
        #   $1  KEY
        #       Config variable name.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Outputs (globals):
        #   Unsets $KEY in the current shell.
        #
        # Side effects:
        #   - Updates TD_CFG_FILE on disk.
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   td_cfg_unset KEY
        #
        # Examples:
        #   td_cfg_unset "APP_TITLE"
        #
        #   td_cfg_unset "SGND_PAGE_MAX_ROWS"
    td_cfg_unset() {
        local key="$1"
        __td_is_ident "$key" || { saywarning "Skipping invalid cfg key: '$key'"; return 1; }
        local file
        file="${TD_CFG_FILE}"
        __td_kv_unset "$file" "$key"
        unset "$key" || true
    }

    # td_cfg_reset
        # Purpose:
        #   Hard-reset the config file by deleting it.
        #
        # Behavior:
        #   - Resolves the target file from TD_CFG_FILE.
        #   - Removes the file if present.
        #   - Does not recreate a skeleton or defaults.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Side effects:
        #   - Deletes TD_CFG_FILE.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_cfg_reset
        #
        # Examples:
        #   td_cfg_reset
        #
        # Notes:
        #   - Skeleton recreation is the responsibility of bootstrap/domain logic.
    td_cfg_reset() {
        local file
        file="${TD_CFG_FILE}"
        __td_kv_reset_file "$file"
    }

    # td_cfg_get
        # Purpose:
        #   Read a config value from the config file.
        #
        # Behavior:
        #   - Validates the requested key.
        #   - Reads the value directly from TD_CFG_FILE.
        #   - Does not read from the current shell variable.
        #
        # Arguments:
        #   $1  KEY
        #       Config variable name.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Output:
        #   Prints the value to stdout without a trailing newline.
        #
        # Side effects:
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 if found.
        #   1 if missing or invalid.
        #
        # Usage:
        #   td_cfg_get KEY
        #
        # Examples:
        #   value="$(td_cfg_get "APP_TITLE")" || value=""
        #
        #   td_cfg_get "SGND_PAGE_MAX_ROWS"
    td_cfg_get() {
        local key="$1"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid cfg key: '$key'"
            return 1
        }
        __td_kv_get "$TD_CFG_FILE" "$key"
    }

    # td_cfg_has
        # Purpose:
        #   Test whether a config key exists in the config file.
        #
        # Behavior:
        #   - Validates the requested key.
        #   - Checks TD_CFG_FILE for a matching KEY=VALUE entry.
        #   - Treats empty values as present when the key exists.
        #
        # Arguments:
        #   $1  KEY
        #       Config variable name.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Side effects:
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 if present.
        #   1 if missing or invalid.
        #
        # Usage:
        #   td_cfg_has KEY
        #
        # Examples:
        #   if td_cfg_has "APP_TITLE"; then
        #       printf 'configured\n'
        #   fi
        #
        #   td_cfg_has "SGND_PAGE_MAX_ROWS"
    td_cfg_has() {
        local key="$1"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid cfg key: '$key'"
            return 1
        }
        __td_kv_has "$TD_CFG_FILE" "$key"
    }
    
    # td_cfg_show_keys
        # Purpose:
        #   Display selected config keys and their stored values.
        #
        # Behavior:
        #   - Reads values from TD_CFG_FILE, not from in-memory shell variables.
        #   - Renders a formatted section using td_print_* helpers.
        #   - Shows empty values as "" and missing values as <unset>.
        #
        # Arguments:
        #   $@  KEYS
        #       Config keys to display.
        #
        # Inputs (globals):
        #   TD_CFG_FILE
        #
        # Side effects:
        #   - Writes formatted output to stdout.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_cfg_show_keys KEY [KEY ...]
        #
        # Examples:
        #   td_cfg_show_keys APP_TITLE SGND_PAGE_MAX_ROWS
        #
        #   td_cfg_show_keys TD_FRAMEWORK_ROOT TD_USRCFG_FILE
    td_cfg_show_keys() {
        local key val

        td_print_sectionheader --text "CFG" --pad 2 --padend 1

        for key in "$@"; do
            if td_cfg_has "$key"; then
                val="$(td_cfg_get "$key")" || val=""
                if [[ -z "$val" ]]; then
                    td_print_fill --left "$key" --right '""' --pad 2
                else
                    td_print_fill --left "$key" --right "$val" --pad 2
                fi
            else
                td_print_fill --left "$key" --right "<unset>" --pad 2
            fi
        done

        td_print
    }

# --- Bootstrap/advanced: cfg domain loading ---------------------------------------
    # These helpers implement "system + user cfg" behavior driven by a specs array.
    # Intended for bootstrap; stable but not part of the minimal surface area.

    # td_cfg_has_audience
        # Purpose:
        #   Test whether a cfg spec array contains entries for a requested audience.
        #
        # Behavior:
        #   - Scans the supplied spec array.
        #   - Matches entries marked for the requested audience.
        #   - Treats "both" entries as matching either "system" or "user".
        #
        # Arguments:
        #   $1  SPEC_ARRAY_NAME
        #       Name of the specs array variable.
        #   $2  AUDIENCE
        #       Requested audience: "system" or "user".
        #
        # Returns:
        #   0 if at least one matching spec exists.
        #   1 otherwise.
        #
        # Usage:
        #   td_cfg_has_audience SPEC_ARRAY_NAME system
        #
        # Examples:
        #   if td_cfg_has_audience TD_CFG_SPECS "user"; then
        #       printf 'user cfg supported\n'
        #   fi
        #
        #   td_cfg_has_audience TD_CFG_SPECS "system"
    td_cfg_has_audience() {
        local spec_array_name="${1:-}"
        local want="${2:-}"          # "system" or "user"
        [[ -n "$spec_array_name" && -n "$want" ]] || return 1

        local -n specs="$spec_array_name"

        local spec audience var desc extra
        for spec in "${specs[@]}"; do
            IFS='|' read -r audience var desc extra <<< "$spec"
            case "$audience" in
                "$want"|both) return 0 ;;
            esac
        done

        return 1
    }

    # td_cfg_warn_missing_syscfg
        # Purpose:
        #   Emit a warning when a required system cfg file is missing.
        #
        # Behavior:
        #   - Tracks emitted warnings in TD_CFG_WARNED_SYS.
        #   - Suppresses duplicate warnings for the same domain/path combination.
        #   - Adjusts the wording based on framework or script mode.
        #
        # Arguments:
        #   $1  DOMAIN
        #       Logical config domain name.
        #   $2  SYSCFG
        #       System cfg file path.
        #   $3  MODE
        #       Optional mode: "framework" or "script".
        #       Default: script
        #
        # Outputs (globals):
        #   TD_CFG_WARNED_SYS
        #
        # Side effects:
        #   - Updates TD_CFG_WARNED_SYS.
        #   - Writes a warning via saywarning.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_cfg_warn_missing_syscfg DOMAIN SYSCFG [MODE]
        #
        # Examples:
        #   td_cfg_warn_missing_syscfg "framework" "$TD_SYSCFG_FILE" "framework"
        #
        #   td_cfg_warn_missing_syscfg "script" "$TD_SYSCFG_FILE"
    td_cfg_warn_missing_syscfg() {
        local domain="${1:-}"
        local syscfg="${2:-}"
        local mode="${3:-script}"

        [[ -n "$syscfg" ]] || return 0

        : "${TD_CFG_WARNED_SYS:=}"
        local key="${domain}|${syscfg}"

        case " $TD_CFG_WARNED_SYS " in
            *" $key "*) return 0 ;;
        esac
        TD_CFG_WARNED_SYS="$TD_CFG_WARNED_SYS $key"

        if [[ "$mode" == "framework" ]]; then
            saywarning "[$domain] system cfg not found: $syscfg (using default settings; installer should create it)"
        else
            saywarning "[$domain] system cfg not found: $syscfg (using default settings; run as root once to create it)"
        fi
    }

    # td_cfg_ensure_files
        # Purpose:
        #   Ensure required config files exist for a domain based on its specs.
        #
        # Behavior:
        #   - Creates a user cfg file when user-audience specs exist and the file is missing.
        #   - Creates a system cfg file only in script mode and only when running as root.
        #   - Defers system cfg creation in framework mode to the installer.
        #   - Writes generated skeletons filtered by audience.
        #
        # Arguments:
        #   $1  DOMAIN
        #       Logical config domain name.
        #   $2  SYSCFG
        #       System cfg file path.
        #   $3  USRCFG
        #       User cfg file path.
        #   $4  SPEC_ARRAY_NAME
        #       Name of the cfg specs array.
        #   $5  MODE
        #       Optional mode: "framework" or "script".
        #       Default: script
        #
        # Side effects:
        #   - Creates parent directories as needed.
        #   - Creates cfg files when required.
        #   - Writes informational output to stdout.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid arguments or file creation failure.
        #
        # Usage:
        #   td_cfg_ensure_files DOMAIN SYSCFG USRCFG SPEC_ARRAY_NAME [MODE]
        #
        # Examples:
        #   td_cfg_ensure_files "framework" "$TD_SYSCFG_FILE" "$TD_USRCFG_FILE" TD_FRAMEWORK_CFG_SPECS "framework"
        #
        #   td_cfg_ensure_files "script" "$TD_SYSCFG_FILE" "$TD_USRCFG_FILE" TD_SCRIPT_CFG_SPECS
    td_cfg_ensure_files() {
        local domain="${1:-}"
        local syscfg="${2:-}"
        local usrcfg="${3:-}"
        local spec_array_name="${4:-}"
        local mode="${5:-script}"   # "framework" or "script"

        [[ -n "$domain" && -n "$spec_array_name" ]] || return 1

        local is_root=0
        (( EUID == 0 )) && is_root=1

        # system cfg ---
        if td_cfg_has_audience "$spec_array_name" "system"; then
            if [[ "$mode" == "script" ]]; then
                if (( is_root )); then
                    if [[ -n "$syscfg" && ! -f "$syscfg" ]]; then
                        td_ensure_writable_dir "$(dirname -- "$syscfg")" || return 1
                        td_cfg_write_skeleton_filtered "$syscfg" "system" "$spec_array_name" || return 1
                        printf '%s\n' "INFO: [$domain] created system cfg: $syscfg"
                    fi
                fi
            fi
            # framework mode: do not create syscfg here (installer responsibility)
        fi

        # user cfg ---
        if td_cfg_has_audience "$spec_array_name" "user"; then
            if [[ -n "$usrcfg" && ! -f "$usrcfg" ]]; then
                td_ensure_writable_dir "$(dirname -- "$usrcfg")" || return 1
                td_cfg_write_skeleton_filtered "$usrcfg" "user" "$spec_array_name" || return 1
                printf '%s\n' "INFO: [$domain] created user cfg: $usrcfg"
            fi
        fi

        return 0
    }

    # td_cfg_write_skeleton_filtered
        # Purpose:
        #   Write an auto-generated cfg skeleton filtered by audience.
        #
        # Behavior:
        #   - Writes a plain KEY=VALUE config template.
        #   - Includes only specs matching the requested audience.
        #   - Includes specs marked "both" for either audience.
        #   - Uses current shell values as initial defaults where available.
        #
        # Arguments:
        #   $1  FILE
        #       Target cfg file path.
        #   $2  AUDIENCE
        #       Audience filter: "system" or "user".
        #   $3  SPEC_ARRAY_NAME
        #       Name of the cfg specs array.
        #
        # Side effects:
        #   - Creates or overwrites the target file.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid arguments.
        #
        # Usage:
        #   td_cfg_write_skeleton_filtered FILE AUDIENCE SPEC_ARRAY_NAME
        #
        # Examples:
        #   td_cfg_write_skeleton_filtered "$TD_USRCFG_FILE" "user" TD_FRAMEWORK_CFG_SPECS
        #
        #   td_cfg_write_skeleton_filtered "$TD_SYSCFG_FILE" "system" TD_SCRIPT_CFG_SPECS
    td_cfg_write_skeleton_filtered() {
        local file="${1:-}"
        local audience_want="${2:-}"     # "system" or "user"
        local spec_array_name="${3:-}"

        [[ -n "$file" && -n "$audience_want" && -n "$spec_array_name" ]] || return 1

        local -n specs="$spec_array_name"

        {
            printf '%s\n' "# Auto-generated config ($audience_want)"
            printf '%s\n' "# Lines must be VAR=VALUE. Other lines are ignored."
            printf '\n'

            local spec audience var desc extra
            for spec in "${specs[@]}"; do
                IFS='|' read -r audience var desc extra <<< "$spec"
                [[ -n "$var" ]] || continue

                case "$audience" in
                    "$audience_want"|both)
                        printf '# %s\n' "${desc:-$var}"
                        local val
                        val="${!var:-}"
                        printf '%s=%s\n\n' "$var" "$val"
                        ;;
                esac
            done
        } > "$file"

        return 0
    }

    # td_cfg_load_file
        # Purpose:
        #   Load a specific cfg file into shell variables for domain-level processing.
        #
        # Behavior:
        #   - Reads plain KEY=VALUE lines from the target file.
        #   - Ignores blank lines and comments.
        #   - Accepts only valid shell identifiers as keys.
        #   - Stores values literally without unquoting or escape processing.
        #
        # Arguments:
        #   $1  FILE
        #       Config file path to load.
        #
        # Outputs (globals):
        #   Sets variables defined in the file.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_cfg_load_file FILE
        #
        # Examples:
        #   td_cfg_load_file "$TD_SYSCFG_FILE"
        #
        #   [[ -r "$TD_USRCFG_FILE" ]] && td_cfg_load_file "$TD_USRCFG_FILE"
        #
        # Notes:
        #   - Intended for domain/bootstrap flow readability.
    td_cfg_load_file() {
        local file="${1:-}"
        [[ -r "$file" ]] || return 0

        local line key value
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Trim leading/trailing whitespace (basic)
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"

            [[ -n "$line" ]] || continue
            [[ "${line:0:1}" == "#" ]] && continue

            # Must contain '=' and a non-empty key
            [[ "$line" == *"="* ]] || continue
            key="${line%%=*}"
            value="${line#*=}"

            # Trim key whitespace
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            [[ -n "$key" ]] || continue

            # Validate key is a shell variable name
            [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

            # Set variable (value can be anything; keep literal)
            printf -v "$key" '%s' "$value"
        done < "$file"

        return 0
    }

    # td_cfg_domain_apply
        # Purpose:
        #   Apply configuration for a domain from system and user cfg files.
        #
        # Behavior:
        #   - Ensures required cfg files exist for the domain.
        #   - Loads system cfg first when applicable.
        #   - Loads user cfg after system cfg so user values override system values.
        #   - Warns once when a required system cfg file is missing.
        #
        # Arguments:
        #   $1  DOMAIN
        #       Logical config domain name.
        #   $2  SYSCFG
        #       System cfg file path.
        #   $3  USRCFG
        #       User cfg file path.
        #   $4  SPEC_ARRAY_NAME
        #       Name of the cfg specs array.
        #   $5  MODE
        #       Optional mode: "framework" or "script".
        #       Default: script
        #
        # Side effects:
        #   - May create cfg files.
        #   - Loads cfg values into shell variables.
        #   - May emit warnings for missing system cfg.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid arguments or setup failure.
        #
        # Usage:
        #   td_cfg_domain_apply DOMAIN SYSCFG USRCFG SPEC_ARRAY_NAME [MODE]
        #
        # Examples:
        #   td_cfg_domain_apply "framework" "$TD_FRAMEWORK_SYSCFG" "$TD_FRAMEWORK_USRCFG" TD_FRAMEWORK_CFG_SPECS "framework"
        #
        #   td_cfg_domain_apply "script" "$TD_SYSCFG_FILE" "$TD_USRCFG_FILE" TD_SCRIPT_CFG_SPECS
    td_cfg_domain_apply() {
        local domain="${1:-}"
        local syscfg="${2:-}"
        local usrcfg="${3:-}"
        local spec_array_name="${4:-}"
        local mode="${5:-script}"   # "framework" or "script"

        [[ -n "$domain" && -n "$spec_array_name" ]] || return 1

        td_cfg_ensure_files "$domain" "$syscfg" "$usrcfg" "$spec_array_name" "$mode" || return 1

        if td_cfg_has_audience "$spec_array_name" "system"; then
            if [[ -r "$syscfg" ]]; then
                td_cfg_load_file "$syscfg"
            else
                td_cfg_warn_missing_syscfg "$domain" "$syscfg" "$mode"
            fi
        fi

        if td_cfg_has_audience "$spec_array_name" "user"; then
            [[ -r "$usrcfg" ]] && td_cfg_load_file "$usrcfg"
        fi

        return 0
    }

# --- Bootstrap/advanced: State loading --------------------------------------------
    # td_state_load
        # Purpose:
        #   Load the state file into shell variables.
        #
        # Behavior:
        #   - Reads KEY=VALUE pairs from TD_STATE_FILE.
        #   - Ignores missing files.
        #   - Emits a debug message before loading.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Outputs (globals):
        #   Sets variables found in the file.
        #
        # Side effects:
        #   - May write a debug message.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_state_load
        #
        # Examples:
        #   td_state_load
    td_state_load() {
        saydebug "Loading state from file ${TD_STATE_FILE}"
        __td_kv_load_file "$TD_STATE_FILE"
    }

    # td_state_set
        # Purpose:
        #   Persist a state KEY=VALUE pair and update the current shell variable.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Writes or replaces the KEY=VALUE entry in TD_STATE_FILE.
        #   - Updates the in-memory shell variable to the same value.
        #   - Emits a debug message describing the change.
        #
        # Arguments:
        #   $1  KEY
        #       State variable name.
        #   $2  VALUE
        #       Value to persist.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Outputs (globals):
        #   Sets $KEY in the current shell.
        #
        # Side effects:
        #   - Updates TD_STATE_FILE on disk.
        #   - May emit debug or warning output.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   td_state_set KEY VALUE
        #
        # Examples:
        #   td_state_set "CURRENT_PAGE" "2"
        #
        #   td_state_set "LAST_MODULE" "devtools"
    td_state_set() {
        local key="$1" val="$2"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid state key: '$key'"
            return 1
        }   

        saydebug "Setting state key '$key' to '$val' in file ${TD_STATE_FILE}"

        __td_kv_set "$TD_STATE_FILE" "$key" "$val"
        printf -v "$key" '%s' "$val"
    }

    # td_state_unset
        # Purpose:
        #   Remove a state key from the file and unset it in the current shell.
        #
        # Behavior:
        #   - Validates the key as a shell identifier.
        #   - Removes the KEY=VALUE entry from TD_STATE_FILE.
        #   - Unsets the variable in the current shell.
        #   - Emits a debug message describing the change.
        #
        # Arguments:
        #   $1  KEY
        #       State variable name.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Outputs (globals):
        #   Unsets $KEY in the current shell.
        #
        # Side effects:
        #   - Updates TD_STATE_FILE on disk.
        #   - May emit debug or warning output.
        #
        # Returns:
        #   0 on success.
        #   1 on invalid key or write failure.
        #
        # Usage:
        #   td_state_unset KEY
        #
        # Examples:
        #   td_state_unset "CURRENT_PAGE"
        #
        #   td_state_unset "LAST_MODULE"
    td_state_unset() {
        local key="$1"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid state key: '$key'"
            return 1
        }   

        saydebug "Unsetting state key '$key' in file ${TD_STATE_FILE}"

        __td_kv_unset "$TD_STATE_FILE" "$key"
        unset "$key" || true
    }

    # td_state_reset
        # Purpose:
        #   Hard-reset the state file by deleting it.
        #
        # Behavior:
        #   - Returns quietly when TD_STATE_FILE is empty.
        #   - Emits a debug message before deletion.
        #   - Removes the state file if present.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Side effects:
        #   - Deletes TD_STATE_FILE.
        #   - May emit a debug message.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_state_reset
        #
        # Examples:
        #   td_state_reset
    td_state_reset() {
        [[ -n "$TD_STATE_FILE" ]] || return 0
        saydebug "Deleting statefile $TD_STATE_FILE"
        __td_kv_reset_file "$TD_STATE_FILE"
    }

    # td_state_get
        # Purpose:
        #   Read a state value from the state file.
        #
        # Behavior:
        #   - Validates the requested key.
        #   - Reads the value directly from TD_STATE_FILE.
        #   - Does not read from the current shell variable.
        #
        # Arguments:
        #   $1  KEY
        #       State variable name.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Output:
        #   Prints the value to stdout without a trailing newline.
        #
        # Side effects:
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 if found.
        #   1 if missing or invalid.
        #
        # Usage:
        #   td_state_get KEY
        #
        # Examples:
        #   page="$(td_state_get "CURRENT_PAGE")" || page="1"
        #
        #   td_state_get "LAST_MODULE"
    td_state_get() {
        local key="$1"
        __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                return 1
        }
        __td_kv_get "$TD_STATE_FILE" "$key"
    }

    # td_state_has
        # Purpose:
        #   Test whether a state key exists in the state file.
        #
        # Behavior:
        #   - Validates the requested key.
        #   - Checks TD_STATE_FILE for a matching KEY=VALUE entry.
        #   - Treats empty values as present when the key exists.
        #
        # Arguments:
        #   $1  KEY
        #       State variable name.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Side effects:
        #   - May emit a warning for invalid keys.
        #
        # Returns:
        #   0 if present.
        #   1 if missing or invalid.
        #
        # Usage:
        #   td_state_has KEY
        #
        # Examples:
        #   if td_state_has "CURRENT_PAGE"; then
        #       printf 'page stored\n'
        #   fi
        #
        #   td_state_has "LAST_MODULE"
    td_state_has() {
        local key="$1"
        __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                return 1
        }
        
        __td_kv_has "$TD_STATE_FILE" "$key"
    }

    # td_state_save_keys
        # Purpose:
        #   Persist a list of shell variables to the state store.
        #
        # Behavior:
        #   - Iterates over the supplied variable names.
        #   - Reads each current value using safe indirect expansion.
        #   - Persists each value via td_state_set.
        #   - Skips invalid identifiers with a warning.
        #
        # Arguments:
        #   $@  KEYS
        #       Variable names to save.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Side effects:
        #   - Updates TD_STATE_FILE on disk.
        #   - May emit debug or warning output through td_state_set.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_state_save_keys KEY [KEY ...]
        #
        # Examples:
        #   td_state_save_keys CURRENT_PAGE LAST_MODULE
        #
        #   td_state_save_keys FLAG_DEBUG FLAG_VERBOSE FLAG_DRYRUN
    td_state_save_keys() {
        local key val
        for key in "$@"; do
            __td_is_ident "$key" || { saywarning "Skipping invalid state key: '$key'"; continue; }

            # Safe under set -u
            val="${!key-}"

            # Optional: skip unset keys instead of saving empty
            # [[ -z "${!key+x}" ]] && continue

            td_state_set "$key" "$val"
        done
    }

    # td_state_load_keys
        # Purpose:
        #   Load selected state keys from the state store into shell variables.
        #
        # Behavior:
        #   - Iterates over the supplied variable names.
        #   - Reads each value from TD_STATE_FILE.
        #   - Assigns only keys that exist in the state store.
        #   - Skips invalid identifiers with a warning.
        #
        # Arguments:
        #   $@  KEYS
        #       Variable names to load.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Outputs (globals):
        #   Sets variables for keys found in the state store.
        #
        # Side effects:
        #   - May emit warnings for invalid keys.
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_state_load_keys KEY [KEY ...]
        #
        # Examples:
        #   td_state_load_keys CURRENT_PAGE LAST_MODULE
        #
        #   td_state_load_keys FLAG_DEBUG FLAG_VERBOSE FLAG_DRYRUN
    td_state_load_keys() {
        local key val
        for key in "$@"; do
             __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                continue
            }

            if val="$(td_state_get "$key")"; then
                printf -v "$key" '%s' "$val"
            fi
        done
    }

    # td_state_list_keys
        # Purpose:
        #   List keys currently present in the state file.
        #
        # Behavior:
        #   - Reads TD_STATE_FILE when it is readable.
        #   - Emits one key/value pair per line in preserved file order.
        #   - Treats a missing or unreadable state file as non-fatal.
        #
        # Inputs (globals):
        #   TD_STATE_FILE
        #
        # Output:
        #   Prints lines in the format: key|value
        #
        # Returns:
        #   0 always.
        #
        # Usage:
        #   td_state_list_keys
        #
        # Examples:
        #   td_state_list_keys
    td_state_list_keys() {
        [[ -r "${TD_STATE_FILE:-}" ]] || return 0
        __td_kv_list_keys "$TD_STATE_FILE"
    }
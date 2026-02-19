# ==================================================================================
# Testadura Consultancy — cfg.sh
# ----------------------------------------------------------------------------------
# Purpose    : Minimal KEY=VALUE config and state file management
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# ----------------------------------------------------------------------------------
# Description:
#   Provides small helpers for loading and maintaining configuration and state
#   stored as plain KEY=VALUE text files.
#
#   Conceptually:
#   - Config files are user-editable settings (persistent inputs).
#   - State files are script-managed runtime data (persistent outputs).
#
# Assumptions:
#   - This is a FRAMEWORK library (may depend on the framework as it exists).
#   - File paths (TD_CFG_FILE / TD_STATE_FILE or equivalents) are resolved by
#     bootstrap or the caller; this module does not perform path detection.
#
# Rules / Contract:
#   - Plain KEY=VALUE format only (no sections, includes, quoting rules, or typing).
#   - No interpretation or validation of values (strings only).
#   - No default injection or merge/inheritance policy (caller decides precedence).
#   - No environment or shell option changes.
#   - Library-only: must be sourced, never executed.
#   - Safe to source multiple times (must be guarded).
#
# Public API (summary):
#   - td_cfg_load, td_cfg_set, td_cfg_unset, td_cfg_reset, td_cfg_get, td_cfg_has, td_cfg_show_keys
#   - td_state_load, td_state_set, td_state_unset, td_state_reset, td_state_get, td_state_has, td_state_save_keys, td_state_load_keys, td_state_list_keys
# Bootstrap/advanced (used by bootstrap):
#   - td_cfg_domain_apply, td_cfg_ensure_files, td_cfg_write_skeleton_filtered, td_cfg_has_audience, td_cfg_warn_missing_syscfg, td_cfg_load_file
#
# Non-goals:
#   - Structured formats (INI, YAML, JSON)
#   - Schema or type enforcement
#   - Merging/inheritance logic or config precedence policy
# ==================================================================================

# --- Library guard ----------------------------------------------------------------
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

# --- Internal: file and value manipulation ----------------------------------------
    # - Ignores empty lines and comments
    # - Accepts only names: [A-Za-z_][A-Za-z0-9_]*
    # - Loads by eval of sanitized assignment (value preserved as-is)

    
    # __td_is_ident
        # Test whether a string is a valid bash variable identifier.
        # - Must match: [A-Za-z_][A-Za-z0-9_]*
        # - Used to protect file/state operations from invalid keys.
        # Returns:
        #   0 if valid
        #   1 if invalid
    __td_is_ident() {
        [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
    }

    # __td_kv_load_file
        # Load KEY=VALUE pairs from FILE into the current shell.
        # - Ignores empty lines and comments (#...).
        # - Accepts only keys matching: [A-Za-z_][A-Za-z0-9_]*
        # - Assign via printf -v (value preserved as-is).
        # Notes:
        # - Values are taken verbatim as the substring after the first '=' (no unquoting).
        # - Leading/trailing whitespace is trimmed from the line and the key only.
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
        # Upsert KEY=VALUE into FILE.
        # - Removes any existing assignment for KEY (leading whitespace tolerated).
        # - Appends KEY=VALUE at the end of the file (VALUE written verbatim).
        # - Creates parent directory if needed.
        # - Writes file with mode 600; directory mode 700.
        # - If running under sudo as root, file/dir ownership is set to SUDO_UID:SUDO_GID.
        # Returns 0 on success; non-zero on error.
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
        # Remove KEY from FILE.
        # - No-op if FILE does not exist.
        # - Deletes FILE if it becomes empty after removal.
        # Returns 0 on success; non-zero on error.
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
        # Delete FILE (hard reset). Caller decides whether to recreate a skeleton.
    __td_kv_reset_file() {
        local file="$1"
        rm -f "$file"
    }

    # __td_kv_get
        # Read KEY's value from FILE and print it to stdout.
        # - Matches lines like: KEY=..., optionally with whitespace around KEY and '='.
        # Returns:
        #   0 if found
        #   1 if not found
        #   2 on read/argument error
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
        # Test whether KEY exists in FILE (even if the value is empty).
        # Returns:
        #   0 if found
        #   1 if not found
        #   2 on read/argument error
    __td_kv_has() {
        local file="$1" key="$2"

        [[ -n "$file" && -n "$key" ]] || return 2
        __td_is_ident "$key" || return 2
        [[ -r "$file" ]] || return 2

        grep -q -E "^[[:space:]]*${key}[[:space:]]*=" -- "$file" 2>/dev/null
    }

    # __td_kv_list_keys
        # Emit file contents as 'key|value' lines (order preserved).
        # Notes:
        # - Intended for display/debug; not a stable interchange format.
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
        # Load TD_CFG_FILE (KEY=VALUE) into the current shell.
        # Returns 0; missing file is not an error.
    td_cfg_load() {
        local file="${1:-$TD_CFG_FILE}"
        __td_kv_load_file "$file"
    }

    # td_cfg_set
        # Persist KEY=VALUE to TD_CFG_FILE and update the current shell variable.
        # Usage: td_cfg_set KEY VALUE
        # Returns 0 on success; non-zero on write error.
    td_cfg_set() {
        local key="$1" val="$2"
        local file
        file="${TD_CFG_FILE}"
        __td_kv_set "$file" "$key" "$val"
        printf -v "$key" '%s' "$val"
    }

    # td_cfg_unset
        # Remove KEY from TD_CFG_FILE and unset it in the current shell.
        # Usage: td_cfg_unset KEY
    td_cfg_unset() {
        local key="$1"
        local file
        file="${TD_CFG_FILE}"
        __td_kv_unset "$file" "$key"
        unset "$key" || true
    }

    # td_cfg_reset
        # Reset TD_CFG_FILE to an empty/default file (implementation-defined).
    td_cfg_reset() {
        local file
        file="${TD_CFG_FILE}"
        __td_kv_reset_file "$file"
    }

    # td_cfg_get
        # Get KEY's value from TD_CFG_FILE. Prints value to stdout.
        # Returns 0 if found, 1 if missing.
    td_cfg_get() {
        local key="$1"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid cfg key: '$key'"
            return 1
        }
        __td_kv_get "$TD_CFG_FILE" "$key"
    }

    # td_cfg_has
        # Return 0 if KEY exists in TD_CFG_FILE (even if empty).
    td_cfg_has() {
        local key="$1"
        __td_is_ident "$key" || {
            saywarning "Skipping invalid cfg key: '$key'"
            return 1
        }
        __td_kv_has "$TD_CFG_FILE" "$key"
    }
    
    # td_cfg_show_keys
        # Show cfg keys and their values (reads from file, does not rely on shell vars).
        # Usage: td_cfg_show_keys KEY1 [KEY2 ...]
        # Notes: values are read from file each time (does not rely on shell variables).
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
        # Return 0 if SPEC_ARRAY contains any entries for the given audience ("system"|"user"),
        # or entries marked "both".
        # Usage: td_cfg_has_audience SPEC_ARRAY_NAME system|user
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
        # Emit a warning when a system cfg file is missing (once per domain+path).
        # - Suppresses duplicate warnings using TD_CFG_WARNED_SYS.
        # - Message differs for "framework" vs "script" mode.
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
        # Ensure cfg files exist based on specs:
        # - Creates user cfg if needed.
        # - Creates system cfg only when mode="script" and running as root.
        # - In framework mode, system cfg is installer responsibility (no creation here).
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
                        ensure_writable_dir "$(dirname -- "$syscfg")" || return 1
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
                ensure_writable_dir "$(dirname -- "$usrcfg")" || return 1
                td_cfg_write_skeleton_filtered "$usrcfg" "user" "$spec_array_name" || return 1
                printf '%s\n' "INFO: [$domain] created user cfg: $usrcfg"
            fi
        fi

        return 0
    }

    # td_cfg_write_skeleton_filtered
        # Write an auto-generated cfg skeleton containing only variables that match audience.
        # Audience is "system" or "user"; specs may mark entries as "both".
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
                        val="${!var-}"
                        printf '%s=%s\n\n' "$var" "$val"
                        ;;
                esac
            done
        } > "$file"

        return 0
    }

    # td_cfg_load_file
        # Domain-level loader used by td_cfg_domain_apply.
        # Mirrors __td_kv_load_file (kept separate for readability in bootstrap flow).
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
        # Apply cfg for a domain by:
        # - Ensuring cfg files exist (see td_cfg_ensure_files)
        # - Loading system cfg (if specified and readable)
        # - Loading user cfg (if specified and readable)
        # Later loads override earlier loads (user overrides system).
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

# --- Public API: State ------------------------------------------------------------
    # td_state_load
        # Load TD_STATE_FILE (KEY=VALUE) into the current shell.
    td_state_load() {
        saydebug "Loading state from file ${TD_STATE_FILE}"
        __td_kv_load_file "$TD_STATE_FILE"
    }

    # td_state_set
        # Persist KEY=VALUE to TD_STATE_FILE and update the current shell variable.
        # Usage: td_state_set KEY VALUE
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
        # Remove KEY from TD_STATE_FILE and unset it in the current shell.
        # Usage: td_state_unset KEY
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
        # Reset TD_STATE_FILE to an empty/default file (implementation-defined).
    td_state_reset() {
        [[ -n "$TD_STATE_FILE" ]] || return 0
        saydebug "Deleting statefile $TD_STATE_FILE"
        __td_kv_reset_file "$TD_STATE_FILE"
    }

    # td_state_get
        # Get KEY's value from TD_STATE_FILE. Prints value to stdout.
        # Returns 0 if found, 1 if missing.
    td_state_get() {
        local key="$1"
        __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                return 1
        }
        __td_kv_get "$TD_STATE_FILE" "$key"
    }

    # td_state_has
        # Return 0 if KEY exists in TD_STATE_FILE (even if empty).
    td_state_has() {
        local key="$1"
        __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                return 1
        }
        
        __td_kv_has "$TD_STATE_FILE" "$key"
    }

    # td_state_save_keys
        # Save a list of variable names to the state store.
    td_state_save_keys() {
        local key val
        for key in "$@"; do
            __td_is_ident "$key" || {
                saywarning "Skipping invalid state key: '$key'"
                continue
            }
            val="${!key}"
            td_state_set "$key" "$val"
        done
    }

    # td_state_load_keys
        # Load a list of variable names from the state store into shell variables.
        # Existing values are left untouched if no state value exists.
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
        # List keys currently present in TD_STATE_FILE (one per line).
    td_state_list_keys() {
        [[ -r "${TD_STATE_FILE:-}" ]] || return 0
        __td_kv_list_keys "$TD_STATE_FILE"
    }
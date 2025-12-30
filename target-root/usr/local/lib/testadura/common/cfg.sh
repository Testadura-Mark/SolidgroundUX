# ================================================================================
# Testadura — cfg.sh
# --------------------------------------------------------------------------------
# Purpose : Minimal cfg/state management
# Author  : Mark Fieten
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description :
#   Simple key=value config and state file management.
#   - Config and state files are simple KEY=VALUE text files.
#   - Config is for user-editable settings; state is for script-managed data.
#
#  Usage examples:
#   
#   td_cfg_load          # Load config file into shell variables
#   td_cfg_set KEY VAL   # Set/update config key
#   td_cfg_unset KEY     # Remove config key
#   td_cfg_reset         # Clear entire config file
#
#   td_state_load        # Load state file into shell variables
#   td_state_set KEY VAL # Set/update state key
#   td_state_unset KEY   # Remove state key
#   td_state_reset       # Clear entire state file
# ==============================================================================

# --- internal: file and value manipulation ==---------------------------------
    # - Ignores empty lines and comments
    # - Accepts only names: [A-Za-z_][A-Za-z0-9_]*
    # - Loads by eval of sanitized assignment (value preserved as-is)

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
            # Set variable safely (printf %q ensures it becomes a valid literal)
            eval "$key=$(printf "%q" "$val")"
        done < "$file"
    }

    # --- internal: write/update/remove a key in KEY=VALUE file --------------------
    __td_kv_set() {
        local file="$1" key="$2" val="$3"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

        mkdir -p "$(dirname "$file")"

        local tmp
        tmp="$(mktemp)"

        if [[ -f "$file" ]]; then
            # keep all lines except existing key=
            grep -v -E "^[[:space:]]*${key}[[:space:]]*=" "$file" > "$tmp" || true
        fi

        printf "%s=%s\n" "$key" "$val" >> "$tmp"
        mv -f "$tmp" "$file"
    }

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

        mv -f "$tmp" "$file"
    }

    __td_kv_reset_file() {
        local file="$1"
        rm -f "$file"
    }

# --- public: config ----------------------------------------------------------

    td_cfg_load() {
        local file
        file="${CFG_FILE}"
        __td_kv_load_file "$file"
    }

    td_cfg_set() {
        local key="$1" val="$2"
        local file
        file="${CFG_FILE}"
        __td_kv_set "$file" "$key" "$val"
        # also update current shell variable to match
        eval "$key=$(printf "%q" "$val")"
    }

    td_cfg_unset() {
        local key="$1"
        local file
        file="${CFG_FILE}"
        __td_kv_unset "$file" "$key"
        unset "$key" || true
    }

    td_cfg_reset() {
        local file
        file="${CFG_FILE}"
        __td_kv_reset_file "$file"
    }

# --- public: state -----------------------------------------------------------

    td_state_load() {
        local file
        #saydebug "Loading state from file ${STATE_FILE}"
        file="${STATE_FILE}"
        __td_kv_load_file "$file"
    }

    td_state_set() {
        #saydebug "Setting state key '$1' to '$2' in file ${STATE_FILE}"
        local key="$1" val="$2"
        local file
        file="${STATE_FILE}"
        __td_kv_set "$file" "$key" "$val"
        eval "$key=$(printf "%q" "$val")"
    }

    td_state_unset() {
        local key="$1"
        local file
        file="${STATE_FILE}"
        __td_kv_unset "$file" "$key"
        unset "$key" || true
    }

    td_state_reset() {
        local file
        file="$(td_state_file)"
        __td_kv_reset_file "$file"
    }

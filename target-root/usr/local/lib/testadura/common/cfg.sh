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
#   td_cfg_load | td_cfg_set | td_cfg_unset | td_cfg_reset
#   td_state_load | td_state_set | td_state_unset | td_state_reset
#
# Non-goals:
#   - Structured formats (INI, YAML, JSON)
#   - Schema or type enforcement
#   - Merging/inheritance logic or config precedence policy
# ==================================================================================

# --- Validate use ----------------------------------------------------------------
    # Refuse to execute (library only)
    [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "This is a library; source it, do not execute it: ${BASH_SOURCE[0]}" >&2
    exit 2
    }

    # Load guard
    [[ -n "${TD_CFG_LOADED:-}" ]] && return 0
    TD_CFG_LOADED=1

# --- internal: file and value manipulation ==-------------------------------------
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

# --- public: config --------------------------------------------------------------
    # --- td_cfg_load -----------------------------------------------------------------
    # Load TD_CFG_FILE (KEY=VALUE) into the current shell.
    # Returns 0 on success; non-zero on read/parse failure.
    td_cfg_load() {
        local file
        file="${TD_CFG_FILE}"
        __td_kv_load_file "$file"
    }

    # --- td_cfg_set ----------------------------------------------------------------
    # Persist KEY=VALUE to TD_CFG_FILE and update the current shell variable.
    # Usage: td_cfg_set KEY VALUE
    td_cfg_set() {
        local key="$1" val="$2"
        local file
        file="${TD_CFG_FILE}"
        __td_kv_set "$file" "$key" "$val"
        eval "$key=$(printf "%q" "$val")"
    }

    # --- td_cfg_unset --------------------------------------------------------------
    # Remove KEY from TD_CFG_FILE and unset it in the current shell.
    # Usage: td_cfg_unset KEY
    td_cfg_unset() {
        local key="$1"
        local file
        file="${TD_CFG_FILE}"
        __td_kv_unset "$file" "$key"
        unset "$key" || true
    }

    # --- td_cfg_reset --------------------------------------------------------------
    # Reset TD_CFG_FILE to an empty/default file (implementation-defined).
    td_cfg_reset() {
        local file
        file="${TD_CFG_FILE}"
        __td_kv_reset_file "$file"
    }

# --- public: state ---------------------------------------------------------------
    # --- td_state_load -----------------------------------------------------------
    # Load TD_STATE_FILE (KEY=VALUE) into the current shell.
    td_state_load() {
        saydebug "Loading state from file ${TD_STATE_FILE}"
        __td_kv_load_file "$TD_STATE_FILE"
    }

    # --- td_state_set ------------------------------------------------------------
    # Persist KEY=VALUE to TD_STATE_FILE and update the current shell variable.
    # Usage: td_state_set KEY VALUE
    td_state_set() {
        local key="$1" val="$2"
        saydebug "Setting state key '$key' to '$val' in file ${TD_STATE_FILE}"

        __td_kv_set "$TD_STATE_FILE" "$key" "$val"
        eval "$key=$(printf "%q" "$val")"
    }

    # --- td_state_unset ----------------------------------------------------------
    # Remove KEY from TD_STATE_FILE and unset it in the current shell.
    # Usage: td_state_unset KEY
    td_state_unset() {
        local key="$1"
        saydebug "Unsetting state key '$key' in file ${TD_STATE_FILE}"
        __td_kv_unset "$TD_STATE_FILE" "$key"
        unset "$key" || true
    }

    # --- td_state_reset ----------------------------------------------------------
    # Reset TD_STATE_FILE to an empty/default file (implementation-defined).
    td_state_reset() {
        [[ -n "$TD_STATE_FILE" ]] || return 0
        saydebug "Deleting statefile %s" "$TD_STATE_FILE"
        __td_kv_reset_file "$TD_STATE_FILE"
    }

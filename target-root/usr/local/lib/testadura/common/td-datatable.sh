# =================================================================================
# Testadura Consultancy — Bash DataTable Abstraction Module
# ---------------------------------------------------------------------------------
# Module     : td-datatable.sh
# Purpose    : Lightweight DataTable-style abstraction for Bash arrays
#
# Description:
#   Provides a minimal relational-style table model using:
#     - a pipe-separated schema definition
#     - indexed arrays storing pipe-separated row strings
#
#   Enables structured data handling in Bash scripts without external tools.
#
# Core capabilities:
#   - Schema validation and column resolution
#   - Row construction and validation
#   - Column-based access (get/set)
#   - Table operations (insert, delete, find, append)
#
# Design principles:
#   - Explicit schema required at all times
#   - No implicit structure or dynamic typing
#   - No multiline or pipe-containing values
#   - Row identity is the array index
#   - Minimal feature set (no SQL-like complexity)
#
# Typical usage:
#   SCHEMA="id|name|desc"
#   declare -a ROWS=()
#
#   td_dt_append "$SCHEMA" ROWS "1" "Tools" "Utility module"
#   value="$(td_dt_get "$SCHEMA" ROWS 0 name)"
#
# Role in framework:
#   - Provides structured data handling for modules such as:
#       * menu systems
#       * configuration tables
#       * registry-style collections
#
# Non-goals:
#   - No persistence layer
#   - No querying language
#   - No type enforcement beyond basic validation
#
# Author     : Mark Fieten
# Copyright  : © 2025 Mark Fieten — Testadura Consultancy
# License    : Testadura Non-Commercial License (TD-NC) v1.0
# =================================================================================
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

# --- Internal helpers -------------------------------------------------------------
    # td__dt_array_length
        # Purpose:
        #   Return the length of an indexed array by name.
        #
        # Arguments:
        #   $1  ARRAY_NAME
        #
        # Outputs:
        #   Prints array length to stdout.
        #
        # Returns:
        #   0  success
        #
        # Usage:
        #   td__dt_array_length ARRAY_NAME
        #
        # Examples:
        #   count="$(td__dt_array_length MY_ROWS)"
    td__dt_array_length() {
        local array_name="${1:?missing array name}"

        eval "printf '%s\n' \"\${#$array_name[@]}\""
    }

    # td__dt_split_schema
        # Purpose:
        #   Split a schema string into positional column names.
        #
        # Arguments:
        #   $1  SCHEMA
        #
        # Outputs:
        #   Writes column names into global helper array TD_DT_SPLIT.
        #
        # Returns:
        #   0  success
        #
        # Usage:
        #   td__dt_split_schema "$SCHEMA"
        #
        # Examples:
        #   td__dt_split_schema "id|name|desc"
        #   echo "${TD_DT_SPLIT[1]}"   # name
        #   0  success
    td__dt_split_schema() {
        local schema="${1:?missing schema}"

        IFS='|' read -r -a TD_DT_SPLIT <<< "$schema"
    }

    # td__dt_split_row
        # Purpose:
        #   Split a row string into positional field values.
        #
        # Arguments:
        #   $1  ROW
        #
        # Outputs:
        #   Writes field values into global helper array TD_DT_SPLIT.
        #
        # Returns:
        #   0  success
        #
        # Usage:
        #   td__dt_split_row "$ROW"
        #
        # Examples:
        #   td__dt_split_row "1|Tools|Utility"
        #   echo "${TD_DT_SPLIT[2]}"   # Utility
    td__dt_split_row() {
        local row="${1-}"

        IFS='|' read -r -a TD_DT_SPLIT <<< "$row"
    }

# --- Public API -------------------------------------------------------------------
    # td_dt_validate_value
        # Purpose:
        #   Validate whether a field value is supported by v1 storage rules.
        #
        # Rules:
        #   - value must not contain a literal pipe character
        #   - value must not contain a newline
        #
        # Arguments:
        #   $1  VALUE
        #
        # Returns:
        #   0  value is valid
        #   1  value contains unsupported characters
        #
        # Usage:
        #   td_dt_validate_value VALUE
        #
        # Examples:
        #   if td_dt_validate_value "$input"; then
        #       sayinfo "Value OK"
        #   fi
    td_dt_validate_value() {
        local value="${1-}"

        [[ "$value" == *"|"* ]] && return 1
        [[ "$value" == *$'\n'* ]] && return 1
        return 0
    }

    # td_dt_validate_schema
        # Purpose:
        #   Validate a schema string.
        #
        # Rules:
        #   - schema must not be empty
        #   - each column name must be non-empty
        #   - duplicate column names are not allowed
        #
        # Arguments:
        #   $1  SCHEMA
        #
        # Returns:
        #   0  schema is valid
        #   1  schema is invalid
        #
        # Usage:
        #   td_dt_validate_schema "$SCHEMA"
        #
        # Examples:
        #   if ! td_dt_validate_schema "$MY_SCHEMA"; then
        #       sayfail "Invalid schema"
        #   fi
    td_dt_validate_schema() {
        local schema="${1-}"
        local i
        local j

        [[ -n "$schema" ]] || return 1

        td__dt_split_schema "$schema"

        (( ${#TD_DT_SPLIT[@]} > 0 )) || return 1

        for (( i=0; i<${#TD_DT_SPLIT[@]}; i++ )); do
            [[ -n "${TD_DT_SPLIT[i]}" ]] || return 1

            for (( j=i+1; j<${#TD_DT_SPLIT[@]}; j++ )); do
                [[ "${TD_DT_SPLIT[i]}" != "${TD_DT_SPLIT[j]}" ]] || return 1
            done
        done

        return 0
    }

    # td_dt_column_index
        # Purpose:
        #   Resolve a column name to its zero-based index within a schema.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  COLUMN_NAME
        #
        # Outputs:
        #   Prints the zero-based column index to stdout.
        #
        # Returns:
        #   0  column found
        #   1  column not found
        #
        # Usage:
        #   td_dt_column_index "$SCHEMA" COLUMN
        #
        # Examples:
        #   idx="$(td_dt_column_index "$MY_SCHEMA" "name")"
    td_dt_column_index() {
        local schema="${1:?missing schema}"
        local column="${2:?missing column name}"
        local i

        td__dt_split_schema "$schema"

        for (( i=0; i<${#TD_DT_SPLIT[@]}; i++ )); do
            [[ "${TD_DT_SPLIT[i]}" == "$column" ]] || continue
            printf '%s\n' "$i"
            return 0
        done

        return 1
    }

    # td_dt_column_count
        # Purpose:
        #   Return the number of columns in a schema.
        #
        # Arguments:
        #   $1  SCHEMA
        #
        # Outputs:
        #   Prints column count to stdout.
        #
        # Returns:
        #   0  success
    td_dt_column_count() {
        local schema="${1:?missing schema}"

        td__dt_split_schema "$schema"
        printf '%s\n' "${#TD_DT_SPLIT[@]}"
    }

    # td_dt_make_row
        # Purpose:
        #   Build a row string from positional field values.
        #
        # Arguments:
        #   $1   SCHEMA
        #   $2+  VALUES matching schema order
        #
        # Outputs:
        #   Prints the constructed row string to stdout.
        #
        # Returns:
        #   0  success
        #   1  wrong field count or invalid field value
        #
        # Usage:
        #   td_dt_make_row "$SCHEMA" VALUE1 VALUE2 ...
        #
        # Examples:
        #   row="$(td_dt_make_row "$MY_SCHEMA" "1" "Tools" "Utility module")"
    td_dt_make_row() {
        local schema="${1:?missing schema}"
        shift

        local expected=0
        local actual=$#
        local field=""
        local row=""
        local i

        expected="$(td_dt_column_count "$schema")"
        [[ "$actual" -eq "$expected" ]] || return 1

        for (( i=1; i<=actual; i++ )); do
            field="${!i}"

            td_dt_validate_value "$field" || return 1

            [[ -z "$row" ]] || row+="|"
            row+="$field"
        done

        printf '%s\n' "$row"
    }   

    # td_dt_has_row
        # Purpose:
        #   Test whether a table contains at least one row where a given column
        #   equals the specified value.
        #
        # Behavior:
        #   - Performs a linear scan over the table rows.
        #   - Uses td_dt_find_first internally.
        #   - Produces no output; success/failure is indicated by the return code.
        #
        # Arguments:
        #   $1  SCHEMA             Pipe-separated column definition string
        #   $2  TABLE_ARRAY_NAME   Name of the indexed array containing row strings
        #   $3  COLUMN_NAME        Column to test
        #   $4  VALUE              Value to match
        #
        # Returns:
        #   0  At least one matching row exists
        #   1  No matching row found or column does not exist
        #
        # Example:
        #   if td_dt_has_row "$MY_SCHEMA" MY_ROWS key "Q"; then
        #       sayinfo "Quit item already registered"
        #   fi
    td_dt_has_row() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        local column="${3:?missing column name}"
        local value="${4-}"

        td_dt_find_first "$schema" "$table_name" "$column" "$value" >/dev/null 2>&1
    }
    
    # td_dt_row_get
        # Purpose:
        #   Get the value of one column from a row string.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  ROW
        #   $3  COLUMN_NAME
        #
        # Outputs:
        #   Prints the field value to stdout.
        #
        # Returns:
        #   0  success
        #   1  column not found
    td_dt_row_get() {
        local schema="${1:?missing schema}"
        local row="${2-}"
        local column="${3:?missing column name}"
        local index=0

        index="$(td_dt_column_index "$schema" "$column")" || return 1
        td__dt_split_row "$row"

        printf '%s\n' "${TD_DT_SPLIT[index]-}"
    }

    # td_dt_row_set
        # Purpose:
        #   Set the value of one column within a row string.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  ROW
        #   $3  COLUMN_NAME
        #   $4  VALUE
        #
        # Outputs:
        #   Prints the updated row string to stdout.
        #
        # Returns:
        #   0  success
        #   1  invalid column or invalid value
    td_dt_row_set() {
        local schema="${1:?missing schema}"
        local row="${2-}"
        local column="${3:?missing column name}"
        local value="${4-}"
        local index=0
        local i
        local out=""

        td_dt_validate_value "$value" || return 1
        index="$(td_dt_column_index "$schema" "$column")" || return 1

        td__dt_split_schema "$schema"
        local column_count="${#TD_DT_SPLIT[@]}"

        td__dt_split_row "$row"

        for (( i=0; i<column_count; i++ )); do
            if (( i == index )); then
                [[ -z "$out" ]] || out+="|"
                out+="$value"
            else
                [[ -z "$out" ]] || out+="|"
                out+="${TD_DT_SPLIT[i]-}"
            fi
        done

        printf '%s\n' "$out"
    }

    # td_dt_row_count
        # Purpose:
        #   Return the number of rows in a table array.
        #
        # Arguments:
        #   $1  TABLE_ARRAY_NAME
        #
        # Outputs:
        #   Prints row count to stdout.
        #
        # Returns:
        #   0  success
    td_dt_row_count() {
        local table_name="${1:?missing table name}"

        td__dt_array_length "$table_name"
    }

    # td_dt_insert
        # Purpose:
        #   Append a row string to a table array.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  TABLE_ARRAY_NAME
        #   $3  ROW
        #
        # Returns:
        #   0  success
        #   1  invalid schema or row width mismatch
        #
        # Usage:
        #   td_dt_insert "$SCHEMA" ARRAY_NAME ROW
        #
        # Examples:
        #   td_dt_insert "$MY_SCHEMA" MY_ROWS "1|Tools|Utility module"
    td_dt_insert() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        local row="${3-}"

        local expected=0

        td_dt_validate_schema "$schema" || return 1

        expected="$(td_dt_column_count "$schema")"

        td__dt_split_row "$row"
        [[ "${#TD_DT_SPLIT[@]}" -eq "$expected" ]] || return 1

        eval "$table_name+=(\"\$row\")"
    }

    # td_dt_delete
        # Purpose:
        #   Delete one row from a table array by index.
        #
        # Arguments:
        #   $1  TABLE_ARRAY_NAME
        #   $2  ROW_INDEX
        #
        # Returns:
        #   0  success
        #   1  invalid row index
    td_dt_delete() {
        local table_name="${1:?missing table name}"
        local row_index="${2:?missing row index}"
        local row_count=0

        [[ "$row_index" =~ ^[0-9]+$ ]] || return 1

        row_count="$(td_dt_row_count "$table_name")"
        (( row_index < row_count )) || return 1

        eval "unset '$table_name[$row_index]'"
        eval "$table_name=(\"\${$table_name[@]}\")"
    }

    # td_dt_get
        # Purpose:
        #   Get one cell value from a table by row index and column name.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  TABLE_ARRAY_NAME
        #   $3  ROW_INDEX
        #   $4  COLUMN_NAME
        #
        # Outputs:
        #   Prints the field value to stdout.
        #
        # Returns:
        #   0  success
        #   1  invalid row index or invalid column
        #
        # Usage:
        #   td_dt_get "$SCHEMA" ARRAY INDEX COLUMN
        #
        # Examples:
        #   name="$(td_dt_get "$MY_SCHEMA" MY_ROWS 0 name)"
    td_dt_get() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        local row_index="${3:?missing row index}"
        local column="${4:?missing column name}"
        local row_count=0
        local row=""

        [[ "$row_index" =~ ^[0-9]+$ ]] || return 1

        row_count="$(td_dt_row_count "$table_name")"
        (( row_index < row_count )) || return 1

        eval "row=\${$table_name[$row_index]}"
        td_dt_row_get "$schema" "$row" "$column"
    }

    # td_dt_set
        # Purpose:
        #   Set one cell value in a table by row index and column name.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  TABLE_ARRAY_NAME
        #   $3  ROW_INDEX
        #   $4  COLUMN_NAME
        #   $5  VALUE
        #
        # Returns:
        #   0  success
        #   1  invalid row index, invalid column, or invalid value
        #
        # Usage:
        #   td_dt_set "$SCHEMA" ARRAY INDEX COLUMN VALUE
        #
        # Examples:
        #   td_dt_set "$MY_SCHEMA" MY_ROWS 0 name "Updated"
    td_dt_set() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        local row_index="${3:?missing row index}"
        local column="${4:?missing column name}"
        local value="${5-}"
        local row_count=0
        local row=""
        local updated=""

        [[ "$row_index" =~ ^[0-9]+$ ]] || return 1

        row_count="$(td_dt_row_count "$table_name")"
        (( row_index < row_count )) || return 1

        eval "row=\${$table_name[$row_index]}"
        updated="$(td_dt_row_set "$schema" "$row" "$column" "$value")" || return 1
        eval "$table_name[$row_index]=\"\$updated\""
    }

    # td_dt_find_first
        # Purpose:
        #   Find the first row index where COLUMN_NAME equals VALUE.
        #
        # Arguments:
        #   $1  SCHEMA
        #   $2  TABLE_ARRAY_NAME
        #   $3  COLUMN_NAME
        #   $4  VALUE
        #
        # Outputs:
        #   Prints the first matching row index to stdout.
        #
        # Returns:
        #   0  match found
        #   1  no match
        #
        # Usage:
        #   td_dt_find_first "$SCHEMA" ARRAY COLUMN VALUE
        #
        # Examples:
        #   idx="$(td_dt_find_first "$MY_SCHEMA" MY_ROWS key "Q")"
    td_dt_find_first() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        local column="${3:?missing column name}"
        local value="${4-}"
        local row_count=0
        local i
        local cell=""

        row_count="$(td_dt_row_count "$table_name")"

        for (( i=0; i<row_count; i++ )); do
            cell="$(td_dt_get "$schema" "$table_name" "$i" "$column")" || return 1
            [[ "$cell" == "$value" ]] || continue
            printf '%s\n' "$i"
            return 0
        done

        return 1
    }

    # td_dt_append
        # Purpose:
        #   Build and append a row from positional values.
        #
        # Arguments:
        #   $1   SCHEMA
        #   $2   TABLE_ARRAY_NAME
        #   $3+  VALUES
        #
        # Returns:
        #   0  success
        #   1  invalid values or width mismatch
        #
        # Usage:
        #   td_dt_append "$SCHEMA" ARRAY VALUE1 VALUE2 ...
        #
        # Examples:
        #   td_dt_append "$MY_SCHEMA" MY_ROWS "2" "Config" "Settings module"
    td_dt_append() {
        local schema="${1:?missing schema}"
        local table_name="${2:?missing table name}"
        shift 2

        local row=""

        row="$(td_dt_make_row "$schema" "$@")" || return 1
        td_dt_insert "$schema" "$table_name" "$row"
    }
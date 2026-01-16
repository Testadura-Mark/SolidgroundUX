# ===============================================================================
# Testadura Consultancy — default-colors.sh
# -------------------------------------------------------------------------------
# Purpose    : ANSI color/style escape codes for console output
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design rules:
#   - Constants only (no functions, no side effects).
#
# Usage:
#   printf "%sItalic Yellow%s\n" "$ITALIC_YELLOW" "$RESET"
#   printf "%sFaint Red%s\n" "$FAINT_RED" "$RESET"
#   printf "%sUnderlined Cyan%s\n" "$UNDERLINE_CYAN" "$RESET"
#   printf "%sOrange text%s\n" "$ORANGE" "$RESET"
# ===============================================================================

# --- Color codes ---------------------------------------------------------------
  # Reset
    RESET=$'\e[0m'

  # Normal (no extra attributes)
    BLACK=$'\e[0;30m'
    RED=$'\e[0;31m'
    GREEN=$'\e[0;32m'
    YELLOW=$'\e[0;33m'
    BLUE=$'\e[0;34m'
    MAGENTA=$'\e[0;35m'
    CYAN=$'\e[0;36m'
    WHITE=$'\e[0;37m'
    ORANGE=$'\e[38;5;208m'   # renamed from ORANGE_256
    SILVER=$'\e[38;5;250m'   # light gray / "silver"

  # Bold / Bright
    BOLD_BLACK=$'\e[1;30m'
    BOLD_RED=$'\e[38;5;196m' 
    BOLD_GREEN=$'\e[38;5;82m'
    BOLD_YELLOW=$'\e[1;33m'
    BOLD_BLUE=$'\e[1;34m'
    BOLD_MAGENTA=$'\e[1;35m'
    BOLD_CYAN=$'\e[1;36m'
    BOLD_WHITE=$'\e[1;37m'
    BOLD_ORANGE=$'\e[1;38;5;208m'
    BOLD_SILVER=$'\e[1;38;5;250m'

  # Faint / Dim 
    FAINT_BLACK=$'\e[2;30m'
    FAINT_RED=$'\e[2;31m'
    FAINT_GREEN=$'\e[2;32m'
    FAINT_YELLOW=$'\e[2;33m'
    FAINT_BLUE=$'\e[2;34m'
    FAINT_MAGENTA=$'\e[2;35m'
    FAINT_CYAN=$'\e[2;36m'
    FAINT_WHITE=$'\e[2;37m'
    FAINT_ORANGE=$'\e[2;38;5;208m'
    FAINT_SILVER=$'\e[2;38;5;250m'

  # Italic 
    ITALIC_BLACK=$'\e[3;30m'
    ITALIC_RED=$'\e[3;31m'
    ITALIC_GREEN=$'\e[3;32m'
    ITALIC_YELLOW=$'\e[3;33m'
    ITALIC_BLUE=$'\e[3;34m'
    ITALIC_MAGENTA=$'\e[3;35m'
    ITALIC_CYAN=$'\e[3;36m'
    ITALIC_WHITE=$'\e[3;37m'
    ITALIC_ORANGE=$'\e[3;38;5;208m'
    ITALIC_SILVER=$'\e[3;38;5;250m'

  # Underline
    UNDERLINE_BLACK=$'\e[4;30m'
    UNDERLINE_RED=$'\e[4;31m'
    UNDERLINE_GREEN=$'\e[4;32m'
    UNDERLINE_YELLOW=$'\e[4;33m'
    UNDERLINE_BLUE=$'\e[4;34m'
    UNDERLINE_MAGENTA=$'\e[4;35m'
    UNDERLINE_CYAN=$'\e[4;36m'
    UNDERLINE_WHITE=$'\e[4;37m'
    UNDERLINE_ORANGE=$'\e[4;38;5;208m'
    UNDERLINE_SILVER=$'\e[4;38;5;250m'

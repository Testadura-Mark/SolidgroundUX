# ===============================================================================
# Testadura Consultancy — default-colors.sh
# -------------------------------------------------------------------------------
# Purpose    : ANSI color and style escape constants for console output
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Description:
#   Provides a curated set of ANSI escape code constants for styling
#   console output in a consistent and readable way.
#
#   Colors are defined declaratively and grouped by semantic intent:
#     - DARK_*        : darker / muted foreground colors
#     - *             : normal foreground colors
#     - BRIGHT_*      : high-intensity foreground colors (256-color palette)
#     - BG_*          : background color variants (mirroring foreground sets)
#
#   Text attributes (bold, faint, underline, etc.) are defined separately
#   as FX_* constants and may be combined with colors as needed.
#
# Design rules:
#   - Constants only (no functions, no side effects).
#   - Foreground and background colors are separate namespaces.
#   - Styling is applied by concatenating constants and always terminated
#     with RESET (ESC[0m) to avoid style leakage.
#
# Usage:
#   printf "%s%sAlert message%s\n" "$BG_DARK_RED" "$BRIGHT_WHITE" "$RESET"
#   printf "%sInfo message%s\n" "$DARK_SILVER" "$RESET"
#   printf "%sSuccess%s\n" "$BRIGHT_GREEN" "$RESET"
#
# Notes:
#   - RESET resets all attributes, foreground and background colors.
#   - Partial resets (foreground-only or background-only) are intentionally
#     not encouraged to keep output predictable.
# ===============================================================================

# --- Text attributes (SGR) ------------------------------------------------------
  # Note: Support depends on terminal emulator; bold and underline are
  # universally supported, others may be ignored gracefully.

  FX_RESET=0          # Reset all attributes
  FX_BOLD=1           # Bold / increased intensity
  FX_FAINT=2          # Faint / decreased intensity
  FX_ITALIC=3         # Italic (not supported by all terminals)
  FX_UNDERLINE=4      # Underline
  FX_BLINK=5          # Slow blink (often ignored)
  FX_REVERSE=7        # Reverse foreground/background
  FX_CONCEAL=8        # Conceal / hidden text (rarely useful)
  FX_STRIKE=9         # Strikethrough (not universally supported)

# --- Color codes ---------------------------------------------------------------
  # Reset
    RESET=$'\e[0m'
# --- Foreground colors ---------------------------------------------------------
# Naming conventions:
#   DARK_*    : darker / muted variants (typically faint or lower-intensity)
#   *         : normal ANSI base colors
#   BRIGHT_*  : high-intensity colors using the 256-color palette
#
# Notes:
#   - Foreground colors use ANSI SGR codes 30–37 or 38;5;<n>
#   - These MUST NOT be reused as background colors
#   - Always terminate styled output with $RESET

# --- Foreground: Dark / muted --------------------------------------------------
  DARK_RED=$'\e[38;5;88m'
  DARK_GREEN=$'\e[38;5;22m'
  DARK_YELLOW=$'\e[38;5;94m'
  DARK_BLUE=$'\e[38;5;18m' 
  DARK_MAGENTA=$'\e[38;5;90m'
  DARK_CYAN=$'\e[38;5;23m'
  DARK_WHITE=$'\e[38;5;250m'   # or drop DARK_WHITE entirely
  DARK_GRAY=$'\e[38;5;240m'
  DARK_ORANGE=$'\e[38;5;130m'
  DARK_SILVER=$'\e[38;5;245m'
  DARK_PURPLE=$'\e[38;5;55m' 
  DARK_TEAL=$'\e[38;5;29m' 
  DARK_PINK=$'\e[38;5;168m'
  DARK_GOLD=$'\e[38;5;178m'
  DARK_BROWN=$'\e[38;5;94m'

# --- Foreground: Normal --------------------------------------------------------
  BLACK=$'\e[0;30m'
  RED=$'\e[0;31m'
  GREEN=$'\e[0;32m'
  YELLOW=$'\e[0;33m'
  BLUE=$'\e[38;5;25m'
  MAGENTA=$'\e[0;35m'
  CYAN=$'\e[0;36m'
  WHITE=$'\e[0;37m'
  GRAY=$'\e[38;5;245m'
  ORANGE=$'\e[0;38;5;208m'
  SILVER=$'\e[0;38;5;250m'
  PURPLE=$'\e[38;5;93m'         
  TEAL=$'\e[38;5;37m'  
  PINK=$'\e[38;5;213m' 
  GOLD=$'\e[38;5;220m' 
  BROWN=$'\e[38;5;130m'


# --- Foreground: Bright --------------------------------------------------------
  BRIGHT_RED=$'\e[38;5;196m'
  BRIGHT_GREEN=$'\e[38;5;46m'
  BRIGHT_YELLOW=$'\e[38;5;226m'
  BRIGHT_BLUE=$'\e[38;5;39m'
  BRIGHT_MAGENTA=$'\e[38;5;201m'
  BRIGHT_CYAN=$'\e[38;5;51m'
  BRIGHT_WHITE=$'\e[38;5;15m'
  BRIGHT_ORANGE=$'\e[38;5;214m' 
  BRIGHT_PURPLE=$'\e[38;5;135m'
  BRIGHT_TEAL=$'\e[38;5;49m'
  BRIGHT_PINK=$'\e[38;5;219m' 
  BRIGHT_GOLD=$'\e[38;5;226m'  
  BRIGHT_BROWN=$'\e[38;5;172m'

# --- Background colors ---------------------------------------------------------
# Naming conventions:
#   BG_DARK_*    : darker / muted background shades
#   BG_*         : normal ANSI background colors
#   BG_BRIGHT_*  : high-intensity backgrounds using the 256-color palette
#
# Notes:
#   - Background colors use ANSI SGR codes 40–47 or 48;5;<n>
#   - Background colors are independent of foreground colors
#   - Combine with foreground colors by concatenation:
#       printf "%s%sText%s\n" "$BG_DARK_BLUE" "$BRIGHT_WHITE" "$RESET"

# --- Background: Dark / muted --------------------------------------------------
  BG_DARK_RED=$'\e[48;5;88m'
  BG_DARK_GREEN=$'\e[48;5;22m'
  BG_DARK_YELLOW=$'\e[48;5;94m'
  BG_DARK_BLUE=$'\e[48;5;18m'
  BG_DARK_MAGENTA=$'\e[48;5;90m'
  BG_DARK_CYAN=$'\e[48;5;23m'
  BG_DARK_WHITE=$'\e[48;5;250m'
  BG_DARK_GRAY=$'\e[48;5;234m'
  BG_DARK_ORANGE=$'\e[48;5;130m'
  BG_DARK_SILVER=$'\e[48;5;245m'
  BG_DARK_PURPLE=$'\e[48;5;55m'
  BG_DARK_TEAL=$'\e[48;5;29m'
  BG_DARK_PINK=$'\e[48;5;168m'
  BG_DARK_GOLD=$'\e[48;5;178m'
  BG_DARK_BROWN=$'\e[48;5;94m'

# --- Background: Normal --------------------------------------------------------
  BG_BLACK=$'\e[40m'
  BG_RED=$'\e[41m'
  BG_GREEN=$'\e[42m'
  BG_YELLOW=$'\e[43m'
  BG_BLUE=$'\e[44m'
  BG_MAGENTA=$'\e[45m'
  BG_CYAN=$'\e[46m'
  BG_WHITE=$'\e[47m'
  BG_GRAY=$'\e[48;5;245m'
  BG_ORANGE=$'\e[48;5;208m'
  BG_SILVER=$'\e[48;5;250m'
  BG_PURPLE=$'\e[48;5;93m'
  BG_TEAL=$'\e[48;5;37m'
  BG_PINK=$'\e[48;5;213m'
  BG_GOLD=$'\e[48;5;220m'
  BG_BROWN=$'\e[48;5;130m'

# --- Background: Bright --------------------------------------------------------
  BG_BRIGHT_RED=$'\e[48;5;196m'
  BG_BRIGHT_GREEN=$'\e[48;5;46m'
  BG_BRIGHT_YELLOW=$'\e[48;5;226m'
  BG_BRIGHT_BLUE=$'\e[48;5;21m'
  BG_BRIGHT_MAGENTA=$'\e[48;5;201m'
  BG_BRIGHT_CYAN=$'\e[48;5;51m'
  BG_BRIGHT_WHITE=$'\e[48;5;15m'
  BG_BRIGHT_ORANGE=$'\e[48;5;214m'
  BG_BRIGHT_PURPLE=$'\e[48;5;135m'
  BG_BRIGHT_TEAL=$'\e[48;5;49m'
  BG_BRIGHT_PINK=$'\e[48;5;219m'
  BG_BRIGHT_GOLD=$'\e[48;5;226m'
  BG_BRIGHT_BROWN=$'\e[48;5;172m'


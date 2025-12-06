#!/usr/bin/env bash
# ===============================================================================
# Testadura Consultancy — default-styles.sh
# -------------------------------------------------------------------------------
# Purpose : Centralized styles for cli bash scripts
# Author  : Mark <mark@solidground.local>
# 
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Usage:
#   printf "%s%s %s%s\n" "$CLR_INFO" "$LBL_INFO" /
#           "System initialized" "$RESET"
# ===============================================================================

# --- Message type labels and icons ---------------------------------------------

  # --- say() global defaults ---------------------------------------------------
    SAY_DATE_DEFAULT=0     # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="label"   # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT="label"  # none|label|msg|both|all
    SAY_DATE_FORMAT="%Y-%m-%d %H:%M:%S" 
  
  # -- Say prefixes -------------------------------------------------------------
    # Labels
      LBL_CNCL="[CNCL]"
      LBL_EMPTY="     "
      LBL_END="[ END]"
      LBL_FAIL="[FAIL]"
      LBL_INFO="[INFO]"
      LBL_OK="[ OK ]"
      LBL_STRT="[STRT]"
      LBL_WARN="[WARN]"
      LBL_DEBUG="DEBUG"

    # Icons
      ICO_CNCL=$'⏹️'
      ICO_EMPTY=$''
      ICO_END=$'🏁'
      ICO_FAIL=$'❌'
      ICO_INFO=$'ℹ️'
      ICO_OK=$'✅'
      ICO_STRT=$'▶️'
      ICO_WARN=$'⚠️'
      ICO_DEBUG=$'🐞'

    # Symbols
      SYM_CNCL="(-)"
      SYM_EMPTY=""
      SYM_END="<<<"
      SYM_FAIL="(X)"
      SYM_INFO="(+)"
      SYM_OK="(✓)"
      SYM_STRT=">>>"
      SYM_WARN="(!)"
      SYM_DEBUG="(~)"

  # -- Colors -------------------------------------------------------------------
    # By message type
      CLR_INFO=$BLUE
      CLR_STRT=$GREEN
      CLR_OK=$BOLD_GREEN
      CLR_WARN=$ORANGE
      CLR_FAIL=$BOLD_RED
      CLR_CNCL=$FAINT_RED
      CLR_END=$BOLD_GREEN
      CLR_EMPTY=$FAINT_SILVER
      CLR_DEBUG=$MAGENTA

    # Text elements
      CLR_LABEL=$CYAN
      CLR_MSG=$SILVER
      CLR_INPUT=$YELLOW
      CLR_TEXT=$ITALIC_SILVER
      CLR_INVALID=$ORANGE
      CLR_VALID=$GREEN
      CLR_DEFAULT=$FAINT_SILVER


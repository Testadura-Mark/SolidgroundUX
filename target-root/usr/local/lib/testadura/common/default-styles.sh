# ===============================================================================
# Testadura Consultancy — default-styles.sh
# -------------------------------------------------------------------------------
# Purpose    : Default CLI labels, symbols, and color mappings
# Author     : Mark Fieten
#
# © 2025 Mark Fieten — Testadura Consultancy
# Licensed under the Testadura Non-Commercial License (TD-NC) v1.0.
# -------------------------------------------------------------------------------
# Design rules:
#   - Constants only (no functions, no side effects).
#
# Non-goals:
#   - Output formatting logic (see ui-say.sh)
#   - User interaction (see ui-ask.sh)
#
# Usage:
#   printf "%s%s %s%s\n" "$MSG_CLR_INFO" "$LBL_INFO" "System initialized" "$RESET"
# ===============================================================================

# --- Message type labels and icons ---------------------------------------------

  # --- say() global defaults ---------------------------------------------------
    SAY_DATE_DEFAULT=0     # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="label"   # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT="label"  # none|label|msg|both|all
    SAY_DATE_FORMAT="%Y-%m-%d %H:%M:%S" 
  
  # -- Say prefixes -------------------------------------------------------------
    # Labels
      LBL_CNCL="CANCEL"
      LBL_EMPTY="     "
      LBL_END="END"
      LBL_FAIL="ERROR"
      LBL_INFO="INFO"
      LBL_OK="SUCCESS"
      LBL_STRT="START"
      LBL_WARN="WARNING"
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
      MSG_CLR_INFO=$SILVER
      MSG_CLR_STRT=$BOLD_GREEN
      MSG_CLR_OK=$BOLD_GREEN
      MSG_CLR_WARN=$BOLD_ORANGE
      MSG_CLR_FAIL=$BOLD_RED
      MSG_CLR_CNCL=$YELLOW
      MSG_CLR_END=$BOLD_GREEN
      MSG_CLR_EMPTY=$FAINT_SILVER
      MSG_CLR_DEBUG=$BOLD_MAGENTA
    
    # CLI colors
      CLI_BORDER=$BOLD_CYAN

      CLI_LABEL=$SILVER
      CLI_VALUE=$ITALIC_SILVER
      
      CLI_COMMIT=$BOLD_RED
      CLI_DRYRUN=$GREEN

      CLI_ENABLED=$BOLD_WHITE
      CLI_DISABLED=$FAINT_WHITE
      
      CLI_INPUT=$YELLOW
      CLI_PROMPT=$BOLD_CYAN

      CLI_INVALID=$ORANGE
      CLI_VALID=$GREEN

      CLI_SUCCESS=$BOLD_GREEN
      CLI_ERROR=$BOLD_RED

      CLI_HIGHLIGHT=$WHITE
      CLI_TEXT=$SILVER
      CLI_ITALIC=$ITALIC_SILVER
      CLI_FAINT=$FAINT_SILVER

      CLI_DEFAULT=$FAINT_SILVER


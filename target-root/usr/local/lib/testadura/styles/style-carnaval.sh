#!/usr/bin/env bash
# Carnaval style

# --- say() global defaults ----------------------------------------------------
    SAY_DATE_DEFAULT=1    # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="all"   # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT="all"  # none|label|msg|both|all
    SAY_DATE_FORMAT="%Y-%j %H:%M:%S" 
# -- Say prefixes --------------------------------------------------------------
    # Labels
      #LBL_CNCL="[CNCL]"
      #LBL_EMPTY="     "
      #LBL_END="[ END]"
      #LBL_FAIL="[FAIL]"
      #LBL_INFO="[INFO]"
      #LBL_OK="[ OK ]"
      #LBL_STRT="[STRT]"
      #LBL_WARN="[WARN]"

    # Icons
      #ICO_CNCL=$'⏹️'
      #ICO_EMPTY=$''
      #ICO_END=$'🏁'
      #ICO_FAIL=$'❌'
      #ICO_INFO=$'ℹ️'
      #ICO_OK=$'✅'
      #ICO_STRT=$'▶️'
      #ICO_WARN=$'⚠️'

    # Symbols
        SYM_CNCL="⏹"
        SYM_EMPTY=" "
        SYM_END="🏁"
        SYM_FAIL="✖"
        SYM_INFO="🛈"
        SYM_OK="✓"
        SYM_STRT="⮞"
        SYM_WARN="⚠"

# -- Colors --------------------------------------------------------------------
    # By message type
        MSG_CLR_INFO=$BOLD_CYAN
        MSG_CLR_STRT=$BOLD_BLUE
        MSG_CLR_OK=$BOLD_GREEN
        MSG_CLR_WARN=$BOLD_YELLOW
        MSG_CLR_FAIL=$BOLD_RED
        MSG_CLR_CNCL=$BOLD_MAGENTA
        MSG_CLR_END=$BOLD_ORANGE
        MSG_CLR_EMPTY=$FAINT_SILVER
    # Text elements
        TUI_LABEL=$BOLD_MAGENTA
        TUI_MSG=$BOLD_BLUE
        TUI_INPUT=$BOLD_ORANGE
        TUI_TEXT=$BOLD_CYAN
        TUI_INVALID=$BOLD_RED
        TUI_VALID=$BOLD_GREEN
        TUI_DEFAULT=$FAINT_SILVER

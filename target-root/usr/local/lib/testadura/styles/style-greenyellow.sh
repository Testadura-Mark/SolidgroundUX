#!/usr/bin/env bash
# Green-Yellow (labels green, values yellow)

# --- say() global defaults ----------------------------------------------------
    SAY_DATE_DEFAULT=0       # 0 = no date, 1 = add date
    SAY_SHOW_DEFAULT="label, symbol"   # label|icon|symbol|all|label,icon|...
    SAY_COLORIZE_DEFAULT=label  # none|label|msg|both|all
    SAY_DATE_FORMAT="%Y-%m-%d %H:%M:%S" 
    
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
        SYM_INFO="i"
        SYM_STRT=">"
        SYM_OK="+"
        SYM_WARN="!"
        SYM_FAIL="x"
        SYM_CNCL="/"
        SYM_EMPTY=" "

# -- Colors --------------------------------------------------------------------
    # By message type
        MSG_CLRINFO=$GREEN
        MSG_CLRSTRT=$BOLD_GREEN
        MSG_CLROK=$BOLD_GREEN
        MSG_CLRWARN=$BOLD_YELLOW
        MSG_CLRFAIL=$BOLD_RED
        MSG_CLRCNCL=$FAINT_RED
        MSG_CLREND=$FAINT_SILVER
        MSG_CLREMPTY=$FAINT_SILVER
    # Text elements
        TUI_LABEL=$GREEN
        TUI_MSG=$ITALIC_GREEN
        TUI_INPUT=$YELLOW
        TUI_TEXT=$YELLOW
        TUI_INVALID=$ORANGE
        TUI_VALID=$GREEN
        TUI_DEFAULT=$FAINT_SILVER

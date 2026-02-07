#!/usr/bin/env bash
# ==================================================================================
# Testadura Consultancy — td-framework-config.sh
# ----------------------------------------------------------------------------------
# Purpose    : Create or recreate the Testadura framework system configuration file
# ==================================================================================

set -euo pipefail

# must be root
(( EUID == 0 )) || { echo "Run as root (sudo)"; exit 1; }

TARGET_ROOT=""

while (( $# > 0 )); do
    case "$1" in
        -t|--target-root)
            TARGET_ROOT="${2:-}"
            if [[ -z "$TARGET_ROOT" ]]; then
                printf 'ERROR: %s requires a path argument\n' "$1" >&2
                exit 1
            fi
            shift 2
            ;;
          -h|--help)
            printf '%s\n' \
                "Usage: td-framework-config.sh [-t|--target-root DIR]" \
                "" \
                "Creates the framework system cfg file." \
                "" \
                "No -t:" \
                "  writes to /etc/testadura/..." \
                "" \
                "With -t DIR:" \
                "  writes to DIR/etc/testadura/..."
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# normalize target root (optional, but keeps paths clean)
if [[ -n "$TARGET_ROOT" ]]; then
    if [[ "$TARGET_ROOT" != /* ]]; then
        TARGET_ROOT="$(cd "$TARGET_ROOT" && pwd)"
    fi
    TARGET_ROOT="${TARGET_ROOT%/}"
fi

# resolve own dir, source libs
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/bootstrap-env.sh"
# shellcheck source=/dev/null
source "$DIR/core.sh"
# shellcheck source=/dev/null
source "$DIR/cfg.sh"
# shellcheck source=/dev/null
source "$DIR/ui-say.sh"

# ensure defaults exist so skeleton gets values
td_defaults_apply
td_rebase_directories
td_rebase_framework_cfg_paths

# framework syscfg target (framework-level: /etc, possibly under target-root)
SYSCFG="$TD_FRAMEWORK_SYSCFG_FILE"
if [[ -n "$TARGET_ROOT" ]]; then
    SYSCFG="$TARGET_ROOT$SYSCFG"
fi

# ask before overwrite
if [[ -f "$SYSCFG" ]]; then
    read -r -p "Framework syscfg exists. Overwrite? [y/N] " ans
    case "${ans,,}" in
        y|yes) ;;
        *) exit 0 ;;
    esac
fi

# ensure target directory (do not hardcode /etc when using -t)
install -d -m 0755 "$(dirname -- "$SYSCFG")"

# write skeleton from spec
td_cfg_write_skeleton_filtered "$SYSCFG" system TD_FRAMEWORK_GLOBALS
chmod 0644 "$SYSCFG"

echo "Framework syscfg written: $SYSCFG"

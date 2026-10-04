# shellcheck shell=bash
# Runs a single step file in a fresh bash process: bash lib/step-runner.sh steps/40-ssh.sh
# Called by bootstrap.sh with SOL_ROOT, SOL_ENV_FILE, SOL_DRY_RUN, SOL_CHANGES and SOL_STEP set.
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source "$SOL_ROOT/lib/common.sh"
# shellcheck source=lib/pi.sh
source "$SOL_ROOT/lib/pi.sh"
# shellcheck source=lib/settings.sh
source "$SOL_ROOT/lib/settings.sh"

trap 'printf "  %sfailed%s  %s (line %s of %s)\n" "$C_RED" "$C_OFF" "$BASH_COMMAND" "$LINENO" "${BASH_SOURCE[0]##*/}" >&2' ERR

load_settings
# shellcheck source=/dev/null
source "$1"
apply

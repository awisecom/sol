#!/usr/bin/env bash
# bootstrap.sh: bring a fresh Raspberry Pi OS Lite (64-bit) install up to the sol baseline.
#
#   bash bootstrap.sh --dry-run          show every planned change as a diff, touch nothing
#   sudo bash bootstrap.sh               apply all steps (idempotent: re-running is safe)
#   sudo bash bootstrap.sh --only ssh,firewall
#   bash bootstrap.sh --list             list the steps
#
# Options: --env FILE (default ./sol.env), --only a,b, --skip a,b
set -Eeuo pipefail

SOL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SOL_ROOT/lib/common.sh"

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SOL_ENV_FILE=$SOL_ROOT/sol.env
ONLY='' SKIP='' LIST=0
while (($#)); do
  case $1 in
    --dry-run) SOL_DRY_RUN=1 ;;
    --env) SOL_ENV_FILE=${2:?--env needs a file}; shift ;;
    --only) ONLY=${2:?--only needs step names}; shift ;;
    --skip) SKIP=${2:?--skip needs step names}; shift ;;
    --list) LIST=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

step_name() {
  local n=${1##*/}
  n=${n%.sh}
  echo "${n#[0-9][0-9]-}"
}
step_desc() { sed -n 's/^STEP_DESC="\(.*\)"$/\1/p' "$1"; }
in_list() { [[ ",$2," == *",$1,"* ]]; }

STEP_FILES=("$SOL_ROOT"/steps/[0-9][0-9]-*.sh)
ALL=''
for f in "${STEP_FILES[@]}"; do ALL+="$(step_name "$f"),"; done
for n in ${ONLY//,/ } ${SKIP//,/ }; do
  in_list "$n" "$ALL" || die "unknown step: $n (see --list)"
done

if ((LIST)); then
  for f in "${STEP_FILES[@]}"; do printf '%-15s %s\n' "$(step_name "$f")" "$(step_desc "$f")"; done
  exit 0
fi

[[ -r $SOL_ENV_FILE ]] || die "no settings at $SOL_ENV_FILE: cp sol.env.example sol.env, then edit it"
is_dry_run || ((EUID == 0)) || die "run as root (sudo), or look first with --dry-run"

SOL_CHANGES=$(mktemp)
trap 'rm -f "$SOL_CHANGES"' EXIT
export SOL_ROOT SOL_DRY_RUN SOL_CHANGES SOL_ENV_FILE

started=$SECONDS
if is_dry_run; then
  say "${C_BLD}sol bootstrap${C_OFF}, dry run: nothing on this machine will change"
else
  say "${C_BLD}sol bootstrap${C_OFF} on $(hostname), $(date '+%Y-%m-%d %H:%M')"
fi

for f in "${STEP_FILES[@]}"; do
  name=$(step_name "$f")
  [[ -z $ONLY ]] || in_list "$name" "$ONLY" || continue
  [[ -z $SKIP ]] || ! in_list "$name" "$SKIP" || continue
  say ""
  say "${C_BLD}== $name${C_OFF}  ${C_DIM}$(step_desc "$f")${C_OFF}"
  # Each step runs in its own bash process. A subshell would not do: bash
  # ignores `set -e` inside anything that is part of an || or && list.
  if ! SOL_STEP=$name bash "$SOL_ROOT/lib/step-runner.sh" "$f"; then
    die "step '$name' failed. Fix the cause and re-run: finished steps are no-ops."
  fi
done

total=$(awk -F'\t' '$2 !~ /^reboot needed: /' "$SOL_CHANGES" | grep -c . || true)
reboot=$(awk -F'\t' 'sub(/^reboot needed: /, "", $2) { print $2 }' "$SOL_CHANGES" | sort -u | paste -sd, - | sed 's/,/, /g')
say ""
if is_dry_run; then
  say "${C_BLD}$total change(s) planned.${C_OFF} Nothing was touched."
else
  say "${C_BLD}done in $((SECONDS - started)) s, $total change(s).${C_OFF} Run it again: it should report 0."
  { printf '== %s  %s change(s)\n' "$(date -Is)" "$total"; cat "$SOL_CHANGES"; } >>/var/log/sol-bootstrap.log
fi
if [[ -n $reboot ]]; then say "reboot to finish: $reboot"; fi

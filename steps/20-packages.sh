# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="baseline packages"

BASE_PACKAGES=(
  ca-certificates curl git jq rsync tmux # daily use
  htop iotop fio                         # looking at the machine
  nftables avahi-daemon                  # firewall, sol.local on the LAN
)

apply() {
  # Refresh the package index only when it is older than six hours.
  local newest age
  newest=$(find /var/lib/apt/lists -maxdepth 1 -type f -name '*Packages*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
  if [[ -z $newest ]]; then
    changed "fetch the apt index (none yet)"
    perform apt-get update -q
  elif age=$(($(date +%s) - ${newest%.*})) && ((age > 21600)); then
    changed "refresh the apt index ($((age / 3600)) h old)"
    perform apt-get update -q
  else
    ok "apt index is $((age / 60)) min old"
  fi

  local extra=()
  read -ra extra <<<"$SOL_EXTRA_PACKAGES"
  ensure_packages "${BASE_PACKAGES[@]}" "${extra[@]}"
}

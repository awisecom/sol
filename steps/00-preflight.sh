# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="what this machine is, and whether sol.env is complete"

apply() {
  if is_pi; then
    ok "$(pi_model)"
    if [[ $(uname -m) != aarch64 ]]; then warn "expected aarch64 (64-bit Raspberry Pi OS), got $(uname -m)"; fi
  else
    warn "not a Raspberry Pi: Pi-only steps will skip themselves"
  fi
  ok "$(. /etc/os-release && echo "$PRETTY_NAME"), kernel $(uname -r), $(uname -m)"

  local v missing=()
  for v in SOL_HOSTNAME SOL_USER SOL_TIMEZONE SOL_LOCALE SOL_WIFI_COUNTRY; do
    [[ -n ${!v} ]] || missing+=("$v")
  done
  ((${#missing[@]} == 0)) || die "sol.env is missing: ${missing[*]}"
  ok "settings complete ($SOL_ENV_FILE)"

  if id "$SOL_USER" >/dev/null 2>&1; then
    ok "admin user $SOL_USER exists"
  elif is_dry_run; then
    warn "user $SOL_USER does not exist on this machine"
  else
    die "user $SOL_USER does not exist: create it first (Raspberry Pi Imager does this)"
  fi

  if [[ -f $SOL_ENV_FILE ]] && [[ $(stat -c '%a' "$SOL_ENV_FILE") != 600 ]]; then
    warn "$SOL_ENV_FILE is readable by others: chmod 600 it"
  fi

  local free_mb
  free_mb=$(df -BM --output=avail / | tail -1 | tr -dc '0-9')
  if ((free_mb < 1024)); then warn "only ${free_mb} MB free on /"; else ok "${free_mb} MB free on /"; fi
}

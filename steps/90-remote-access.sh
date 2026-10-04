# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="private remote access over Tailscale: no ports open to the internet"

apply() {
  if [[ $SOL_TAILSCALE != yes ]]; then
    note "SOL_TAILSCALE=$SOL_TAILSCALE: skipped"
    return 0
  fi

  # The vendor's signed apt repository rather than `curl | sh`: the key and the
  # source list are two files you can read, and upgrades come through apt.
  if ! pkg_installed tailscale; then
    local repo keyring=/usr/share/keyrings/tailscale-archive-keyring.gpg list=/etc/apt/sources.list.d/tailscale.list
    repo=https://pkgs.tailscale.com/stable/$(os_id)/$(os_codename)
    changed "add the Tailscale apt repository ($repo)"
    perform curl -fsSL "$repo.noarmor.gpg" -o "$keyring"
    perform curl -fsSL "$repo.tailscale-keyring.list" -o "$list"
    perform apt-get update -q
  fi
  ensure_packages tailscale
  ensure_service tailscaled
  is_dry_run && return 0

  local state
  state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' || true)
  case $state in
    Running)
      ok "on the tailnet as $(tailscale ip -4 2>/dev/null | head -1)"
      ;;
    NeedsLogin | Stopped | '')
      if [[ -n $SOL_TAILSCALE_AUTHKEY_FILE ]]; then
        changed "join the tailnet with the auth key in $SOL_TAILSCALE_AUTHKEY_FILE"
        perform tailscale up --auth-key="file:$SOL_TAILSCALE_AUTHKEY_FILE" --hostname="$SOL_HOSTNAME"
      else
        warn "not on the tailnet yet: run 'sudo tailscale up --hostname=$SOL_HOSTNAME' once and open the link it prints"
      fi
      ;;
    *)
      warn "tailscale state: $state"
      ;;
  esac
}

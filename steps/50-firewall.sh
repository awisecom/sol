# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="nftables: inbound closed, SSH only on trusted links"

apply() {
  ensure_packages nftables

  if [[ $SOL_SSH_FROM_LAN == yes ]]; then
    SOL_NFT_LAN_SSH='iifname { "eth0", "wlan0" } tcp dport 22 accept comment "LAN SSH, bring-up only: set SOL_SSH_FROM_LAN=no once the tailnet works"'
  else
    SOL_NFT_LAN_SSH='# LAN SSH is off (SOL_SSH_FROM_LAN=no): reach the box over the tailnet or the USB cable'
  fi

  # Check the new ruleset with the kernel before it goes anywhere near /etc.
  if ! is_dry_run; then
    local candidate
    candidate=$(mktemp)
    render "$SOL_ROOT/config/nftables.conf" >"$candidate"
    nft -c -f "$candidate" || { rm -f "$candidate"; die "nft rejected the ruleset; nothing was changed"; }
    rm -f "$candidate"
  fi

  # Debian ships /etc/nftables.conf executable (#!/usr/sbin/nft -f), keep it that way.
  install_file "$SOL_ROOT/config/nftables.conf" /etc/nftables.conf 0755
  if ((SOL_LAST_CHANGED)); then
    perform nft -f /etc/nftables.conf
  fi
  ensure_service nftables
  if ! is_dry_run; then
    ok "inbound policy: $(nft list chain inet sol input 2>/dev/null | grep -o 'policy [a-z]*' || echo 'table not loaded')"
  fi
}

# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="unattended Debian updates; Pi kernel and firmware stay manual"

apply() {
  ensure_packages unattended-upgrades apt-listchanges needrestart
  # Debian's own origins (security and point releases) update unattended. The
  # Raspberry Pi archive (kernel, firmware, bootloader) is deliberately not in
  # the list: a bad boot on a headless box means walking over with a screen,
  # so those updates happen by hand, with someone watching.
  install_file "$SOL_ROOT/config/apt-unattended.conf" /etc/apt/apt.conf.d/52sol-unattended-upgrades
  ensure_service unattended-upgrades
}

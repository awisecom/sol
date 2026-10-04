# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="fewer writes to flash: journal in RAM, low swappiness, noatime"

apply() {
  local root transport
  root=$(findmnt -no SOURCE /)
  transport=$(storage_transport "$root")
  note "root filesystem on $root ($transport)"

  # Journal: RAM when / is on an SD card (lost on reboot, but no constant small
  # writes to the card), on disk when booting from USB or NVMe.
  if [[ $transport == sd ]]; then SOL_JOURNAL_STORAGE=volatile; else SOL_JOURNAL_STORAGE=persistent; fi
  install_file "$SOL_ROOT/config/journald.conf" /etc/systemd/journald.conf.d/50-sol.conf
  if ((SOL_LAST_CHANGED)) && ! is_dry_run; then perform systemctl restart systemd-journald; fi

  # Swappiness only matters when swap lives on the flash. zram swap is RAM.
  if swapon --noheadings --show=NAME 2>/dev/null | grep -qv '^/dev/zram'; then
    SOL_SWAPPINESS_LINE='vm.swappiness = 10'
  else
    SOL_SWAPPINESS_LINE='# vm.swappiness left at the default: no swap on flash (none, or zram only)'
  fi
  install_file "$SOL_ROOT/config/sysctl.conf" /etc/sysctl.d/90-sol.conf
  if ((SOL_LAST_CHANGED)) && ! is_dry_run; then perform sysctl -q --system; fi

  # noatime: without it, every read of a file is also a metadata write.
  edit_file /etc/fstab "noatime on /" _f_fstab_opt / noatime
  if ((SOL_LAST_CHANGED)); then perform mount -o remount,noatime /; fi
}

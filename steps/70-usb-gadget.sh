# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="SSH over the USB-C cable (dwc2 + g_ether): a way in with no network at all"

apply() {
  if ! is_pi; then
    note "not a Raspberry Pi: skipped"
    return 0
  fi
  local boot reboot=0
  boot=$(boot_dir)

  # The Pi 4's USB-C port can act as a USB device. dwc2 is the controller driver
  # in device mode, g_ether makes the Pi show up as a network adapter.
  edit_file "$boot/config.txt" "dtoverlay=dwc2 under [all]" _f_configtxt_all "dtoverlay=dwc2"
  if ((SOL_LAST_CHANGED)); then reboot=1; fi
  edit_file "$boot/cmdline.txt" "load dwc2 and g_ether at boot" _f_cmdline_param "modules-load=dwc2,g_ether"
  if ((SOL_LAST_CHANGED)); then reboot=1; fi

  # NetworkManager "shared" mode: the Pi is 10.42.0.1 on usb0 and runs a small
  # DHCP server, so the laptop on the other end of the cable gets an address.
  SOL_GADGET_UUID=$(stable_uuid usb-gadget)
  install_file "$SOL_ROOT/config/usb-gadget.nmconnection" \
    /etc/NetworkManager/system-connections/sol-usb-gadget.nmconnection 0600
  if ((SOL_LAST_CHANGED)) && have nmcli; then perform nmcli connection reload; fi

  if ((reboot)); then flag_reboot "USB gadget mode"; fi
}

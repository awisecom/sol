# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="Wi-Fi profiles by priority, then an internet and captive-portal check"

apply() {
  if ! have nmcli; then
    note "NetworkManager not installed: Wi-Fi profiles skipped"
  elif ((${#SOL_WIFI_NETWORKS[@]} == 0)); then
    note "SOL_WIFI_NETWORKS empty: Wi-Fi profiles left alone"
  else
    local entry ssid pskfile prio reload=0
    for entry in "${SOL_WIFI_NETWORKS[@]}"; do
      IFS='|' read -r ssid pskfile prio <<<"$entry"
      [[ -n $ssid && -n $pskfile ]] || die "bad SOL_WIFI_NETWORKS entry '$entry' (want SSID|password-file|priority)"
      if [[ -r $pskfile ]]; then
        SOL_WIFI_PSK=$(<"$pskfile")
      elif is_dry_run; then
        SOL_WIFI_PSK="(read from $pskfile)"
      else
        die "$ssid: password file $pskfile is missing or unreadable"
      fi
      SOL_WIFI_SSID=$ssid
      SOL_WIFI_PRIO=${prio:-0}
      SOL_WIFI_UUID=$(stable_uuid "wifi-$ssid")
      # Profiles are NetworkManager keyfiles: root-only, compared byte for byte,
      # so re-running changes nothing. The password never shows up in `ps`.
      SOL_NO_DIFF=1 install_file "$SOL_ROOT/config/wifi.nmconnection" \
        "/etc/NetworkManager/system-connections/sol-$(slug "$ssid").nmconnection" 0600
      if ((SOL_LAST_CHANGED)); then reload=1; fi
    done
    if ((reload)); then perform nmcli connection reload; fi
  fi

  case $(internet_status) in
    online) ok "internet reachable (generate_204 answered 204)" ;;
    captive) warn "network joined, but HTTP is intercepted: captive portal. See docs/remote-access.md" ;;
    offline) warn "no internet right now" ;;
  esac
}

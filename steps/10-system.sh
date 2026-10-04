# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="hostname, timezone, locale, Wi-Fi country"

current_timezone() {
  timedatectl show -p Timezone --value 2>/dev/null && return 0
  [[ -r /etc/timezone ]] && cat /etc/timezone && return 0
  readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||'
}

apply() {
  # Hostname, and the 127.0.1.1 entry Debian expects for it.
  if [[ $(hostname) == "$SOL_HOSTNAME" ]]; then
    ok "hostname $SOL_HOSTNAME"
  else
    changed "hostname $(hostname) -> $SOL_HOSTNAME"
    perform hostnamectl set-hostname "$SOL_HOSTNAME"
  fi
  edit_file /etc/hosts "127.0.1.1 -> $SOL_HOSTNAME" _f_hosts_name "$SOL_HOSTNAME"

  # Timezone
  if [[ $(current_timezone) == "$SOL_TIMEZONE" ]]; then
    ok "timezone $SOL_TIMEZONE"
  else
    changed "timezone -> $SOL_TIMEZONE"
    perform timedatectl set-timezone "$SOL_TIMEZONE"
  fi

  # Locale. Generate it, make it the default, and drop the bogus LC_CTYPE=UTF-8
  # that macOS forwards over SSH (it made every login print setlocale warnings).
  edit_file /etc/locale.gen "enable $SOL_LOCALE" _f_uncomment "$SOL_LOCALE UTF-8"
  local want have_locale
  want=$(printf '%s' "$SOL_LOCALE" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/')
  have_locale=$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -cx "$want" || true)
  if ((SOL_LAST_CHANGED || have_locale == 0)); then
    changed "generate locale $SOL_LOCALE"
    perform locale-gen
  else
    ok "locale $SOL_LOCALE generated"
  fi
  local current_lang
  current_lang=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"')
  if [[ $current_lang == "$SOL_LOCALE" ]]; then
    ok "default LANG=$SOL_LOCALE"
  else
    changed "default LANG ${current_lang:-unset} -> $SOL_LOCALE"
    perform update-locale "LANG=$SOL_LOCALE"
  fi
  install_file "$SOL_ROOT/config/profile-locale.sh" /etc/profile.d/sol-locale.sh 0644

  # Wi-Fi country. Raspberry Pi OS keeps the radio soft-blocked (rfkill) until
  # a country is set. Skipping that screen in Imager means: boots fine, no Wi-Fi.
  if ! have raspi-config; then
    note "raspi-config not found (not Raspberry Pi OS): Wi-Fi country left alone"
    return 0
  fi
  if [[ $(raspi-config nonint get_wifi_country 2>/dev/null) == "$SOL_WIFI_COUNTRY" ]]; then
    ok "Wi-Fi country $SOL_WIFI_COUNTRY"
  else
    changed "Wi-Fi country -> $SOL_WIFI_COUNTRY"
    perform raspi-config nonint do_wifi_country "$SOL_WIFI_COUNTRY"
  fi
  if have rfkill && rfkill list wifi 2>/dev/null | grep -q 'Soft blocked: yes'; then
    changed "unblock the Wi-Fi radio (rfkill)"
    perform rfkill unblock wifi
  fi
}

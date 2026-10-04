# shellcheck shell=bash
# Loads sol.env and fills in defaults for every optional setting, so the steps
# can run under `set -u` without guarding each variable.

load_settings() {
  [[ -r ${SOL_ENV_FILE:?} ]] || die "settings file $SOL_ENV_FILE not readable"
  # shellcheck source=sol.env.example
  source "$SOL_ENV_FILE"

  : "${SOL_HOSTNAME:=sol}"
  : "${SOL_USER:=}"
  : "${SOL_TIMEZONE:=}"
  : "${SOL_LOCALE:=}"
  : "${SOL_WIFI_COUNTRY:=}"
  : "${SOL_SSH_PUBKEY:=}"
  : "${SOL_SSH_FROM_LAN:=yes}"
  : "${SOL_EXTRA_PACKAGES:=}"
  : "${SOL_AUTO_REBOOT:=false}"
  : "${SOL_TAILSCALE:=yes}"
  : "${SOL_TAILSCALE_AUTHKEY_FILE:=}"
  : "${SOL_RESTIC_REPOSITORY:=}"
  : "${SOL_RESTIC_PASSWORD_FILE:=/etc/sol/restic.pass}"
  : "${SOL_BACKUP_PATHS:=/etc /home /root}"
  [[ -v SOL_WIFI_NETWORKS ]] || SOL_WIFI_NETWORKS=()
}

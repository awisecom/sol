# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="nightly restic backup, weekly integrity check and restore test"

apply() {
  if [[ -z $SOL_RESTIC_REPOSITORY ]]; then
    note "SOL_RESTIC_REPOSITORY empty: skipped"
    return 0
  fi
  ensure_packages restic
  if ! is_dry_run && [[ ! -r $SOL_RESTIC_PASSWORD_FILE ]]; then
    die "restic password file $SOL_RESTIC_PASSWORD_FILE is missing (create it, chmod 600)"
  fi

  # Repository and password file only. Storage credentials (S3, B2, SFTP) go in
  # /etc/sol/restic-backend.env, written by hand, so they never touch this repo.
  install_file "$SOL_ROOT/config/restic.env" /etc/sol/restic.env 0600
  install_file "$SOL_ROOT/tools/restore-test" /usr/local/sbin/sol-restore-test 0755

  local unit reload=0
  for unit in sol-backup.service sol-backup.timer sol-check.service sol-check.timer; do
    install_file "$SOL_ROOT/config/$unit" "/etc/systemd/system/$unit"
    if ((SOL_LAST_CHANGED)); then reload=1; fi
  done
  if ((reload)); then perform systemctl daemon-reload; fi

  if ! is_dry_run; then
    if (restic_env && restic cat config) >/dev/null 2>&1; then
      ok "restic repository reachable"
    else
      changed "initialise the restic repository"
      (restic_env && restic init)
    fi
  fi
  ensure_service sol-backup.timer
  ensure_service sol-check.timer
}

restic_env() {
  set -a
  # shellcheck source=/dev/null
  source /etc/sol/restic.env
  # shellcheck source=/dev/null
  if [[ -r /etc/sol/restic-backend.env ]]; then source /etc/sol/restic-backend.env; fi
  set +a
}

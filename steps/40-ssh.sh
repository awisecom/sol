# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034  # SOL_* come from sol.env; STEP_DESC and template variables are read by bootstrap.sh and render
STEP_DESC="key-only SSH, no root login, with a lockout guard"

apply() {
  local home auth dropin=/etc/ssh/sshd_config.d/00-sol.conf
  home=$(getent passwd "$SOL_USER" | cut -d: -f6)
  [[ -n $home ]] || home=/home/$SOL_USER
  auth=$home/.ssh/authorized_keys

  # 1. Install the admin's public key.
  if [[ -n $SOL_SSH_PUBKEY ]]; then
    ssh-keygen -l -f /dev/stdin <<<"$SOL_SSH_PUBKEY" >/dev/null 2>&1 ||
      die "SOL_SSH_PUBKEY is not a valid public key"
    if [[ ! -d $home/.ssh ]]; then
      changed "create $home/.ssh"
      perform install -d -m 700 -o "$SOL_USER" -g "$(id -gn "$SOL_USER" 2>/dev/null || echo "$SOL_USER")" "$home/.ssh"
    fi
    edit_file "$auth" "add the key from SOL_SSH_PUBKEY" _f_append_line "$SOL_SSH_PUBKEY"
    if ((SOL_LAST_CHANGED)) && ! is_dry_run; then
      chown "$SOL_USER:" "$auth"
      chmod 600 "$auth"
    fi
  else
    note "SOL_SSH_PUBKEY empty: keeping authorized_keys as it is"
  fi

  # 2. Lockout guard: password logins stay on until at least one key is in place.
  local keys=0
  if [[ -r $auth ]]; then keys=$(grep -cE '^(ssh-|ecdsa-|sk-)' "$auth" || true); fi
  if is_dry_run && [[ -n $SOL_SSH_PUBKEY ]]; then keys=$((keys + 1)); fi
  if ((keys == 0)); then
    warn "no SSH key for $SOL_USER yet: leaving password logins on so you can't lock yourself out"
    return 0
  fi
  ok "$keys key(s) authorised for $SOL_USER"

  # 3. Harden sshd with a drop-in. Validate before reloading; roll back if sshd rejects it.
  local saved=''
  if ! is_dry_run && [[ -f $dropin ]]; then
    saved=$(mktemp)
    cp -a "$dropin" "$saved"
  fi
  install_file "$SOL_ROOT/config/sshd-hardening.conf" "$dropin" 0644
  if ((SOL_LAST_CHANGED)) && ! is_dry_run; then
    if sshd -t; then
      perform systemctl reload ssh
      ok "sshd -t passed, ssh reloaded (open sessions stay up)"
    else
      if [[ -n $saved ]]; then cp -a "$saved" "$dropin"; else rm -f "$dropin"; fi
      die "sshd -t rejected the new drop-in; the previous config is back in place"
    fi
  fi
  if [[ -n $saved ]]; then rm -f "$saved"; fi

  if ! is_dry_run; then
    local effective
    effective=$(sshd -T 2>/dev/null | awk '$1 ~ /^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication)$/ { printf "%s %s, ", $1, $2 }')
    ok "effective: ${effective%, }"
  fi
}

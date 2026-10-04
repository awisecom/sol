# shellcheck shell=bash
# Shared helpers for bootstrap.sh, the steps and the tools.
#
# One rule: nothing touches the system except through `perform` or `edit_file`.
# That keeps --dry-run honest and lets the summary count real changes.

SOL_DRY_RUN=${SOL_DRY_RUN:-0}
SOL_CHANGES=${SOL_CHANGES:-/dev/null}
SOL_BACKUP_DIR=${SOL_BACKUP_DIR:-/var/backups/sol}
SOL_LAST_CHANGED=0

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C_DIM=$'\e[2m' C_RED=$'\e[31m' C_YEL=$'\e[33m' C_GRN=$'\e[32m' C_BLD=$'\e[1m' C_OFF=$'\e[0m'
else
  C_DIM='' C_RED='' C_YEL='' C_GRN='' C_BLD='' C_OFF=''
fi

say()  { printf '%s\n' "$*"; }
note() { printf '  %s        %s\n' "$C_DIM" "$*$C_OFF"; }
ok()   { printf '  %sok%s      %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '  %swarn%s    %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

is_dry_run() { [[ $SOL_DRY_RUN == 1 ]]; }
have()       { command -v "$1" >/dev/null 2>&1; }

# perform CMD [ARGS...]: execute, or only print it in dry-run mode.
# (Not called `run`: bats owns that name, and the tests source this file.)
perform() {
  if is_dry_run; then
    printf '  %swould run%s %s\n' "$C_DIM" "$C_OFF" "$*"
    return 0
  fi
  "$@"
}

# changed MESSAGE: report a change and record it for the end-of-run summary.
changed() {
  local verb=change
  is_dry_run && verb=plan
  printf '  %s%-7s%s %s\n' "$C_BLD" "$verb" "$C_OFF" "$*"
  printf '%s\t%s\n' "${SOL_STEP:-}" "$*" >>"$SOL_CHANGES"
}

backup_file() {
  local file=$1 name
  [[ -f $file ]] || return 0
  name=$(printf '%s' "${file#/}" | tr '/' '_')
  mkdir -p "$SOL_BACKUP_DIR"
  cp -a -- "$file" "$SOL_BACKUP_DIR/$name.$(date +%Y%m%d-%H%M%S)"
}

# edit_file FILE DESCRIPTION FILTER [ARGS...]
# Pipes FILE (or nothing, if it doesn't exist yet) through FILTER and writes the
# result back only when it differs. Old versions go to $SOL_BACKUP_DIR.
# Dry-run prints the diff instead; set SOL_NO_DIFF=1 for files holding secrets.
# Sets SOL_LAST_CHANGED=1 when the file changed (or would have).
edit_file() {
  local file=$1 desc=$2 tmp
  shift 2
  SOL_LAST_CHANGED=0
  tmp=$(mktemp)
  if [[ -f $file ]]; then
    "$@" <"$file" >"$tmp" || { rm -f "$tmp"; die "$file: filter $1 failed"; }
  else
    "$@" </dev/null >"$tmp" || { rm -f "$tmp"; die "$file: filter $1 failed"; }
  fi
  if [[ -f $file ]] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  SOL_LAST_CHANGED=1
  changed "$file: $desc"
  if is_dry_run; then
    if [[ ${SOL_NO_DIFF:-0} == 1 ]]; then
      note "(contents hidden: file holds secrets)"
    else
      local old=$file
      [[ -f $file ]] || old=/dev/null
      { diff -u --label "$file" --label "$file (planned)" "$old" "$tmp" || true; } | sed 's/^/            /'
    fi
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  backup_file "$file"
  cat "$tmp" >"$file" # keeps owner, mode and inode of an existing file
  rm -f "$tmp"
}

# install_file SRC DEST [MODE]: render template SRC and install it at DEST.
install_file() {
  local src=$1 dest=$2 mode=${3:-0644}
  edit_file "$dest" "install ${src#"${SOL_ROOT:-}"/}" render "$src"
  local changed_content=$SOL_LAST_CHANGED
  if [[ -f $dest ]] && [[ $(stat -c '%a' "$dest") != "${mode#0}" ]]; then
    changed "$dest: mode $mode"
    perform chmod "$mode" "$dest"
  elif is_dry_run && [[ ! -f $dest ]]; then
    note "mode $mode"
  fi
  SOL_LAST_CHANGED=$changed_content
}

# ---------------------------------------------------------------------------
# Filters: stdin -> stdout, no side effects. Used through edit_file and
# unit-tested on their own (tests/lib.bats). Arguments go in through the
# environment because `awk -v` would interpret backslashes.

# render TEMPLATE: print TEMPLATE with every @NAME@ replaced by $NAME.
# Fails on a placeholder whose variable is unset, so a typo can't ship an empty value.
render() {
  local src=$1 content name
  content=$(<"$src")
  content+=$'\n'
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    [[ -v $name ]] || { echo "template ${src##*/} needs \$$name" >&2; return 1; }
    content=${content//"@${name}@"/"${!name}"}
  done < <({ grep -o '@[A-Z][A-Z0-9_]*@' "$src" || true; } | tr -d '@' | sort -u)
  printf '%s' "$content"
}

# _f_append_line LINE: append LINE unless it is already there verbatim.
_f_append_line() {
  L=$1 awk 'BEGIN { line = ENVIRON["L"] } { print; if ($0 == line) found = 1 } END { if (!found) print line }'
}

# _f_uncomment LINE: enable LINE by uncommenting "# LINE", or append it.
_f_uncomment() {
  L=$1 awk '
    BEGIN { line = ENVIRON["L"] }
    { lines[NR] = $0; if ($0 == line) active = 1 }
    END {
      for (i = 1; i <= NR; i++) {
        t = lines[i]; sub(/^[ \t]*#[ \t]*/, "", t)
        if (!active && !done && t == line) { print line; done = 1; continue }
        print lines[i]
      }
      if (!active && !done) print line
    }'
}

# _f_cmdline_param PARAM: set a kernel parameter in cmdline.txt.
# The firmware only reads the first line, so the output is always one line.
# key=value parameters replace an existing value for the same key.
_f_cmdline_param() {
  P=$1 awk '
    BEGIN { p = ENVIRON["P"]; key = p; sub(/=.*/, "", key) }
    { buf = buf " " $0 }
    END {
      n = split(buf, a, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (a[i] == "") continue
        k = a[i]; sub(/=.*/, "", k)
        if (k == key) { if (!done) { out = out (out == "" ? "" : " ") p; done = 1 }; continue }
        out = out (out == "" ? "" : " ") a[i]
      }
      if (!done) out = out (out == "" ? "" : " ") p
      print out
    }'
}

# _f_configtxt_all LINE: make LINE active in an [all] section of config.txt.
# Lines under [pi4], [cm4], [HDMI:0] and friends only apply conditionally,
# so they don't count; the line is added under a trailing [all] instead.
_f_configtxt_all() {
  L=$1 awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN { line = trim(ENVIRON["L"]); section = "all" }
    {
      lines[NR] = $0
      t = trim($0)
      if (t ~ /^\[.*\]$/) section = tolower(substr(t, 2, length(t) - 2))
      else if (t == line && section == "all") found = 1
    }
    END {
      for (i = 1; i <= NR; i++) print lines[i]
      if (found) exit
      if (section != "all") { print ""; print "[all]" }
      print line
    }'
}

# _f_fstab_opt MOUNTPOINT OPTION: add OPTION to that fstab entry's mount options.
_f_fstab_opt() {
  MP=$1 OPT=$2 awk '
    BEGIN { mp = ENVIRON["MP"]; opt = ENVIRON["OPT"] }
    /^[ \t]*#/ || NF < 4 { print; next }
    $2 == mp {
      n = split($4, o, ","); has = 0
      for (i = 1; i <= n; i++) if (o[i] == opt) has = 1
      if (!has) $4 = $4 "," opt
    }
    { print }'
}

# _f_hosts_name NAME: point the 127.0.1.1 line of /etc/hosts at NAME.
# Debian resolves its own hostname there; without it sudo complains on every call.
_f_hosts_name() {
  N=$1 awk '
    BEGIN { name = ENVIRON["N"] }
    $1 == "127.0.1.1" { if (!done) print "127.0.1.1\t" name; done = 1; next }
    { print }
    END { if (!done) print "127.0.1.1\t" name }'
}

# ---------------------------------------------------------------------------
# Small utilities

# stable_uuid NAME: the same UUID for the same NAME on every run (keeps generated files idempotent).
stable_uuid() { python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "sol:" + sys.argv[1]))' "$1"; }

# slug TEXT: safe file-name fragment.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# internet_status: online | captive | offline.
# generate_204 answers 204 with an empty body; anything else means something in
# between rewrote the request, which on hotel and guest Wi-Fi is a captive portal.
internet_status() {
  local code
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204 2>/dev/null) || true
  case ${code:-000} in
    204) echo online ;;
    000) echo offline ;;
    *) echo captive ;;
  esac
}

# ---------------------------------------------------------------------------
# Packages and services

pkg_installed() {
  # shellcheck disable=SC2016  # ${db:Status-Status} is a dpkg-query format, not a shell variable
  [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}

ensure_packages() {
  local p missing=()
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  if ((${#missing[@]} == 0)); then
    ok "packages present: $*"
    return 0
  fi
  changed "apt install ${missing[*]}"
  perform env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
}

ensure_service() {
  local unit=$1
  if systemctl is-enabled --quiet "$unit" 2>/dev/null && systemctl is-active --quiet "$unit"; then
    ok "$unit enabled and running"
    return 0
  fi
  changed "enable and start $unit"
  perform systemctl enable --now "$unit"
}

# ---------------------------------------------------------------------------
# Platform

is_pi() { [[ -r /proc/device-tree/model ]] && grep -qa 'Raspberry Pi' /proc/device-tree/model; }

pi_model() {
  if [[ -r /proc/device-tree/model ]]; then tr -d '\0' </proc/device-tree/model; else echo "not a Raspberry Pi"; fi
}

# Bookworm and later mount the boot partition at /boot/firmware.
boot_dir() { if [[ -d /boot/firmware ]]; then echo /boot/firmware; else echo /boot; fi; }

os_codename() { (. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-unknown}"); }
os_id() { (. /etc/os-release 2>/dev/null && echo "${ID:-debian}"); }

flag_reboot() {
  changed "reboot needed: $*"
  is_dry_run || printf '%s\n' "$*" >>/run/sol-reboot-required
}

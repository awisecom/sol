#!/usr/bin/env bats
# Filters and file helpers from lib/common.sh. No root needed: everything runs on temp files.

load test_helper

setup() {
  load_lib
  SOL_CHANGES=$BATS_TEST_TMPDIR/changes
  SOL_BACKUP_DIR=$BATS_TEST_TMPDIR/backups
  : >"$SOL_CHANGES"
}

@test "append_line adds a missing line exactly once" {
  out=$(printf 'a\n' | _f_append_line b)
  [ "$out" = $'a\nb' ]
  again=$(printf '%s\n' "$out" | _f_append_line b)
  [ "$again" = "$out" ]
}

@test "append_line copes with a file that lacks a trailing newline" {
  out=$(printf 'a' | _f_append_line b)
  [ "$out" = $'a\nb' ]
}

@test "append_line keeps backslashes literal" {
  out=$(printf '' | _f_append_line 'path\to\thing')
  [ "$out" = 'path\to\thing' ]
}

@test "uncomment enables a commented-out locale" {
  out=$(printf '# en_GB.UTF-8 UTF-8\n# en_US.UTF-8 UTF-8\n' | _f_uncomment 'en_GB.UTF-8 UTF-8')
  [ "$out" = $'en_GB.UTF-8 UTF-8\n# en_US.UTF-8 UTF-8' ]
}

@test "uncomment leaves an already active line alone" {
  in=$'# en_GB.UTF-8 UTF-8\nen_GB.UTF-8 UTF-8'
  out=$(printf '%s\n' "$in" | _f_uncomment 'en_GB.UTF-8 UTF-8')
  [ "$out" = "$in" ]
}

@test "uncomment appends a line that is not there at all" {
  out=$(printf '# en_US.UTF-8 UTF-8\n' | _f_uncomment 'en_GB.UTF-8 UTF-8')
  [ "$out" = $'# en_US.UTF-8 UTF-8\nen_GB.UTF-8 UTF-8' ]
}

@test "cmdline_param appends a parameter and keeps cmdline.txt on one line" {
  out=$(printf 'console=serial0,115200 root=PARTUUID=0a1b2c3d-02 rootfstype=ext4 fsck.repair=yes rootwait\n' |
    _f_cmdline_param modules-load=dwc2,g_ether)
  [ "$out" = "console=serial0,115200 root=PARTUUID=0a1b2c3d-02 rootfstype=ext4 fsck.repair=yes rootwait modules-load=dwc2,g_ether" ]
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]
}

@test "cmdline_param replaces the value of an existing key in place" {
  out=$(printf 'root=/dev/mmcblk0p2 modules-load=dwc2 rootwait\n' | _f_cmdline_param modules-load=dwc2,g_ether)
  [ "$out" = "root=/dev/mmcblk0p2 modules-load=dwc2,g_ether rootwait" ]
}

@test "cmdline_param is idempotent" {
  once=$(printf 'rootwait\n' | _f_cmdline_param quiet)
  twice=$(printf '%s\n' "$once" | _f_cmdline_param quiet)
  [ "$once" = "rootwait quiet" ]
  [ "$twice" = "$once" ]
}

@test "cmdline_param repairs a cmdline.txt that was split over two lines" {
  out=$(printf 'root=/dev/mmcblk0p2 rootwait\nquiet\n' | _f_cmdline_param modules-load=dwc2,g_ether)
  [ "$out" = "root=/dev/mmcblk0p2 rootwait quiet modules-load=dwc2,g_ether" ]
}

@test "configtxt adds the line under a trailing [all] section" {
  in=$'[pi4]\narm_boost=1\n\n[all]\ndtparam=audio=on'
  out=$(printf '%s\n' "$in" | _f_configtxt_all dtoverlay=dwc2)
  [ "$out" = "$in"$'\ndtoverlay=dwc2' ]
}

@test "configtxt opens a new [all] section after a model filter" {
  in=$'dtparam=audio=on\n[pi4]\narm_boost=1'
  out=$(printf '%s\n' "$in" | _f_configtxt_all dtoverlay=dwc2)
  [ "$out" = "$in"$'\n\n[all]\ndtoverlay=dwc2' ]
}

@test "configtxt does not count a line that only applies under [pi4]" {
  in=$'[pi4]\ndtoverlay=dwc2'
  out=$(printf '%s\n' "$in" | _f_configtxt_all dtoverlay=dwc2)
  [ "$out" = "$in"$'\n\n[all]\ndtoverlay=dwc2' ]
}

@test "configtxt treats lines before any section as [all]" {
  in=$'dtoverlay=dwc2\n[pi4]\narm_boost=1'
  out=$(printf '%s\n' "$in" | _f_configtxt_all dtoverlay=dwc2)
  [ "$out" = "$in" ]
}

@test "configtxt is idempotent" {
  once=$(printf '[pi4]\narm_boost=1\n' | _f_configtxt_all dtoverlay=dwc2)
  twice=$(printf '%s\n' "$once" | _f_configtxt_all dtoverlay=dwc2)
  [ "$twice" = "$once" ]
}

@test "fstab_opt adds noatime to the root entry only" {
  in=$'proc /proc proc defaults 0 0\nPARTUUID=0a1b2c3d-01 /boot/firmware vfat defaults 0 2\nPARTUUID=0a1b2c3d-02 / ext4 defaults 0 1'
  out=$(printf '%s\n' "$in" | _f_fstab_opt / noatime)
  [ "$(sed -n 1p <<<"$out")" = "proc /proc proc defaults 0 0" ]
  [ "$(sed -n 2p <<<"$out")" = "PARTUUID=0a1b2c3d-01 /boot/firmware vfat defaults 0 2" ]
  [ "$(sed -n 3p <<<"$out")" = "PARTUUID=0a1b2c3d-02 / ext4 defaults,noatime 0 1" ]
}

@test "fstab_opt is idempotent and leaves comments alone" {
  in=$'# / ext4 defaults\nPARTUUID=0a1b2c3d-02 / ext4 defaults,noatime 0 1'
  out=$(printf '%s\n' "$in" | _f_fstab_opt / noatime)
  [ "$out" = "$in" ]
}

@test "hosts_name rewrites the 127.0.1.1 entry" {
  out=$(printf '127.0.0.1\tlocalhost\n127.0.1.1\traspberrypi\n' | _f_hosts_name sol)
  [ "$out" = $'127.0.0.1\tlocalhost\n127.0.1.1\tsol' ]
}

@test "render fills placeholders from the environment" {
  printf 'AllowUsers @SOL_USER@\n' >"$BATS_TEST_TMPDIR/t"
  SOL_USER=admin
  [ "$(render "$BATS_TEST_TMPDIR/t")" = "AllowUsers admin" ]
}

@test "render refuses a template whose variable is unset" {
  printf 'x=@SOL_NOT_SET@\n' >"$BATS_TEST_TMPDIR/t"
  unset SOL_NOT_SET
  run render "$BATS_TEST_TMPDIR/t"
  [ "$status" -ne 0 ]
  [[ $output == *SOL_NOT_SET* ]]
}

@test "render keeps & and backslashes in values literal" {
  printf 'v=@SOL_V@\n' >"$BATS_TEST_TMPDIR/t"
  SOL_V='a&b\c'
  [ "$(render "$BATS_TEST_TMPDIR/t")" = 'v=a&b\c' ]
}

@test "edit_file writes only when the content changes, and backs up the old file" {
  f=$BATS_TEST_TMPDIR/app.conf
  printf 'a\n' >"$f"
  edit_file "$f" "add b" _f_append_line b
  [ "$(cat "$f")" = $'a\nb' ]
  [ "$SOL_LAST_CHANGED" = 1 ]
  edit_file "$f" "add b" _f_append_line b
  [ "$SOL_LAST_CHANGED" = 0 ]
  [ "$(wc -l <"$SOL_CHANGES")" -eq 1 ]
  ls "$SOL_BACKUP_DIR" | grep -q app.conf
}

@test "edit_file creates a missing file" {
  f=$BATS_TEST_TMPDIR/new/dir/file.conf
  edit_file "$f" "create" _f_append_line hello
  [ "$(cat "$f")" = hello ]
}

@test "dry run shows a diff and leaves the file untouched" {
  f=$BATS_TEST_TMPDIR/app.conf
  printf 'a\n' >"$f"
  SOL_DRY_RUN=1
  run edit_file "$f" "add b" _f_append_line b
  [ "$status" -eq 0 ]
  [[ $output == *"+b"* ]]
  [ "$(cat "$f")" = a ]
}

@test "dry run hides the diff of files that hold secrets" {
  f=$BATS_TEST_TMPDIR/wifi.nmconnection
  SOL_DRY_RUN=1
  SOL_NO_DIFF=1 run edit_file "$f" "install" _f_append_line 'psk=hunter2'
  [ "$status" -eq 0 ]
  [[ $output != *hunter2* ]]
}

@test "install_file renders, installs and sets the mode" {
  printf 'user=@SOL_USER@\n' >"$BATS_TEST_TMPDIR/tpl"
  SOL_USER=admin
  install_file "$BATS_TEST_TMPDIR/tpl" "$BATS_TEST_TMPDIR/out.conf" 0600
  [ "$(cat "$BATS_TEST_TMPDIR/out.conf")" = "user=admin" ]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/out.conf")" = 600 ]
}

@test "stable_uuid is stable" {
  [ "$(stable_uuid wifi-home)" = "$(stable_uuid wifi-home)" ]
  [ "$(stable_uuid wifi-home)" != "$(stable_uuid wifi-work)" ]
}

@test "every config template renders with the CI settings" {
  source "$SOL_ROOT/lib/settings.sh"
  SOL_ENV_FILE=$SOL_ROOT/tests/fixtures/test.env
  load_settings
  SOL_NFT_LAN_SSH='# lan' SOL_WIFI_SSID=x SOL_WIFI_UUID=x SOL_WIFI_PSK=x SOL_WIFI_PRIO=1
  SOL_GADGET_UUID=x SOL_JOURNAL_STORAGE=volatile SOL_SWAPPINESS_LINE='# none'
  for t in "$SOL_ROOT"/config/*; do
    render "$t" >/dev/null
    ! render "$t" | grep -q '@[A-Z][A-Z0-9_]*@'
  done
}

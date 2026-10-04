#!/usr/bin/env bats
# bootstrap.sh as a whole, in dry-run mode, against the CI fixture settings.

load test_helper

ENV=""
setup() { ENV=$SOL_ROOT/tests/fixtures/test.env; }

@test "--list shows every step, in order" {
  run bash "$SOL_ROOT/bootstrap.sh" --list
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq "$(ls "$SOL_ROOT"/steps/*.sh | wc -l)" ]
  [[ ${lines[0]} == preflight* ]]
  [[ ${lines[-1]} == backup* ]]
}

@test "a full dry run plans changes and exits cleanly without root" {
  run bash "$SOL_ROOT/bootstrap.sh" --dry-run --env "$ENV"
  [ "$status" -eq 0 ]
  [[ $output == *"dry run"* ]]
  [[ $output == *"change(s) planned"* ]]
}

@test "the dry run shows the sshd drop-in it would install" {
  run bash "$SOL_ROOT/bootstrap.sh" --dry-run --env "$ENV" --only ssh
  [ "$status" -eq 0 ]
  [[ $output == *"+PasswordAuthentication no"* ]]
}

@test "the dry run never prints Wi-Fi passwords" {
  run bash "$SOL_ROOT/bootstrap.sh" --dry-run --env "$ENV" --only network
  [ "$status" -eq 0 ]
  [[ $output != *"psk="* ]]
}

@test "unknown step names are rejected" {
  run bash "$SOL_ROOT/bootstrap.sh" --dry-run --env "$ENV" --only nope
  [ "$status" -ne 0 ]
  [[ $output == *"unknown step: nope"* ]]
}

@test "missing settings stop the run at preflight" {
  printf 'SOL_HOSTNAME=x\n' >"$BATS_TEST_TMPDIR/bad.env"
  run bash "$SOL_ROOT/bootstrap.sh" --dry-run --env "$BATS_TEST_TMPDIR/bad.env" --only preflight
  [ "$status" -ne 0 ]
  [[ $output == *"missing: SOL_USER"* ]]
}

@test "applying for real requires root" {
  if [ "$(id -u)" -eq 0 ]; then skip "running as root"; fi
  run bash "$SOL_ROOT/bootstrap.sh" --env "$ENV"
  [ "$status" -ne 0 ]
  [[ $output == *"run as root"* ]]
}

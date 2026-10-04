#!/usr/bin/env bats
# The tools run against regular files here; on the Pi they get block devices.

load test_helper

setup() {
  IMG=$BATS_TEST_TMPDIR/disk.img
  head -c $((3 << 20)) /dev/urandom >"$IMG"
}

@test "sdbench --scan reads chunk by chunk and reports zero errors" {
  run bash "$SOL_ROOT/tools/sdbench" --scan --chunk 1M "$IMG"
  [ "$status" -eq 0 ]
  [[ $output == *"0-1M"* ]]
  [[ $output == *"2M-3M"* ]]
  [[ $output == *"0 read error(s)"* ]]
}

@test "sdbench sequential read prints a throughput" {
  run bash "$SOL_ROOT/tools/sdbench" --size 2M "$IMG"
  [ "$status" -eq 0 ]
  [[ $output == *"sequential read"*"MB/s"* ]]
}

@test "sdbench --write measures and cleans up after itself" {
  run bash "$SOL_ROOT/tools/sdbench" --size 2M --write "$BATS_TEST_TMPDIR" "$IMG"
  [ "$status" -eq 0 ]
  [[ $output == *"sequential write"* ]]
  [ -z "$(find "$BATS_TEST_TMPDIR" -name '.sdbench.*')" ]
}

@test "sdbench refuses a missing target" {
  run bash "$SOL_ROOT/tools/sdbench" /nonexistent/device
  [ "$status" -ne 0 ]
  [[ $output == *"does not exist"* ]]
}

@test "pi-doctor --json emits valid JSON on any Linux box" {
  run bash -c "bash '$SOL_ROOT/tools/pi-doctor' --json"
  [ "$status" -le 2 ]
  printf '%s' "$output" | python3 -c 'import json, sys; d = json.load(sys.stdin); assert d["checks"] and "summary" in d'
}

@test "pi-doctor prints every section" {
  run bash "$SOL_ROOT/tools/pi-doctor"
  [ "$status" -le 2 ]
  for s in system "power and heat" storage boot memory network security; do
    [[ $output == *"$s"* ]]
  done
}

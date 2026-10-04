#!/usr/bin/env bats
# Pure diagnostics helpers from lib/pi.sh.

load test_helper

setup() { load_lib; }

@test "decode_throttled: healthy board" {
  [ "$(decode_throttled throttled=0x0)" = none ]
}

@test "decode_throttled: under-voltage and throttling, now and since boot" {
  run decode_throttled throttled=0x50005
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "under-voltage now" ]
  [ "${lines[1]}" = "throttled now" ]
  [ "${lines[2]}" = "under-voltage has occurred since boot" ]
  [ "${lines[3]}" = "throttling has occurred since boot" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "decode_throttled: history only" {
  [ "$(decode_throttled 0x80000)" = "soft temperature limit has occurred since boot" ]
}

@test "decode_throttled rejects garbage" {
  run decode_throttled nonsense
  [ "$status" -ne 0 ]
}

@test "throttle_severity: now is a failure, history a warning" {
  [ "$(throttle_severity 0x0)" = ok ]
  [ "$(throttle_severity 0x50000)" = warn ]
  [ "$(throttle_severity 0x8)" = warn ]
  [ "$(throttle_severity 0x50005)" = fail ]
  [ "$(throttle_severity throttled=0x1)" = fail ]
}

@test "to_bytes understands binary suffixes" {
  [ "$(to_bytes 4096)" = 4096 ]
  [ "$(to_bytes 64k)" = 65536 ]
  [ "$(to_bytes 512M)" = 536870912 ]
  [ "$(to_bytes 1G)" = 1073741824 ]
  [ "$(to_bytes 1GiB)" = 1073741824 ]
  run to_bytes 1.5G
  [ "$status" -ne 0 ]
}

@test "mbps reproduces the original card measurement" {
  # sol's first card: 18.9 GB read in 1294.5 s
  [ "$(mbps 18900000000 1294500000000)" = 14.6 ]
}

@test "human_bytes uses decimal units like card vendors" {
  [ "$(human_bytes 18900000000)" = "18.9 GB" ]
  [ "$(human_bytes 999)" = "999 B" ]
}

@test "sd_read_verdict" {
  [ "$(sd_read_verdict 14.6 | cut -d'|' -f1)" = fail ]
  [ "$(sd_read_verdict 25 | cut -d'|' -f1)" = warn ]
  [ "$(sd_read_verdict 85 | cut -d'|' -f1)" = ok ]
}

@test "iops_class maps to the A1 and A2 application classes" {
  [ "$(iops_class 900)" = "below A1 (1500 random-read IOPS)" ]
  [ "$(iops_class 1600)" = "meets A1 (1500 random-read IOPS)" ]
  [ "$(iops_class 4100)" = "meets A2 (4000 random-read IOPS)" ]
}

@test "storage_transport recognises SD and NVMe device names" {
  [ "$(storage_transport /dev/mmcblk0p2)" = sd ]
  [ "$(storage_transport /dev/nvme0n1p2)" = nvme ]
}

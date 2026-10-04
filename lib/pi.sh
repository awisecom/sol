# shellcheck shell=bash
# Pure helpers for Raspberry Pi diagnostics. No side effects, unit-tested in tests/pi.bats.

# decode_throttled VALUE: one line per flag set in `vcgencmd get_throttled`.
# Accepts "throttled=0x50005", "0x50005" or a decimal number.
decode_throttled() {
  local raw=${1#throttled=}
  [[ $raw =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]] || { echo "invalid throttle value: $1" >&2; return 1; }
  local v=$((raw)) bit any=0
  local -A name=(
    [0]="under-voltage now"
    [1]="ARM frequency capped now"
    [2]="throttled now"
    [3]="soft temperature limit active now"
    [16]="under-voltage has occurred since boot"
    [17]="ARM frequency capping has occurred since boot"
    [18]="throttling has occurred since boot"
    [19]="soft temperature limit has occurred since boot"
  )
  for bit in 0 1 2 3 16 17 18 19; do
    if (((v >> bit) & 1)); then
      printf '%s\n' "${name[$bit]}"
      any=1
    fi
  done
  ((any)) || echo none
}

# throttle_severity VALUE: ok | warn | fail.
# Anything happening right now that costs performance is a fail; history is a warning.
throttle_severity() {
  local raw=${1#throttled=}
  [[ $raw =~ ^(0x[0-9a-fA-F]+|[0-9]+)$ ]] || { echo fail; return 0; }
  local v=$((raw))
  if ((v & 0x5)); then echo fail
  elif ((v & 0xF000A)); then echo warn
  else echo ok
  fi
}

# to_bytes SIZE: "512M", "1G", "64k", "4096" -> bytes (binary units).
to_bytes() {
  local s=${1^^} n
  [[ $s =~ ^([0-9]+)([KMGT]?)(I?B)?$ ]] || { echo "invalid size: $1" >&2; return 1; }
  n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]} in
    K) echo $((n << 10)) ;;
    M) echo $((n << 20)) ;;
    G) echo $((n << 30)) ;;
    T) echo $((n << 40)) ;;
    *) echo "$n" ;;
  esac
}

# human_bytes BYTES: 19700000000 -> "19.7 GB" (decimal units, like dd and card vendors use).
human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1000 && i < 5) { b /= 1000; i++ }
    printf(i == 1 ? "%d %s\n" : "%.1f %s\n", b, u[i])
  }'
}

# mbps BYTES NANOSECONDS: throughput in MB/s (decimal megabytes), one decimal.
mbps() {
  awk -v b="$1" -v ns="$2" 'BEGIN { printf "%.1f\n", (ns > 0 ? b / (ns / 1e9) / 1e6 : 0) }'
}

# sd_read_verdict MBPS: "status|explanation" for a microSD sequential read result.
# Healthy cards read 40-90 MB/s on a Pi 4. Class 10 only promises 10 MB/s *write*,
# and reads are normally several times faster, so a card reading below 20 MB/s
# is unusual: worn out, counterfeit or a very old design.
sd_read_verdict() {
  awk -v s="$1" 'BEGIN {
    if (s >= 40)      print "ok|normal for microSD (40-90 MB/s)"
    else if (s >= 20) print "warn|below a healthy card (40-90 MB/s)"
    else              print "fail|far below a healthy card (40-90 MB/s): expect slow boots and timeouts"
  }'
}

# iops_class IOPS: which SD application-performance class a random-read result meets.
iops_class() {
  awk -v i="$1" 'BEGIN {
    if (i >= 4000)      print "meets A2 (4000 random-read IOPS)"
    else if (i >= 1500) print "meets A1 (1500 random-read IOPS)"
    else                print "below A1 (1500 random-read IOPS)"
  }'
}

# storage_transport DEVICE: sd | usb | nvme | other, from a device path like /dev/mmcblk0p2.
storage_transport() {
  local dev=${1#/dev/} base
  case $dev in
    mmcblk*) echo sd; return ;;
    nvme*) echo nvme; return ;;
  esac
  base=${dev%%[0-9]*}
  if [[ -e /sys/block/$base ]] && readlink -f "/sys/block/$base" | grep -q '/usb'; then
    echo usb
  else
    echo other
  fi
}

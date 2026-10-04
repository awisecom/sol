# shellcheck shell=bash
SOL_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
export SOL_ROOT NO_COLOR=1

load_lib() {
  # shellcheck source=../lib/common.sh
  source "$SOL_ROOT/lib/common.sh"
  # shellcheck source=../lib/pi.sh
  source "$SOL_ROOT/lib/pi.sh"
}

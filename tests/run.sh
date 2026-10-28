#!/usr/bin/env bash
# Run every tests/test_*.sh. Each test_* function runs in its own subshell.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/helpers.sh"

pass=0
fail=0
if [ "$#" -gt 0 ]; then files=("$@"); else files=("$HERE"/test_*.sh); fi
for file in "${files[@]}"; do
  [ -e "$file" ] || continue
  names="$(bash -c '. "$1"; declare -F | sed -n "s/^declare -f \(test_.*\)$/\1/p"' _ "$file")"
  for name in $names; do
    # Not inside an `if` condition: bash ignores set -e there.
    (
      set -euo pipefail
      af_test_setup
      trap af_test_teardown EXIT
      . "$file"
      "$name"
    )
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "PASS $name"
      pass=$((pass + 1))
    else
      echo "FAIL $name"
      fail=$((fail + 1))
    fi
  done
done

echo "passed: $pass failed: $fail"
[ "$fail" -eq 0 ]

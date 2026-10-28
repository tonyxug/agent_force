#!/usr/bin/env bash
test_runner_reports_masked_failure() {
  local out rc=0
  out="$(bash "$REPO/tests/run.sh" "$REPO/tests/fixtures/masked_failure.sh" 2>/dev/null)" || rc=$?
  assert_contains "$out" "FAIL test_masked" "fixture reported FAIL"
  assert_eq 1 "$rc" "runner exit code"
}

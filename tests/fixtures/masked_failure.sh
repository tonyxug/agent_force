#!/usr/bin/env bash
# Deliberately failing fixture: an early failed assert must not be masked.
test_masked() {
  assert_eq 1 2 "must fail"
  true
}

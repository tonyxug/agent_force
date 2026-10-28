#!/usr/bin/env bash
T="(task agent_03-002)"
test_notag()                      { assert_eq "notag 0" "$(printf 'hi\n' | af-parse agent_03 "$T")" ""; }
test_tag_no_marker()              { assert_eq "none 0" "$(printf 'x %s\nthinking\n' "$T" | af-parse agent_03 "$T")" ""; }
test_done_with_bullet()           { assert_eq "done 1" "$(printf '%s\n⏺ result\n⏺ [agent_03: done]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_done_with_black_circle()     { assert_eq "done 1" "$(printf '%s\n● [agent_03: done]  \n' "$T" | af-parse agent_03 "$T")" ""; }
test_c_locale()                   { assert_eq "done 1" "$(printf '%s\n⏺ [agent_03: done]\n' "$T" | LC_ALL=C af-parse agent_03 "$T")" ""; }
test_last_marker_wins()           { assert_eq "blocked 2" "$(printf '%s\n[agent_03: working]\nQ?\n  [agent_03: blocked]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_marker_inside_prompt_above_tag_ignored() {
  s=$(printf 'write [agent_03: done] when done\n[agent_03: done]\n%s\nworking on it\n' "$T")
  assert_eq "none 0" "$(printf '%s\n' "$s" | af-parse agent_03 "$T")" ""
}
test_old_tag_ignored()            { s=$(printf '(task agent_03-001)\n[agent_03: done]\n%s\n' "$T"); assert_eq "none 0" "$(printf '%s\n' "$s" | af-parse agent_03 "$T")" ""; }
test_inline_marker_ignored()      { assert_eq "none 0" "$(printf '%s\nI will print [agent_03: done] later\n' "$T" | af-parse agent_03 "$T")" ""; }
test_other_agent_marker_ignored() { assert_eq "none 0" "$(printf '%s\n[agent_04: done]\n' "$T" | af-parse agent_03 "$T")" ""; }
test_body() {
  out=$(printf 'old\n> go %s\nline one\nline two\n[agent_03: done]\n> \n' "$T" | af-parse --body agent_03 "$T")
  assert_eq "$(printf 'line one\nline two')" "$out" "body"
}
test_body_empty_without_marker() {
  out=$(printf '%s\nline one\n' "$T" | af-parse --body agent_03 "$T")
  assert_eq "" "$out" "body"
}
test_usage_error() { assert_fail af-parse agent_03; }

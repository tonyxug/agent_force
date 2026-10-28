#!/usr/bin/env bash
test_name_normalize() {
  assert_eq agent_03 "$(af_name 3)" "3"
  assert_eq agent_03 "$(af_name 03)" "03"
  assert_eq agent_03 "$(af_name agent_03)" "agent_03"
  assert_eq agent_03 "$(af_name agent_3)" "agent_3"
  assert_eq agent_12 "$(af_name 12)" "12"
  assert_eq agent_01 "$(af_name 1)" "leader"
  assert_fail af_name foo
  assert_fail af_name 0
  assert_fail af_name 100
  assert_fail af_name ""
}
test_meta_roundtrip() {
  af_meta_set agent_02 branch "agent_force/agent_02"
  af_meta_set agent_02 cwd "/tmp/a b"
  assert_eq "agent_force/agent_02" "$(af_meta_get agent_02 branch)" "branch"
  assert_eq "/tmp/a b" "$(af_meta_get agent_02 cwd)" "space path"
  assert_eq "" "$(af_meta_get agent_02 missing)" "missing key"
  assert_eq "" "$(af_meta_get agent_09 branch)" "missing meta file"
}
test_meta_json() {
  af_meta_set_json agent_02 closed true
  assert_eq true "$(af_meta_get agent_02 closed)" "bool"
  assert_eq boolean "$(jq -r '.closed|type' "$(af_dir agent_02)/meta.json")" "type is bool"
}
test_status_roundtrip() { af_status_set agent_02 working; assert_eq working "$(af_status_get agent_02)" "status"; }
test_next_number() {
  assert_eq 2 "$(af_next_number)" "empty"
  mkdir -p "$AF_HOME/agents/agent_02" "$AF_HOME/agents/agent_09"
  assert_eq 10 "$(af_next_number)" "after 09"
}
test_uuid() { assert_contains "$(af_uuid)" "-" "uuid"; }
test_die() {
  out="$( (af_die boom) 2>&1 || true)"
  assert_eq "agent_force: boom" "$out" "die msg"
}
test_alive() {
  assert_fail af_alive agent_02
  af_tmux new-session -d -s agent_02 "sleep 30"
  af_alive agent_02
}
test_launch_puts_utils_first_on_path() {
  # tmux gives a new session the client's PATH, so `-e PATH=` alone is not enough.
  mkdir -p "$AF_TMP/adapter"
  printf '#!/usr/bin/env bash\necho "sh -c '"'"'echo \\"\\$PATH\\" > %s/path; sleep 30'"'"'"\n' "$AF_TMP" >"$AF_TMP/adapter/launch.sh"
  chmod +x "$AF_TMP/adapter/launch.sh"
  PATH="$(dirname "$(command -v tmux)"):/usr/bin:/bin" AF_ADAPTER_DIR="$AF_TMP/adapter" \
    af_launch worker agent_02 "$AF_TMP" id new
  i=0
  while [ ! -s "$AF_TMP/path" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  assert_contains ":$(cat "$AF_TMP/path")" ":$AF_ROOT/utils:" "utils on PATH"
}

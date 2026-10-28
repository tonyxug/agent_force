#!/usr/bin/env bash
# Fake agent: reads lines, answers once per task (line containing "(task ").
set -u
name="${AF_AGENT:-agent_??}"
echo "FAKE READY ${1:-new}"
text=""
while IFS= read -r line; do
  line="${line//$'\e[200~'/}"
  line="${line//$'\e[201~'/}"
  text="$text$line
"
  case "$line" in
    *"(task "*) ;;
    *) continue ;;
  esac
  case "$text" in
    *PLEASE_FAIL*)
      echo "[$name: failed]" ;;
    *PLEASE_BLOCK*)
      echo "Question: which one?"
      echo "[$name: blocked]" ;;
    *PLEASE_SLOW*)
      echo "[$name: working]"
      sleep 3
      echo "slow ok"
      echo "[$name: done]" ;;
    *)
      echo "result: ok"
      echo "[$name: done]" ;;
  esac
  text=""
done

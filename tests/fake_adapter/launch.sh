#!/usr/bin/env bash
# Fake adapter: launch.sh ROLE NAME SESSION_ID MODE -> prints the pane command.
set -euo pipefail
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${4:-new}"
printf 'bash %q %q\n' "$here/fake_agent.sh" "$mode"

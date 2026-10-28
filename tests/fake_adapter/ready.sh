#!/usr/bin/env bash
# Fake adapter: exit 0 when the screen (stdin) shows FAKE READY.
grep 'FAKE READY' >/dev/null

#!/usr/bin/env bash
# Print the clipboard's text for a paste into an Opal field, bounded: at most
# LIMIT+1 bytes, within TIMEOUT seconds. Run as its own process, so a clipboard
# owner that streams without end or never answers stalls this script, not
# the shell, and the shell never holds more than LIMIT+1 bytes of it.
#
# Exits 0 only when the whole clipboard was read; the caller still refuses
# anything over LIMIT bytes (a clipboard of exactly LIMIT+1 bytes ends
# before `head` closes the pipe). Nothing copied, a timeout, or a clipboard
# cut off by `head` (wl-paste then dies of SIGPIPE) all exit non-zero.
set -o pipefail
limit=${1:-16384}
seconds=${2:-2}
timeout -k 1 "$seconds" wl-paste --no-newline --type text 2>/dev/null | head -c "$((limit + 1))"

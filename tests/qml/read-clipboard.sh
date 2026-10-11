#!/usr/bin/env bash
# shell-plugin/read-clipboard.sh against fake wl-paste programs: whatever
# the clipboard owner does, the read ends in bounded time with bounded output.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$here/../../shell-plugin/read-clipboard.sh
bin=$(mktemp -d); out=$(mktemp)
trap 'rm -rf "$bin" "$out"' EXIT
fails=0

# fake NAME BODY: wl-paste is a script running BODY.
fake() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$bin/wl-paste"; chmod +x "$bin/wl-paste"; echo "- $1"; }

# check LIMIT WANT_CODE WANT_BYTES MAX_SECONDS
check() {
  local start=$SECONDS code bytes
  PATH="$bin:$PATH" bash "$script" "$1" 2 >"$out"; code=$?
  bytes=$(wc -c <"$out")
  local took=$((SECONDS - start)) ok=1
  case $2 in any) ;; nonzero) (( code != 0 )) || ok=0 ;; *) (( code == $2 )) || ok=0 ;; esac
  [[ $3 == any ]] || (( bytes == $3 )) || ok=0
  (( bytes <= $1 + 1 )) || ok=0
  (( took <= $4 )) || ok=0
  if (( ok )); then echo "  ok"; else echo "  FAIL: exit $code, $bytes bytes, ${took}s"; fails=$((fails + 1)); fi
}

fake "plain text comes through" 'printf "nostrconnect://abc"'
check 100 0 18 1
fake "nothing copied" 'echo "Nothing is copied" >&2; exit 1'
check 100 nonzero 0 1
fake "an endless stream stops at the limit" 'exec yes'
check 1000 nonzero 1001 2
fake "exactly the limit is read whole" 'head -c 1000 /dev/zero | tr "\0" a'
check 1000 0 1000 1
fake "one byte over is passed on for the caller to refuse" 'head -c 1001 /dev/zero | tr "\0" a'
check 1000 any 1001 1
fake "an owner that never answers times out" 'exec sleep 60'
check 100 nonzero 0 4
fake "one that ignores SIGTERM is killed" 'trap "" TERM; sleep 60 & wait; sleep 60'
check 100 nonzero 0 5
fake "a child holding the pipe open is killed too" 'printf partial; (sleep 60) & wait'
check 100 nonzero any 5
fake "a slow trickle is cut off by the deadline" 'while :; do printf x; sleep 0.2; done'
check 1000 nonzero any 4

echo
(( fails == 0 )) && echo "read-clipboard: all ok" || { echo "read-clipboard: $fails failed"; exit 1; }

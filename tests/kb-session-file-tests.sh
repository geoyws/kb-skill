#!/usr/bin/env bash
# Offline checks for scripts/kb-session-file. Fake TMUX values only; no tmux
# server, board or network is touched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
F="$HERE/../scripts/kb-session-file"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# run <TMUX> <TMUX_PANE> [args...] -> prints "<status> <path>"
run() {
  local tmux=$1 pane=$2 out status
  shift 2
  set +e
  out=$(env -u TMUX -u TMUX_PANE ${tmux:+TMUX="$tmux"} ${pane:+TMUX_PANE="$pane"} KB_SESSION_HOME="$T/home" "$F" "$@" 2>/dev/null)
  status=$?
  set -e
  printf '%s %s\n' "$status" "$out"
}

a=$(run "/tmp/tmux-501/sockA,111,0" "%0")
a_again=$(run "/tmp/tmux-501/sockA,222,3" "%0")
b=$(run "/tmp/tmux-501/sockB,111,0" "%0")
c=$(run "/tmp/tmux-501/sockA,111,0" "%7")

[ "${a%% *}" = 0 ] || fail "in-tmux status: $a"
case "${a#* }" in "$T/home/kb-session.d/tmux-"*-0) ;; *) fail "unexpected path: $a";; esac
# Same socket and pane is the same session, whatever the server pid/session.
[ "$a" = "$a_again" ] || fail "same pane differs: $a vs $a_again"
# The collision this fixes: pane %0 on two different tmux servers.
[ "$a" != "$b" ] || fail "two servers' %0 collide: $a"
[ "$a" != "$c" ] || fail "two panes on one server collide: $a"

mode=$(stat -f '%Lp' "$T/home/kb-session.d" 2>/dev/null || stat -c '%a' "$T/home/kb-session.d")
[ "$mode" = 700 ] || fail "session dir mode $mode, want 700"

outside=$(run "" "")
[ "$outside" = "3 $T/home/kb-session" ] || fail "outside tmux: $outside"
[ "$(run "/tmp/s,1,0" "%0" --legacy)" = "0 $T/home/kb-session" ] || fail "--legacy"
[ "$(run "/tmp/s,1,0" "%x")" = "65 " ] || fail "malformed pane accepted"
[ "$(run "/tmp/s,1,0" "%0" --bogus)" = "64 " ] || fail "unknown argument accepted"

printf 'kb-session-file tests: ok\n'

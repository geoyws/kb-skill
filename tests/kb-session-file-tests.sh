#!/usr/bin/env bash
# Offline checks for scripts/kb-session-file. Fake TMUX/KB_SESSION_ID values
# only; no tmux server, board or network is touched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
F="$HERE/../scripts/kb-session-file"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Portable mode probe: GNU stat first (Linux), BSD stat fallback (macOS).
# BSD-first mixes filesystem text into stdout on Linux, so the GNU spelling
# must win where it exists. Prints the bare mode, or nothing on failure so
# the caller's assertion still fires instead of passing silently.
stat_mode() {
  local m
  if m=$(stat -c '%a' "$1" 2>/dev/null); then
    printf '%s\n' "$m"
    return 0
  fi
  stat -f '%Lp' "$1" 2>/dev/null
}

# run <TMUX> <TMUX_PANE> [args...] -> prints "<status> <path>"
run() {
  local tmux=$1 pane=$2 out status
  shift 2
  set +e
  out=$(env -u TMUX -u TMUX_PANE -u KB_SESSION_ID KB_SESSION_HOME="$T/home" ${tmux:+TMUX="$tmux"} ${pane:+TMUX_PANE="$pane"} "$F" "$@" 2>/dev/null)
  status=$?
  set -e
  printf '%s %s\n' "$status" "$out"
}

# srun <sid|-> [args...] -> prints "<status> <path>"; TMUX always unset.
# A first argument of "-" means KB_SESSION_ID unset; "=" means set-but-empty.
srun() {
  local sid=$1 out status home=${SID_HOME:-$T/home}
  shift
  set +e
  case "$sid" in
    -) out=$(env -u TMUX -u TMUX_PANE -u KB_SESSION_ID KB_SESSION_HOME="$home" "$F" "$@" 2>/dev/null); status=$?;;
    =) out=$(env -u TMUX -u TMUX_PANE KB_SESSION_ID= KB_SESSION_HOME="$home" "$F" "$@" 2>/dev/null); status=$?;;
    *) out=$(env -u TMUX -u TMUX_PANE KB_SESSION_HOME="$home" KB_SESSION_ID="$sid" "$F" "$@" 2>/dev/null); status=$?;;
  esac
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

mode=$(stat_mode "$T/home/kb-session.d")
[ "$mode" = 700 ] || fail "session dir mode $mode, want 700"

outside=$(run "" "")
[ "$outside" = "3 $T/home/kb-session" ] || fail "outside tmux: $outside"
[ "$(run "/tmp/s,1,0" "%0" --legacy)" = "0 $T/home/kb-session" ] || fail "--legacy"
[ "$(run "/tmp/s,1,0" "%x")" = "65 " ] || fail "malformed pane accepted"
[ "$(run "/tmp/s,1,0" "%0" --bogus)" = "64 " ] || fail "unknown argument accepted"

# --- Explicit session identity (KB_SESSION_ID) namespace ---
# Measured defect: with TMUX unset, session-a and session-b both printed the
# legacy path with exit 3. A nonempty id must win its own file with exit 0.
sa=$(srun "session-a")
sb=$(srun "session-b")
[ "${sa%% *}" = 0 ] || fail "session-a status: $sa"
[ "${sb%% *}" = 0 ] || fail "session-b status: $sb"
[ "$sa" != "3 $T/home/kb-session" ] || fail "session-a fell back to legacy: $sa"
[ "${sa#* }" != "${sb#* }" ] || fail "concurrent sessions share a file: $sa vs $sb"
base_a=${sa#* }; base_a=${base_a##*/}
base_b=${sb#* }; base_b=${base_b##*/}
rest_a=${base_a#session-}; rest_b=${base_b#session-}
case "${sa#* }" in "$T/home/kb-session.d/session-"*) ;; *) fail "unexpected session path: $sa";; esac
[ "${#rest_a}" = 64 ] || fail "session name not 64 hex chars: $sa"
[ "${#rest_b}" = 64 ] || fail "session name not 64 hex chars: $sb"
case "$rest_a" in ''|*[!0-9a-f]*) fail "session name not hex-only: $sa";; esac
case "$rest_b" in ''|*[!0-9a-f]*) fail "session name not hex-only: $sb";; esac
# Deterministic reopen: the same id derives the same file.
[ "$(srun "session-a")" = "$sa" ] || fail "same session id reopened a different file"
# Precedence: an explicit id wins over tmux pane detection.
set +e
prec_out=$(env TMUX="/tmp/tmux-501/sockA,111,0" TMUX_PANE="%0" KB_SESSION_HOME="$T/home" KB_SESSION_ID="session-a" "$F" 2>/dev/null)
prec_status=$?
set -e
[ "$prec_status $prec_out" = "$sa" ] || fail "session id must take precedence over tmux: $prec_status $prec_out vs $sa"
# Traversal segments and sanitization lookalikes must not collide.
trav=$(srun "../evil"); te=$(srun "a/b"); tu=$(srun "a_b")
[ "${trav%% *}" = 0 ] || fail "traversal-style id refused: $trav"
[ "${te%% *}" = 0 ] || fail "slash id refused: $te"
for p in "$trav" "$te" "$tu"; do
  case "${p#* }" in "$T/home/kb-session.d/session-"*) ;; *) fail "unsafe session path: $p";; esac
done
[ "${trav#* }" != "${te#* }" ] || fail "traversal-style ids collide: $trav vs $te"
[ "${te#* }" != "${tu#* }" ] || fail "sanitization-style ids collide: $te vs $tu"
# A fresh home proves the session branch creates its own private directory.
SID_HOME="$T/home2"
fresh=$(srun "session-a")
unset SID_HOME
[ "${fresh%% *}" = 0 ] || fail "session status in fresh home: $fresh"
[ "${fresh#* }" = "$T/home2/kb-session.d/$base_a" ] || fail "session name not deterministic across homes: $fresh vs $base_a"
mode2=$(stat_mode "$T/home2/kb-session.d")
[ "$mode2" = 700 ] || fail "session dir mode $mode2, want 700"
# Real files: each session's task id and lease token stay isolated.
fa=${sa#* }; fb=${sb#* }
(umask 077; printf '%s\n%s\n' "task-a" "token-a" > "$fa")
(umask 077; printf '%s\n%s\n' "task-b" "token-b" > "$fb")
[ "$(cat "$fa")" = "$(printf '%s\n%s' "task-a" "token-a")" ] || fail "session-a content clobbered"
[ "$(cat "$fb")" = "$(printf '%s\n%s' "task-b" "token-b")" ] || fail "session-b content clobbered"
fmode_a=$(stat_mode "$fa"); [ "$fmode_a" = 600 ] || fail "session-a token mode $fmode_a, want 600"
fmode_b=$(stat_mode "$fb"); [ "$fmode_b" = 600 ] || fail "session-b token mode $fmode_b, want 600"
n_before=$(ls -A "$T/home/kb-session.d" | wc -l)
# Refusals: explicitly empty, control-character, and over-long ids print no
# path, so a caller capturing stdout writes no token file.
[ "$(srun "=")" = "65 " ] || fail "explicitly empty KB_SESSION_ID accepted"
[ "$(srun "-")" = "3 $T/home/kb-session" ] || fail "unset KB_SESSION_ID changed behavior: $(srun "-")"
[ "$(srun "$(printf 'a\nb')")" = "65 " ] || fail "newline session id accepted"
[ "$(srun "$(printf 'a\rb')")" = "65 " ] || fail "CR session id accepted"
[ "$(srun "$(printf '%257s' ' ' | tr ' ' 'x')")" = "65 " ] || fail "over-long session id accepted"
# Byte limit is bytes, not characters: 200 é is 200 chars but 400 bytes.
uni=''; i=0; while [ "$i" -lt 200 ]; do uni="${uni}é"; i=$((i + 1)); done
[ "$(srun "$uni")" = "65 " ] || fail "over-long-in-bytes unicode session id accepted"
# Exactly 256 bytes is accepted (separate home: acceptance creates a file).
SID_HOME="$T/home3"
b256=$(srun "$(printf '%256s' ' ' | tr ' ' 'x')")
unset SID_HOME
[ "${b256%% *}" = 0 ] || fail "256-byte session id refused: $b256"
case "${b256#* }" in "$T/home3/kb-session.d/session-"*) ;; *) fail "unexpected 256-byte session path: $b256";; esac
# A trailing newline cannot survive command substitution, so export it directly.
set +e
trail_out=$(env -u TMUX -u TMUX_PANE KB_SESSION_HOME="$T/home" KB_SESSION_ID=$'a\n' "$F" 2>/dev/null)
trail_status=$?
set -e
[ "$trail_status $trail_out" = "65 " ] || fail "trailing-newline session id accepted: $trail_status $trail_out"
[ "$(srun "session-a" --legacy)" = "0 $T/home/kb-session" ] || fail "--legacy with session id"
[ "$(srun "session-a" --bogus)" = "64 " ] || fail "unknown argument with session id accepted"
[ "$(cat "$fa")" = "$(printf '%s\n%s' "task-a" "token-a")" ] || fail "refused call touched session-a token"
[ "$(cat "$fb")" = "$(printf '%s\n%s' "task-b" "token-b")" ] || fail "refused call touched session-b token"
n_after=$(ls -A "$T/home/kb-session.d" | wc -l)
[ "$n_before" = "$n_after" ] || fail "refused call created a session file"

printf 'kb-session-file tests: ok\n'

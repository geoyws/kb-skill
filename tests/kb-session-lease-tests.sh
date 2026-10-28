#!/bin/bash
set -euo pipefail
source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rm -rf -- "$t"' EXIT
mkdir -p "$t/scripts" "$t/home"
cp "$source_dir/scripts/kb-session-lease" "$source_dir/scripts/kb-session-file" "$t/scripts/"
cat >"$t/scripts/kb-board" <<'SH'
#!/bin/bash
set -eu
printf '%s\n' "$*" >>"$TEST_ROOT/calls"
# Like kb: a flag given twice is refused before anything else (t-75164807).
if [ "$(printf '%s\n' "$@" | grep -cx -- '--json')" -gt 1 ]; then
  printf '{"error":"--json (true, true) given more than once; it takes a single value"}\n'
  echo 'Error: --json (true, true) given more than once; it takes a single value' >&2
  exit 2
fi
# Real board and transport failures for one call, chosen by FAKE_FAIL (t-8ccffdeb).
case "${FAKE_FAIL:-}" in
  ended) echo 'Error: task t-fake has no active lease: it was never claimed, or the lease expired and was retired; claim the task to write to it' >&2; exit 1 ;;
  mismatch) echo 'Error: task t-fake is leased by @:x/y/z/executor until 1793182679357, and that is not the lease you presented: it was superseded, so reacquire the task before writing to it' >&2; exit 1 ;;
  ssh) exit 255 ;;
  silent) exit 1 ;;
  routing) echo 'kb-board: unknown board: nosuch' >&2; exit 64 ;;
  gated) echo 'Error: task t-fake is gated on work that is not done' >&2; exit 1 ;;
  exec127) echo 'bash: line 1: kb: command not found' >&2; exit 127 ;;
  exec126) echo 'bash: line 1: /usr/local/bin/kb: Permission denied' >&2; exit 126 ;;
esac
case "$2 $3" in
  'claim t-fake') printf '{"taskID":"t-fake","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' ;;
  # A LINKED scope binding made without a session refuses a sessioned triple.
  'claim t-bound')
    case " $* " in
      *' --session '*) printf '{"error":"task t-bound is not claimable under selected set ss-1: test matches no live binding; the actor holds lane driver, session (none) on that set. Present the bound triple, or rebind with an audited `scope bind` revision"}\n'; exit 1 ;;
    esac
    printf '{"taskID":"t-bound","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' ;;
  # Any other refusal must not trigger the sessionless retry.
  'claim t-refused') printf '{"error":"task t-refused is gated"}\n'; exit 1 ;;
  'h acc')
    if [ "$4" = h-session ]; then
      printf '{"claim":null,"handoff":{"id":"h-session","taskID":null}}\n'
    else
      printf '{"claim":{"taskID":"t-fake","leaseToken":"87654321-4321-4321-4321-210987654321"},"handoff":{"id":"h-test"}}\n'
    fi ;;
  'cp t-fake')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*) ;; *) exit 61 ;; esac
    # A refusal that quotes the lease must reach the caller masked.
    case " $* " in *' --summary quote-lease '*) printf '{"error":"lease 12345678-1234-1234-1234-123456789012 refused: blocker required"}\n'; exit 1 ;; esac
    case " $* " in
      *' --state done '*) printf '{"state":"done"}\n' ;;
      *' --state blocked '*) printf '{"state":"blocked"}\n' ;;
      *) printf '{"state":"continue"}\n' ;;
    esac ;;
  # The lease is granted, but the session path fills before the wrapper stores it.
  'claim t-race')
    printf 'other\n' >"$LEASE_SESSION_PATH"
    printf '{"taskID":"t-race","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' ;;
  # The lease is granted, then the session directory stops taking new files.
  'claim t-nowrite')
    chmod 500 "$(dirname "$LEASE_SESSION_PATH")"
    printf '{"taskID":"t-nowrite","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' ;;
  'release t-nowrite')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*) ;; *) exit 61 ;; esac
    printf '{"ok":true}\n' ;;
  # Granted and unstorable, and the first give-back release fails.
  'claim t-relfail'|'claim t-nwrf'|'claim t-norec')
    case "$3" in
      t-relfail) printf 'other\n' >"$LEASE_SESSION_PATH" ;;
      *) chmod 500 "$(dirname "$LEASE_SESSION_PATH")" ;;
    esac
    printf '{"taskID":"%s","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' "$3" ;;
  'release t-relfail'|'release t-nwrf'|'release t-norec')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*) ;; *) exit 61 ;; esac
    if [ ! -e "$TEST_ROOT/released-$3" ]; then : >"$TEST_ROOT/released-$3"; exit 1; fi
    printf '{"ok":true}\n' ;;
  'release t-race')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*) ;; *) exit 61 ;; esac
    printf '{"ok":true}\n' ;;
  'hb t-fake'|'release t-fake'|'h new')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*|*' --lease 87654321-4321-4321-4321-210987654321 '*) ;; *) exit 61 ;; esac
    printf '{"ok":true}\n' ;;
  't cat')
    case "$4" in
      t-settled) printf '{"id":"t-settled","claim":null}\n' ;;
      t-expired) printf '{"id":"t-expired","claim":{"expiresAt":1}}\n' ;;
      t-active) printf '{"id":"t-active","claim":{"expiresAt":9999999999999}}\n' ;;
      t-ambiguous) printf '{"id":"t-ambiguous","claim":{}}\n' ;;
      t-wrongboard) printf '{"id":"t-someone-else","claim":null}\n' ;;
      # A long trail refuses an uncapped show, as the ledger does past its default caps (ADR-037).
      t-longtrail) case " $* " in *' --limit '*) printf '{"id":"t-longtrail","claim":null}\n' ;; *) exit 4 ;; esac ;;
      t-boardfail) exit 3 ;;
      *) exit 62 ;;
    esac ;;
  *) exit 62 ;;
esac
SH
chmod +x "$t/scripts/kb-board"
export HOME="$t/home" KB_SESSION_ID=lease-test-session TEST_ROOT="$t"
lease="$t/scripts/kb-session-lease"
session=$("$t/scripts/kb-session-file")
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles claim t-fake --as test)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
case "$out" in *12345678*) exit 1 ;; esac
[ "$(stat -c %a "$session" 2>/dev/null || stat -f %Lp "$session")" = 600 ] || exit 1
[ "$(sed -n '1p' "$session")" = t-fake ] || exit 1
# The claim is recorded under KB_SESSION_ID, so `release --session` can end it.
[ "$(sed -n '1p' "$t/calls")" = 'dotfiles claim t-fake --as test --session lease-test-session --json' ] || exit 1
# An unrelated second claim must not silently overwrite this session's token.
if "$lease" dotfiles claim t-other --as test >"$t/refusal" 2>&1; then exit 1; fi
[ "$(wc -l < "$t/calls" | tr -d ' ')" = 1 ] || exit 1
out=$("$lease" dotfiles hb t-fake)
[ "$out" = '{"taskID":"t-fake","operation":"hb","ok":true}' ] || exit 1
out=$("$lease" dotfiles checkpoint t-fake --as test --state continue --summary progress --intent work --next-action next)
[ "$out" = '{"taskID":"t-fake","operation":"checkpoint","ok":true}' ] || exit 1
[ -f "$session" ] || exit 1
out=$("$lease" dotfiles release t-fake)
[ "$out" = '{"taskID":"t-fake","operation":"release","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles claim t-fake --as test)
[ -f "$session" ] || exit 1
out=$("$lease" dotfiles checkpoint t-fake --as test --state done --summary done --intent done --next-action next)
[ "$out" = '{"taskID":"t-fake","operation":"checkpoint","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
# An explicit --session is passed through once and wins over KB_SESSION_ID.
out=$("$lease" dotfiles claim t-fake --as test --session explicit-session)
[ "$(tail -n 1 "$t/calls")" = 'dotfiles claim t-fake --as test --session explicit-session --json' ] || exit 1
out=$("$lease" dotfiles release t-fake)
# A blocked checkpoint parks the row: the lease leaves the session, so a lane
# waiting on a long job can claim its next row from the same pane.
out=$("$lease" dotfiles claim t-fake --as test)
[ -f "$session" ] || exit 1
out=$("$lease" dotfiles checkpoint t-fake --as test --state blocked --blocker 'gate running' --summary parked --intent wait --next-action reclaim)
[ "$out" = '{"taskID":"t-fake","operation":"checkpoint","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles claim t-fake --as test)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
out=$("$lease" dotfiles checkpoint t-fake --as test --state done --summary done --intent done --next-action next)
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles handoff-accept h-test --as test)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
[ "$(grep -c '^dotfiles h acc h-test --as test --session lease-test-session --json$' "$t/calls")" = 1 ] || exit 1
out=$("$lease" dotfiles release t-fake)
[ ! -e "$session" ] || exit 1
# Sessionless scope binding: one sessioned try, one sessionless retry, a warning, and the lease stored.
n=$(wc -l < "$t/calls" | tr -d ' ')
out=$("$lease" dotfiles claim t-bound --as test 2>"$t/warn")
[ "$out" = '{"taskID":"t-bound","leaseStored":true}' ] || exit 1
grep -qF 'release --session will not free this lease' "$t/warn" || exit 1
[ "$(tail -n 2 "$t/calls" | head -n 1)" = 'dotfiles claim t-bound --as test --session lease-test-session --json' ] || exit 1
[ "$(tail -n 1 "$t/calls")" = 'dotfiles claim t-bound --as test --json' ] || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = $((n + 2)) ] || exit 1
rm -f "$session"
# Any other refusal fails once, with no retry.
n=$(wc -l < "$t/calls" | tr -d ' ')
if "$lease" dotfiles claim t-refused --as test >"$t/refusal" 2>&1; then exit 1; fi
[ "$(wc -l < "$t/calls" | tr -d ' ')" = $((n + 1)) ] || exit 1
out=$("$lease" dotfiles handoff-accept h-test --as test)
out=$("$lease" dotfiles handoff-create t-fake --as test --summary done --intent done --next-action done)
[ "$out" = '{"taskID":"t-fake","operation":"handoff-create","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles handoff-accept h-session --as test)
[ "$out" = '{"handoffID":"h-session","leaseStored":false}' ] || exit 1
[ ! -e "$session" ] || exit 1
# Wrong task, manually supplied token, and symlinked session file fail before a board call.
n=$(wc -l < "$t/calls" | tr -d ' ')
if "$lease" dotfiles hb t-other >"$t/refusal" 2>&1; then exit 1; fi
if "$lease" dotfiles claim t-fake --lease forged >"$t/refusal" 2>&1; then exit 1; fi
ln -s "$t/target" "$session"
if "$lease" dotfiles claim t-fake >"$t/refusal" 2>&1; then exit 1; fi
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
rm -f "$session"
# A caller's own --json reaches the board once (t-75164807: px driver-4 claims
# failed 6/6 on "--json given more than once"), for claim and checkpoint.
out=$("$lease" dotfiles claim t-fake --as test --json)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
[ "$(tail -n 1 "$t/calls")" = 'dotfiles claim t-fake --as test --session lease-test-session --json' ] || exit 1
out=$("$lease" dotfiles checkpoint t-fake --as test --state continue --json --summary s --intent i --next-action n)
[ "$out" = '{"taskID":"t-fake","operation":"checkpoint","ok":true}' ] || exit 1
[ "$(tail -n 1 "$t/calls" | grep -o -- '--json' | wc -l | tr -d ' ')" = 1 ] || exit 1
# A refusal reaches the caller readable, with the lease masked.
if "$lease" dotfiles checkpoint t-fake --as test --state blocked --summary quote-lease >"$t/out-q" 2>"$t/err-q"; then exit 1; fi
grep -qF 'lease operation (checkpoint) failed [cause=refused]: lease <lease> refused: blocker required' "$t/err-q" || exit 1
out=$("$lease" dotfiles release t-fake)
[ ! -e "$session" ] || exit 1
if "$lease" dotfiles claim t-refused --as test >"$t/out-r" 2>"$t/err-r"; then exit 1; fi
grep -qF 'claim or handoff acceptance failed [cause=refused]: task t-refused is gated' "$t/err-r" || exit 1
# Every failure names a stable cause class and the next step; the session
# record stays put on a board or transport failure.
out=$("$lease" dotfiles claim t-fake --as test)
for mode in ended:claim_ended mismatch:lease_mismatch ssh:transport silent:transport routing:transport gated:refused exec127:transport exec126:transport; do
  if FAKE_FAIL=${mode%%:*} "$lease" dotfiles hb t-fake >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
  grep -qF "lease operation (hb) failed [cause=${mode#*:}]:" "$t/err-c" || exit 1
  grep -qF '; next: ' "$t/err-c" || exit 1
  [ "$(sed -n '1p' "$session")" = t-fake ] || exit 1
  if grep -qF 12345678-1234 "$t/out-c" "$t/err-c"; then exit 1; fi
done
if FAKE_FAIL=ssh "$lease" dotfiles hb t-fake >/dev/null 2>"$t/err-c"; then exit 1; fi
grep -qF 'may or may not have taken effect' "$t/err-c" || exit 1
if FAKE_FAIL=routing "$lease" dotfiles hb t-fake >/dev/null 2>"$t/err-c"; then exit 1; fi
grep -qF 'never reached the board' "$t/err-c" || exit 1
if FAKE_FAIL=ended "$lease" dotfiles checkpoint t-fake --as test --state continue --summary s --intent i --next-action n >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF "kb-session-lease dotfiles recover t-fake" "$t/err-c" || exit 1
if FAKE_FAIL=ssh "$lease" dotfiles claim t-other --as test >/dev/null 2>"$t/err-c"; then exit 1; fi
grep -qF 'session already has a lease' "$t/err-c" || exit 1
if "$lease" dotfiles hb t-other >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF 'lease operation failed [cause=no_session_file]: task does not match session lease: this session holds t-fake' "$t/err-c" || exit 1
out=$("$lease" dotfiles release t-fake)
if "$lease" dotfiles hb t-fake >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF 'lease operation failed [cause=no_session_file]: no session lease for t-fake' "$t/err-c" || exit 1
if FAKE_FAIL=ssh "$lease" dotfiles claim t-fake --as test >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF 'claim or handoff acceptance failed [cause=transport]:' "$t/err-c" || exit 1
[ ! -e "$session" ] || exit 1
[ "$(wc -l <"$t/err-c" | tr -d ' ')" = 1 ] || exit 1
# A handoff names a handoff lookup, and cleanup prints nothing more.
if FAKE_FAIL=ssh "$lease" dotfiles handoff-accept h-test --as test >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF 'claim or handoff acceptance failed [cause=transport]:' "$t/err-c" || exit 1
grep -qF 'kb-board dotfiles h ls --all --json (find h-test' "$t/err-c" || exit 1
if grep -qF 't cat h-test' "$t/err-c"; then exit 1; fi
[ "$(wc -l <"$t/err-c" | tr -d ' ')" = 1 ] || exit 1
[ ! -e "$session" ] || exit 1
# Local refusals name a cause too: usage, a busy session (claim and handoff
# accept), and each recover refusal.
cause_of() { "$@" >/dev/null 2>"$t/err-c" && return 1; sed -n 's/.*failed \[cause=\([a-z_]*\)\].*/\1/p' "$t/err-c" | head -n 1; }
[ "$(cause_of "$lease" dotfiles)" = usage ] || exit 1
[ "$(cause_of "$lease" dotfiles claim x-1)" = usage ] || exit 1
[ "$(cause_of "$lease" dotfiles hb t-fake --lease forged)" = usage ] || exit 1
[ "$(cause_of "$lease" dotfiles recover t-fake)" = no_session_file ] || exit 1
out=$("$lease" dotfiles claim t-fake --as test)
[ "$(cause_of "$lease" dotfiles claim t-other --as test)" = session_busy ] || exit 1
[ "$(cause_of "$lease" dotfiles handoff-accept h-test --as test)" = session_busy ] || exit 1
[ "$(cause_of "$lease" dotfiles recover t-other)" = no_session_file ] || exit 1
out=$("$lease" dotfiles release t-fake)
printf 't-active\n12345678-1234-1234-1234-123456789012\n' >"$session"; chmod 600 "$session"
[ "$(cause_of "$lease" dotfiles recover t-active)" = claim_active ] || exit 1
printf 't-boardfail\n12345678-1234-1234-1234-123456789012\n' >"$session"; chmod 600 "$session"
[ "$(cause_of "$lease" dotfiles recover t-boardfail)" = transport ] || exit 1
rm -f "$session"
# A damaged record with the token on its first line is never quoted.
printf '12345678-1234-1234-1234-123456789012\nt-fake\n' >"$session"; chmod 600 "$session"
if "$lease" dotfiles hb t-fake >"$t/out-c" 2>"$t/err-c"; then exit 1; fi
grep -qF '[cause=no_session_file]: malformed session record for t-fake' "$t/err-c" || exit 1
if grep -qF 12345678 "$t/out-c" "$t/err-c"; then exit 1; fi
rm -f "$session"
# A malformed record names a path that works: recover refuses it, mv frees it.
printf 't-fake\n' >"$session"; chmod 600 "$session"
if "$lease" dotfiles hb t-fake >/dev/null 2>"$t/err-c"; then exit 1; fi
grep -qF '[cause=no_session_file]: malformed session record for t-fake' "$t/err-c" || exit 1
if "$lease" dotfiles recover t-fake >/dev/null 2>&1; then exit 1; fi
aside=$(sed -n "s/.*move it aside with \(mv '[^']*' '[^']*'\).*/\1/p" "$t/err-c")
[ -n "$aside" ] || exit 1
eval "$aside"
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles claim t-fake --as test)
out=$("$lease" dotfiles release t-fake)
# A granted lease that cannot be stored is released again: no orphaned lease.
if LEASE_SESSION_PATH="$session" "$lease" dotfiles claim t-race --as test >"$t/out-race" 2>"$t/err-race"; then exit 1; fi
[ "$(tail -n 1 "$t/calls")" = 'dotfiles release t-race --lease 12345678-1234-1234-1234-123456789012' ] || exit 1
grep -qF 'released the board lease on t-race again, nothing is held' "$t/err-race" || exit 1
[ "$(cat "$session")" = other ] || exit 1
rm -f "$session"
# A failure before the link (no new file in the session directory) also gives the lease back.
if LEASE_SESSION_PATH="$session" "$lease" dotfiles claim t-nowrite --as test >"$t/out-nw" 2>"$t/err-nw"; then chmod 700 "$(dirname "$session")"; exit 1; fi
chmod 700 "$(dirname "$session")"
rm -f -- "$(dirname "$session")"/.lease-*
[ "$(tail -n 1 "$t/calls")" = 'dotfiles release t-nowrite --lease 12345678-1234-1234-1234-123456789012' ] || exit 1
grep -qF 'released the board lease on t-nowrite again, nothing is held' "$t/err-nw" || exit 1
[ ! -e "$session" ] || exit 1
fmode0() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# A failed give-back keeps a private record the lane can still release with.
if LEASE_SESSION_PATH="$session" "$lease" dotfiles claim t-relfail --as test >"$t/out-rf" 2>"$t/err-rf"; then exit 1; fi
rec=$(ls "$(dirname "$session")"/unreleased-t-relfail.* 2>/dev/null)
[ -n "$rec" ] && [ "$(fmode0 "$rec")" = 600 ] || exit 1
[ "$(sed -n '1p' "$rec")" = t-relfail ] && [ "$(sed -n '2p' "$rec")" = 12345678-1234-1234-1234-123456789012 ] || exit 1
grep -qF "lease record is kept at $rec" "$t/err-rf" || exit 1
[ "$(cat "$session")" = other ] || exit 1
rm -f "$session"
mv "$rec" "$session"
out=$("$lease" dotfiles release t-relfail)
[ "$out" = '{"taskID":"t-relfail","operation":"release","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
# With the session directory unwritable, the record goes to ~/.kb-session-unreleased.
if LEASE_SESSION_PATH="$session" "$lease" dotfiles claim t-nwrf --as test >"$t/out-nwrf" 2>"$t/err-nwrf"; then chmod 700 "$(dirname "$session")"; exit 1; fi
chmod 700 "$(dirname "$session")"
rm -f -- "$(dirname "$session")"/.lease-*
rec=$(ls "$HOME/.kb-session-unreleased"/unreleased-t-nwrf.* 2>/dev/null)
[ -n "$rec" ] && [ "$(fmode0 "$rec")" = 600 ] && [ "$(fmode0 "$HOME/.kb-session-unreleased")" = 700 ] || exit 1
grep -qF "lease record is kept at $rec" "$t/err-nwrf" || exit 1
rm -f -- "$rec"
# No new record possible anywhere: the private grant reply survives, and the
# printed recovery command releases the lease through the wrapper.
rm -rf -- "$HOME/.kb-session-unreleased"
mkdir -p "$t/elsewhere"
ln -s "$t/elsewhere" "$HOME/.kb-session-unreleased"
if LEASE_SESSION_PATH="$session" "$lease" dotfiles claim t-norec --as test >"$t/out-nr" 2>"$t/err-nr"; then chmod 700 "$(dirname "$session")"; exit 1; fi
chmod 700 "$(dirname "$session")"
rm -f -- "$(dirname "$session")"/.lease-error.* "$(dirname "$session")"/.lease-next.*
kept=$(sed -n 's/.*The board reply holding the lease is kept at \(.*\) (mode 0600).*/\1/p' "$t/err-nr")
[ -n "$kept" ] && [ -f "$kept" ] && [ "$(fmode0 "$kept")" = 600 ] || exit 1
[ -z "$(ls -A "$t/elsewhere")" ] || exit 1
recovery=$(sed -n 's/.*run: //p' "$t/err-nr")
out=$(PATH="$t/scripts:$PATH" eval "$recovery")
[ "$out" = '{"taskID":"t-norec","operation":"release","ok":true}' ] || exit 1
[ ! -e "$session" ] && [ ! -e "$kept" ] || exit 1
rm -f -- "$HOME/.kb-session-unreleased"
if grep -qF 12345678-1234 "$t/out-q" "$t/err-q" "$t/out-r" "$t/err-r" "$t/out-race" "$t/err-race" "$t/out-nw" "$t/err-nw" "$t/out-rf" "$t/err-rf" "$t/out-nwrf" "$t/err-nwrf" "$t/out-nr" "$t/err-nr"; then exit 1; fi
printf '%s\n' 'kb-session-lease: claim, heartbeat, release, accept, handoff, and refusal PASS'
# Stale-record recover coverage: fresh fake tokens and separate session ids per scenario.
fmode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
mkrec() {
  _s=$(KB_SESSION_ID="$1" "$t/scripts/kb-session-file")
  rm -f -- "$_s"
  (umask 077; printf '%s\n%s\n' "$2" "$3" >"$_s")
  chmod 600 "$_s"
  printf '%s' "$_s"
}
TOK_SETTLED='recTok-settled-0001-aaaa'
TOK_EXPIRED='recTok-expired-0002-bbbb'
TOK_ACTIVE='recTok-active-0003-cccc'
TOK_AMBIG='recTok-ambig-0004-dddd'
TOK_WRONGTASK='recTok-wrongtask-0005-eeee'
TOK_WRONGBOARD='recTok-wrongboard-0006-ffff'
TOK_BOARDFAIL='recTok-boardfail-0007-gggg'
TOK_MALFORMED='recTok-malformed-0008-hhhh'
TOK_RACE='recTok-race-0009-iiii'
TOK_LOCK='recTok-lock-0010-jjjj'
TOK_LONG='recTok-long-0011-kkkk'
# (a) settled record recovers, preserves bytes, and frees the path for a new claim.
s=$(mkrec rec-settled t-settled "$TOK_SETTLED")
cp "$s" "$t/settled.orig"
rc=0; KB_SESSION_ID=rec-settled "$lease" dotfiles recover t-settled >"$t/rec-out-a" 2>"$t/rec-err-a" || rc=$?
[ "$rc" = 0 ] || exit 1
[ -z "$(cat "$t/rec-err-a")" ] || exit 1
out=$(cat "$t/rec-out-a")
[ "$(printf '%s' "$out" | jq -r '[.taskID, (.recovered|tostring), .reason] | join(" ")')" = 't-settled true settled' ] || exit 1
pres=$(printf '%s' "$out" | jq -r .preserved)
case "$pres" in "$s.stale-"*) ;; *) exit 1 ;; esac
[ -f "$pres" ] || exit 1
cmp "$t/settled.orig" "$pres" || exit 1
[ "$(fmode "$pres")" = 600 ] || exit 1
[ ! -e "$s" ] || exit 1
out=$(KB_SESSION_ID=rec-settled "$lease" dotfiles claim t-fake --as test)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
[ "$(sed -n '1p' "$s")" = t-fake ] || exit 1
# (b) expired record recovers with reason=expired.
s=$(mkrec rec-expired t-expired "$TOK_EXPIRED")
cp "$s" "$t/expired.orig"
rc=0; KB_SESSION_ID=rec-expired "$lease" dotfiles recover t-expired >"$t/rec-out-b" 2>"$t/rec-err-b" || rc=$?
[ "$rc" = 0 ] || exit 1
out=$(cat "$t/rec-out-b")
[ "$(printf '%s' "$out" | jq -r '[.taskID, (.recovered|tostring), .reason] | join(" ")')" = 't-expired true expired' ] || exit 1
pres=$(printf '%s' "$out" | jq -r .preserved)
case "$pres" in "$s.stale-"*) ;; *) exit 1 ;; esac
cmp "$t/expired.orig" "$pres" || exit 1
[ "$(fmode "$pres")" = 600 ] || exit 1
[ ! -e "$s" ] || exit 1
# (c) active claim refuses, file byte-identical with mode unchanged.
s=$(mkrec rec-active t-active "$TOK_ACTIVE")
cp "$s" "$t/active.orig"
rc=0; KB_SESSION_ID=rec-active "$lease" dotfiles recover t-active >"$t/rec-out-c" 2>"$t/rec-err-c" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s" "$t/active.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
grep -q 'active claim' "$t/rec-err-c" || exit 1
# (d) ambiguous claim refuses, file unchanged.
s=$(mkrec rec-ambig t-ambiguous "$TOK_AMBIG")
cp "$s" "$t/ambig.orig"
rc=0; KB_SESSION_ID=rec-ambig "$lease" dotfiles recover t-ambiguous >"$t/rec-out-d" 2>"$t/rec-err-d" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s" "$t/ambig.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
grep -q 'ambiguous' "$t/rec-err-d" || exit 1
# (e) wrong task refuses before any board call, file unchanged.
s=$(mkrec rec-wrongtask t-settled "$TOK_WRONGTASK")
cp "$s" "$t/wrongtask.orig"
n=$(wc -l < "$t/calls" | tr -d ' ')
rc=0; KB_SESSION_ID=rec-wrongtask "$lease" dotfiles recover t-other >"$t/rec-out-e" 2>"$t/rec-err-e" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s" "$t/wrongtask.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
grep -q 'different task' "$t/rec-err-e" || exit 1
# (f) wrong board (.id mismatch) refuses, file unchanged.
s=$(mkrec rec-wrongboard t-wrongboard "$TOK_WRONGBOARD")
cp "$s" "$t/wrongboard.orig"
rc=0; KB_SESSION_ID=rec-wrongboard "$lease" dotfiles recover t-wrongboard >"$t/rec-out-f" 2>"$t/rec-err-f" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s" "$t/wrongboard.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
grep -q 'wrong board' "$t/rec-err-f" || exit 1
# (g) malformed records refuse before any board call, files unchanged.
s=$(KB_SESSION_ID=rec-malformed1 "$t/scripts/kb-session-file")
rm -f -- "$s"
(umask 077; printf 't-malformed\n%s\njunk-third-line\n' "$TOK_MALFORMED" >"$s")
chmod 600 "$s"
cp "$s" "$t/malformed1.orig"
n=$(wc -l < "$t/calls" | tr -d ' ')
rc=0; KB_SESSION_ID=rec-malformed1 "$lease" dotfiles recover t-malformed >"$t/rec-out-g1" 2>"$t/rec-err-g1" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s" "$t/malformed1.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
grep -q 'malformed' "$t/rec-err-g1" || exit 1
s2=$(KB_SESSION_ID=rec-malformed2 "$t/scripts/kb-session-file")
rm -f -- "$s2"
(umask 077; printf 't-malformed\n\n' >"$s2")
chmod 600 "$s2"
cp "$s2" "$t/malformed2.orig"
rc=0; KB_SESSION_ID=rec-malformed2 "$lease" dotfiles recover t-malformed >"$t/rec-out-g2" 2>"$t/rec-err-g2" || rc=$?
[ "$rc" = 64 ] || exit 1
cmp "$s2" "$t/malformed2.orig" || exit 1
[ "$(fmode "$s2")" = 600 ] || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
grep -q 'malformed' "$t/rec-err-g2" || exit 1
# (h) symlinked session file refuses before any board call.
s=$(KB_SESSION_ID=rec-symlink "$t/scripts/kb-session-file")
rm -f -- "$s"
ln -s "$t/target" "$s"
n=$(wc -l < "$t/calls" | tr -d ' ')
rc=0; KB_SESSION_ID=rec-symlink "$lease" dotfiles recover t-settled >"$t/rec-out-h" 2>"$t/rec-err-h" || rc=$?
[ "$rc" = 64 ] || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
# (i) board read failure exits 1, file unchanged.
s=$(mkrec rec-boardfail t-boardfail "$TOK_BOARDFAIL")
cp "$s" "$t/boardfail.orig"
rc=0; KB_SESSION_ID=rec-boardfail "$lease" dotfiles recover t-boardfail >"$t/rec-out-i" 2>"$t/rec-err-i" || rc=$?
[ "$rc" = 1 ] || exit 1
cmp "$s" "$t/boardfail.orig" || exit 1
[ "$(fmode "$s")" = 600 ] || exit 1
grep -q 'board read failed' "$t/rec-err-i" || exit 1
# (j) no session file refuses and names the claim next step.
s=$(KB_SESSION_ID=rec-empty "$t/scripts/kb-session-file")
rm -f -- "$s"
rc=0; KB_SESSION_ID=rec-empty "$lease" dotfiles recover t-settled >"$t/rec-out-j" 2>"$t/rec-err-j" || rc=$?
[ "$rc" = 64 ] || exit 1
grep -q 'claim' "$t/rec-err-j" || exit 1
[ ! -e "$s" ] || exit 1
# (k) race: two concurrent recovers yield exactly one success and one preserved file.
s=$(mkrec rec-race t-settled "$TOK_RACE")
KB_SESSION_ID=rec-race "$lease" dotfiles recover t-settled >"$t/rec-out-k1" 2>"$t/rec-err-k1" & p1=$!
KB_SESSION_ID=rec-race "$lease" dotfiles recover t-settled >"$t/rec-out-k2" 2>"$t/rec-err-k2" & p2=$!
r1=0; wait "$p1" || r1=$?
r2=0; wait "$p2" || r2=$?
case "$r1 $r2" in '0 64'|'64 0') ;; *) exit 1 ;; esac
[ "$(grep -h '"recovered":true' "$t/rec-out-k1" "$t/rec-out-k2" | wc -l | tr -d ' ')" = 1 ] || exit 1
set -- "$s".stale-*
[ "$#" = 1 ] || exit 1
[ -f "$1" ] || exit 1
# (m) a recover that loses the lock refuses and leaves the holder's lock and the record intact.
s=$(mkrec rec-lock t-settled "$TOK_LOCK")
cp "$s" "$t/lock.orig"
mkdir "$s.lock"
n=$(wc -l < "$t/calls" | tr -d ' ')
rc=0; KB_SESSION_ID=rec-lock "$lease" dotfiles recover t-settled >"$t/rec-out-m" 2>"$t/rec-err-m" || rc=$?
[ "$rc" = 64 ] || exit 1
[ -d "$s.lock" ] || exit 1
cmp "$s" "$t/lock.orig" || exit 1
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
grep -q 'lock held' "$t/rec-err-m" || exit 1
rmdir "$s.lock"
# (n) a settled row with a long trail still proves settled.
s=$(mkrec rec-long t-longtrail "$TOK_LONG")
rc=0; KB_SESSION_ID=rec-long "$lease" dotfiles recover t-longtrail >"$t/rec-out-n" 2>"$t/rec-err-n" || rc=$?
[ "$rc" = 0 ] || exit 1
[ "$(jq -r .reason "$t/rec-out-n")" = settled ] || exit 1
[ ! -e "$s" ] || exit 1
# (l) no fake token leaks into any captured recover stdout/stderr.
cat "$t"/rec-out-* "$t"/rec-err-* >"$t/recover-io"
if grep -qF -e "$TOK_SETTLED" -e "$TOK_EXPIRED" -e "$TOK_ACTIVE" -e "$TOK_AMBIG" -e "$TOK_WRONGTASK" -e "$TOK_WRONGBOARD" -e "$TOK_BOARDFAIL" -e "$TOK_MALFORMED" -e "$TOK_RACE" -e "$TOK_LOCK" -e "$TOK_LONG" "$t/recover-io"; then exit 1; fi
printf '%s\n' 'kb-session-lease: recover (settled, expired, active, ambiguous, wrong-task, wrong-board, malformed, symlink, boardfail, no-file, race, held-lock, long-trail, no-leak) PASS'

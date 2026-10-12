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
case "$2 $3" in
  'claim t-fake') printf '{"taskID":"t-fake","leaseToken":"12345678-1234-1234-1234-123456789012","agentID":"test"}\n' ;;
  'h acc') printf '{"claim":{"taskID":"t-fake","leaseToken":"87654321-4321-4321-4321-210987654321"},"handoff":{"id":"h-test"}}\n' ;;
  'hb t-fake'|'release t-fake'|'h new')
    case " $* " in *' --lease 12345678-1234-1234-1234-123456789012 '*|*' --lease 87654321-4321-4321-4321-210987654321 '*) ;; *) exit 61 ;; esac
    printf '{"ok":true}\n' ;;
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
# An unrelated second claim must not silently overwrite this session's token.
if "$lease" dotfiles claim t-other --as test >"$t/refusal" 2>&1; then exit 1; fi
[ "$(wc -l < "$t/calls" | tr -d ' ')" = 1 ] || exit 1
out=$("$lease" dotfiles hb t-fake)
[ "$out" = '{"taskID":"t-fake","operation":"hb","ok":true}' ] || exit 1
out=$("$lease" dotfiles release t-fake)
[ "$out" = '{"taskID":"t-fake","operation":"release","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
out=$("$lease" dotfiles handoff-accept h-test --as test)
[ "$out" = '{"taskID":"t-fake","leaseStored":true}' ] || exit 1
out=$("$lease" dotfiles handoff-create t-fake --as test --summary done --intent done --next-action done)
[ "$out" = '{"taskID":"t-fake","operation":"handoff-create","ok":true}' ] || exit 1
[ ! -e "$session" ] || exit 1
# Wrong task, manually supplied token, and symlinked session file fail before a board call.
n=$(wc -l < "$t/calls" | tr -d ' ')
if "$lease" dotfiles hb t-other >"$t/refusal" 2>&1; then exit 1; fi
if "$lease" dotfiles claim t-fake --lease forged >"$t/refusal" 2>&1; then exit 1; fi
ln -s "$t/target" "$session"
if "$lease" dotfiles claim t-fake >"$t/refusal" 2>&1; then exit 1; fi
[ "$(wc -l < "$t/calls" | tr -d ' ')" = "$n" ] || exit 1
printf '%s\n' 'kb-session-lease: claim, heartbeat, release, accept, handoff, and refusal PASS'

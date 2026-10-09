#!/bin/bash
set -euo pipefail
here=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d "${TMPDIR:-/tmp}/kb-group-tests.XXXXXX")
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
cat >"$t/bin/ssh" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'ssh\n' >>"$CALLS"
[[ ${OUTAGE:-0} = 0 ]] || { echo 'ssh: connection refused' >&2; exit 255; }
[[ ${TIMEOUT:-0} = 0 ]] || { echo 'ssh: timed out' >&2; exit 124; }
[[ $1 = -- ]] && shift
[[ $1 = home-target ]] || exit 98
shift
cmd=${1//\/bin\/hostname/$REMOTE_HOSTNAME_BIN}
/bin/sh -c "$cmd"
SH
cat >"$t/bin/hostname" <<'SH'
#!/bin/bash
printf '%s\n' "${REMOTE_HOST:-unexpected}"
SH
cat >"$t/bin/kb" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ "${1-} ${2-} ${3-}" = 'workspace tag show' ]]; then
  printf 'show\n' >>"$CALLS"
  [[ ${NO_GROUP:-0} = 0 ]] || exit 64
  if [[ ${RACE_MEMBER:-0} = 1 || ${RACE_RECREATE:-0} = 1 ]]; then
    if [[ -e "$SEEN_SHOW" ]]; then
      if [[ ${RACE_RECREATE:-0} = 1 ]]; then
        printf '{"groupName":"group/test","revision":3,"groupSnapshot":"%s","members":[{"boardName":"kanban"},{"boardName":"px"}]}\n' "$RECREATED_SNAPSHOT"
      else
        printf '%s\n' '{"groupName":"group/test","revision":4,"groupSnapshot":"bg1.changed","members":[{"boardName":"kanban"},{"boardName":"px"},{"boardName":"alien"}]}'
      fi
      exit 0
    fi
    : >"$SEEN_SHOW"
  fi
  if [[ ${SNAPSHOT+x} = x ]]; then
    printf '%s\n' "$SNAPSHOT"
  else
    printf '{"groupName":"group/test","revision":3,"groupSnapshot":"%s","members":[{"boardName":"kanban"},{"boardName":"px"}]}\n' "$TEST_SNAPSHOT"
  fi
else
  printf 'operation\n' >>"$CALLS"
  printf '%s\0' "$@" >"$ARGS"
  if [[ ${RACE_MEMBER:-0} = 1 || ${RACE_RECREATE:-0} = 1 ]]; then
    # The compiled resolver sees either a new cross-home member or a new
    # group UUID under the same name and revision after wrapper verification.
    current=$("$0" workspace tag show group/test --json)
    actual=$(printf '%s' "$current" | jq -r '.groupSnapshot')
    [[ "$actual" != "$TEST_SNAPSHOT" ]] || exit 98
    case " $* " in
      *" --group-snapshot $TEST_SNAPSHOT "*|*" --expect-group-snapshot $TEST_SNAPSHOT "*)
        printf '%s\n' 'board group group/test changed since --expect-group-snapshot was issued; re-run `kanban workspace tag show group/test` and retry' >&2
        exit 64 ;;
    esac
    printf '%s\n' 'unchecked group operation' >"$ACTED"
  fi
fi
SH
chmod +x "$t/bin/"*
export KB_SSH_BIN="$t/bin/ssh" KB_HOSTS_TABLE="$t/hosts.tsv" CALLS="$t/calls" ARGS="$t/args"
export REMOTE_HOSTNAME_BIN="$t/bin/hostname" REMOTE_HOST=home-remote
export ACTED="$t/acted"
export SEEN_SHOW="$t/seen-show"
TEST_SNAPSHOT=$(python3 - <<'PY'
import base64, json
assertion = {"v": 1, "registryId": "registry-1", "groupId": "group-1", "groupName": "group/test", "revision": 3, "members": [["kanban-1", "inc-1"], ["px-1", "inc-1"]]}
print('bg1.' + base64.urlsafe_b64encode(json.dumps(assertion, separators=(',', ':')).encode()).decode().rstrip('='))
PY
)
export TEST_SNAPSHOT
RECREATED_SNAPSHOT=$(python3 - "$TEST_SNAPSHOT" <<'PY'
import base64, json, sys
assertion = json.loads(base64.urlsafe_b64decode(sys.argv[1].split('.', 1)[1] + '==='))
assertion['groupId'] = 'group-2'
print('bg1.' + base64.urlsafe_b64encode(json.dumps(assertion, separators=(',', ':')).encode()).decode().rstrip('='))
PY
)
export RECREATED_SNAPSHOT
kb="$t/bin/kb"
make_table() {
  printf 'kanban\thome-local\thome-target\thome-remote\t%s\npx\t%s\t%s\t%s\t%s\n' "$kb" "${1:-home-local}" "${2:-home-target}" "${3:-home-remote}" "${4:-$kb}" >"$KB_HOSTS_TABLE"
}
make_table
pass=0
ok() { pass=$((pass+1)); }
fail() { echo "kb-group test failed: $*" >&2; exit 1; }
check_calls() {
  local expected=$1 actual
  actual=$(cat "$CALLS" 2>/dev/null || :)
  [[ "$actual" = "$expected" ]] || fail "calls expected [$expected], got [$actual]"
}
refuse() {
  local message=$1; shift
  : >"$CALLS"; rm -f "$ARGS"
  local output status=0
  output=$("$here/scripts/kb-group" "$@" 2>&1) || status=$?
  [[ $status != 0 && "$output" = *"kb-group: $message"* ]] || fail "expected '$message', got exit $status: $output"
  [[ ! -e "$ARGS" ]] || fail 'refusal invoked compiled operation'
  ok
}
: >"$CALLS"
"$here/scripts/kb-group" group/test attention list --json --label "two words ' \$(touch nope); *" >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'attention', b'list', b'--json', b'--label', b"two words ' $(touch nope); *", b'--board-tag', b'group/test', b'--group-snapshot', __import__('os').environ['TEST_SNAPSHOT'].encode()]
PY
[[ ! -e nope ]] || fail 'shell expansion executed'
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test attention list --group-snapshot "$TEST_SNAPSHOT" --json >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import os, sys
args = Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert args == [b'attention', b'list', b'--group-snapshot', os.environ['TEST_SNAPSHOT'].encode(), b'--json', b'--board-tag', b'group/test']
PY
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test claim --next --as worker --expect-group-snapshot "$TEST_SNAPSHOT" >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'claim', b'--next', b'--as', b'worker', b'--expect-group-snapshot', __import__('os').environ['TEST_SNAPSHOT'].encode(), b'--board-tag', b'group/test']
PY
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test claim --candidates --as 'name; $HOME' --limit 2 >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'claim', b'--candidates', b'--as', b'name; $HOME', b'--limit', b'2', b'--board-tag', b'group/test', b'--expect-group-snapshot', __import__('os').environ['TEST_SNAPSHOT'].encode()]
PY
ok
# The fake compiled resolver sees an added cross-home member on its second
# show. The checked token must refuse both claims and watch bootstrap.
for mode in next candidates watch; do
  : >"$CALLS"; rm -f "$ACTED" "$ARGS" "$SEEN_SHOW"
  status=0
  if [[ "$mode" = watch ]]; then
    output=$(RACE_MEMBER=1 "$here/scripts/kb-group" group/test watch --cursor 0 --json 2>&1) || status=$?
  else
    output=$(RACE_MEMBER=1 "$here/scripts/kb-group" group/test claim "--$mode" --as worker 2>&1) || status=$?
  fi
  [[ $status != 0 && "$output" = *'board group group/test changed since --expect-group-snapshot was issued'* ]] || fail "race was not refused: $status $output"
  check_calls $'ssh\nshow\noperation\nshow'
  [[ ! -e "$ACTED" ]] || fail 'race acted on unchecked member'
  ok
done
# Same revision is insufficient after deletion/recreation: the compiled token
# also binds the immutable group ID.
: >"$CALLS"; rm -f "$ACTED" "$ARGS" "$SEEN_SHOW"
status=0
output=$(RACE_RECREATE=1 "$here/scripts/kb-group" group/test claim --next --as worker 2>&1) || status=$?
[[ $status != 0 && "$output" = *'board group group/test changed since --expect-group-snapshot was issued'* ]] || fail "name reuse was not refused: $status $output"
check_calls $'ssh\nshow\noperation\nshow'
[[ ! -e "$ACTED" ]] || fail 'name reuse acted on unchecked group'
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test watch --cursor 0 --json >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import os, sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'watch', b'--cursor', b'0', b'--json', b'--board-tag', b'group/test', b'--expect-group-snapshot', os.environ['TEST_SNAPSHOT'].encode()]
PY
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test watch --cursor 0 --expect-group-snapshot "$TEST_SNAPSHOT" --json >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import os, sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'watch', b'--cursor', b'0', b'--expect-group-snapshot', os.environ['TEST_SNAPSHOT'].encode(), b'--json', b'--board-tag', b'group/test']
PY
ok
: >"$CALLS"
"$here/scripts/kb-group" group/test claim --next --as worker >/dev/null
check_calls $'ssh\nshow\noperation'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'claim', b'--next', b'--as', b'worker', b'--board-tag', b'group/test', b'--expect-group-snapshot', __import__('os').environ['TEST_SNAPSHOT'].encode()]
PY
ok
python3 - "$here/SKILL.md" <<'PY'
from pathlib import Path
import sys
recipe = Path(sys.argv[1]).read_text().split('## Explicit board-group routing (coordinator only)', 1)[1].split('## Board home host', 1)[0]
assert 'claim --candidates --as ACTOR --limit N --json' in recipe
assert 'claim --candidates --as ACTOR --limit N --group-snapshot' not in recipe
assert 'claim --next --as ACTOR --json' in recipe
assert '--expect-group-snapshot' in recipe
PY
ok
refuse 'group tag must start with group/' board/test attention list
refuse 'invalid group tag' group/ attention list
refuse 'unsupported group command' group/test task update x
refuse 'unsupported group command' group/test claim --force
for selector in --project=px --db=/tmp/foo --workspace=. --all --all-boards --board-tag=group/else --except-board-tag=group/else --registry; do
  refuse 'conflicting scope selector' group/test attention list "$selector"
done
refuse 'conflicting scope selector' group/test attention list --project px
refuse 'conflicting scope selector' group/test attention list --board-tag group/else
stale=$(python3 - "$TEST_SNAPSHOT" <<'PY'
import base64, json, sys
assertion = json.loads(base64.urlsafe_b64decode(sys.argv[1].split('.', 1)[1] + '==='))
assertion['revision'] = 2
print('bg1.' + base64.urlsafe_b64encode(json.dumps(assertion, separators=(',', ':')).encode()).decode().rstrip('='))
PY
)
refuse 'board group group/test changed since --group-snapshot was issued; re-run `kanban workspace tag show group/test`' group/test attention list --group-snapshot "$stale"
check_calls $'ssh\nshow'
refuse 'board group group/test changed since --expect-group-snapshot was issued' group/test claim --next --expect-group-snapshot "$RECREATED_SNAPSHOT"
check_calls $'ssh\nshow'
refuse 'unknown precondition --expect-group-revision' group/test claim --next --expect-group-revision 4
check_calls ''
refuse 'board group group/test changed since --expect-group-snapshot was issued' group/test watch --cursor 0 --expect-group-snapshot "$RECREATED_SNAPSHOT"
check_calls $'ssh\nshow'
refuse 'invalid group snapshot' group/test attention list --group-snapshot bg1.other
refuse 'file selector is not applicable' group/test attention list --body-file 'body space.txt'
refuse 'file selector is not applicable' group/test attention list --items-file=/dev/stdin
KANBAN_PROJECT=px refuse 'ambient KANBAN_PROJECT or KANBAN_DB' group/test attention list
KANBAN_DB=/tmp/foo refuse 'ambient KANBAN_PROJECT or KANBAN_DB' group/test attention list
NO_GROUP=1 refuse 'group snapshot unavailable' group/test attention list
SNAPSHOT='{}' refuse 'invalid group snapshot' group/test attention list
SNAPSHOT='{"groupName":"group/test","revision":3,"groupSnapshot":"bg1.test","members":[{"boardName":"missing"}]}' refuse 'unregistered group member: missing' group/test attention list
printf 'px\thome-local\thome-target\thome-remote\t%s\n' "$kb" >"$KB_HOSTS_TABLE"
refuse 'registry board has no route: kanban' group/test attention list
make_table
make_table home-local home-target home-remote /other/bin/kb
refuse 'cross-home group member: px' group/test attention list
make_table
make_table other other other
refuse 'cross-home group member: px' group/test attention list
make_table home-local other-target home-remote
refuse 'cross-home group member: px' group/test attention list
make_table
REMOTE_HOST=wrong refuse 'remote hostname mismatch' group/test attention list
OUTAGE=1 refuse 'registry home unavailable (ssh exit 255)' group/test attention list
TIMEOUT=1 refuse 'registry home timed out (ssh exit 124)' group/test attention list
# At the local boundary no ssh is needed; the same catalogue read and one
# compiled operation use the configured absolute binary.
local_host=$(/bin/hostname)
make_table "$local_host" home-target home-remote
printf 'kanban\t%s\thome-target\thome-remote\t%s\npx\t%s\thome-target\thome-remote\t%s\n' "$local_host" "$kb" "$local_host" "$kb" >"$KB_HOSTS_TABLE"
: >"$CALLS"
"$here/scripts/kb-group" group/test task list --json >/dev/null
check_calls $'show\noperation'
ok
make_table
: >"$CALLS"
"$here/scripts/kb-board" px task list --json >/dev/null || fail 'single-board wrapper changed'
python3 - "$ARGS" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes().split(b'\0')[:-1] == [b'--project', b'px', b'task', b'list', b'--json']
PY
ok
printf 'kb-group: %d tests passed\n' "$pass"

# Session lease helper and heartbeat session file

Read when: claiming inside OMP, a `kb-session-lease` failure, or the heartbeat file.

**Inside OMP, do not print a claim response containing `leaseToken`.** Its
secret filter correctly redacts bearer tokens, which makes a printed claim
unusable for later writes. Use the routed opt-in `kb-session-lease` helper:
`kb-session-lease BOARD claim TASK --as ACTOR --lane LANE`,
`kb-session-lease BOARD hb TASK`,
`kb-session-lease BOARD checkpoint TASK --as ACTOR --state continue|blocked|done --summary ... --intent ... --next-action ...`,
`kb-session-lease BOARD handoff-create TASK --as ACTOR --summary ... --intent ... --next-action ...`,
or `kb-session-lease BOARD release TASK`. If the board claim has ended elsewhere
but the private record survives, `kb-session-lease BOARD recover TASK` verifies
the board shows a settled or expired claim and preserves the stale record aside.
For an incoming handoff use
`kb-session-lease BOARD handoff-accept HANDOFF --as ACTOR`. Claim and
accept capture the raw reply privately and persist its token in the existing
session file; only a constructed token-free receipt reaches the agent. A
successful `checkpoint --state blocked|done` clears the lease file;
a continuing checkpoint keeps it. A second claim in the same session refuses
until release, handoff or terminal checkpoint settles the first (the refusal
names the recover recovery for a record whose board claim has ended).
The helper needs `jq` and a valid tmux pane or `KB_SESSION_ID`; outside
tmux without a session ID it refuses rather than sharing the legacy file.
Every helper failure prints one line, `kb-session-lease: <what> failed
[cause=<class>]: <reason>`, with the token masked and, for board calls, a
`next:` step. Classes: `usage`, `session_busy`, `session_unsafe`,
`no_session_file`, `persist_failed`, `claim_active`, `claim_ended` (the board
holds no lease: recover), `lease_mismatch` (another lease holds the row: do
not write), `transport` (the call never reached the board, or its answer was
lost and the outcome is unknown: read the row first) and `refused` (kb dotfiles
t-8ccffdeb). A caller's own `--json` is dropped; the helper adds it where it
parses the reply (t-75164807).
Ordinary `kb-board` commands and transaction/MCP surfaces retain their
existing contract; never allowlist real lease tokens in the OMP filter.
**Write the heartbeat session file right after every claim** (George,
2026-09-29, kb dotfiles t-c991e76a option A): mode 0600, two lines — task id,
then lease token, at the path `<skill-dir>/scripts/kb-session-file` prints. The
PostToolUse heartbeat hook (`claude/hooks/kb-heartbeat.sh`) runs the same
helper and reads exactly that file; it never guesses, and no file means no
heartbeats and the lease quietly expires. With a nonempty `KB_SESSION_ID` in
the environment, the path is a deterministic per-session file
(`~/.claude/kb-session.d/session-<full sha256 hex of the id>`), which takes precedence
over tmux detection: two concurrent sessions with different ids get different
files holding their own task id and lease token, and reopening the same id
derives the same path. Without `KB_SESSION_ID` the path is one file per tmux
pane (`~/.claude/kb-session.d/tmux-<socket hash>-<pane>`), so concurrent lanes
on one host never overwrite each other's token (kb infra t-c827bfb2). Run the
helper from the shell of the pane your harness runs in; never write the path
by hand. An explicitly empty, over-long (>256 bytes), newline-bearing, or
control-character session id is refused with no path printed, so set no token file. The session id is only a
filename namespace: it grants no board, lane, role, or lease authority, and
both sides must already agree on the id out of band. Without `KB_SESSION_ID`,
outside tmux it prints the legacy single file `~/.claude/kb-session`
and exits 3, which is safe only while one session per host claims. One
session holds one task, so a second secure claim refuses rather than
overwriting the file. Direct claimers must still manage the file themselves.
The board is resolved off the session cwd by
lane-detect, never stored in the file. A session started with an explicit
session context (`--session-context PATH` or `KB_SESSION_CONTEXT`) takes its
board and lane from that file instead, and no pane is consulted; export
`KB_SESSION_ID` equal to the file's `sessionId`, so this helper and the
heartbeat hook resolve the same session file.

For direct, non-redacting callers only (OMP uses `kb-session-lease`):
```bash
f=$(<skill-dir>/scripts/kb-session-file) || [ $? -eq 3 ] || exit 1
(umask 077; printf '%s\n%s\n' "$TASK" "$TOKEN" > "$f")
```

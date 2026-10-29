# Board-group routing

Read when: coordinating a registered board group (`kb-group`).

## Explicit board-group routing (coordinator only)

The default is still **one board**. Group mode is opt-in, and only a
coordinator uses it, when George names a registered group (BOARDGROUP-18/19):

```bash
"<skill-dir>/scripts/kb-host" HOME workspace tag show group/NAME --json   # inspect current scope
"<skill-dir>/scripts/kb-group" group/NAME attention list --json
"<skill-dir>/scripts/kb-group" group/NAME claim --candidates --as ACTOR --limit N --json
"<skill-dir>/scripts/kb-group" group/NAME claim --next --as ACTOR --json  # returns the board and lease
```

- `kb-group` routes through the registry-home row of `KB_HOSTS_TABLE`. It
  checks the home host's name and every member's one-ledger route, then runs
  one compiled group operation with literal argv and `--board-tag`.
- An unknown group, an unavailable home, a member on another home, or a
  conflicting selector is refused. There is no per-member loop and no local
  database fallback. `--body-file` and `--items-file` are refused, because
  no group operation reads them. `kb-board` stays single-board.
- Keep the `groupSnapshot` from `workspace tag show`. The wrapper checks
  member routes, then forwards a caller's `--group-snapshot TOKEN` on
  snapshot-capable reads or `--expect-group-snapshot TOKEN` on claim/watch
  only if it matches the verified show. If omitted, it supplies the verified
  assertion itself. A revision alone cannot distinguish a recreated group;
  `--expect-group-revision` is not supported. Never pass a read snapshot to
  `claim --candidates`; on scope change, restart from show.
- Before a board-local write: show the group again, re-read the qualified
  `(board, id)` target, then write through `kb-board BOARD`. After a
  group claim, heartbeat/checkpoint/release/handoff use exactly the returned
  board and lease, even if group membership changes. Only the coordinator
  resolves groups; never pass a group token to a worker or widen its grants.

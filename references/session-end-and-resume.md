# Session end, stale and orphaned claims, resuming

Read when: ending a session, `staleClaims`, `orphanedFrom`, or resuming.

### Session end releases its own claims — `release --session`

A session that ends without releasing leaves its rows locked until the lease
runs out, invisible to every other lane. The session-end form frees them at
once:

```bash
kb release --session "$KB_SESSION_ID" --as "$ACTOR" --force --json
# {"session": "<id>", "released": ["t-1a2b3c4d", "t-5e6f7a8b"]}
```

- It selects every live claim whose stored session is that id, on the board
  the command addresses. Run it once per board the session claimed on.
- It frees only claims held by the worker `--as` names (the two seats of one
  lane are one worker). If any selected claim belongs to another worker, the
  whole call is refused and nothing is freed:
  `release --session ID found task T held by H, not ACTOR; that session is not yours to end`.
- `--force` is required; it is what makes the release audited. Each freed
  claim writes a `lease_seized` event and then a `claim_released` event
  carrying `{"sessionId", "endedBy"}`.
- With no matching claims it succeeds and prints an empty `released` list, so
  a harness session-end hook can run it unconditionally.
- `kb-session-lease BOARD claim` and `handoff-accept` record the lease under
  `KB_SESSION_ID` when it is set (they add `--session "$KB_SESSION_ID"`; an
  explicit `--session` wins). A bare `kb claim` records a session from
  `--session`, or from the `sessionId` of a `--session-context` file. A claim
  with no session is never selected; end it with `release ID --lease TOKEN`.
- A LINKED scope binding made without `--session` refuses a sessioned claim.
  The helper then retries once without the session and warns that
  `release --session` will not free that lease; rebind with
  `scope bind ... --session` to make it reachable.
- The harness must export the same `KB_SESSION_ID` to the claiming shell and
  to its session-end hook. A pane-keyed session (no `KB_SESSION_ID`) records
  no session, so its claims are not reachable by this form.

The single-task form `kb release <id> --lease "$TOKEN"` is unchanged, and it
stays the right verb inside a session: the session form is for the end.

### `staleClaims` — holders that have gone quiet

`kb doctor --json` (each readable entry in `projects`) and `kb dashboard
--json` (each readable board row, including `--all` and `--board-tag`) carry
`staleClaims`: live claims whose last heartbeat is more than 30 minutes old.

```json
{ "taskID": "t-1a2b3c4d", "holder": "@:example/example/driver-2",
  "sessionID": "…", "heartbeatAt": 1788599100000, "expiresAt": 1788602700000,
  "ageMinutes": 41 }
```

It is advisory: it never changes `healthy` or the exit status, and reading it
writes, sweeps and renews nothing. `sessionID` is `null` for a claim taken
without a session. A stale claim is still live; ask its holder, or wait for
expiry. Do not end it for them: besides expiry, only the holder, its own
session's end, or an audited `--force` ends a live claim.

### `orphanedFrom` — what the previous holder left behind

When you claim or read a task whose previous holder died, the claim receipt and
`kb ctx` carry an `orphanedFrom` block:

```json
{ "agent": "@:example/example/driver-2", "sessionID": "…", "expiredAt": 1788600000000,
  "lastCheckpointAt": 1788599100000, "worktree": "/home/operator/work/src/example",
  "branch": "kanban-example-driver", "headSha": "e87c5a6" }
```

It is **absent**, not null, when there is nothing to report, and it describes
only the current `todo` spell: a task that was orphaned, reclaimed and finished
does not hand a later holder that old orphan. `lastCheckpointAt` is `null` when
the dead holder wrote no checkpoint after claiming, which is the case where the
tree may be further along than anything the ledger knows — `cd` to `worktree`
and compare `git rev-parse HEAD` against `headSha` before trusting either.

### Resuming, in order

1. `kb h ls --project P --status pending --json` — **no `--to`**. Every session
   handoff has an addressee (`h new` refuses one without `--to`), but the
   addressee is a lane name, and lanes get renumbered and recreated. Filtering
   with `--to driver-2` hides a brief left for `driver-3`, which is precisely
   the brief you need after a renumber. List them all and read the addressees.
   More than one match is a stop, not a pick.
2. `kb h acc <id> --as "$LANE" --json`. On a task-form handoff this mints the
   lease and sets `in_progress` in one transaction, so when it succeeds you do
   not also run `claim --next`. A session handoff mints no lease by design.
3. `claim --next` **ignores pending handoffs**, and a task a handoff returned to
   `todo` keeps its assignee — so a different lane needs `--allow-reassign` to
   take it.
4. `kb ctx <id> --json` — newest handoff and checkpoint first, then sitreps,
   then `orphanedFrom` if it is there.
5. `cd` to the record's `repoPath` and check the tree: `git rev-parse HEAD`
   against `headSha`, `git status --short` against `dirtySummary`. A mismatch
   outranks everything else in the brief.
6. `kb note <id> "…" --kind plan --as "$ACTOR"` before touching code.

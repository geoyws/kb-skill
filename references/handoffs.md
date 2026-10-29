# Handoffs

Read when: stopping with work unfinished, or any handoff.

## Handoffs

TRIGGER: write a handoff whenever you stop with work unfinished. Token
pressure, `/clear`, rotation, lane renumbering, or any boundary where a
successor must pick the work up. A checkpoint alone never hands work over.
It keeps your lease, so nobody else can take the row.

REQUIRED ACTION, task handoff. A claimed task returns to the queue with its
lease released in the same transaction:

1. Run `kb h new <task-id> --lease "$TOKEN" --as "$ACTOR" --summary "…" --intent "…" --next-action "…" --reason token_pressure --json` in the board home host shell. `$ACTOR` is your callsign from `/whoami` (`@:<group>/<team>/<lane>/<seat>`), never a bare lane and never harness-qualified.
2. The task id and `--lease` travel together. Each half alone is refused, because a lease exists only over a task and a task cannot be handed over without one.

REQUIRED ACTION, session handoff. The lane's position as a whole: no task,
no lease. Through `kb-board`, run from inside the checkout so `--repo`,
`--branch`, `--head` and `--dirty` are captured from it:

1. Run `<skill-dir>/scripts/kb-board BOARD_ID h new --as "$ACTOR" --to "$ACTOR" --reason session_end --summary "…" --intent "…" --next-action "…" --json` from inside the checkout, and omit all four provenance flags there: they are auto-captured from the cwd and stored as `repoPath`, `branch`, `headSha`, `dirtySummary`, and the wrapper adds `--git-captured` so the head is recorded as read (`headSource: kb-wrapper`). `--to` takes the full canonical lane actor, not the short lane name.
2. In an interactive board-host shell your checkout is not there, so pass all four provenance flags yourself: `--repo "$REPO" --branch "$BRANCH" --head "$HEAD_SHA" --dirty "$DIRTY"`. Never add `--git-captured` by hand.
3. `--dirty` is measured, never guessed: `clean`, `1 file changed`, or `N files changed`. An explicit flag always wins over capture.

REQUIRED ACTION, list and accept:

1. List every pending handoff with no `--to` filter: `kb-board <board> h ls --status pending --limit 25 --json`. Lanes get renumbered and recreated, so `--to driver-2` hides a brief left for `driver-3`, which is exactly the brief you need after a renumber. List them all and read the addressees.
2. Read the brief before accepting it. A task handoff's full text rides on `kb t cat <task>`. Reconcile the record with the tree: `git rev-parse HEAD` against `headSha`, `git status --short` against `dirtySummary`. A mismatch outranks everything else in the brief.
3. Accept with `kb h acc <handoff-id> --as "$ACTOR" --lease-minutes 180 --json`, only after the content is absorbed. The reply carries top-level `claim`, `handoff` and `rules`; the new lease token is at `.claim.leaseToken`. A task handoff mints the lease and sets `in_progress` in one transaction, so never `claim --next` after it. A session handoff mints no lease by design.
4. More than one matching brief is a stop, not a pick.

FORBIDDEN SHORTCUTS. A pane message as the only record: the board row is
the record, the message is only the notification. A handoff without the
worktree facts: a handoff without a head is one nobody can verify against a
tree. A task id without its lease, or a lease without its task id.

COMPLETION EVIDENCE. The create reply carries no top-level id (the record is
wrapped), so read the id back with `kb h ls --task <task> --limit 5 --json | jq '.[0].id'`, and check `kb t cat <task>` shows the handoff on the task. A session handoff has no task to list by: read its id back with `kb h ls --status pending --limit 25 --json | jq -r --arg a "$ACTOR" 'map(select(.taskID == null and .fromAgent == $a)) | .[0].id'` (record fields `taskID` and `fromAgent`, measured 2026-10-01). Report the id either way.

CONTENT CONTRACT. Every handoff carries these, short enough to act on:

- Worktree host: the board home host the record was written from.
- Worktree absolute realpath, branch, and base or candidate SHA (the `--repo`, `--branch`, `--head` facts).
- Dirty state, measured never guessed (`clean`, `1 file changed`, `N files changed`).
- The exact next action: the one concrete first move.
- Open leases (task handoffs only): which task the lease belonged to. It is released by the handoff itself. A session handoff carries no task and no lease, so it writes `none (session handoff)`.
- Evidence paths: commits, files, or receipts the successor can check.
- What was NOT verified: the layer you did not run, the tree you did not compare.

Example:

```bash
kb h new t-48c302f0 --lease "$TOKEN" --as "@:geoyws/px/driver-3" \
  --summary "Second aix-root exit done in writer tree; lane integration not run." \
  --intent "Land the writer branch on pai-geoyws-driver-3, then re-measure." \
  --next-action "Merge writer branch wt-px-t48c302f0-w1 into pai-geoyws-driver-3 in an isolated integration tree and run the gates." \
  --reason token_pressure --json
# Historical worktree example (pre-cutover): hax /srv/work/px-driver-3, branch pai-geoyws-driver-3, base 9f2c1ab; never a current board target.
# Evidence: commit 4d5e6f7 on wt-px-t48c302f0-w1. NOT verified: e2e on the merged lane.
```

Handoffs are history: removing a task drops the link and keeps the account.
A task can be restricted to models: `kb h acc --model NAME` is checked
against the task's list the same way a claim is.

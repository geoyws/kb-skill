# Sprints

Read when: working with a sprint.

## Sprints — a versioned, proof-gated boundary

A sprint is a board-owned delivery boundary: one goal, an explicit set of task
rows, and one target version. It is not an estimate bucket, and there is no
sprint `draft` state or automatic rollover. The only states are `planned`,
`current`, `closed`, and `abandoned`; at most one sprint is current. The
scheduled `--start` and `--end` values are epoch **milliseconds** and remain
separate from the actual start/end lifecycle stamps.

First verify the routed host's installed binary, not a checkout or local copy:

```bash
<skill-dir>/scripts/kb-host BOARD_HOME_HOST v
<skill-dir>/scripts/kb-host BOARD_HOME_HOST schema --json
```

Inspect the reported command surface for `sprint`. An older installed binary
may not have it. If the installed version/surface lacks sprint support, stop
and report that capability boundary; never improvise with a locally built
binary, open a local board copy, or attempt a schema migration yourself.

### Sprint-scoped rules and sprint search

These forms are newer parts of the sprint schema. Confirm that the installed
`v` and `schema --json` output above includes them before use; an older
installed binary may support sprints without these rule and search additions.

Add a rule for one board and one of its sprints through the registry-owned
`kb-host` path, never `kb-board`:

```bash
<skill-dir>/scripts/kb-host BOARD_HOME_HOST rule add "..." --title "..." \
  --board BOARD --sprint sp-ID [--tag slug] [--load always|lazy] --as ACTOR
<skill-dir>/scripts/kb-host BOARD_HOME_HOST rule update RULE_ID \
  --sprint sp-ID --as ACTOR
<skill-dir>/scripts/kb-host BOARD_HOME_HOST rule update RULE_ID \
  --clear-sprint --as ACTOR
```

The sprint must exist on that board, including historical closed sprints. The
optional tag further intersects that scope. On update, `--sprint` and
`--clear-sprint` are mutually exclusive. The rule applies only when the task
is attached to that sprint during claim, handoff acceptance, and context
assembly; unattached tasks and tasks in another sprint do not receive it.

Sprint cards are also searchable by title, body, and target version:

```bash
<skill-dir>/scripts/kb-board BOARD search QUERY --source sprint --json
```

Sprint results cite `kanban://BOARD/sprint/ID`.

Create a planned card, then give planning a required goal body and deliberate
scope:

```bash
<skill-dir>/scripts/kb-board BOARD_ID sprint new "Release boundary" \
  --target-version 2.4.0 --start 1799702400000 --end 1800307200000 \
  --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID sprint plan sp-ID \
  --body "Ship the agreed acceptance criteria." --parent-epic EPIC_ID \
  --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID sprint start sp-ID --as ACTOR --json
```

Repeated `--candidate TASK_ID` values and `--parent-epic EPIC_ID` may be
combined; planning attaches their union and retains rows already explicitly
attached to this sprint. If that existing scope is itself the deliberate
scope, the body alone is sufficient. Use `--empty-scope` only for an
intentionally empty boundary: it is exclusive of candidates, a parent epic,
and existing scope. `sprint plan` always refuses a missing body, and refuses
an absent scope only when there is neither new nor existing explicit scope.
`sprint start` refuses while another sprint is current.

Task scope is explicit and audited:

```bash
<skill-dir>/scripts/kb-board BOARD_ID task add "Work item" \
  --sprint sp-ID --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID task update TASK_ID \
  --sprint sp-ID --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID task update TASK_ID \
  --clear-sprint --as ACTOR --json
```

Attaching an epic or other container carries its subtree except descendants
already explicitly attached to another sprint. The named row itself moves when
explicitly reattached; `--clear-sprint` deliberately detaches only that row.

While a sprint is current, every claim path and task-handoff acceptance defaults
to its attached rows; unattached work is outside the boundary. With no current
sprint this filter is a no-op, preserving the ordinary claim behavior and
payload. Cross a boundary only explicitly:

```bash
<skill-dir>/scripts/kb-board BOARD_ID claim --next --as AGENT --sprint sp-ID --json
<skill-dir>/scripts/kb-board BOARD_ID claim --next --as AGENT --any-sprint --json
<skill-dir>/scripts/kb-board BOARD_ID handoff accept HANDOFF_ID \
  --as AGENT --sprint sp-ID --json
```

`--sprint sp-ID` names the boundary; `--any-sprint` deliberately removes the
filter. They are mutually exclusive, and the override is recorded in the
claim/handoff audit event rather than becoming an invisible exception.

Closing requires served proof for the same sprint and target version. These
ledger commands only record evidence: they do not deploy, inspect, or verify
the actual target. Bind the deployment at start and keep the returned
capability token only in private ephemeral state—never put it in task or sprint
notes, checkpoints, handoffs, receipts, chat, or logs. Independently observe
the served target's exact commit and version, and only then record a successful
verification finish with the matching `--served-version`:

```bash
<skill-dir>/scripts/kb-board BOARD_ID deploy start --repo OWNER/REPO \
  --commit FULL_40_CHAR_SHA --tier TIER --environment ENVIRONMENT \
  --host DEPLOY_HOST --url SERVICE_URL --sprint sp-ID --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID deploy finish DEPLOYMENT_ID --token TOKEN \
  --result succeeded --phase verification --served-commit FULL_40_CHAR_SHA \
  --served-version 2.4.0 --receipt "Observed the served release" \
  --as ACTOR --json
<skill-dir>/scripts/kb-board BOARD_ID sprint close sp-ID \
  --deployment DEPLOYMENT_ID --as ACTOR --json
```

The close proof must be a succeeded verification deployment bound to that
sprint, and its served version must equal the sprint's target version. If any
attached rows remain unfinished, close refuses unless they are deliberately
moved in the same operation to one named planned/current sprint:

```bash
<skill-dir>/scripts/kb-board BOARD_ID sprint close sp-ID \
  --deployment DEPLOYMENT_ID --carry-to sp-NEXT \
  --carry-note "Deferred after the verified release" --as ACTOR --json
```

There is no implicit rollover. Abandoning is also deliberate and requires a
reason:

```bash
<skill-dir>/scripts/kb-board BOARD_ID sprint abandon sp-ID \
  --note "The delivery boundary changed" --as ACTOR --json
```

Read the boundary without inventing a `sprint current` command:

```bash
<skill-dir>/scripts/kb-board BOARD_ID sprint list --json
<skill-dir>/scripts/kb-board BOARD_ID sprint list --all --json
<skill-dir>/scripts/kb-board BOARD_ID sprint show sp-ID --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST dash --json
<skill-dir>/scripts/kb-board BOARD_ID ctx TASK_ID --json
```

`sprint list` hides closed/abandoned history unless `--all` (or an explicit
status) is requested; `sprint show` returns the sprint, its attached tasks,
and its deployment proof. The registry-wide `dash` projects each board's
current sprint summary. A task's `ctx` includes its attached sprint.
See ADR-045.

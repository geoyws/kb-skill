# Cleanup ledger

Read when: allocating host resources for a task, or a cleanup refusal.

## Cleanup ledger — what you allocated, you remove

**A done row holds no host resources.** Every worktree, container, volume,
scratch dir or hal clone a unit of work allocates leaks past the row unless
something records it — so the moment you create one, register it on the
task, and before the row moves done every entry is either removed with a
measured receipt or held with a live expiry. Kanban records the attestation
and never deletes anything itself: removal happens on the host, the ledger
holds the receipt.

```bash
kb task cleanup add t-1a2b3c4d --host hal --kind worktree --path /tmp/wt-1 --run run-7 --as "$AGENT" --json
kb task cleanup list t-1a2b3c4d --json
kb task cleanup remove t-1a2b3c4d --host hal --kind worktree --path /tmp/wt-1 --proof-kind tree-merged-published --proof "rev-list empty, status clean, ls-remote merged" --bytes 412000 --as "$AGENT" --json
kb task cleanup hold t-1a2b3c4d --host hal --kind e2e-database --ref e2e-9 --owner "@:geoyws/acies/driver" --expiry "$(( ($(date +%s) + 7*86400) * 1000 ))" --reason "kept for the next lane's repro" --as "$AGENT" --json   # expiry: epoch ms, a week out
kb task cleanup hold t-1a2b3c4d --host hal --kind e2e-database --ref e2e-9 --release --as "$AGENT" --json
kb cleanup report --json
```

The manifest is per task: `task cleanup add ID --host HOST --kind KIND
(--path ABSPATH | --ref ID) --run RUN --as ACTOR` registers one `allocated`
entry the moment the resource is created, carrying host, kind, path-or-id,
the creating run id, and state. Filesystem kinds (`worktree`,
`hal-cargo-dir`, `gate-dir`, `tmp-log`) take an absolute `--path`; runtime
kinds (`container`, `image`, `volume`, `network`, `e2e-database`) take a
non-empty `--ref`. `kind` is exactly one of `worktree hal-cargo-dir gate-dir
container image volume network e2e-database tmp-log`. Entries survive
restarts, retags and metadata patches; removing the task deletes its
manifest rows in the same transaction. A duplicate non-removed `(host, kind,
path_or_id)` on the same task is refused as already registered. `--as` is
mandatory on every write verb, and each write appends one hash-chained board
event (`cleanup_registered`, `cleanup_removed`, `cleanup_held`,
`cleanup_released`).

Remove when torn down: `task cleanup remove ID --host HOST --kind KIND
(--path ABSPATH | --ref ID) --proof-kind KIND --proof TEXT --bytes N --as
ACTOR` marks the entry `removed`, storing the receipt — a validated
`--proof-kind` from the entry kind's allowed set, inline `--proof` text of
1..2000 characters naming the measurement run on the host, and `--bytes` of
0 or more reclaimed. `worktree` takes `tree-merged-published` only (fresh
`git ls-remote` showing the branch merged/published, `git rev-list HEAD
--not --remotes` empty, `git status --porcelain` empty); `hal-cargo-dir`
takes `build-dir-removed`; `gate-dir` takes `gate-dir-removed`;
`container`, `image` and `volume` take `runtime-gone`; `network` takes
`network-gone`; `e2e-database` takes `database-gone`; `tmp-log` takes
`log-gone`. Whether the named checks actually ran is attested, not checked:
a false attestation is attributable to the `--as` writer in the chained
event, never to a host check.

Hold what must outlive the row: `task cleanup hold ID --host HOST --kind
KIND (--path ABSPATH | --ref ID) --owner OWNER --expiry MS --reason TEXT --as
ACTOR` holds one entry with a non-empty owner, an expiry in epoch
milliseconds strictly after the write time, and a reason of 1..500
characters; `--release` returns it to `allocated`, and holding an
already-held entry refreshes owner, expiry and reason in place. An expired
hold — `held` with expiry at or before now — counts as outstanding: it
refuses the done-write and renders with the `(held by {owner} until
{expiry}, expired)` suffix. Nothing auto-releases it; refreshing the hold or
removing the entry opens the gate again. Removing a held entry is allowed;
holding or re-holding a removed one is refused.

Read it back with `task cleanup list ID [--include-removed]`, which answers
`allocated` and `held` first in registration order and `removed` only with
the flag. `task show` and `task ctx` include the task's open entries.
`cleanup report [--board-tag group/NAME [--group-snapshot TOKEN]]` answers
per board which task rows reached `done` with nothing outstanding
(`cleanupDone`), every outstanding entry with its age, and every live hold
in its own held section — or one section per member board across a named
group, with the same membership and read-only snapshot rules as the other
group reads. There is no `--all` flag.

MCP mirrors the five verbs as generated tools with the same fields and
refusals: `task_cleanup_add`, `task_cleanup_remove` and `task_cleanup_hold`
are write tools, while `task_cleanup_list` and `cleanup_report` are read
tools.

The done refusal: every write whose resulting status is `done` on a
task-type row — `task move ID done` (including done-to-done), `checkpoint
--state done` (refused inside the one transaction, so the checkpoint row
rolls back too), an import upsert that flips an existing entry-carrying row
to `done` (the whole import rolls back), and the same dispatch through
`transact` items — is refused while any entry is `allocated` or
held-expired, landing nothing. (`task add --status done` carries no manifest
and always passes this gate; story and epic rows check none.) It applies to
every actor including `geoyws`, and there is no `--force` past it — the way
past is removal or hold, both audited. The sentence, verbatim with only the
bracketed values varying:

```
task {id} cannot reach done: {n} cleanup resource(s) still allocated — {entry}, {entry} — remove each with task cleanup remove {id} --host HOST --kind KIND --path PATH|--ref ID --proof-kind KIND --proof PROOF --bytes N --as ACTOR or hold it with task cleanup hold {id} --host HOST --kind KIND --path PATH|--ref ID --owner OWNER --expiry MS --reason TEXT --as ACTOR
```

Each entry renders as `{host}/{kind}/{path_or_id}` in registration order,
oldest first, joined with `, `; pass that sentence on rather than
paraphrasing it.

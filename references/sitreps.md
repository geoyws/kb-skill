# Sitreps

Read when: posting or reading a sitrep.

## Sitreps — where a lane stands, cheaply

```bash
kb sr new "Retry path is the culprit; fix is in the queuer, tests still red." \
  --as "$AGENT" --lane driver-2 --json          # --task <ID> optional
kb sr ls --lane driver-2 --json                 # the current view, newest first; capped at 20 without --limit
kb sr ls --lane driver-2 --all --limit 100 --json   # including what it superseded
```

**No task, no lease, no ceremony** — that is the whole point. A note needs a
task; a checkpoint needs a task *and* a live lease. Work done across tasks,
between them, or before anything is claimed had nowhere to go, so it went into a
reply that scrolls away.

**Post often.** This is the one record here cheap enough to write twenty times a
day, and it is what a successor reads when there was no time to write a handoff.
`kb ctx <id>` carries the sitreps that mention a task, so they reach a resuming
agent without anyone going looking.

**Old entries archive themselves.** Posting retires everything past the newest
ten in that lane. Archived sitreps are hidden from the default read and returned
by `--all` — **nothing is ever deleted**, and archiving is per lane, so another
driver's chatter cannot push yours out of view.

Provenance rides along: worktree, branch, HEAD, root HEAD, dirty count are
captured from where the **binary** ran. "Tests green" that does not say which
checkout is a claim nobody can check. Over `kb-board` the binary runs on the
board host, so the wrapper reads your checkout first and forwards it as
`--repo` / `--branch` / `--head` / `--dirty`, exactly as it does for
checkpoints and handoffs (see Handoffs). A sitrep with blank provenance is
refused, not stored.

**A sitrep is not a handoff, and not a task status.**

| | what it is | costs |
|---|---|---|
| `kb sr new` | where this lane stands right now | one command |
| `kb cp` | a resumable point on a task you hold | a lease |
| `kb h new` | *I am leaving, here is everything* | releases the lease, names a successor |

A task's **status** is a workflow state (`todo`, `in_progress`) and is always the
`--status` flag. A **sitrep** is prose about a lane and is always the `sitrep`
command. The old `status` command has no deprecated alias and fails closed.

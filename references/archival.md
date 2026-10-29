# Archival

Read when: archiving rows or reading cold history.

## Archival — bounded hot indexes, intact history

```bash
kb archive --older-than-days 90 --as system@archive --dry-run --json
kb archive --older-than-days 90 --as system@archive --json
kb t ls --all --json             # active plus cold tasks
kb ev --task <id> --all --json   # cold audit history for one task
```

The sweep archives only settled rows older than the cutoff:
`done`/`cancelled`/`abandoned` tasks without a lease, their
notes/checkpoints/tags/events, settled handoffs,
resolved attention and linked sitreps. Old taskless settled records are included.
`kiv` rows are never archived for age: parking is not settling, and only an
explicit resume or abandon moves them.
It also archives terminal deployment attempts that are no longer the current
verified success for their `(repo, tier, environment)`. Started attempts and
each target's latest verified success always remain hot.
Rows remain in the same backed-up SQLite board and `--all` reads them; nothing is
deleted. Operational secondary indexes contain only `archived=0` rows, so their
size follows current work rather than the board's lifetime.

Reads never run retention implicitly. The nightly backup timer explicitly sweeps
every present registered board at 90 days before snapshotting it. `--dry-run`
executes the real transaction, reports its counts, and rolls it back. See ADR-021.

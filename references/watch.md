# Watch

Read when: running `kb watch`.

## Watch — cursor-native live subscription

`kb watch` is the canonical long-running process over the append-only ledgers.
It is `longRunning` and `readOnly`, so generated MCP tool schemas exclude it.
`kb events` stays the newest-first snapshot reader.

`kb watch` emits protocol-v1 NDJSON envelopes. The payload is additive:
`board {id,name?}` for board scope or `board: null` for registry scope,
`eventID`, `eventHash`, `seq`, `timestamp`, `actor`, `kind`, `subject`, typed
`parent`/`ancestor`/`depends-on` relations,
`priorStatus`, `currentStatus`, sorted registered tags, bounded recursively
redacted metadata, and explicit `null` semantic fields on legacy events. Board
event payloads also store private `_semanticV1`; it is hash-covered in the
ledger but never emitted.

```bash
kb watch --project NAME --task t-12345678 --cursor 0 --follow --json
kb watch --project NAME --relation-json '[{"relation":"depends-on","boardID":"00000000-0000-4000-8000-000000000001","id":"t-prerequisite"}]' --cursor 0 --json
kb watch --registry --cursor CURSOR --limit 100 --json
```

Rules:

- Exactly one scope is active at a time: a board via `--project`, a task via
  `--task`, a registry rule via `--rule`, or the registry via `--registry`.
  There is no cross-board fan-in.
- `--task` is the subject selector. `--kind`, `--relation`, `--prior-status`,
  `--current-status`, and `--tag` are repeatable predicates. `--relation`
  accepts typed forms `parent:ID`, `ancestor:ID`, and `depends-on:ID`; all
  these scalar relations, including `depends-on:ID`, remain local to the
  watched board even if the opaque ID contains `:` or `/`.
- For an existing foreign dependency edge, pass `--relation-json` with a JSON
  array of exact `{"relation":"depends-on","boardID":"UUID","id":"ID"}`
  objects. `boardID` is the canonical lowercase hyphenated registered source
  UUID, and `id` is a nonempty exact opaque item ID; no other relation kind or
  extra object fields are accepted. A target-board UUID normalizes to the
  local relation. A scratch `--db` target without a registered UUID refuses
  `--relation-json`; keep scalar `--relation` for local filters there.
- Values within one predicate family are ORed. Families are ANDed together.
  Thus scalar local and JSON-qualified relations match either edge, not both.
  The filter still reads events on the selected target board only: it never
  subscribes to source-board events or enables cross-board fan-in.
- The command normalizes the full predicate set before binding it to the
  cursor. Reusing a cursor with any different normalized predicate set fails
  closed.
- Unknown tasks, relation targets, kinds, statuses, or tags fail closed.
- Removed subjects and historical relation targets remain replayable because
  replay uses stored rows, not live lookups.
- Registry scope supports `--kind` only and rejects board semantic predicates,
  including `--relation-json`.
- `--cursor` is opaque. Literal `0` bootstraps from the start, and a persisted
  cursor is bound to the exact source, selector, normalized predicate set,
  archive state, and last consumed ledger `seq`.
- Malformed, mismatched, or future cursors fail closed.
- `--follow` reopens read-only transactions between polls and emits rows
  synchronously, with no intermediate queue. It requires `--limit` to be at
  least `1`, so `--follow --limit 0` fails.
- `--limit` is constrained to `0..1000000` in every mode, the one ceiling every
  `--limit` on this ledger shares (kanban 8991e9f, 2026-09-08 - effectively
  unbounded for any board this tool holds; a batch is a SQL LIMIT, never a
  preallocated buffer); follow mode additionally rejects `0`. Sparse filtering happens before `--limit`, so the limit slices
  the filtered result set rather than the raw rows.
- `--db PATH` opens that exact database file.
- NDJSON envelopes carry `version`, `scope`, `cursor`, `type`, and `payload`
  on stdout only; errors and diagnostics go to stderr.
- Idle heartbeats do not advance the durable cursor. If predicates skip a
  committed unmatched tail, an `advanced` heartbeat moves the opaque cursor to
  the last scanned row so follow mode does not loop over the same rows.
- Secrets are redacted recursively before emission.
- `payload` stays the existing event JSON, including `seq` as the ledger row
  number.

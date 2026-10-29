# Validation layers and review verdicts

Read when: filling `--validation` or recording a review verdict.

### `--validation` says which layer, by convention

`--validation` is free text and nothing refuses a malformed value, so the
convention is carried here: start every one with `unit:`, `integration:`,
`e2e:` or `substitute:`. Naming the layer is the whole point — "tests pass" on
a row whose only coverage is a unit test reads as end-to-end to the next
person. A fail-closed check was considered and rejected as disproportionate for
an optional flag.

Plan steps are child rows or one `--kind plan` note. There is no checklist
field, and adding one would put the same truth in two places.

### Recording a review — `task verdict add`

**A review result goes on the ledger as a verdict row.** `task verdict add` is
the one structured record that a reviewer checked a SHA, whether it passed or
failed. A note beginning `review verdict:` is free text: the done gate cannot
read it, the review lists in `doctor` and `dash` only point at it as something
to convert, and the model scorecard reads it only through a one-off backfill
of old notes, marked `backfilled`. One reader still needs
the note: Kanban's milestone check (MILESTONE-06) judges a milestone task from
its latest `review verdict:` note, until kanban `t-43967001` teaches it the
verdict row. Until then write the verdict row first, then the note.

```bash
# pass: the reviewer checked these exact published SHAs
kb task verdict add <ID> --result pass --reviewer "<reviewer callsign>" \
  --sha <40-char SHA> [--sha …] --evidence <a-id> [--evidence …] \
  --attest-published [--writer-model NAME …] --as "<your callsign>"
# fail: evidence and a short reason are required
kb task verdict add <ID> --result fail --reviewer "<reviewer callsign>" \
  --sha <40-char SHA> --evidence <a-id> --reason "<one line: what failed>" \
  --attest-published --as "<your callsign>"
kb task verdict list <ID> --json      # both results, oldest first
```

What the verb checks, so you are not surprised by a refusal:

- **Who writes it.** Neither `--as` nor `--reviewer` may be anyone who holds or
  held the row's claim. The lane that did the work never records its own
  review: the planner seat or the coordinator writes the row for the
  reviewer it spawned. A reviewer subagent never writes to the ledger itself.
- **Who closes it.** On a gated board the actor that moves the row to `done`
  must be neither the verdict's writer nor its reviewer, or the move is
  refused as self-review. The planner writes the verdict; the executor closes.
- **Which SHA.** Full 40-character SHAs only, already on origin.
  `--attest-published` is your statement that you checked; the ledger records
  who said so and when, and does not ask the remote.
- **What it cites.** `--evidence` names attention ids, the decisions the
  reviewer checked the work against. A pass satisfies the done gate only when
  every cited item is `resolved` at the done move and the pass covers the row's
  current head; otherwise the move is refused as stale or unverified. A row
  with no decision behind it has nothing to cite yet: raise one for the owner
  rather than citing an unrelated item.
- **Fail rows stay.** Both results are append-only. A fail never opens the
  gate, and a later pass at a new SHA does not erase it.
- **`--reason` is for a fail only.** A pass given `--reason` is refused.
- **Older boards.** A board below schema 50 stores passes only, and refuses a
  fail or `--writer-model` until its owner runs
  `kanban board upgrade NAME --as ACTOR`.

The findings themselves still go in a `note` (or an attention row, when they
need the owner); the verdict row is what the gate and the scorecard read.

**The done gate is per board, and off by default.** `task verdict gate on|off
--as geoyws` switches it; only `geoyws` may. With it on, a task or bug reaches
`done` only with a current-head pass (or `geoyws --force`, audited, which
answers only a missing verdict). On code work the final proof (see Trunk)
still applies and no `--force` passes it. With the gate off, verdict rows are
still the record: write them the same way.

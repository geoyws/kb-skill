# Model attribution

Read when: recording `--model`/`--writer-model`, bugs, test runs, or `kb stats models`.

## Which model did the work — `--model`, `--writer-model`, bugs, test runs

The ledger counts, per model, the tasks it finished, the bugs it introduced,
the reviews and test cases that failed on its work, and what it filed
(`kb stats models`, below). It knows only what you record. Nothing infers a
model from the lane, the actor or the harness, because the real writer is
often a subagent on a different model from the lane's own session.

**Two inputs, never mixed.**

- **The author** is the model that ran the command. Every write that takes
  `--as` stores it as `author_model`. Pass `--model NAME`, or let the harness
  export `KB_MODEL=NAME` once per session; the flag wins. With neither, the
  write proceeds, warns
  `no model recorded: pass --model or export KB_MODEL; counted as unknown`,
  and counts as `unknown`. An uncatalogued `KB_MODEL` warns
  `KB_MODEL names unknown model {m}: counted as unknown; pass --model or fix KB_MODEL`.
  An uncatalogued `--model` on any other verb, or an uncatalogued
  `--writer-model`, is refused and writes nothing, except while the catalogue
  is empty, when it warns and counts `unknown`. On `claim` and
  `handoff accept`, `--model` is never refused for being uncatalogued: it is
  stored as given and the author counts as `unknown`, with a warning.
- **The writers** are the models whose code the row carries. Name each with
  `--writer-model NAME` (repeatable) on `claim`, `checkpoint`,
  `handoff create`, `handoff accept` and `task verdict add`. It is never
  filled from `--model` or `KB_MODEL`: a lane that delegates to a subagent on
  another model names that model here, and a write without the flag adds no
  writer. Done tasks, bugs, failed reviews and failed test cases are credited
  to the writers recorded at or before the event, never to the author.

Names are catalogue ids or their aliases (`kb model list --json`), and the
author and writer fields store the canonical id. On `claim` and
`handoff accept`, `--model` is also the restricted-row declaration checked
against `--allowed-model`. That declaration is stored exactly as given, and
`KB_MODEL` never satisfies it, so a restricted row still needs the explicit
flag. A board that has not taken its schema-50 upgrade refuses a verdict
`--writer-model` or `--result fail`, naming `kanban board upgrade`.
`kb-board`, `kb-host` and `kb-group` carry your `KB_MODEL` across ssh to the
board host unchanged; if it is unset here, it stays unset there.

```bash
export KB_MODEL=claude-opus-5-5                       # once, from the harness
kb claim <id> --as "$AGENT" --writer-model kimi-k3 --json
kb cp <id> --lease "$TOKEN" --as "$AGENT" --state continue \
  --summary "…" --intent "…" --next-action "…" --writer-model kimi-k3 --json
kb h new <id> --lease "$TOKEN" --as "$AGENT" --summary "…" --intent "…" \
  --next-action "…" --writer-model kimi-k3 --json
```

**A bug names what introduced it.** A bug row claims, nests and gates like a
task, and needs `--evidence` (an attention id; cited, not looked up). `--introduced-by`
names the row whose work broke it, or the full 40- or 64-hex SHA. That link is
what the scorecard blames, so a bug without one counts as `unattributed`:

```bash
kb t new "Cart total drops the discount" --type bug --evidence <a-id> \
  --introduced-by <t-id or full SHA> --as "$AGENT" --json
```

**A red run is recorded with its failing cases.** Each failing case names the
fix task (any existing row on this board; file it first). A fix task carrying
`--introduced-by` is what attributes the failure. `--run-id` makes a retry
answer the stored run instead of storing a second one:

```bash
kb test record --suite shop-e2e --layer e2e --host hal --image <digest> \
  --sha <40-char SHA> --result fail --evidence <receipt path> \
  --run-id ci-shop-50 --as "$AGENT" --json
kb test case add <run-id> --case c-12 --error "nil cart" --fix-task <t-id> --as "$AGENT" --json
kb test list --json
```

**A failed review is a verdict, not only a note.** Record it with
`task verdict add --result fail --reason …` (above), so it counts against the
writers of the reviewed head.

**The scorecard is a read.** It writes nothing and authorizes nothing:

```bash
kb stats models --json                                # this board
kb stats models --all-boards --since <epoch-ms> --json
kb stats models --drill tests-failed --model kimi-k3 --json
```

`--drill` takes `tasks-done`, `bugs`, `reviews-failed`, `reviews-passed`,
`tests-failed`, `filed-by-tasks`, `filed-by-bugs`, `filed-by-attention`,
`filed-by-sitreps` or `filed-by-verdicts`, and needs `--model`. The coverage
line says how many done tasks carry a recorded writer: the share this section
exists to raise.

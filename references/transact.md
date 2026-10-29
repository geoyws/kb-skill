# Batched writes — transact

Read when: writing any `transact` batch, its envelope, replay or rollback.

## Batched writes — `transact`

Each write above is its own round trip and its own transaction, and the loop's
writes are not independent: a `claim` yields the lease token a `checkpoint`
needs, and a checkpoint that landed after a claim that did not is not a smaller
success, it is a board that lies. `transact` takes an ordered list of ordinary
operations, runs them in one process against one open board inside one
transaction, and **either all of them land or none of them do** (ADR-041).

```bash
kb transact --items-file items.json --json
kb transact --items '[{"name": "note", "arguments": {"id": "t-1a2b3c4d", "text": "…"}}]' --json
<skill-dir>/scripts/kb-board BOARD_ID transact --items-file /dev/stdin --json < items.json
```

`--items` and `--items-file` are one question in two spellings, so passing both
is refused. Prefer the file: one argv string is capped at 128 KiB, which a batch
carrying checkpoint bodies reaches. From outside the board home host, `kb-board`
streams a local `--items-file PATH` on the single ssh connection's stdin and
rewrites the flag to `/dev/stdin`, so both wrapper forms are **one** ssh and the
unmodified items arrive byte-for-byte; the three lease-write items receive
caller-side identity before streaming (see Provenance). The wrapper refuses a
second `--items-file` before transport, including mixed `--items-file PATH` and
`--items-file /dev/stdin` spellings (with or without `=`).

**An item is `{"name": TOOL, "arguments": {…}}`** — the read-only batch's own
shape. `TOOL` is an MCP tool name, which is the command with its subcommand
joined by `_` (`task_move` is `kb task move`), and `arguments` names that
command's flags and positionals literally, hyphens included: `id`, `text`,
`next-action`, `lease-minutes`. A boolean flag is `true`; `false` and `null` are
absence. At most 32 items.

Refused as items, before anything runs: `batch` and `transact` themselves — a
batch may not carry a batch — plus `import` and `search-rebuild`, which open a
board-wide transaction of their own, and anything that does not address one
board's rows.

**The selector goes to `transact`, never to an item.** A batch addresses the one
board it resolved; an item carrying `project`, `workspace`, `db` or `all-boards`
is refused rather than having it silently discarded, and `kb-board` already
injects exactly one board selector. There is no batch-level `--as` either: each item
carries its own actor and is authorized exactly as if it had arrived alone, so a
batch cannot elevate.

**The envelope**, on stdout either way:

```json
{ "batchId": "9f1c…", "ok": true, "failedIndex": null, "rolledBack": false,
  "results": [ { "index": 0, "ok": true, "result": { "…": "what that command answers alone" } } ] }
```

Execution stops at the first failure. That item reports
`{"index", "ok": false, "error"}` with the CLI's own refusal text, every later
item reports `{"index", "ok": false, "skipped": true}` and was never attempted,
and the batch answers `ok: false` and exits non-zero. `rolledBack: true` means
the board is exactly where the batch found it. `rolledBack: false` beside
`ok: false` means one thing only: the list was refused before anything ran, so
`results` is empty. Reads may sit in a write batch and see the earlier items'
writes; a read that fails fails the batch, because continuing past it would be
deciding on absent information.

**`$ref` carries a value forward.** Any argument value may be
`{"$ref": {"item": N, "path": "/json/pointer"}}`, replaced by the value at that
RFC 6901 pointer inside item `N`'s result, where `N` is strictly earlier —
forward and self-references are refused. That is how the lease token a `claim`
mints (`/leaseToken`) reaches the checkpoint without the agent ever handling it.
Every reference is checked for shape before any item runs, so a malformed
pointer refuses the whole batch and nothing lands.

**What a rollback does not undo.** Opening the board retires expired claims and
commits that sweep before any batch scope exists, so a `transact` that rolled
back may still have retired somebody else's lapsed lease and appended those
events. That is correct — the sweep is not part of your batch and reverting it
would resurrect dead leases — but a rolled-back `transact` is not a no-op on the
ledger in every possible sense.

**A replayed batch is not a no-op.** There is no idempotency key. A replayed
loop batch is refused at its claim, because an active claim makes the second
attempt fail by name, so it fails at index 0, skips every later item and lands
nothing — good, but good by accident of `claim`'s own semantics rather than
anything `transact` does. A batch whose first item is additive has no such
protection: two replayed `note` items are two notes, two replayed `sitrep post`
items are two sitreps. After a transport failure, read the board and decide;
never retry a batch blindly.

### The loop's write half, in one batch

`items.json` — claim the task, checkpoint it with the lease the claim just
minted, and write the plan note:

```json
[
  { "name": "claim",
    "arguments": { "id": "t-1a2b3c4d", "as": "@:geoyws/kanban/driver", "lane": "driver" } },
  { "name": "checkpoint",
    "arguments": { "id": "t-1a2b3c4d",
                   "lease": { "$ref": { "item": 0, "path": "/leaseToken" } },
                   "as": "@:geoyws/kanban/driver", "state": "continue",
                   "summary": "wrapper streams the items on one ssh",
                   "intent": "land the batched write surface",
                   "next-action": "document the envelope in the skill",
                   "repo": "/root/work/src/kanban", "branch": "kanban-geoyws-driver",
                   "head": "da9a794", "dirty": "clean" } },
  { "name": "note",
    "arguments": { "id": "t-1a2b3c4d", "kind": "plan", "as": "@:geoyws/kanban/driver",
                   "text": "wrapper first, then the skill, then the tests" } }
]
```

```bash
kb transact --items-file items.json --json                                    # at the boundary
<skill-dir>/scripts/kb-board BOARD_ID transact --items-file /dev/stdin --json < items.json
```

Three writes, one round trip, a lease token that never passes through the agent,
and — if the claim fails because somebody else holds the task — nothing on the
board at all.

**A provenance writer inside a batch carries its own provenance.** `kb-board`
fills `--repo`, `--branch`, `--head` and `--dirty` from your checkout for a
`checkpoint`, `handoff create` or `sitrep post` **command**; a batch's items are
data, so it cannot fill them there. The binary runs on the board home host,
whose cwd is not your checkout, and it refuses a row with blank provenance
rather than storing a null:

```
refusing to record a row with blank provenance: repo_path, branch, head_sha,
dirty_summary missing … Pass --repo PATH --branch NAME --head SHA --dirty TEXT
```

So put `repo`, `branch`, `head` and `dirty` in the item, as above, from
`git rev-parse --show-toplevel`, `git symbolic-ref --short HEAD`,
`git rev-parse HEAD` and a count of `git status --porcelain` lines (`clean`,
`1 file changed`, `N files changed`). The separate overlap identity for
`claim`, `heartbeat`, and `handoff_accept` **is** handled in
batch items by `kb-board` on the caller (see Provenance). `note`,
`release` and `task update` need nothing extra.

### The loop in three batches

One unit of work, start to finish: claim, read, checkpoint. Two `transact`s
for the writes, one `batch` for the reads between them.

**1. START** — `start.json`, one `transact`: the claim and the plan note.

```json
[
  { "name": "claim",
    "arguments": { "id": "t-1a2b3c4d", "as": "@:geoyws/kanban/driver/executor",
                   "lane": "driver", "lease-minutes": 120 } },
  { "name": "note",
    "arguments": { "id": "t-1a2b3c4d", "kind": "plan",
                   "as": "@:geoyws/kanban/driver/executor",
                   "text": "read the context, then the wrapper change" } }
]
```

Keep `TOKEN` from `results[0].result.leaseToken`; the END batch needs it.

**2. READ** — `read.json`, one `batch`: everything about the task you now hold.

```json
[
  { "name": "task_show",      "arguments": { "id": "t-1a2b3c4d", "limit": 200 } },
  { "name": "context",        "arguments": { "id": "t-1a2b3c4d" } },
  { "name": "attention_list", "arguments": { "status": "open", "task": "t-1a2b3c4d" } }
]
```

Each item answers on its own, in order, as `{"index": N, "ok": true, "result":
…}` or `{"index": N, "ok": false, "error": …}`; `result` is exactly what that
read prints alone (`kb ctx t-1a2b3c4d --json` and item 1 are the same JSON). The
rules ride item 1: `context` already carries the task's applicable `rulesIndex`
and inline `alwaysRules`, so the READ batch adds no `rule_list`; fetch a lazy
page with `kb r cat ID` only when the index says you need it. A
failed item does not stop the others, and the batch exits zero. Item names are
the MCP tool names: the command words joined by `_` (`t cat` is `task_show`,
`ctx` is `context`); argument keys are the flag names without `--`
(`"with-relations": true`).

**3. END** — a finished unit closes **outside** `transact`. A done write needs
a full head read from a checkout (Trunk, below), and `kb-board` reads it only
for a direct `checkpoint`, never for a `transact` item; a typed `head` such as
`da9a794` is refused and takes the whole batch, closing note included, down
with it. So land the work on trunk first, then run the done checkpoint from
that checkout and send the closing note after it. `--state done` releases the
lease in the same write, so no `release` follows it. Leave `--repo`,
`--branch`, `--head` and `--dirty` off: the wrapper fills all four from one git
read and attests them, and any one typed by hand voids the attestation.

```bash
cd /root/work/src/kanban            # the trunk checkout, at the landed commit
<skill-dir>/scripts/kb-board BOARD_ID cp t-1a2b3c4d --lease TOKEN \
  --as "@:geoyws/kanban/driver/executor" --state done \
  --summary "wrapper change merged and gated" --intent "close the unit" \
  --next-action "none; the train carries it" --json
<skill-dir>/scripts/kb-board BOARD_ID note t-1a2b3c4d "gate green at <full head>" \
  --as "@:geoyws/kanban/driver/executor" --kind evidence --json
```

A unit that continues later still ends in one `transact` — `checkpoint`
`state: continue` + `note` + `release` — because nothing in it reaches done.

```bash
kb transact --items-file start.json --json
kb batch    --items-file read.json  --json
kb transact --items-file end.json   --json   # a continue-later END only
# through the wrapper, each file travels on the one ssh's stdin:
<skill-dir>/scripts/kb-board BOARD_ID batch --items-file /dev/stdin --json < read.json
```

Replace `TOKEN` with the real token before sending: `$ref` reaches earlier
items of its own batch only, never back into the START batch.

**A replayed START batch lands nothing** — by `claim`'s semantics, not by
`transact`'s. There is no idempotency key (ADR-041 §9): the replayed claim is
refused by name at index 0, every later item is `skipped`, and because the batch
is atomic nothing at all lands. An END batch has no such protection, and neither
has any batch whose first item is additive: two replayed `note` items are two
notes.

**An agent that cannot tell whether a `transact` was received reads the board.**
`kb t cat <id> --limit 200 --json` settles it — the claim is there or it is not,
the checkpoint is there or it is not — and that is what to act on, rather than
retrying blindly.

One thing a rollback leaves standing: the expired-claim sweep every board open
commits before any batch scope exists, so a rolled-back batch may still have
retired somebody else's lapsed lease (**Batched writes — `transact`**, "What a
rollback does not undo").

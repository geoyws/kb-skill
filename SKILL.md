---
name: kb
description: Use the authoritative Kanban work ledger over SSH — tasks, claims and leases, checkpoints, handoffs, sitreps, and attention items that need the board owner. Use whenever recording, reading, resuming, or handing over durable work state.
---

# /kb — the kanban work ledger

`kb` and `kanban` are the same binary, installed under both names. It is a
durable, per-project SQLite ledger for agent work: what there is to do, who
holds it, what happened, what was handed over, and what needs the owner.

**Two rules shape everything below.** The ledger never states something that
isn't true, and it never does something other than what the caller asked. Every
refusal you meet here names the fix — pass the message on rather than
paraphrasing it.

Output is **always JSON**, with or without `--json`.

Every command below is checked against `kb/references/verified-recipes.md` (kanban 0.3.0, board schema 37, 2026-10-01).

## Quick lookups: "did we already do X?" / "what state is row Y?"

Use these exact forms first; each was run against kanban 0.3.1 on 2026-10-13.

- **The wrappers are not on `PATH`.** Call them by path:
  `K=~/.agents/skills/kb/scripts/kb-board` (the installed skill is a flat
  symlink; the source is `agents/skills/kb/kb/scripts/`, never `bin/`).
  `KB_HOSTS_TABLE` defaults to the skill's own `hosts.tsv`; do not set it.
- **Every subcommand needs its noun.** `kb-board BOARD show ID` is refused
  (`unknown command`); write `t cat ID` (`cat` = `show`).
- **Epics are task rows.** There is no `e` noun: `e show e-…` is refused.
  Read an epic with `t cat e-… --json`; `.type` says `epic`.
- **No `--epic` filter.** List an epic's children by `parentID`:

```bash
K=~/.agents/skills/kb/scripts/kb-board
$K BOARD search "skills audit" --all --limit 5 --json | jq -c '.results[] | {sourceId, title}'   # find it
$K BOARD t cat e-1a2b3c4d --json | jq -c '{id, type, status, title, completedAt}'               # its state
$K BOARD t ls --all --with-relations --fields id,status,title,parentID --json \
  | jq -r '.[] | select(.parentID == "e-1a2b3c4d") | [.id, .status, .title] | @tsv'              # its children
```

- `--all` includes done and archived rows; without it, finished work is missing
  and "not found" is not a finding. `search` returns `{results: [...]}`, not an
  array. `completedAt` is epoch milliseconds.
- For "did we do X", also grep the journal (`~/work/journals/.sb/YYYY/MM/*.md`):
  it carries the decision and the why; the row carries the status.

Outside the board home host, board commands go through `kb-board` and registry commands through `kb-host`; for routing, selectors and batched reads, read `references/board-home-host.md`.

## Addressing a board

Each project is one board. Give **exactly one** selector; two that disagree are
refused rather than ranked, because only one is what you meant and nothing in
the receipt would say which was used.

```bash
--project NAME      # a registered project, from any directory
--workspace PATH    # the project containing PATH
--db PATH           # a board file directly
```

`KANBAN_PROJECT` and `KANBAN_DB` are defaults a flag may override — a default is
not a second request. With none of them, the board is the one containing the
working directory.

The board name is identity; roots are optional discovery hints. The same
repository may appear at several paths (including as submodules in several
projects), and a board remains authoritative and fully usable through
`--project NAME` when any or every registered root is absent. Rootless boards
are valid. Do not infer board identity from `TODO.md`, `HANDOFF.md`, a checkout
basename, or a privileged "canonical" root. Prefer an explicit project
selector whenever the directory is ambiguous.

```bash
kb ws ls --json                 # every registered project and its board path
kb init --name NAME [--workspace PATH] [--rootless]   # register a board by name
kb ws det --root /retired/worktree --as "$AGENT" --json
kb ws ls --all --json           # including detached aliases
```

## Who you are — the lane is the worker

George, 2026-09-17: *"u should be @:geoyws/acies/driver and it doesn't matter
if youre codex or claude"*, and *"write to the skill for all lane executors to
just claim the lane work even if it has codex or claude or anything and rename
it to canonical @:geoyws/acies/driver etc"*.

**An agent's `--as` is its actor's name, its callsign** (George, 2026-10-08:
"the NAME of the ACTOR, is a CALLSIGN"): a path, `@:` then one segment per
identifier from the cockpit root down, ending where the identifiers run out.
A traced pane signs `@:<group>/<team>/<lane>/<seat>` —
`@:geoyws/acies/driver/executor`, `@:ifca/px/driver-3/planner`; the lane is
always the third segment. The harness never appears in
it. `claude@driver` and `codex@driver` were one lane wearing two labels, and
every check that compared whole actor strings turned that into a fake
ownership boundary: a lane's own rows read as assigned to someone else, so its
queue hid work from itself.

Consequences, all of them load-bearing:

- **Claim your lane's work regardless of the assignee's label.** An assignee
  of `claude@…`, `codex@…` or `kimi@…` on your lane is you. Only a different
  LANE is a different worker.
- **Rename the rows you touch**, so the estate converges without a mass
  rewrite: `kb t up <id> --assignee "<your callsign>" --as
  "<your callsign>"` before you claim.
- **A live lease still stops you.** Identity is not a licence to `--force`
  over another session that is working right now.
- **`geoyws` remains the owner identity**, and only it resolves or reopens an
  attention row. A lane actor that resolves its own attention has forged the
  owner's verdict.
- Settled rows keep the harness-qualified actor they were written with. That
  is history; do not rewrite it to look tidy.

Measured on the acies board 2026-09-17: the ledger accepts both
`--as "@:geoyws/acies/driver"` and `--as "geoyws/acies/driver"` on notes,
updates and claims. Write the full callsign. Seatless three-segment actors
written before 2026-10-08 are history, not errors; the lane is the third
segment of either form.

**The longer name wins, and the lane field lives alongside it** (George,
2026-09-17, reconciling this section with the callsign rule in the root
`AGENTS.md`). Where a short and a long spelling of one identity are both
defensible, write the long one — so `@:geoyws/acies/driver/executor`, never
`@:geoyws` and never `driver`. And the actor never *replaces* the lane field,
which never carries the seat:

```bash
kb att raise "…" --as "@:geoyws/px/driver-3/planner" --lane driver-3 …
kb sr new "…"   --as "@:geoyws/px/driver-3/executor" --lane driver-3
```

Both, never either. They answer different questions and are read by different
things: the **actor** is who wrote the row, and the **lane field** is what the
row belongs to — and the field is what `att ls --lane`, `sr ls --lane` and
every lane queue filter actually match on. A row whose actor names its lane
but whose `--lane` is empty is invisible to its own lane's queue, which is the
same failure the harness-qualified actor caused, wearing different clothes.

Inside OMP, claim and accept through `kb-session-lease`, never a printed `leaseToken`: read `references/session-lease.md`.

Run `/whoami` for your callsign: it traces the pane from the cockpit root to
`@:<group>/<team>/<lane>/<seat>` (George, 2026-10-05; seat 2026-10-08) —
`@:ifca/prjx/superdriver/planner`, `@:geoyws/acies/driver/executor`. The team
segment is your cage's name and stays the same when you write another board's
row. A callsign's length is dynamic (George, 2026-10-08): it ends where the
identifiers run out. A cockpit-side pane (`_medic`, `_superdriver`) has no
group, team or lane, so its callsign is the window token, then its seat —
`@:superdriver/executor`, `@:medic/planner` — with `--lane` set to that token.

The ledger checks that the two agree on the six self-lane writes: `--as
"@:geoyws/px/driver-3/executor" --lane driver-2` on a `claim` is refused, naming
both lanes (the `--as` and `--lane` rule under the refusal list below).

## Working a task

**A unit of work is two write round trips**, one at each boundary, with a single
read before them — on the measured link that is two round trips where there were
six (ADR-041, Consequences). The reads collapse into one `batch`: up to 32 reads
in one request, answered by one process with one board open — `kb batch
--items-file items.json --json` from the CLI, or the MCP `batch` tool
(`readOnlyHint: true`, under **As an MCP server**) — so `t cat`, `ctx` and
`att ls` for the task you are about to pick up all arrive together; `ctx`
already carries the task's rules index and always-tier bodies, so the batch
takes no `r ls`. This is the default for any run of three or more related
reads, never a string of one-shots (**Runs of reads do not go one-shot**,
above). A batch
is reads only: an item that writes refuses the whole batch before anything runs.
Each boundary is one `transact` (**Batched writes — `transact`**), which lands
entirely or not at all. The three together are **The loop in three batches**,
below.

**The START batch** — take the task, and say what you are about to do:

| # | item | arguments that matter |
|---|---|---|
| 0 | `claim` | `id` (or `next: true`), `as`, `lane`, `lease-minutes` |
| 1 | `note` | `id`, `kind: plan`, `as`, `text` |

`claim` alone, **not** `claim` + `heartbeat`. ADR-041 names the start sequence
"claim, heartbeat, first note", but a fresh claim already carries its 15-minute
lease and `lease-minutes` on the claim itself buys a longer one in the same
item, so a heartbeat milliseconds later renews what was just minted.
`heartbeat` belongs in the middle of a long unit, not at its start. `note`
needs no lease, so this batch never threads the token at all; add an item that
does need it — a `heartbeat`, an early `checkpoint` — and it takes
`{"$ref": {"item": 0, "path": "/leaseToken"}}`, so the agent still never
handles the token. Take `$TOKEN` off the envelope once, from
`results[0].result.leaseToken`, and it serves the rest of the unit.

**The END batch** — one of three shapes, because the checkpoint's own state
decides what may follow it:

| the unit | items |
|---|---|
| finished | not a `transact`: `kb-board BOARD cp ID --state done` from the trunk checkout, then `note` (see below) |
| continues later | `checkpoint` `state: continue` + `note` + `release` |
| continues in another lane | `note` + `handoff_create` |

`--state done` or `blocked` on a checkpoint **releases the lease in the same
transaction** that records it — there is no window where the work reads finished
but the lease is still held. Which is why no `release` may follow one: the token
it presents is already gone, `release` refuses with `task <id> has no active
lease`, and an atomic batch takes the checkpoint and the note down with it. A
task `handoff_create` is the same story from the other end — it writes its own
`continue` checkpoint, releases the lease and returns the row to `todo`, so it
wants no checkpoint before it and no release after it. Every END item carries
`lease: "$TOKEN"` literally, the token the START batch returned: `$ref` reaches
strictly earlier items **of its own batch**, never back into an earlier one.

Definition of Done includes cleanup — the `finished` shape moves the row
done only when every manifest entry is removed or held with a live expiry;
see **Cleanup ledger — what you allocated, you remove**.

The worked JSON is **The loop's write half, in one batch**, below — a claim, a
checkpoint that takes the lease from item 0 by `$ref`, and the note: three
writes, one round trip, a token the agent never handles. Read it there for the
item shapes and the threading, which both boundaries use; the tables above say
which items each boundary carries. It is deliberately not repeated here.

Replayed batches, an unclear `transact` receipt and what a rollback leaves standing: read `references/transact.md`.

### Single commands — interactive, and the fallback

Nothing about the individual commands changed, so each of them is still exactly
correct alone. This is the form for an interactive board-host shell, for a
boundary that really does hold one write, and for finding out which item a
refused batch was wrong about.

```bash
kb t new "Title" --priority 3 --lane fe --json     # 0 most urgent … 9 least, 3 default
kb t new "Half-formed idea" --status draft --json  # not ready for action yet
kb t ls --status todo --json
kb t ls --status in_progress --lane driver-2 --with-claims --json   # who holds what, in one query
kb t ls --status todo --fields id,title,lane,priority,claimed --json # keys only; or --no-body
kb t cat <id> --limit 200 --json                   # one task with claim, notes, checkpoints, handoffs
kb claim --next --as "$AGENT" --json               # or: kb claim <id> --as "$AGENT"
kb hb <id> --lease "$TOKEN" --lease-minutes 30     # renew
kb cp <id> --lease "$TOKEN" --as "$AGENT" --state continue \
  --summary "…" --intent "…" --next-action "…" --json
# author model from KB_MODEL or --model; a subagent writer adds --writer-model (below)
kb rel <id> --lease "$TOKEN"
kb transact --items-file items.json --json         # those writes as one atomic batch, below
```

Model-restricted tasks, task holders, dependency and parked gates, `claim --candidates`: read `references/task-queue-and-gates.md`. The done move's head proof: `references/trunk.md`.

### The lease is 15 minutes, and only `kb hb` extends it

A claim expires 15 minutes after it is taken unless something renews it, and
`kb hb` is the only thing that does — a checkpoint records progress but does
not buy time. An agent that works for an hour without a heartbeat is not
holding the task at the end of it, however busy it was.

Every board command sweeps expired claims before it reads anything, so the
first symptom is usually a refusal on your own next write:

```
task t-1234abcd has no active lease: it was never claimed, or the lease
expired and was retired; claim the task to write to it
```

That is not a lost task. The sweep returned it to `todo`, released your
assignee if it was still yours, and recorded a `claim_expired` event naming
you. Re-claim it (`kb claim <id> --as "$AGENT"`) and carry on — but everything
you had not written down is gone, which is what the next block is for.

### Write at boundaries, because a dead agent writes nothing

Context exhaustion, a provider limit and a kill all end a turn without warning.
The ledger cannot capture what was only ever in the turn, so the discipline is
to write at each boundary rather than at the end:

| When | Write |
|---|---|
| after claiming | `kb note <id> --kind plan "…" --as "$ACTOR"` — what you are about to do |
| on each commit | `kb note <id> --kind progress "<sha> one line" --as "$ACTOR"` |
| on any blocker | `kb cp <id> --lease "$TOKEN" --as "$ACTOR" --state blocked --blocker "…" --summary "…" --intent "…" --next-action "…"` |
| before `/clear`, rotation, or an expected compaction | `kb cp` for one task, or `kb h new` in the session form for the lane |

The last row is the END batch: at a real boundary the checkpoint, the note and
the release — or the handoff — go in one `transact`, so either the whole
boundary is recorded or nothing is.

`kb note` needs no lease, so a progress line still lands after a lease lapsed —
which is exactly when you most want it to.

Session end, `staleClaims`, `orphanedFrom`, resuming in order: `references/session-end-and-resume.md`. `--validation` and review verdicts: `references/review-verdicts.md`.

## Refusals worth knowing

These are deliberate. Do not work around them; they exist because each one was
once a silent wrong answer.

- Unknown flags and extra positionals are **errors**, never dropped. Quote
  anything containing spaces.
- A single-valued flag given twice is refused — last-wins is how the wrong board
  gets written.
- `--force` is required to override a live lease or nest a board inside a
  registered tree, and every override is recorded. It lives on `task move` and
  `task remove` — `claim` has no `--force`, and `--allow-reassign` only
  inspects candidates. To recover a task whose agent died holding its lease,
  `task move <id> todo --as <lane> --force`, then claim for a fresh token.
  `handoff accept` can seize a lease only when a pending handoff exists.
- A diagnostic never modifies what it diagnoses; a missing registered board is
  reported, never silently recreated.
- `restore` takes the data root exclusively and refuses while anything else
  holds it.
- A tag that is not in the board's master file is refused on attach **and on
  filter**. `kb t ls --tag acme/infr` does not answer "nothing" — an empty list
  reads like a finding, and that is how a typo becomes a wrong answer somebody acts on.
- `--tag` and `--clear-tags` together are refused rather than ranked, like every
  other pair of answers to one question.
- `--as` (or `--actor`) and `--lane` must name the same lane on the six
  self-lane writes — `claim`, `handoff accept`, `scope bind`, `scope revoke`,
  `scope release`, `contrib record` — and a disagreement is refused before
  anything is opened, naming both: `--as @:geoyws/kanban/driver-3 --lane
  driver-2` answers `--as @:geoyws/kanban/driver-3 names lane driver-3 but
  --lane is driver-2: pass --lane driver-3, or name lane driver-2's own
  callsign`. The lane of a callsign of three or more segments is its third
  segment; seat and deeper segments are ignored. The
  one- and two-segment cockpit-side form (`@:superdriver/executor`, `@:medic`)
  names its first segment instead; that half is specified (kanban
  `t-0fb1e43d`, SPEC-READY) and implemented (kanban `t-af6a3630`), so until
  the binary you call carries it, only the three-or-more-segment check fires.
  Routing verbs (`task add`, `sitrep post`, `attention raise`, ...) are never
  checked: there `--lane` names where the row goes, not who writes it.
- A capped listing with more rows than the default the caller never set is
  refused naming `--limit N`. `kb att list` on a busy board without `--limit`
  fails, and that is correct: a page cut at the default would read as the
  whole (ADR-037).
- `--fields` naming a key the rows do not carry is refused listing the keys they
  do; `claim` needs `--with-claims`, `dependencies` needs `--with-relations`.
- A `transact` item naming its own board selector, or a second `transact`, is
  refused before any item runs — a batch addresses one board and may not carry
  a batch.
- A card is refused by name rather than half-written: a `--consequence` or
  `--recommend` naming a key no `--choice` declared, a duplicate key, a count
  outside two to four, a recommendation that is not exactly one, a choice with
  no consequence, `--question` without `--context`, `custom` as an authored
  key, `--outcome` without `--choice custom`, a resolve with no `--choice` or
  one naming a key the row does not carry, and any card flag at all on a
  resolved item.
- A restricted task refuses a claim that does not match: `task {id} is
  restricted to models [{list}]; pass --model with one of them to claim it`
  with no `--model`, and `task {id} is restricted to models [{list}]; model
  {model} may not claim it` with a `--model` outside the list. `claim --next`
  and `--candidates` never produce these refusals — they skip restricted rows
  silently unless `--model` matches one.

## References

- `references/board-group-routing.md` — read when coordinating a registered board group (`kb-group`).
- `references/board-home-host.md` — read when routing, SSH, the hosts table, selectors, or a run of reads.
- `references/rules.md` — read when reading or changing registry rules, adopting a board, or moving rules.
- `references/aliases.md` — read when a short command form is unclear.
- `references/session-lease.md` — read when claiming inside OMP, a `kb-session-lease` failure, or the heartbeat file.
- `references/attention.md` — read when raising, answering or resolving an attention item.
- `references/incidents.md` — read when working an incident (`i-` row).
- `references/search.md` — read when searching the ledger or building RAG context.
- `references/sitreps.md` — read when posting or reading a sitrep.
- `references/handoffs.md` — read when stopping with work unfinished, or any handoff.
- `references/messages.md` — read when sending or reading a lane message (`m-` row).
- `references/task-queue-and-gates.md` — read when a task is model-restricted, you need its holder, a gate refuses, or you run `claim --candidates`.
- `references/session-end-and-resume.md` — read when ending a session, `staleClaims`, `orphanedFrom`, or resuming.
- `references/review-verdicts.md` — read when filling `--validation` or recording a review verdict.
- `references/model-attribution.md` — read when recording `--model`/`--writer-model`, bugs, test runs, or `kb stats models`.
- `references/cleanup-ledger.md` — read when allocating host resources for a task, or a cleanup refusal.
- `references/transact.md` — read when writing any `transact` batch, its envelope, replay or rollback.
- `references/plans.md` — read when writing or reading a plan or epic.
- `references/sprints.md` — read when working with a sprint.
- `references/tags.md` — read when tagging rows or a tag refusal.
- `references/provenance.md` — read when checking recorded repo, branch, head or dirty state.
- `references/trunk.md` — read when taking a code row to `done`.
- `references/reading.md` — read when doing context, dashboard, events, doctor or review-visibility reads.
- `references/watch.md` — read when running `kb watch`.
- `references/subscriptions.md` — read when managing subscriptions or dispatcher delivery.
- `references/archival.md` — read when archiving rows or reading cold history.
- `references/deployments.md` — read when recording a deployment (`kb deploy`).
- `references/mcp-server.md` — read when using `kb mcp`.
- `references/adr-index.md` — read when you need the reasoning behind a ledger rule.

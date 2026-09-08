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

## Board home host is the execution boundary

The authoritative Kanban registry and boards live on the board home host chosen
by the consumer table. Before any `/kb` read or write, check the current host
**before attempting SSH**:

```bash
hostname                   # if this prints exactly the selected board home host, stay here
test "$(command -v kb)" = /root/.local/bin/kb
/root/.local/bin/kb v
```

If `hostname` prints anything other than the selected board home host, enter
the routed SSH target and verify the remote boundary there:

```bash
ssh "$BOARD_SSH_TARGET"
hostname                   # must now print exactly the selected remote hostname
test "$(command -v kb)" = /root/.local/bin/kb
/root/.local/bin/kb v
```

Outside the board home host, do not call `kb` directly.

- Use `skills/kb/scripts/kb-board PROJECT KB_COMMAND [ARGS...]` for every
  board-owned one-shot command. It injects exactly one project selector, rejects
  caller-supplied `--project` / `--workspace` / `--db` selectors, and refuses
  `r` / `rule` so registry operations cannot be routed through a board helper.
  On `checkpoint` and `handoff create` it also forwards your checkout as
  `--repo` / `--branch` / `--head` / `--dirty`, because the binary would
  otherwise capture the board host's cwd (see Provenance).
- Use `skills/kb/scripts/kb-host BOARD_HOME_HOST KB_COMMAND [ARGS...]` for raw
  registry-owned or non-board operations only. It resolves the host identity
  from the consumer table, verifies the routed SSH target and remote hostname,
  and preserves argv literally. Registry rule verbs stay on the raw registry
  routing path rather than `kb-board`.

Full detail: reference.md#board-home-host-is-the-execution-boundary

## Aliases

Aliases resolve by **exact match**. Prefix inference is refused in both
directions — `task li` is not `task list`, and `--proj` is not `--project`. A
near-miss flag is *suggested* in the error, never accepted.

| Short | Full |
|---|---|
| `t` | `task` |
| `s` | `story` |
| `h` | `handoff` |
| `att`, `attn` | `attention` |
| `sr` | `sitrep` |
| `w`, `ws` | `workspace` |
| `cp` | `checkpoint` |
| `hb` | `heartbeat` |
| `rel` | `release` |
| `ctx` | `context` |
| `ev` | `events` |
| `dash` | `dashboard` |
| `n` | `note` |
| `r` | `rule` |
| `v` | `version` |

⚠ `att` means **attach** inside `workspace` and **attention** at the top level.
Both are exact-match and scoped, so they never collide — but read
`kb ws att` as attach and `kb att` as attention.

Full detail: reference.md#aliases

## Addressing a board

Each project is one board. Give **exactly one** selector; two that disagree are
refused rather than ranked, because only one is what you meant and nothing in
the receipt would say which was used.

```bash
--project NAME      # a registered project, from any directory
--workspace PATH    # the project containing PATH
--db PATH           # a board file directly
```

```bash
kb ws ls --json                 # every registered project and its board path
kb init --name NAME [--workspace PATH] [--rootless]   # register a board by name
kb ws det --root /retired/worktree --as "$AGENT" --json
kb ws ls --all --json           # including detached aliases
```

Full detail: reference.md#addressing-a-board

## Attention — anything that needs the owner

**Raise it the moment you find it, every time.** A reply, a report and a commit
message are channels that scroll away: an item raised at 03:00 and never acted
on leaves no trace it was ever raised, so the same question gets asked again
three sessions later — or worse, quietly answered by an agent that had no
business deciding it.

```bash
kb att raise "<verdict-first body — receipts, paths, the concrete next action>" \
  --as "<agent>@<lane>" --kind blocking --task <ID if it is about one> \
  --question "<the decision, one sentence, ending in ?>" \
  --context "<what is true now, what is blocked, what waiting costs>" \
  --choice "<key>=<verb-phrase label>|approve" \
  --consequence "<key>=<what happens if it is picked, and what it costs>" \
  --choice "<key>=<verb-phrase label>|reject" \
  --consequence "<key>=<what happens if it is picked, and what it costs>" \
  --recommend <key> --json
```

```bash
kb att list --status open --limit 200 --json              # what is waiting on the owner
kb att list --status open --fields id,priority,question,choices --limit 200 --json   # the cards, without the bodies
kb att list --status open --lane driver-2 --limit 200 --json   # raised from @driver-2, or about a driver-2 task
kb att list --status resolved --fields id,decision,resolution --limit 200 --json     # what he decided, and how

kb att resolve <id> --as geoyws --choice keep-parked --json                        # an authored choice
kb att resolve <id> --as geoyws --choice custom --outcome defer --note "…" --json  # the free-text answer
```

Full detail: reference.md#attention--anything-that-needs-the-owner

## Sitreps — where a lane stands, cheaply

```bash
kb sr new "Retry path is the culprit; fix is in the queuer, tests still red." \
  --as "$AGENT" --lane driver-2 --json          # --task <ID> optional
kb sr ls --lane driver-2 --json                 # the current view, newest first; capped at 20 without --limit
kb sr ls --lane driver-2 --all --limit 100 --json   # including what it superseded
```

**A sitrep is not a handoff, and not a task status.**

| | what it is | costs |
|---|---|---|
| `kb sr new` | where this lane stands right now | one command |
| `kb cp` | a resumable point on a task you hold | a lease |
| `kb h new` | *I am leaving, here is everything* | releases the lease, names a successor |

Full detail: reference.md#sitreps--where-a-lane-stands-cheaply

## Handoffs — task and session

A **task handoff** passes a claimed task to whoever comes next. It needs the
lease, writes a checkpoint, releases the lease, and returns the task to the
queue:

```bash
kb h new <task-id> --lease "$TOKEN" --as "$AGENT" \
  --summary "…" --intent "…" --next-action "…" --reason token_pressure --json
```

A **session handoff** is about the work as a whole — no task, no lease. This is
what a lane hands its successor. Through `kb-board`, run from inside the
checkout: `--repo`, `--branch`, `--head` and `--dirty` are filled in from it.

```bash
<skill-dir>/scripts/kb-board BOARD_ID h new --as "claude@driver-2" --to "driver-2" \
  --reason session_end --summary "…" --intent "…" --next-action "…" --json
```

```bash
kb h ls --project px-crm --status pending --to driver-2 --limit 200 --json
kb h acc <id> --as driver-2 --json      # task lease when claimable; acknowledgement only when settled
```

Full detail: reference.md#handoffs--task-and-session

## Working a task

The loop itself — the START and END `transact` batches, `orphanedFrom`, resuming in order — is reference.md#working-a-task.

### Single commands — interactive, and the fallback

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
kb rel <id> --lease "$TOKEN"
kb transact --items-file items.json --json         # those writes as one atomic batch, below
```

### The lease is 15 minutes, and only `kb hb` extends it

A claim expires 15 minutes after it is taken unless something renews it, and
`kb hb` is the only thing that does — a checkpoint records progress but does
not buy time. An agent that works for an hour without a heartbeat is not
holding the task at the end of it, however busy it was.

### Write at boundaries, because a dead agent writes nothing

| When | Write |
|---|---|
| after claiming | `kb note <id> --kind plan "…"` — what you are about to do |
| on each commit | `kb note <id> --kind progress "<sha> one line"` |
| on any blocker | `kb cp <id> --lease "$TOKEN" --state blocked --blocker "…"` |
| before `/clear`, rotation, or an expected compaction | `kb cp` for one task, or `kb h new` in the session form for the lane |

Full detail: reference.md#working-a-task

## Batched writes — `transact`

```bash
kb transact --items-file items.json --json
kb transact --items '[{"name": "note", "arguments": {"id": "t-1a2b3c4d", "text": "…"}}]' --json
<skill-dir>/scripts/kb-board BOARD_ID transact --items-file /dev/stdin --json < items.json
```

**An item is `{"name": TOOL, "arguments": {…}}`** — the read-only batch's own
shape. `TOOL` is an MCP tool name, which is the command with its subcommand
joined by `_` (`task_move` is `kb task move`), and `arguments` names that
command's flags and positionals literally, hyphens included: `id`, `text`,
`next-action`, `lease-minutes`. A boolean flag is `true`; `false` and `null` are
absence. At most 32 items.

Full detail: reference.md#batched-writes--transact

## Tags — which part of the system this is about

**Tag your rows.** A board that cannot say whether a task is infra, queuer or
askie makes you read titles to find out, and you are the one who knows.

```bash
kb tag ls --json                                   # the vocabulary, with use counts
kb tag new infra --description "hosts, containers, deploys" --as "$AGENT" --json
kb t new "Retry backoff" --tag queuer --tag infra --json
kb t up <id> --tag queuer --as "$AGENT" --json     # replaces, does not append
kb t up <id> --clear-tags --as "$AGENT" --json     # the only way to say "none"
kb t ls --status todo --tag queuer --json          # open work in one subsystem
```

**Read `kb tag ls` before you tag.** The vocabulary is a per-board **master
file**: only a registered tag can be attached, and attaching an unregistered one
is refused naming the nearest match. That refusal is the feature — it is what
stops `infra`, `Infra` and `infrastructure` becoming three answers to one
question.

Full detail: reference.md#tags--which-part-of-the-system-this-is-about

## Refusals worth knowing

These are deliberate. Do not work around them; they exist because each one was
once a silent wrong answer.

- Unknown flags and extra positionals are **errors**, never dropped. Quote
  anything containing spaces.
- A single-valued flag given twice is refused — last-wins is how the wrong board
  gets written.
- `--force` is required to override a live lease or nest a board inside a
  registered tree, and every override is recorded.
- A diagnostic never modifies what it diagnoses; a missing registered board is
  reported, never silently recreated.
- `restore` takes the data root exclusively and refuses while anything else
  holds it.

Full detail: reference.md#refusals-worth-knowing

## Reference

| topic | long form |
|---|---|
| Workspace adoption and rule transfer | `reference.md#workspace-adoption-and-rule-transfer` |
| Tag-scoped rules — what frames work | `reference.md#tag-scoped-rules--what-frames-work` |
| Search and bounded RAG context | `reference.md#search-and-bounded-rag-context` |
| Plans | `reference.md#plans` |
| Provenance — where and when work happened | `reference.md#provenance--where-and-when-work-happened` |
| Reading | `reference.md#reading` |
| Watch — cursor-native live subscription | `reference.md#watch--cursor-native-live-subscription` |
| Subscription records and dispatcher delivery | `reference.md#subscription-records-and-dispatcher-delivery` |
| Archival — bounded hot indexes, intact history | `reference.md#archival--bounded-hot-indexes-intact-history` |
| Deployment attempts — exact release receipts | `reference.md#deployment-attempts--exact-release-receipts` |
| The web view | `reference.md#the-web-view` |
| As an MCP server | `reference.md#as-an-mcp-server` |
| Reference - ADRs and the reasoning | `reference.md#reference` |

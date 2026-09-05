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

An SSH one-shot does **not** load the interactive `PATH`, so it can report
`kb: command not found` even though the binary is installed. Do not rediscover
or re-quote this on every call. From outside the board home host, use the
bundled argv-preserving wrapper for one-shot commands:

```bash
<skill-dir>/scripts/kb-host BOARD_HOME_HOST r ls --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST v
<skill-dir>/scripts/kb-host BOARD_HOME_HOST audit verify --json
```

The wrapper verifies that the routed remote host matches the expected
hostname, invokes the fixed installed path `/root/.local/bin/kb`, and
preserves spaces and shell metacharacters as literal arguments. In an
interactive SSH shell, use the same exact fail-closed check and invocation as
above; any other `kb` resolution is a stale or shadowed PATH. Use an
interactive SSH session for a related series of commands or prose-heavy
mutations; use the wrapper for deterministic one-shots. Never fall back to a
local `kb` after either path fails.

Every `kb …` example below is a command to run **inside the verified board
home host shell**. Keep one SSH session open for related operations to save
connection overhead and tokens. Never run `ssh "$BOARD_SSH_TARGET"` from a
shell whose exact `hostname` already matches the selected board home host; that
shell is already at the required boundary.

From another machine, never invoke a local `kb` or read a local Kanban SQLite
file as a fallback. If SSH or the installed binary is unavailable, stop and report that boundary as blocked; do not run `kb init`, create a replacement board, or let local state diverge.

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

```bash
<skill-dir>/scripts/kb-board BOARD_ID t ls --status todo --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST r ls --json
```

Inside the verified board home host shell, every board-owned command must use
an explicit project selector. Registry rule commands must not receive board
selectors. Use `--workspace PATH` only with a path verified to exist and be
registered by the consumer table. For one-shot automation, shell-quote the
entire remote command and every dynamic value safely; an interactive SSH
session is preferred for prose mutations so titles and bodies cannot be split
or expanded by an intermediate shell.

Selector rule: board-owned commands such as `task`, `tag`, `search`, `claim`,
and `attention` should normally use `--project NAME` remotely. Registry-owned
`rule` commands must not receive `--project`, `--workspace`, or `--db`; rules
live once in the registry and select boards through `ALL`, `ONLY:<board>`, and
`EXCEPT:<board>` tags. Registry watch helpers also reject board selectors and
`--all`. In particular, use `kb-host BOARD_HOME_HOST r ls --json`, never `kb-host BOARD_HOME_HOST r ls --project kanban`.

## Workspace adoption and rule transfer

`workspace adopt` copies an existing board into registry-owned storage. Use it
when the source board already exists and you want the registry to own the copy;
it is not a rename, and it does not mutate the source board file.

```bash
kb workspace adopt --from-board PATH --name NAME (--workspace ROOT | --rootless) --as ACTOR
```

Rule transfer stays on the registry side. `rule export` produces a bundle for a
named source board, and `rule import` consumes that bundle into the destination
registry with fresh destination rule IDs. These are registry rule verbs, so use
`kb-host` or the raw registry routing path rather than `kb-board`.

```bash
kb rule export --board NAME ... --as ACTOR [--output PATH]
kb rule import PATH --as ACTOR
```

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

Scoped to their group:

| Group | Short forms |
|---|---|
| `task` | `ls`=list `mv`=move `rm`=remove `new`=add `up`=update `meta`=metadata `cat`=show |
| `story` | `adv`=advance |
| `handoff` | `ls`=list `new`=create `acc`=accept |
| `workspace` | `ls`=list `att`=attach `det`=detach |
| `attention` | `ls`=list `up`=update `new`=raise |
| `tag` | `ls`=list `rm`=remove `new`=add |
| `rule` | `ls`=list `new`=add `up`=update `cat`=show |
| `sitrep` | `ls`=list `new`=post |
| `deploy` | `ls`=list `cat`=show |
| `subscription` | `ls`=list `new`=add `cat`=show |

⚠ `att` means **attach** inside `workspace` and **attention** at the top level.
Both are exact-match and scoped, so they never collide — but read
`kb ws att` as attach and `kb att` as attention.

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

## Tag-scoped rules — what frames work

Put short, non-secret operating constraints in the one registry-owned rules
document. A board owns work; it is a selector tag on a rule, not a rule scope:

```bash
kb r new "Universal rule." --as "$AGENT" --json       # tags: ALL
kb r new --body-file /tmp/non-secret-rule.md --as "$AGENT" --json
kb r ls --json                         # active table of contents, oldest first
kb r cat r-12345678 --json             # one full body, fetched lazily
kb r up r-12345678 --body "Revised rule" --as "$AGENT" --json
kb rule retire r-12345678 --as "$AGENT" --json
kb r ls --all --full --json            # retired rows and full bodies
kb ev --rule r-12345678 --json          # audited history

# ALL is the default; includes/exclusions are repeatable selector tags.
kb r new "Kanban only." --board kanban --as "$AGENT" --json
kb r new "All except project-a." --except-board project-a --as "$AGENT" --json
kb r up r-12345678 --board kanban --as "$AGENT" --json

# Lowercase subsystem tags intersect the board selector.
kb r new "Queuer only." --tag queuer --as "$AGENT" --json
kb r up r-12345678 --clear-tags --as "$AGENT" --json
```

The first line is the headline. `kb ctx <task>`, every successful new claim and
every accepted handoff carry the applicable active table of contents. Each
summary has one `tags` array plus id, headline, byte size and whether more body
exists. Read a long body with `kb r cat ID`; do not load every detail
speculatively. Other commands do not repeat rules—the injection boundary is
claim/resume, which saves tokens. A stored claim deliberately does not pretend
it re-read current rules.

Rules live once in `registry.db` and are **audited and retire-only**. Updates
retain the previous body; retirement removes a rule from active injection and
the web view without deleting history. There is no `rm` alias. `--global` is
retired and explicitly refused; `g-*` remains valid only as a historical ID.

This is not the secret or long-form memory store. Keep credentials, secrets,
long explanations and cross-machine knowledge in the versioned/git-crypt'd
dotfiles, and let a short rule point there when needed. **Never put a secret
value in the plaintext board database.**

Every rule carries one `tags` array. `ALL` is explicit and default,
`ONLY:<name>` is a named include, and `EXCEPT:<name>` subtracts from `ALL`.
Repeatable `--board`/`--except-board` flags validate exact board names.
Lowercase `--tag` selectors must exist on an active board; several are an OR
set intersected with the board selector. Task claim/context/handoff injection
requires a matching task tag. Taskless session handoffs and web board pages
omit subsystem-scoped rules. See ADR-027.

## Attention — anything that needs the owner

**Raise it the moment you find it, every time.** A reply, a report and a commit
message are channels that scroll away: an item raised at 03:00 and never acted
on leaves no trace it was ever raised, so the same question gets asked again
three sessions later — or worse, quietly answered by an agent that had no
business deciding it.

```bash
kb att raise "<verdict-first, ≤2 sentences, with the concrete next action>" \
  --as "<agent>@<lane>" --kind blocking --task <ID if it is about one> --json

kb att list --status open --limit 200 --json              # what is waiting on the owner
kb att list --status open --lane driver-2 --limit 200 --json   # raised from @driver-2, or about a driver-2 task
kb att list --status open --fields id,kind,raisedBy,taskID --limit 200 --json   # keys only; or --no-body
kb att list --status resolved --limit 200 --json          # the historical trail
kb att resolve <id> --as "$OWNER" --note "…"   # the owner settles it
```

**Say how many you want.** Without `--limit` the listing is capped at 100, and
a board holding more than that **refuses** rather than handing back a page that
reads as the whole; the refusal names `--limit N`. On a busy board
`kb att list` with no `--limit` fails, and that is the right answer — pass a
bound above the count you expect and check the length came back under it
(ADR-037).

`--lane LANE` keeps items raised by `<agent>@LANE` and items about a task whose
lane is `LANE`. `--fields k,k,…` keeps only those keys on each row; a key the
rows do not carry is refused naming the ones they do. `--no-body` drops the
body alone.

`--kind` is a closed set:

| kind | use for |
|---|---|
| `blocking` | work cannot resume until he calls it |
| `decision` | a design or scope call that is his |
| `approval` | production-tier action, `master`/`main` or production-ref push (`prod`, `production`, `*-prod`, `*-production`), destructive op, scope expansion, spend |
| `review` | a deployed tier waiting on his eyes — put the URL in the text |
| `risk` | failed gate, flaky tier, expired credential, half-written file |

There is deliberately no `info`: something that needs nobody is a note, and
`kb n` already holds those.

**Raise, do not resolve.** Agents raise and read; only the owner resolves. The
owner's actor is `geoyws`: the binary gates `resolve` and `reopen` on it and the
refusal names it. `geo` is the pre-2026-09-05 spelling — rows settled then keep
`resolvedBy: geo` as a record, and `--as geo` today is refused like any other
non-raiser. The one exception is an item this same session raised and has since
made moot — retire that with `--note` saying why, so the record shows it was
withdrawn rather than answered. Check `kb att list --status open --limit N`
before raising and add to an existing item rather than duplicating one already
waiting.

Items are **resolved, never deleted**, and resolving twice is refused: that
would overwrite who settled it and when, which is the part worth keeping. Open
items list **oldest first** — an unanswered question does not get less urgent by
being ignored.

Still surface the item in your reply as well. The board makes it survive; the
reply makes the owner see it now. In one and not the other is a bug.

## Search and bounded RAG context

Search before opening many cards speculatively. Results cover board tasks,
notes, checkpoints, handoffs, attention, sitreps and selected audit events,
plus the one registry rules document. Each result has a stable
`kanban://BOARD/KIND/ID` or `kanban://rules/rule/ID` citation.

```bash
kb search "resume the release handoff" --project kanban --json
kb search t-12345678 --source task --limit 5 --max-chars 4000 --json
kb search "authentication recovery" --tag auth --all-boards --json
kb search "retired decision" --all --json       # include archived history
```

Use the returned snippets to choose sources, then read the cited task, rule, or
trail through the ordinary narrow commands. Do not treat a similarity score as
proof and do not cite a snippet without its source URI. `--limit` is 1–100 and
`--max-chars` is 256–100000; use the smallest useful bounds. Filters are
`--source`, `--status`, `--tag`, `--lane`, `--after`, and `--before`.

`search` is read-only. It can calculate a missing deterministic local vector in
memory, but it never writes the cache as a side effect. Cache refresh is an
explicit audited maintenance operation:

```bash
kb search-rebuild --project kanban --as system@search-index --json
kb search-rebuild --all-boards --as system@search-index --json
```

MCP exposes these as `search` (read-only) and `search_rebuild` (write). The web
view at `/search` is cross-board and read-only. `kb doctor --json` reports
`searchIndex` parity and cache freshness for every board.

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

Inside an interactive board-host shell your checkout is not there, so pass the
four yourself — a handoff without a head is one nobody can verify against a
tree:

```bash
kb h new --as "claude@driver-2" --to "driver-2" --reason session_end \
  --summary "…" --intent "…" --next-action "…" \
  --repo "$REPO" --branch "$BRANCH" --head "$HEAD_SHA" --dirty "$DIRTY" --json
```

`--dirty` is measured, never guessed: `clean`, `1 file changed` or `N files
changed`, the wording the binary's own capture writes. An explicit flag always
wins over capture.

The task id and the lease travel together: each half alone is refused, because a
lease exists only over a task and a task cannot be handed over without one.

**Find one by lane, not by directory** — the point of the session form. A
worktree gets recreated, a driver renumbered, a repo cloned to another box; a
brief keyed to a path is then unreachable. The successor knows its project and
its lane, so that is the key:

```bash
kb h ls --project px-crm --status pending --to driver-2 --limit 200 --json
kb h acc <id> --as driver-2 --json      # task lease when claimable; acknowledgement only when settled
```

`--repo`, `--branch`, `--head` and `--dirty` ride inside the record, so the
successor `cd`s from the record and checks the tree against it, rather than the
path ever having been the lookup key. `h ls` is capped at 100 without
`--limit` and refuses past that, naming the flag.

Handoffs are **history**: removing a task drops the link and keeps the account.

## Working a task

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
```

**Who holds a task.** Every `t ls` row carries `claimed: true|false`. The
holder is `claim.agentID`, on `t cat` and on `t ls --with-claims`; there is no
`claim.actor`, and `--fields actor` is refused naming the keys that exist.
`assignee` is intent, never the lease: an assigned task can be free, a held one
assigned to someone else. `--fields claim` needs `--with-claims` and
`--fields dependencies` needs `--with-relations` — each refusal says so.
`--lane LANE` filters on the server, so a big board answers small. `t cat`
caps notes and handoffs at 100 and checkpoints at 20 unless `--limit N` says
otherwise, and refuses past a cap rather than trimming.

A checkpoint takes `--repo`, `--branch`, `--head` and `--dirty` like a handoff
does; `kb-board` fills them from your checkout, and a flag you pass wins.

To inspect the same scheduler queue without taking a lease:

```bash
kb claim --candidates --as "$AGENT" --project NAME \
  [--lane LANE] [--role ROLE] [--caller-scope driver] \
  [--no-cross-lane] [--allow-reassign] [--tag NAME] [--limit N] --json
```

Candidate inspection is strictly read-only and never returns lease tokens.
It shares eligibility and ordering with `claim --next`; claim the selected ID
atomically before starting work because inspection does not reserve it.

`--state done` or `blocked` on a checkpoint **releases the lease in the same
transaction** that records it — there is no window where the work reads finished
but the lease is still held.

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
| after claiming | `kb note <id> --kind plan "…"` — what you are about to do |
| on each commit | `kb note <id> --kind progress "<sha> one line"` |
| on any blocker | `kb cp <id> --lease "$TOKEN" --state blocked --blocker "…"` |
| before `/clear`, rotation, or an expected compaction | `kb cp` for one task, or `kb h new` in the session form for the lane |

`kb note` needs no lease, so a progress line still lands after a lease lapsed —
which is exactly when you most want it to.

### `orphanedFrom` — what the previous holder left behind

When you claim or read a task whose previous holder died, the claim receipt and
`kb ctx` carry an `orphanedFrom` block:

```json
{ "agent": "claude@driver-2", "sessionID": "…", "expiredAt": 1788600000000,
  "lastCheckpointAt": 1788599100000, "worktree": "/root/work/src/kanban",
  "branch": "kanban-geoyws-driver", "headSha": "e87c5a6" }
```

It is **absent**, not null, when there is nothing to report, and it describes
only the current `todo` spell: a task that was orphaned, reclaimed and finished
does not hand a later holder that old orphan. `lastCheckpointAt` is `null` when
the dead holder wrote no checkpoint after claiming, which is the case where the
tree may be further along than anything the ledger knows — `cd` to `worktree`
and compare `git rev-parse HEAD` against `headSha` before trusting either.

### Resuming, in order

1. `kb h ls --project P --status pending --json` — **no `--to`**. Every session
   handoff has an addressee (`h new` refuses one without `--to`), but the
   addressee is a lane name, and lanes get renumbered and recreated. Filtering
   with `--to driver-2` hides a brief left for `driver-3`, which is precisely
   the brief you need after a renumber. List them all and read the addressees.
   More than one match is a stop, not a pick.
2. `kb h acc <id> --as "$LANE" --json`. On a task-form handoff this mints the
   lease and sets `in_progress` in one transaction, so when it succeeds you do
   not also run `claim --next`. A session handoff mints no lease by design.
3. `claim --next` **ignores pending handoffs**, and a task a handoff returned to
   `todo` keeps its assignee — so a different lane needs `--allow-reassign` to
   take it.
4. `kb ctx <id> --json` — newest handoff and checkpoint first, then sitreps,
   then `orphanedFrom` if it is there.
5. `cd` to the record's `repoPath` and check the tree: `git rev-parse HEAD`
   against `headSha`, `git status --short` against `dirtySummary`. A mismatch
   outranks everything else in the brief.
6. `kb note <id> --kind plan` before touching code.

### `--validation` says which layer, by convention

`--validation` is free text and nothing refuses a malformed value, so the
convention is carried here: start every one with `unit:`, `integration:`,
`e2e:` or `substitute:`. Naming the layer is the whole point — "tests pass" on
a row whose only coverage is a unit test reads as end-to-end to the next
person. A fail-closed check was considered and rejected as disproportionate for
an optional flag.

Plan steps are child rows or one `--kind plan` note. There is no checklist
field, and adding one would put the same truth in two places.

## Plans

**A plan is an epic.** Its body is the plan, its children are the work it became,
and `draft` is a plan saved up but not ready to act on. There is no separate plan
object: the container already exists, and `--parent` answers "what did this plan
produce" better than any link would.

```bash
kb t new "Q4 migration" --type epic --status draft --body-file plan.md --json
kb t new "Phase 1" --type epic --parent e-q4 --status draft --json   # a sub-plan
kb t new "Enumerate consumers" --parent e-q4-p1 --json               # the work
kb t mv e-q4 todo --as "$OWNER"                                       # ready to act on
```

**Use this tree for durable todo lists.** For a multi-item roadmap, make the
roadmap an epic and every top-level todo item a direct child epic. Put the
actionable stories and tasks beneath that child, and use dependencies between
child epics for ordering. The roadmap body records scope and success criteria;
do not maintain a duplicate Markdown checkbox list. Any rendered checklist or
progress count is a projection of the board.

The child epic is the roadmap item's checkbox. The current CLI does not
generically derive epic completion from all descendants, so move a child epic
to `done` only after every non-cancelled descendant is settled and its evidence
is durable. A single standalone action stays a task; do not wrap it in
ornamental epics.

`--body-file` reads the body from disk, because a plan is markdown measured in
kilobytes. Passing `--body` and `--body-file` together is refused — two answers
to one question.

**The path is yours, not the board host's.** `kb-board` and `kb-host` read the
file on the machine you typed the command on and transfer its bytes, so
`--body-file plan.md` means the `plan.md` next to you. Until 2026-09-05 the
flag was forwarded literally and the remote read a path that did not exist
there (`Error: read body from /tmp/plan.md: No such file or directory`), which
made it unusable from anywhere but the board home host. An unreadable path now
fails on your machine before any connection, and giving the flag twice is
refused rather than last-wins. It applies to every command that takes it:
`task add`, `task update`, `rule add`, `rule update`, `attention update`.

**A plan has no size limit.** The body travels over the connection's stdin, not
inside the command line, so an epic body is bounded by disk rather than by
`ARG_MAX`. The first version of the fix carried it as an argument and a 128KB
plan died with the remote shell's own `Argument list too long` -- Linux caps a
single argument at 131072 bytes whatever `ARG_MAX` says -- which is a shell
error, not a refusal this wrapper could explain.

**Revising a plan keeps the old one.** `task update --body-file` records the
previous body on the event trail, so the plan's history is
`kb ev --task <epic-id> --json` and needs nobody to have kept a copy:

```json
{ "kind": "task_updated",
  "payload": { "changed": ["body"], "previousBody": "# Q4 migration\n…" } }
```

An epic holds epics, stories and tasks; a story holds tasks; a task holds
nothing. So plans nest and work hangs off them, while a story inside a story is
still refused.

A plan is not an ADR. An ADR records a decision and why it was taken; a plan
records intended work. Keep ADRs in the repo.

**A `draft` is not work yet, and neither is anything under it.** It is the state
before `backlog`: a row still being written, whose title, body or scope may still
be wrong. `claim --next` skips it however urgent its priority, and naming it
explicitly is refused.

Because a plan is an epic, a drafted plan holds back its whole tree: no task
beneath it is offered or granted until the plan is opened, however deep it sits.
Drafts stay **visible to every driver** — a draft is hidden from the queue, not
from the reader — so anyone can read a plan being written and nobody can start
on it by accident.
Promote it with `kb t mv <id> todo --as "$ACTOR"` when it is ready to be acted
on. Use it for anything you are still specifying — an agent reads every row on
the board as a specification, and an unfinished one gets decomposed and worked
as though it were settled.

**Only a task is claimable.** An epic and a story are containers;
`claim --next` skips them, and naming one explicitly is refused pointing at
`story advance` or at the children. Story gates project story status, while
generic epic completion is still an explicit, agent-verified transition.

**A story's status is projected from its gate.** `kb t mv <story> done` is
refused — use `kb s adv <id> --as "$ACTOR"`. `blocked` and `cancelled` stay
directly writable, since the gate cannot express either.

**The tree is enforced**: an epic contains stories, a story contains tasks, a
task contains nothing.

## Tags — which part of the system this is about

**Tag your rows.** A board that cannot say whether a task is infra, queuer or
askie makes you read titles to find out, and you are the one who knows.

Examples below use bare tag names in storage and CLI. Prose may render a
registered Kanban tag as `:slug`, but storage and CLI always use the bare slug
(`--tag slug`). The colon is only presentation notation; do not create another
sigil namespace inside KB tags.

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

**If nothing fits, register it** with a description, then use it. Do not leave
the row unfiled and do not smuggle the subject into the title. Registering is one
command and it is paid once per concept, by whoever names it first.

Names are lowercase letters, digits and inner hyphens. `Infra` is refused rather
than folded — folding would decide for you which spelling you meant.

Tags go on **every row type**, drafts and epics included: a plan belongs to a
subsystem as much as the task it produces does.

**Tags are not lanes.** `lane` is *who picks this up* and `claim --next` routes
on it; a tag is *what part of the system this touches*. Putting a subsystem in
`lane` silently changes which driver receives the work.

`@:team` is atmux routing identity, not a tag. Do not encode board, lane, team,
host, tier, actor, priority, or typed row IDs as tags. In particular, `:module`
means the registered KB tag `module`, while `@:team` names an atmux team; they
are different types and must never be normalized into one another.

Retiring a tag rows still carry is refused and says how many; `--force` strips it
from them and records the count in the trail.

## Provenance — where and when work happened

Recorded automatically. You do not pass it, and you should not have to:

- **A claim** records the worktree it was taken in, whether that worktree is a
  lane (`linked`) or an ordinary checkout (`main`), the branch, the HEAD sha,
  and — for a checkout nested inside a superproject — the **root** commit of the
  outermost repository. That last one is what says which revision of the whole
  tree was checked out; a submodule's own sha does not.
- **Checkpoints and handoffs** fill `repoPath`, `branch`, `headSha`,
  `dirtySummary` and `rootHead` the same way. An explicit `--repo` / `--branch` /
  `--head` / `--dirty` still wins: capture is a default, not an override.
- **Captured where the binary runs.** Over `kb-board` that is the board host,
  whose cwd is no checkout, so the wrapper reads yours before the hop and passes
  `--repo` / `--branch` / `--head` / `--dirty` on `checkpoint`,
  `handoff create` and `sitrep post` — `--branch DETACHED` when HEAD is
  detached, `--dirty` as `clean`, `1 file changed` or `N files changed`. A flag
  you pass is left alone. All three refuse a row whose provenance would be
  blank, so in an interactive board-host shell, pass the four yourself.
- **Timestamps** are on every row already — `createdAt`, `updatedAt`,
  `completedAt`, `claimedAt`, `heartbeatAt`, `expiresAt`, `acceptedAt`,
  `resolvedAt`.
- **`kb ev`** is the audit trail: every mutation, its actor, and what changed.
  Pass `--as` to `kb t new`; compatibility calls that omit it are explicitly
  attributed to `system@cli`, never stored with a blank post-migration actor.
- **`kb audit verify --json`** verifies every board and registry hash chain.
  Keep a snapshot `manifest.json` outside the board data root when rollback
  evidence matters, then run `kb audit verify --against manifest.json --json`.
  A chain proves continuity; the retained manifest is what proves freshness.

Run outside a git repository and provenance is recorded as absent rather than
invented, and the command works exactly the same.

## Reading

```bash
kb ctx <id> --json              # the bounded cold-start packet for a resuming agent
kb dash --json                  # per-board counts, incl. openAttention + pendingHandoffs
kb ev --task <id> --json        # the durable audit trail
kb ev --task <id> --after START_MS --before END_MS --json
kb ev --task <id> --all --after START_MS --before END_MS --json
kb ev --registry --json         # registry rules and workspace lifecycle
kb stale --json                 # work that overran its stale budget
kb doctor --json                # integrity plus advisory unreachable-root hints
kb audit verify --json          # all hash chains, including archived history
kb archive --older-than-days 90 --as system@archive --json
kb w repoint --json             # after moving a repo: point its registered roots at it
```

`ev` is machine-written and append-only — `task_created`, `task_moved`,
`lease_seized`, `handoff_created`, `attention_raised`, `attention_resolved` and
so on. It records **what happened**; `att` records **what needs the owner**. Use
`ev` to reconstruct history, `att` to find open questions.

`ev` time windows are board-only and half-open in milliseconds:
`[after,before)`. SQL filters are applied before `--limit`, `--all` includes
archived history, and registry/rule scopes reject `--after` and `--before`.

`ctx` is bounded and says so: `truncated` is computed, never assumed, and the
marker survives the truncation it describes.

`doctor.unreachableRoots` is advisory discovery maintenance. Non-empty root
hints do not make `healthy` false; missing board files, failed integrity/audit,
schema defects, orphaned rows, future-dated tasks, and search-index drift still
do. Repoint or retire a hint when useful, but never treat a disposable checkout
as the board's identity.

`--limit` must be zero or more. A negative one reads as *no limit* in SQL, so it
is refused rather than silently handing back everything you asked to bound.

**A capped listing refuses a default it would exceed** (ADR-037). Without
`--limit`, `ev` returns up to 50, `sr ls` 20, `search` 10, `att ls`, `h ls`,
`deploy list` and `claim --candidates` 100, and `t cat` 100 notes, 20
checkpoints and 100 handoffs. When more rows exist than that default, the
command fails and names `--limit N` instead of passing the first page off as
the whole; a board holding exactly the default lists all of it. An explicit
`--limit N` is honoured as-is with no marker — ask for one more than you need
if you want to know whether your own bound was hit.

## Watch — cursor-native live subscription

`kb watch` is the canonical long-running process over the append-only ledgers.
It is `longRunning` and `readOnly`, so generated MCP tool schemas exclude it.
`kb events` stays the newest-first snapshot reader, and `/live` remains the
compatibility invalidation socket for the browser.

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
kb watch --registry --cursor CURSOR --limit 100 --json
```

Rules:

- Exactly one scope is active at a time: a board via `--project`, a task via
  `--task`, a registry rule via `--rule`, or the registry via `--registry`.
  There is no cross-board fan-in.
- `--task` is the subject selector. `--kind`, `--relation`, `--prior-status`,
  `--current-status`, and `--tag` are repeatable predicates. `--relation`
  accepts typed forms `parent:ID`, `ancestor:ID`, and `depends-on:ID`.
- Values within one predicate family are ORed. Families are ANDed together.
- The command normalizes the full predicate set before binding it to the
  cursor. Reusing a cursor with any different normalized predicate set fails
  closed.
- Unknown tasks, relation targets, kinds, statuses, or tags fail closed.
- Removed subjects and historical relation targets remain replayable because
  replay uses stored rows, not live lookups.
- Registry scope supports `--kind` only and rejects board semantic predicates.
- `--cursor` is opaque. Literal `0` bootstraps from the start, and a persisted
  cursor is bound to the exact source, selector, normalized predicate set,
  archive state, and last consumed ledger `seq`.
- Malformed, mismatched, or future cursors fail closed.
- `--follow` reopens read-only transactions between polls and emits rows
  synchronously, with no intermediate queue. It requires `--limit` to be at
  least `1`, so `--follow --limit 0` fails.
- `--limit` is constrained to `0..1000` in every mode; follow mode additionally
  rejects `0`. Sparse filtering happens before `--limit`, so the limit slices
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

## Subscription records and dispatcher delivery

Use `kb subscription add|list|show|pause|resume` to manage one board's durable
delivery intent. The addressed board is the tenancy predicate; do not put a
board path or root in the record.

```bash
kb subscription add --project NAME --id sub-codex-queue \
  --subject task:t-12345678 --kind checkpoint_added --tag orchestration \
  --consumer codex.queue --action enqueue-turn \
  --timeout-ms 30000 --max-retries 3 --rate-per-minute 60 \
  --max-concurrency 1 --secret-ref codex_queue_token --as "$OWNER" --json
kb subscription list --project NAME --json
kb subscription show sub-codex-queue --project NAME --json
kb subscription pause sub-codex-queue --project NAME --as "$OWNER" --json
kb subscription resume sub-codex-queue --project NAME --as "$OWNER" --json
```

Rules:

- IDs are immutable `sub-*` identities. There is no update or delete command.
- `--subject` accepts only `task:ID`. `--relation`, `--kind`,
  `--prior-status`, `--current-status`, and `--tag` are repeatable, normalized
  predicates; unknown values fail closed.
- `--consumer` and `--action` are strict names, not executable commands.
- Timeout, retries, rate, and concurrency are required and bounded.
- `--secret-ref` is an optional opaque identifier containing only ASCII
  letters, digits, dot, underscore, and hyphen. Never pass a credential or raw
  token value.
- Subscription rows contain no root, board path, shell text, adapter arguments,
  credentials, delivery acknowledgement, cursor, or dead-letter state.
- Add/pause/resume append audited board events; their payloads omit the secret
  reference. List/show are read-only request-response operations.
- Delivery identity is `(subscriptionID,eventID)`.

The first queue bridge is the Codex consumer `codex.queue` with action
`enqueue-turn`. The subscription row still stores only the normalized
predicates, the named consumer/action, and bounded policy. It does not store
an executable path, shell text, or arbitrary args. Host-local
`dispatchers.json` binds that consumer/action to the checked-in
`kanban-codex-queue-adapter`, the installed Codex executable, the exact
thread/session target, the required installed version, and the fixed host-local
Codex state directory argument `--codex-home /root/.codex` with matching
`CODEX_HOME=/root/.codex`. Every invocation must direct-exec the installed
Codex binary to verify the exact version and the `codex queue --help`
surface, and it must fail closed on drift. The adapter passes only that fixed
`CODEX_HOME` to child Codex processes. On the board home host, direct ingress is
`/root/.local/bin/codex queue --thread UUID_OR_EXACT_SESSION_NAME --message
TEXT` when `codex-cli 0.150.1` is installed. The separately named live
smoke receipt is the distinct runtime check for installed Codex support.

The optional Claude print bridge is consumer `claude.print`, action
`start-readonly-turn`, with capability `start`. Host-local `dispatchers.json`
binds those exact names to `kanban-claude-print-adapter` and fixed arguments
`--claude ABSOLUTE_PATH --home ABSOLUTE_PATH --cwd ABSOLUTE_PATH
--required-version VERSION`; keep executable, home, working-directory, and
version choices outside subscription rows and portable skill text. The
dispatcher serializes this consumer so one fresh worker owns each delivery.
The adapter starts Claude in safe-mode print operation with no tools and no
session persistence; it never resumes or drives an active TUI. Its child
environment contains exactly `HOME` and `PATH=/usr/bin:/bin`, and its configured
working directory is fixed.

Executable, home, working-directory, version/help-surface, authentication, or
response-contract drift fails closed; an invalid Claude response also fails
closed. Treat the compiled-process adapter-contract check and the separately
named installed-version live smoke as distinct evidence: the former proves
protocol and process containment, while the latter proves the pinned installed
Claude can authenticate and complete the real print turn. This bridge is
optional and ships with no active subscription
by default; an operator must deliberately add or resume a matching
subscription after both checks pass.

Run delivery through the separate compiled worker with exactly one explicit
board selector:

```bash
kanban-dispatcher --project NAME [--consumer consumer.name] [--once] [--json]
kanban-dispatcher --workspace /registered/root [--once] [--json]
kanban-dispatcher --db /exact/board.db [--once] [--json]
```

On the board home host use the fixed installed path `/root/.local/bin/kanban-dispatcher` after
the same host-boundary verification used for `/root/.local/bin/kb`. The worker
is not a `kb-board` subcommand. `--consumer` restricts execution to one consumer
identity; `--once` performs one scheduler step; without `--once` it polls until
SIGINT/SIGTERM. Help and version do not open board or registry state.

The allow-list is the private host-local
`$KANBAN_DATA_DIR/dispatchers.json`, protocol version `1`. It maps strict
consumer/action names to a declared capability, an absolute executable, fixed
arguments, and optional secret-reference mappings from `sourceEnv` to one safe
adapter `targetEnv`. Put environment-variable names there, never credential
values. Keep the data root and config inaccessible to group/other users; the
executable must be a regular non-symlink with an execute bit and no group/other
write bit. The adapter starts with an empty environment and receives only the
configured target secret and fixed `CODEX_HOME` when the subscription names
that reference.

Startup validates configuration before the first materialization or claim. Each
scheduler step materializes and recovers work, resolves the candidate, then
serializes per consumer, reloads configuration under the lock, and claims for
`timeoutMs + 30 seconds`. It runs the adapter outside SQLite and finalizes only
the exact lease token. Failures retry deterministically then dead-letter;
pause/resume is rechecked before claim. A crash after adapter success but before
acknowledgement is retried after lease expiry, so adapters must treat
`(subscriptionID,eventID)` as an idempotency key: delivery is at-least-once,
never exactly-once.

## Archival — bounded hot indexes, intact history

```bash
kb archive --older-than-days 90 --as system@archive --dry-run --json
kb archive --older-than-days 90 --as system@archive --json
kb t ls --all --json             # active plus cold tasks
kb ev --task <id> --all --json   # cold audit history for one task
```

The sweep archives only settled rows older than the cutoff: `done`/`cancelled`
tasks without a lease, their notes/checkpoints/tags/events, settled handoffs,
resolved attention and linked sitreps. Old taskless settled records are included.
It also archives terminal deployment attempts that are no longer the current
verified success for their `(repo, tier, environment)`. Started attempts and
each target's latest verified success always remain hot.
Rows remain in the same backed-up SQLite board and `--all` reads them; nothing is
deleted. Operational secondary indexes contain only `archived=0` rows, so their
size follows current work rather than the board's lifetime.

Reads never run retention implicitly. The nightly backup timer explicitly sweeps
every present registered board at 90 days before snapshotting it. `--dry-run`
executes the real transaction, reports its counts, and rolls it back. See ADR-021.

## Deployment attempts — exact release receipts

```bash
kb deploy start --repo OWNER/REPO --commit FULL_40_CHAR_SHA --tier @_p \
  --environment production --host "$BOARD_HOME_HOST" --url "$SERVICE_URL" \
  --task TASK_ID --operation-id OPERATION_ID --as "$AGENT" --json

kb deploy finish DEPLOYMENT_ID --token CAPABILITY_TOKEN --result succeeded \
  --phase verification --served-commit FULL_40_CHAR_SHA \
  --receipt "what was checked live" --as "$AGENT" --json

kb deploy current --json
kb deploy list --status failed --json
kb deploy list --all --json
```

Canonical tiers are `@_bdt`, `@_bd`, `@_bst`, `@_bs`, `@_s`, `@_uat`, and
`@_p`. Record the full pushed commit. `succeeded` is refused unless the served
commit matches it exactly and the phase is `verification` with a non-empty live
receipt. A retry starts a new row with `--retry-of`; never rewrite the old
attempt. Keep the start receipt's capability token until finishing. Use
`deploy abandon --token … --note …` when no failure was observed; `--force` is
an explicit audited recovery override. See ADR-030.

## The web view

`$BOARD_WEB_URL` — every board at once, behind shared Google SSO with only the
allowed account list. Reads use the same Store as the CLI. The sole shipped
write is the Needs-you reply/resolve action, attributed to `$OWNER`.

- **Needs you** (the landing page) — every open attention item across every
  board, oldest first, with its kind, who raised it, how long it has waited, and
  an inline reply plus quick decision buttons. A reply resolves the item and is
  preserved as its resolution note.
- **Lanes** — the counterpart: what every lane last reported, newest first.
- **Boards** — the `kb dash` projection as a table.
- **Plans** — draft epics with their bodies, each naming the work it holds back.
- **Deployments** — verified current releases, active attempts, recent failures,
  and immutable per-attempt receipts; the existing WebSocket refresh keeps it live.
- **Search** — cited exact, lexical, and semantic retrieval across every board.
- **Task detail** — notes, checkpoints, the event trail, and the provenance of
  whoever holds it. Never the lease token: that is a capability, and a page that
  rendered one would hand it to whoever loaded the page.

It is `kanban serve` on loopback 14200, kept up by `kanban-serve.service` and
fronted by nginx. It binds the loopback interface and has **no `--bind` flag** — kanban
implements no authentication and trusts the edge, so the only correct value is
the default. Updating is `install` then `systemctl restart kanban-serve`; the
MCP server's in-place swap does not apply to an HTTP server. `/live` upgrades to
a WebSocket and sends revision-only refresh notifications; agent CLI/MCP access
does not depend on that socket. That socket is compatibility invalidation only;
`kb watch` is the canonical long-running stream over the append-only ledgers,
and `kb events` stays the newest-first snapshot view.

## As an MCP server

```bash
kb mcp     # newline-delimited JSON-RPC over stdio
```

One tool per operation, generated from the command surface, so the tool list
cannot describe something the CLI does not have. Each call runs the real binary,
so validation and refusals are identical to the terminal. Every tool carries
`readOnlyHint`, true only when the operation writes nothing anywhere.

Updating is `install` over the binary — running servers pick it up without any
client reconnecting.

### From another machine: one persistent SSH channel

The board home host boundary applies to the MCP server exactly as it does to
the CLI, so the server runs *there* and the harness talks to it over stdio
through SSH. That gives an interactive harness a connection it holds for the
whole session instead of one handshake per read:

```bash
ssh BOARD_SSH_TARGET /root/.local/bin/kb mcp     # the whole server command
```

Register that command as a stdio MCP server in the harness — Claude Code:
`claude mcp add --scope user --transport stdio kb -- ssh BOARD_SSH_TARGET
/root/.local/bin/kb mcp`; Codex: an `[mcp_servers.kb]` block with
`command = "ssh"` and `args = ["BOARD_SSH_TARGET", "/root/.local/bin/kb",
"mcp"]`. Measured 2026-09-05 from a Mac to the home host over a 210 ms link:
connect 578 ms once, then `task_show` 249-253 ms and a `note` write 285 ms per
call — about one round trip plus the query — against 2.5 s per CLI one-shot
without a ControlMaster. This is the agent API; there is no HTTP service.

What does not change: every tool still takes its own `project`, because the
server resolves a board per call and refuses `--project` on `kb mcp` itself
rather than let one session silently answer about a board it was not asked
about. The same rules, the same refusals, the same `readOnlyHint` — a tool
call is the real binary on the real ledger, as root, on a production-bearing
host. If the host is unreachable the server fails to start and the harness
says so; that is the correct outcome. Never point the registration at a local
`kb` or a local board file to make the error go away.

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
- A tag that is not in the board's master file is refused on attach **and on
  filter**. `kb t ls --tag infr` does not answer "nothing" — an empty list reads
  like a finding, and that is how a typo becomes a wrong answer somebody acts on.
- `--tag` and `--clear-tags` together are refused rather than ranked, like every
  other pair of answers to one question.
- A capped listing with more rows than the default the caller never set is
  refused naming `--limit N`. `kb att list` on a busy board without `--limit`
  fails, and that is correct: a page cut at the default would read as the
  whole (ADR-037).
- `--fields` naming a key the rows do not carry is refused listing the keys they
  do; `claim` needs `--with-claims`, `dependencies` needs `--with-relations`.

## Reference

`docs/adr/` in the kanban repo carries the reasoning. Most load-bearing:
ADR-008 (fail closed), ADR-010 (adapters generated from the surface),
ADR-011 (MCP server + in-place reload), ADR-012 (session handoffs and
attention), ADR-013 (plans are epics), ADR-015 (tags are a master file),
ADR-016 (the web view), ADR-017 (sitreps), ADR-018 (the original board-local
rules). ADR-027 supersedes the scoped rule decisions with one registry-owned,
tag-scoped rules document using `ALL`, `ONLY:<board>`, `EXCEPT:<board>` and
lowercase subsystem tags.
ADR-021 keeps settled history while removing it from operational indexes.
ADR-037 makes a capped listing refuse a default it would exceed.

---
name: kb
description: "Kanban ledger: tasks, claims, leases, checkpoints, att."
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

## Board home host is the execution boundary

Every board's home host is `@@hal` since the P7 ledger cutover on 2026-10-03
(`hosts.tsv`; kb infra t-93c9468e). hal's `/root/.local/bin/kb` is the
installed kanban release binary and the ledger is `/root/.local/share/kanban`
there. Historical note (2026-10-03): hax held a fenced pre-cutover copy;
it is retired, never a board target. Route every board read and write,
including acies, to @@hal through `kb-board` (or `kb-host hal` for registry
commands). An unreachable @@hal blocks ledger operations; never fall back.

The consumer table is `board<TAB>home_host<TAB>ssh_target<TAB>expected_remote<TAB>kb_exec[<TAB>login]`.
Login is `ssh` (the five-field default, unchanged even with `KB_SSH_LOGIN`)
or `own`. For `own`, `kb-board` and `kb-group` select a nonempty
`KB_SSH_LOGIN` with `ssh -l LOGIN -- TARGET`, otherwise query `ssh -G TARGET`.
Root or an absent SSH user is refused before command transport; local effective
UID 0 is refused before the binary. Invalid policies and `own` executables
under `/root/` refuse at table load (exit 64). Group members must share the
registry route's normalized login policy as well as its other route fields.
No wrapper principal claim is forwarded: the remote kernel UID is the identity.
`kb-host` only consumes the extended table; its registry-only authority and
transport are unchanged. `kb-board` refuses `broker` pretransport. This format
support does not authorize account provisioning, installation or enforcement activation.

The authoritative Kanban registry and boards live on the board home host chosen
by the consumer table. `$KB_EXEC` below is the absolute installed `kb` path from that table; `$BOARD_HOME_HOST`, `$BOARD_SSH_TARGET`, and the selected remote hostname likewise come from the consumer's own table — substitute the consumer's values, never another estate's. Before any `/kb` read or write, check the current host
**before attempting SSH**:

```bash
hostname                   # if this prints exactly the selected board home host, stay here
test "$(command -v kb)" = "$KB_EXEC"
"$KB_EXEC" v
```

If `hostname` prints anything other than the selected board home host, enter
the routed SSH target and verify the remote boundary there:

```bash
ssh "$BOARD_SSH_TARGET"
hostname                   # must now print exactly the selected remote hostname
test "$(command -v kb)" = "$KB_EXEC"
"$KB_EXEC" v
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
hostname, invokes the fixed installed path `$KB_EXEC` from the routing table, and
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
  board-owned one-shot command. It injects exactly one board selector (the
  project, or for `--session-board` reads the file instead), rejects
  caller-supplied `--project` / `--workspace` / `--db` selectors, and refuses
  `r` / `rule` and the policy-registry `access`, `worker`, `link`, `scope`,
  `contrib`, `model` and `plugin` verbs so registry operations cannot be routed through a
  board helper. `board`, `sprint`, `batch`, `incident`, `worktree`, `message`,
  `milestone`, `cleanup`, `overlap`, `trunk`, `test` and `stats` are board-owned
  and route here; `kb-host` refuses each of them with this remedy.
  On `checkpoint`, `handoff create` and `sitrep post` it also forwards your
  checkout as `--repo` / `--branch` / `--head` / `--dirty`, because the binary
  would otherwise capture the board host's cwd, and adds `--git-captured` when
  it filled all four itself (see Provenance).
- Use `skills/kb/scripts/kb-host BOARD_HOME_HOST KB_COMMAND [ARGS...]` for raw
  registry-owned or non-board operations only. It resolves the host identity
  from the consumer table, verifies the routed SSH target and remote hostname,
  and preserves argv literally. Registry `rule`, `access`, `worker`, `link`,
  `scope`, `contrib`, `model` and `plugin` verbs stay on the raw registry routing path
  rather than `kb-board`.

```bash
<skill-dir>/scripts/kb-board BOARD_ID t ls --status todo --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST r ls --json
```

**Runs of reads do not go one-shot.** Every wrapper call is its own SSH exec on
the board home host, so three or more related reads — a resume (`ctx`, `r ls`,
`dash`), a queue measurement, a row and its ancestors — take one of two shapes
instead:

1. **The persistent MCP channel, when the harness has it registered** (`ssh
   "$BOARD_SSH_TARGET" "$KB_EXEC" mcp`, `references/mcp-server.md`). One connection
   for the session; each read is then about one round trip plus the query, and
   registry reads (`rule_list`, `dashboard`) ride the same channel as board
   reads.
2. **Otherwise one `batch`**: `kb-board BOARD_ID batch --items-file /dev/stdin
   --json < read.json`, up to 32 board reads in one exec (**Working a task**).
   `rule_list` may sit in it. `dashboard` may not — it reads boards outside the
   batch and is refused with `names dashboard, which reads boards outside the
   batch: run it alone; nothing in it ran` — so it stays its own `kb-host` call.

Writes keep their shape: a single write is one wrapper call, and a unit's two
boundaries are one `transact` each. Measured 2026-10-13 ~07:30 MYT from @@mbp
to @@hal (kanban 0.3.1, SSH `ControlMaster auto`, `ControlPersist 600`, median of
five runs; kanban `t-bbe8d7cc`):

| path | one read | resume: `ctx` + `r ls` + `dash` |
|---|---|---|
| one-shot wrappers (`kb-board ctx`, `kb-host r ls`, `kb-host dash`) | `ctx` 0.52 s, `r ls` 0.50 s, `dash` 1.3–1.9 s | 2.31 s |
| one `kb-board batch` (`context` + `rule_list`), then `kb-host dash` | 0.70 s for both reads | 2.23 s |
| persistent MCP channel, three `tools/call` | `context` 0.20 s, `rule_list` 0.19–0.23 s, `dashboard` 1.17–1.25 s | 1.63 s, after a 0.65 s connect once |

The dashboard's own server time dominates a resume, so the gain there is
modest; the gain grows with the run: N small reads cost about 0.5 N s as
one-shots, about 0.2 N s on the channel, and about 0.7 s flat in one batch.

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
`--all`. In particular, use `kb-host BOARD_HOME_HOST r ls --board kanban --json`
(the rule verb's own board scope), never `kb-host BOARD_HOME_HOST r ls --project kanban`.

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

**Inside OMP, do not print a claim response containing `leaseToken`.** Its
secret filter correctly redacts bearer tokens, which makes a printed claim
unusable for later writes. Use the routed opt-in `kb-session-lease` helper:
`kb-session-lease BOARD claim TASK --as ACTOR --lane LANE`,
`kb-session-lease BOARD hb TASK`,
`kb-session-lease BOARD checkpoint TASK --as ACTOR --state continue|blocked|done --summary ... --intent ... --next-action ...`,
`kb-session-lease BOARD handoff-create TASK --as ACTOR --summary ... --intent ... --next-action ...`,
`kb-session-lease BOARD worktree-register TASK --host HOST --repo REALPATH --path REALPATH --leaf LEAF --branch BRANCH --base-sha SHA --purpose writer|e2e --owner ACTOR`
(kanban IDENTITY IDENT-49: registers the claimed task's worktree with the session's lease and prints the token-free allocation record),
or `kb-session-lease BOARD release TASK`. If the board claim has ended elsewhere
but the private record survives, `kb-session-lease BOARD recover TASK` verifies
the board shows a settled or expired claim and preserves the stale record aside.
A record naming a story or epic (`s-`/`e-`, a lease from before kanban 521c726f
made them unclaimable) is a local exit: `recover s-…`/`recover e-…` sets it
aside without a board read, with `"reason":"unclaimable"`; any board lease it
held expires on its own. Every other operation on an `s-`/`e-` id refuses and
points there, and a `t-` operation over such a record names it.
For an incoming handoff use
`kb-session-lease BOARD handoff-accept HANDOFF --as ACTOR`. Claim and
accept capture the raw reply privately and persist its token in the existing
session file; only a constructed token-free receipt reaches the agent. A
successful `checkpoint --state blocked|done` clears the lease file;
a continuing checkpoint keeps it. A second claim in the same session refuses
until release, handoff or terminal checkpoint settles the first (the refusal
names the recover recovery for a record whose board claim has ended).
The helper needs `jq` and a valid tmux pane or `KB_SESSION_ID`; outside
tmux without a session ID it refuses rather than sharing the legacy file.
Every helper failure prints one line, `kb-session-lease: <what> failed
[cause=<class>]: <reason>`, with the token masked and, for board calls, a
`next:` step. Classes: `usage`, `session_busy`, `session_unsafe`,
`no_session_file`, `persist_failed`, `claim_active`, `claim_ended` (the board
holds no lease: recover), `lease_mismatch` (another lease holds the row: do
not write), `transport` (the call never reached the board, or its answer was
lost and the outcome is unknown: read the row first) and `refused` (kb dotfiles
t-8ccffdeb). A caller's own `--json` is dropped; the helper adds it where it
parses the reply (t-75164807).
Ordinary `kb-board` commands and transaction/MCP surfaces retain their
existing contract; never allowlist real lease tokens in the OMP filter.
**Write the heartbeat session file right after every claim** (George,
2026-09-29, kb dotfiles t-c991e76a option A): mode 0600, two lines — task id,
then lease token, at the path `<skill-dir>/scripts/kb-session-file` prints. The
PostToolUse heartbeat hook (`claude/hooks/kb-heartbeat.sh`) runs the same
helper and reads exactly that file; it never guesses, and no file means no
heartbeats and the lease quietly expires. With a nonempty `KB_SESSION_ID` in
the environment, the path is a deterministic per-session file
(`~/.claude/kb-session.d/session-<full sha256 hex of the id>`), which takes precedence
over tmux detection: two concurrent sessions with different ids get different
files holding their own task id and lease token, and reopening the same id
derives the same path. Without `KB_SESSION_ID` the path is one file per tmux
pane (`~/.claude/kb-session.d/tmux-<socket hash>-<pane>`), so concurrent lanes
on one host never overwrite each other's token (kb infra t-c827bfb2). Run the
helper from the shell of the pane your harness runs in; never write the path
by hand. An explicitly empty, over-long (>256 bytes), newline-bearing, or
control-character session id is refused with no path printed, so set no token file. The session id is only a
filename namespace: it grants no board, lane, role, or lease authority, and
both sides must already agree on the id out of band. Without `KB_SESSION_ID`,
outside tmux it prints the legacy single file `~/.claude/kb-session`
and exits 3, which is safe only while one session per host claims. One
session holds one task, so a second secure claim refuses rather than
overwriting the file. Direct claimers must still manage the file themselves.
The board is resolved off the session cwd by
lane-detect, never stored in the file. A session started with an explicit
session context (`--session-context PATH` or `KB_SESSION_CONTEXT`) takes its
board and lane from that file instead, and no pane is consulted; export
`KB_SESSION_ID` equal to the file's `sessionId`, so this helper and the
heartbeat hook resolve the same session file.

For direct, non-redacting callers only (OMP uses `kb-session-lease`):
```bash
f=$(<skill-dir>/scripts/kb-session-file) || [ $? -eq 3 ] || exit 1
(umask 077; printf '%s\n%s\n' "$TASK" "$TOKEN" > "$f")
```

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
(`readOnlyHint: true`, in `references/mcp-server.md`) — so `t cat`, `ctx` and
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
see `references/cleanup-ledger.md`.

The worked JSON is **The loop's write half, in one batch**, below — a claim, a
checkpoint that takes the lease from item 0 by `$ref`, and the note: three
writes, one round trip, a token the agent never handles. Read it there for the
item shapes and the threading, which both boundaries use; the tables above say
which items each boundary carries. It is deliberately not repeated here.

The worked batches are in **Batched writes — `transact`**, below.

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
- `references/rules.md` — read when reading or changing registry rules, adopting a board, or moving rules.
- `references/aliases.md` — read when a short command form is unclear.
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

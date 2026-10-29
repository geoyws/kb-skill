# Plans

Read when: writing or reading a plan or epic.

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
to `done` only after every non-cancelled, non-abandoned descendant is settled
and its evidence is durable (`abandoned` is terminal dropped work, settled like
`cancelled`; a `kiv` descendant is still parked work and keeps the epic open).
A single standalone action stays a task; do not wrap it in
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

**An explicit session context travels the same way.** `kb-board
--session-context ctx.json` reads the context file on your machine (at most
64 KiB), recreates it in a private temp file on the board host for that one
call, and removes it afterwards. Because ssh carries no environment, a set
`KB_SESSION_ID` is passed to the board host explicitly, an empty one
included, so the core's agreement check sees exactly what you exported.
Unreadable, oversized or repeated `--session-context` refuses on your machine
before any connection.

**A session file can also choose the board for a read.** `kb-board BOARD
task list --session-board ctx.json` (kanban done-gate DG-31) travels exactly
like `--session-context`, but the call then carries no `--project`: the board
host resolves the file's board through its registry and reads it under your
own grants, which is what works under managed enforcement, where `--project`
is refused. It fills no `--as`, `--lane` or `--session`, so a board-wide read
stays board-wide; add `--session-context` naming the same file to scope it to
the file's lane. Only one-board reads accept it (the read-only commands,
`batch`, `claim --candidates`); the binary refuses a write. The file's `board`
must be BOARD, and a missing path, a repeat, an unreadable, oversized or
unparseable file, or one naming no board or another board refuses on your
machine before any connection.

**Revising a plan keeps the old one.** `task update --body-file` records the
previous body on the event trail, so the plan's history is
`kb ev --task <epic-id> --json` and needs nobody to have kept a copy:

```json
{ "kind": "task_updated",
  "payload": { "changed": ["body"], "previousBody": "# Q4 migration\n…" } }
```

An epic holds epics, stories, tasks and bugs; a story holds tasks and bugs; a
task and a bug hold nothing. So plans nest and work hangs off them, while a
story inside a story is still refused.

A plan is not an ADR. An ADR records a decision and why it was taken; a plan
records intended work. Keep ADRs in the repo.

**A `draft` is not work yet, and neither is anything under it.** It is the state
before `backlog`: a row still being written, whose title, body or scope may still
be wrong. `claim --next` skips it however urgent its priority, and naming it
explicitly is refused.

**Below `draft` sit two parked states, neither ever claimable** (kanban 0.3.1):
`kiv` (kept in view) is a parked idea awaiting explicit
resumption — never claimable, `completed_at` stays NULL, and age-archive never
takes it; `abandoned` is terminal dropped work — never claimable,
`completed_at` is set, and it archives like `done`/`cancelled`. Neither is
`cancelled` (stopped committed work) nor `done` (completed work). Default
`t ls` and the working `ctx` omit both; address them explicitly with
`t ls --status kiv` / `--status abandoned --json` or `t cat <id>`. Park with
`kb t mv <id> kiv --as "$ACTOR"`, drop with `kb t mv <id> abandoned --as
"$ACTOR"`; resume a parked idea only with an explicit move to `draft`,
`backlog` or `todo`, and reopen dropped work like a cancelled row. The
adjacency refusals, verbatim:

| move | refusal |
|---|---|
| terminal row to `kiv` | `task {id} is {done|cancelled|abandoned}, not parkable: reopen it to draft, backlog or todo before moving to kiv` |
| `kiv` anywhere but home | `task {id} is kiv: resume it explicitly to draft, backlog or todo before moving to {to}` |
| `done` to `abandoned` | `task {id} is done: completed work cannot be abandoned; use cancelled for stopped committed work` |

Because a plan is an epic, a drafted plan holds back its whole tree: no task
beneath it is offered or granted until the plan is opened, however deep it sits.
Drafts stay **visible to every driver** — a draft is hidden from the queue, not
from the reader — so anyone can read a plan being written and nobody can start
on it by accident.
Promote it with `kb t mv <id> todo --as "$ACTOR"` when it is ready to be acted
on. Use it for anything you are still specifying — an agent reads every row on
the board as a specification, and an unfinished one gets decomposed and worked
as though it were settled.

**Only task and bug rows are claimable.** An epic and a story are containers;
`claim --next` skips them, and naming one explicitly is refused with
`task {id} is {a|an} {type}, and only task and bug rows are claimable: {remedy}`,
whose remedy points at `story advance` or at the children. Story gates project
story status, while generic epic completion is still an explicit,
agent-verified transition.

**A story's status is projected from its gate.** `kb t mv <story> done` is
refused — use `kb s adv <id> --as "$ACTOR"`. `blocked` and `cancelled` stay
directly writable, since the gate cannot express either.

**The tree is enforced**: an epic contains epics, stories, tasks and bugs, a
story contains tasks and bugs, and a task or a bug contains nothing.

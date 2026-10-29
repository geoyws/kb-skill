# Task queue, holders and gates

Read when: a task is model-restricted, you need its holder, a gate refuses, or you run `claim --candidates`.

A task can be **restricted to models** (ADR-049): a task that needs a
capability only one model has must force the harness to run that model, so
the restriction lives on the task row and the declaration lives on the claim.
The allow-list is checked by shape only, not against the model catalogue, so
a typo restricts a task to a model nobody runs.

```bash
kb t new "Title" --allowed-model Astra --allowed-model Kimi --json  # repeatable; empty list is unrestricted
kb t up <id> --allowed-model claude-fable-5-1 --as "$ACTOR" --json    # REPLACES the whole list
kb t up <id> --clear-allowed-models --as "$ACTOR" --json              # together with --allowed-model, refused
kb t ls --allowed-model Astra --json                    # filter
kb claim <id> --as "$AGENT" --model Astra --json        # declares which model is claiming
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

**Read dependency gates before taking work.** `kb t cat ID --json`,
`kb t ls --with-relations --json`, and `kb ctx ID --json` expose
`blockingGates` for unmet prerequisites declared by the task or an ancestor.
Each entry names `sourceTaskID` (the declaring row), `prerequisiteID`,
`prerequisiteTitle`, and `prerequisiteStatus`. A foreign blocker additionally
names `prerequisiteBoardID`, the source board's registered UUID; use that UUID
and the exact opaque item ID together, not the ID alone, to identify it. If
source state cannot be read, `prerequisiteStatus` and `unavailable` are both
`"unavailable"` and `prerequisiteTitle` is `null`: the source's existence and
state are not confirmed, and the gate remains unmet. Full/compact context
also spells out the foreign board UUID beside the item ID; local blocker prose
and fields stay unqualified. `dependencies` still describes only the row's
own readable local edges, not inherited or foreign blockers. For list field
selection, `--fields blockingGates` requires `--with-relations`, just like
`--fields dependencies`. An empty `blockingGates` array says only that no
dependency gate is unmet, not that the task is otherwise claimable.

**Parked rows and parked gates refuse with their own sentences.** Named claim
refuses — and `claim --next` / `claim --candidates` exclude — a row whose own
status **or any ancestor's** is `kiv` or `abandoned`, however urgent it is.
Only `done` satisfies a prerequisite: a `kiv` or `abandoned` prerequisite
stays unmet and its edge is never silently cleared. Pass these on verbatim:

| gate | refusal |
|---|---|
| own status parked | `task {id} is {kiv\|abandoned}, not claimable: resume/reopen it with \`task move {id} todo\` before claiming` |
| parked ancestor | `task {id} sits under {ancestor} ({kiv\|abandoned}), not claimable: resume/reopen with \`task move {ancestor} todo\` or reparent the task` |
| draft ancestor | `task {id} sits under {ancestor}, which is still a draft: open it with \`task move {ancestor} todo\` before this can be worked` |
| unmet prerequisite | `{kind} {id} is gated on work that is not done: {details}. A prerequisite satisfies a gate only at status done: finish it, or drop the edge with \`task update <owner> --depends-on ...\` or \`--clear-dependencies\`.` — plus ` Re-plan the dependency before claiming.` when the blocking prerequisite itself is `kiv` or `abandoned` |

Explicit resumption of a `kiv` ancestor (or an authorized reopen of an
`abandoned` one) restores its descendants under the normal gates; otherwise
reparent or replan — never an automatic release.

A checkpoint takes `--repo`, `--branch`, `--head` and `--dirty` like a handoff
does; `kb-board` fills them from your checkout, and a flag you pass wins.

To inspect the same scheduler queue without taking a lease:

```bash
kb claim --candidates --as "$AGENT" --project NAME \
  [--lane LANE] [--role ROLE] [--caller-scope driver] \
  [--no-cross-lane] [--allow-reassign] [--tag ESTATE/SUBSYSTEM] [--limit N] --json
```

Candidate inspection is strictly read-only and never returns lease tokens.
It shares eligibility and ordering with `claim --next`; claim the selected ID
atomically before starting work because inspection does not reserve it.

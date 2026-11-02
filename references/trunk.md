# Trunk — done means on trunk

Read when: taking a code row to `done`.

## Trunk — done means on trunk

On a board whose trunk has been set, every write that takes a row of any
type to `done` — `task move … done`, `checkpoint --state done`, `story
advance` into `done`, an import flip — is refused when the row has recorded a
head unless that head is a full 40-character SHA, read from a checkout (a
claim's head, kept even after the claim ends, or `headSource` `kanban` /
`kb-wrapper`), and contained in the board's trunk. The head judged is the
newest across the row's checkpoints, handoffs, sitreps and claim heads. The
check is opt-in per board: a board with no trunk set (`trunk show` answers
`null`) is not checked, and a row that never recorded a head (non-code work,
a `task add --status done`, a newly imported row) is not checked either,
whatever the board's `done_gate`. The trunk is asked fresh each time (`git
ls-remote`), so a merge that has not been pushed is not on trunk.

```bash
kb trunk set --repo PATH --remote NAME --branch NAME --as ACTOR --baseline SHA [--repin]   # root; any board writer
kb trunk set --path-chain '["p1","p2"]' --repo PATH --remote NAME --branch NAME --as ACTOR --kind owned --required-suite S --required-layer L   # or --kind third-party --pin SHA
kb trunk show --json   # {"repo","remote","branch","repositoryID","baseline","children","uncovered","revision"} or null
```

- `trunk set` is accepted from any actor the board's write authority admits
  (under `managed`: `write` at the board's scope, `--as` bound to you or your
  live lane actor; kanban `t-0b70d2b3`, 2026-10-30). It is a coordinator
  verb: run it from your lane's own process, never with a worker
  credential (`KANBAN_WORKER_CREDENTIAL`), which is refused as
  coordinator-only. Name the board's real trunk, never your own work
  branch; every set writes a `trunk_set` event naming you. Root pins the trunk with
  `--baseline`, required on gitlinked roots once the DG-46 kanban release
  ships (today kanban stores a hint instead). When a stored pin differs
  from the fresh gitlink, or a stored child's gitlink vanished, the root
  set carries `--repin` once the DG-48 kanban release ships: kept
  third-party children are re-pinned, owned re-verified, vanished gitlinks
  dropped, all or nothing; child sets run only for new chains and kept
  chains whose branch, URL or kind changed, after the root set. A moved
  baseline alone takes a plain `--baseline` root set. Every set
  re-verifies the snapshot; one 30 s limit covers the whole snapshot today,
  per-question deadlines once DG-48 ships.
  One `--path-chain` call per gitlink chain follows, parent before
  descendant, never `--baseline` with `--path-chain`. Owned needs a geoyws integration branch and a named
  suite, else the child is third-party with its exact gitlink `--pin`. Every
  child needs its pin an ancestor of its branch tip, a full non-partial
  checkout, one branch per repository across paths, and a safe remote URL
  (no leading `-`, `?`, `#` or `::`, schemes limited to ssh/https/http/file/
  git, no userinfo, no colon in an scp user part). The checkout's own git
  config must not redirect the remote (`url.`/`include.` rewrites, an ssh
  or proxy command, credential helpers, `http.*proxy` and friends, or
  remote helper overrides). `PATH` is a readable, non-shallow checkout on
  the ledger's host, `NAME` a remote configured there that answers
  `ls-remote` with the branch. A `<trunk>-driver-N` lane branch is refused.
  A set writes one `trunk_set` event naming the actor; there is no unset.
- `trunk show` reads only, and is open to anyone who can read the board.
- To land work: merge and push it to trunk, then record the landed commit
  from that checkout — `kb cp` for a task, `kb sr new --task ID` for a story or
  epic (a story cannot be claimed) — through `kb-board` from inside the
  checkout, so the head is read rather than typed. Then move it to `done`.
- Refusals name the task, the head and `{remote}/{branch}`: a short head, a
  head not read from a checkout, trunk unreachable, not on trunk, or the head
  moved during the check (the old "no trunk set" and "no head" refusals are
  retired). No `--force` passes a miss, for any actor including `geoyws`, and
  no `trunk_gate_override` is written. On code work the done write must also
  find every reviewed commit contained in the task's owner-bound final branch.
- Work that landed only on an interim branch stays open. Record it with
  `kb task promotion record ID --repository-id ID --branch NAME --sha FULL
  --owner ACTOR --next-action TEXT [--integration-task ID | --clear-integration]
  --as ACTOR`, and read it back with `kb task promotion show ID --json`. A
  record is progress, never completion. `kb doctor` and `kb dash` list
  `pendingFinalTasks`; `task show` and `claim --candidates` carry
  `finalPromotion`. A task with promotion progress cannot be removed — cancel
  or abandon it.
- An outstanding cleanup entry refuses every done path on every row type,
  stories and epics included, with no `--force` past it.

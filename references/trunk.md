# Trunk — done means on trunk

Read when: taking a code row to `done`.

## Trunk — done means on trunk

On a board whose trunk `geoyws` has set, every write that takes a row of any
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
kb trunk set --repo PATH --remote NAME --branch NAME --as geoyws --baseline SHA   # root; geoyws only
kb trunk set --path-chain '["p1","p2"]' --repo PATH --remote NAME --branch NAME --as geoyws --kind owned --required-suite S --required-layer L   # or --kind third-party --pin SHA
kb trunk show --json   # {"repo","remote","branch","repositoryID","baseline","children","revision"} or null
```

- `trunk set` is accepted only from `geoyws`. Root pins the trunk with
  `--baseline`, required when the root tree holds gitlinks; one `--path-chain`
  call per gitlink chain follows, parent before descendant, never `--baseline`
  with `--path-chain`. Owned needs a geoyws integration branch and a named
  suite, else the child is third-party with its exact gitlink `--pin`. `PATH`
  is a readable, non-shallow checkout on the ledger's host, `NAME` a remote
  configured there that answers `ls-remote` with the branch. A
  `<trunk>-driver-N` lane branch is refused. A set writes one `trunk_set`
  event; there is no unset.
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

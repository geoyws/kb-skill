# Provenance

Read when: checking recorded repo, branch, head or dirty state.

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
- **`--git-captured` — the wrapper's attestation, never typed.** When
  `kb-board` filled all four of `--repo`, `--branch`, `--head` and `--dirty`
  from its own git read, and you passed none of them, it appends the boolean
  `--git-captured`. Pass any one of the four yourself and it adds nothing.
  kanban records each `checkpoint`, `handoff` and `sitrep` head's
  `headSource`: `kanban` (the binary's own git read at `--repo`, or its cwd,
  agreed with the head), `kb-wrapper` (a complete `--git-captured` call) or
  `typed` (anything else). Only a read head — `kanban` or `kb-wrapper` — can
  take a row to `done` (see Trunk). The wrapper adds the flag; you never type
  it. Typing it is a recorded false attestation that git was read, and a call
  carrying it without all four values is refused before anything is written:
  `--git-captured needs --repo, --branch, --head and --dirty from the same git read`.
- **Cross-board overlap uses a separate repository key.** Routed `kb-board`
  claim and task handoff acceptance derive it on the caller from the canonical
  Git common-dir and stable local machine ID. Linked worktrees of one repository
  share the same key; another repository or machine does not. `--repo-key KEY`
  explicitly asserts identity and wins over `--repo PATH`; the wrapper
  consumes that path locally rather than forwarding it. `--no-repo-capture`
  suppresses implicit capture, and the wrapper always forwards it to keep the
  board host cwd out of routed writes. Heartbeat never derives from cwd: absent
  an explicit key or repo move, it preserves the saved key. A caller outside a
  repository forwards no inferred key. This is not the checkpoint/handoff/sitrep
  provenance above. Routed `transact` applies these rules inside only
  `claim`, `heartbeat` and `handoff_accept` items (both `--items`
  and `--items-file`); `kb-host` refuses these board-owned writes.
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

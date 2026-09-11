# kb public package

This directory stages the public wrapper surface for a board-aware `kb`
installation.

## What is here

- `SKILL.md` documents the public skill surface.
- `scripts/kb-board` routes commands by board and preserves argv literally; on
  `checkpoint` and `handoff create` it also forwards the caller's git checkout
  as `--repo`, `--branch`, `--head` and `--dirty` unless the caller passed them.
- `scripts/kb-host` routes registry commands by board home host and preserves
  argv literally.
- `scripts/denylist-check`, `scripts/leak-gate`, `scripts/commit-gate`, and
  `.githooks/pre-commit` enforce the publication hygiene gate.
- `scripts/install-hooks` and `scripts/check-hooks` manage the versioned hook
  path.
- `tests/kb-wrapper-tests.sh` exercises the wrapper and gate behavior.

## Routing model

The installed package expects either `KB_HOSTS_TABLE` or an adjacent
`hosts.tsv`. The table is consumer-owned and must define, in order:

1. board identifier
2. board home host
3. SSH target
4. expected remote hostname
5. absolute KB executable path

The parser rejects missing, duplicate, unknown, or malformed board mappings.
The KB executable path must be absolute. `kb-board` injects the project
selector for board-owned commands; `kb-host` preserves registry commands
without a board selector. Remote execution uses the board home host identity,
the SSH target, and the remote hostname check is fail-closed.

## Workspace adoption and rule transfer

`workspace adopt` copies an existing board into registry-owned storage. It is a copy into the registry, not a rename, and it leaves the source board file unchanged.

```bash
kb workspace adopt --from-board PATH --name NAME (--workspace ROOT | --rootless) --as ACTOR
```

Rule transfer stays on the registry side. `rule export` writes a bundle for a
named source board, and `rule import` consumes that bundle into the destination
registry with fresh destination rule IDs. Route those verbs through `kb-host`
or the raw registry path, not `kb-board`.

```bash
kb rule export --board NAME ... --as ACTOR [--output PATH]
kb rule import PATH --as ACTOR
```

Example row copied into a TSV table:

```tsv
board_identifier	board_home_host	ssh_target	expected_remote_hostname	<absolute_kb_binary_path>
```

Example `kb-board` body-file invocation copied from the package docs:

```bash
scripts/kb-board board_identifier t new "Title" --body-file /tmp/plan.md --json
```

## Attention decision cards

An open attention item is a **decision card** (ADR-042): a question, the
context needed to answer it, and two to four authored choices, each with the
consequence of picking it and a machine-readable outcome of `approve`,
`reject`, `defer` or `other`, exactly one marked as the recommendation. Every
item also offers an implicit `custom` answer that needs its own `--outcome` and
a note, so nothing closes an item without a verdict; a row that authored no
choices is served as the `approve`/`reject` default pair with no
recommendation, and the body stays the long form.

```bash
scripts/kb-board BOARD_ID att raise "Review the deployed queuer" --as codex@driver --kind review --tag queuer \
  --question "The queuer is deployed but unproven - review it now, or ship and review after?" \
  --context "The queuer has been live on staging since 2026-09-05 with no errors. One task waits on the review, and waiting costs a day of feedback." \
  --choice "review-now=Review the deployed queuer today|approve" \
  --consequence "review-now=You spend about twenty minutes reading it today and the waiting task unblocks this afternoon." \
  --choice "ship-first=Ship it and review after the release|defer" \
  --consequence "ship-first=The release goes out unreviewed and a task is filed to review it on 2026-09-12." \
  --recommend review-now
scripts/kb-board BOARD_ID att resolve a-12345678 --as geoyws --choice review-now
scripts/kb-board BOARD_ID att resolve a-12345678 --as geoyws --choice custom --outcome defer --note "After the aix pin lands."
```

Bounds: question at most 160 characters, context at most 800, choice labels
at most 60, consequences at most 200, two to four choices, every choice needs
a consequence, exactly one recommendation, and `--question`/`--context` come
as a pair. Every refusal is store-level and names its fix — an undeclared
`--consequence` key, a duplicate key, a count outside two to four, no
recommendation or two, a choice with no consequence, half a question/context
pair, the reserved `custom` key, a `--recommend` with no choices, and each
length bound — and the recommendation goes first wherever a card is rendered.

## Hygiene model

The leak gate requires an explicit denylist file path and `gitleaks`. The
commit gate requires `KB_DENYLIST_FILE` and delegates to the leak gate.

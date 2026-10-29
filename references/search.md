# Search and bounded RAG context

Read when: searching the ledger or building RAG context.

## Search and bounded RAG context

Search before opening many cards speculatively. Results cover board tasks,
notes, checkpoints, handoffs, attention, sitreps and selected audit events,
plus the one registry rules document. Each result has a stable
`kanban://BOARD/KIND/ID` or `kanban://rules/rule/ID` citation.

```bash
kb search "resume the release handoff" --project kanban --json
kb search t-12345678 --source task --limit 5 --max-chars 4000 --json
kb search "authentication recovery" --tag acme/auth --all-boards --json
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

MCP exposes these as `search` (read-only) and `search_rebuild` (write). `kb doctor --json` reports
`searchIndex` parity and cache freshness for every board.

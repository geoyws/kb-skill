# Incidents

Read when: working an incident (`i-` row).

## Incidents — what broke, how bad, what happened next

An incident is a typed `i-` row with a severity (`SEV1`–`SEV4`) and a
four-state lifecycle, `open` → `mitigated` → `resolved` → `reviewed`, one step
at a time. The timeline is append-only (`time`/`actor`/`text`); there is no edit
and no delete. Incidents are never claimed and never hold a lease — no claim,
handoff-accept, or scheduler verb takes an `i-` id. The forms below follow the
`kanban incident` usage text in `rust/lib.rs`, which is the grammar authority:

```bash
<skill-dir>/scripts/kb-board BOARD_ID incident open "DB failover stalled" --severity SEV1 --as "$AGENT" --json
<skill-dir>/scripts/kb-board BOARD_ID incident note i-XXXXXXXX "Replica picked up the failover" --as "$AGENT" --json
<skill-dir>/scripts/kb-board BOARD_ID incident link i-XXXXXXXX --task t-XXXXXXXX --as "$AGENT" --json
<skill-dir>/scripts/kb-board BOARD_ID incident mitigate i-XXXXXXXX --as "$AGENT" --json
<skill-dir>/scripts/kb-board BOARD_ID incident resolve i-XXXXXXXX --as "$AGENT" --json
<skill-dir>/scripts/kb-board BOARD_ID incident list --status open --json
<skill-dir>/scripts/kb-board BOARD_ID incident show i-XXXXXXXX --json
```

One line per verb:

- `open` — open a typed incident at status `open` with a severity.
- `mitigate` — move `open` → `mitigated`, stamping `mitigatedAt` once (the
  `incident show --json` field; the column is `mitigated_at`).
- `resolve` — move `mitigated` → `resolved`, stamping `resolvedAt` once (the
  `incident show --json` field; the column is `resolved_at`).
- `review` — the close: move `resolved` → `reviewed` with the four-part review
  and the follow-up, geoyws only (below). There is no separate `close` verb.
- `note` (timeline add) — append one `time`/`actor`/`text` entry; history is
  never rewritten.
- `link` / `unlink` — attach or detach task, attention, deployment, sitrep, or
  host targets; a removal is itself recorded on the timeline.
- `evidence` (update) — record the evidence pointer verbatim; it is stored,
  never fetched or expanded, so keep secrets out of every incident field.
- `list` — read incidents, optionally filtered by status and severity.
- `show` — read one incident: identity, severity, status, timestamps, timeline
  in append order, links, evidence pointer as given, and — once closed — the
  review and the follow-up.

**The reviewed close belongs to the owner.** Only `--as geoyws` with
`--attest-reviewed` moves a row to `reviewed`, carrying the four-part review
(cause, impact, what worked, what did not) and either a follow-up task on the
same board or a recorded reason for none (decision `a-26347425`). Lane agents
author the review text and file or propose the follow-up through `note` and
ordinary task creation; geoyws alone effects the transition. The byte-exact
refusal sentences live in the kanban spec (`docs/specs/incident.md`,
`INCIDENT-09`/`INCIDENT-10`/`INCIDENT-15`) — cite that file and pass any
refusal on verbatim rather than paraphrasing it.

`incident list` and `incident show` are read-only: their generated MCP tools
carry `readOnlyHint` true (ADR-010), like every read. The lane's open incidents
additionally surface on the `/kb-att` digest, `SEV1` first, then oldest first.
An unknown or unreadable `i-` id answers `denied or not found` without
distinguishing unknown from unreadable.

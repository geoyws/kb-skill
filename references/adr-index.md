# ADR index

Read when: you need the reasoning behind a ledger rule.

## Reference

`docs/adr/` in the kanban repo carries the reasoning. Most load-bearing:
ADR-008 (fail closed), ADR-010 (adapters generated from the surface),
ADR-011 (MCP server + in-place reload), ADR-012 (session handoffs and
attention), ADR-013 (plans are epics), ADR-015 (tags are a master file),
ADR-016 (historical retired web view), ADR-017 (sitreps), ADR-018 (the original board-local
rules). ADR-027 supersedes the scoped rule decisions with one registry-owned,
tag-scoped rules document using `ALL`, `ONLY:<board>`, `EXCEPT:<board>` and
namespaced `<estate>/<subsystem>` tags.
ADR-021 keeps settled history while removing it from operational indexes.
ADR-037 makes a capped listing refuse a default it would exceed.
ADR-041 makes `transact` one atomic ordered write batch and leaves the
read-only `batch` untouched.
ADR-042 makes an attention item a decision card: an authored question, its
context, two to four choices with one recommendation, and a free-text answer
that still carries a verdict.

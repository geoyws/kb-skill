# Subscription records and dispatcher delivery

Read when: managing subscriptions or dispatcher delivery.

## Subscription records and dispatcher delivery

Use `kb subscription add|list|show|pause|resume` to manage one board's durable
delivery intent. The addressed board is the tenancy predicate; do not put a
board path or root in the record.

```bash
kb subscription add --project NAME --id sub-codex-queue \
  --subject task:t-12345678 --kind checkpoint_added --tag acme/orchestration \
  --consumer codex.queue --action enqueue-turn \
  --timeout-ms 30000 --max-retries 3 --rate-per-minute 60 \
  --max-concurrency 1 --secret-ref codex_queue_token --as "$OWNER" --json
kb subscription list --project NAME --json
kb subscription show sub-codex-queue --project NAME --json
kb subscription pause sub-codex-queue --project NAME --as "$OWNER" --json
kb subscription resume sub-codex-queue --project NAME --as "$OWNER" --json
```

Rules:

- IDs are immutable `sub-*` identities. There is no update or delete command.
- `--subject` accepts only `task:ID`. `--relation`, `--kind`,
  `--prior-status`, `--current-status`, and `--tag` are repeatable, normalized
  predicates; unknown values fail closed. `--relation-json` accepts the same
  board-qualified array as `watch` above; scalar `--relation` stays local,
  delivers only events on its target board, never source-board events.
  Generated MCP `subscription_add` accepts `relation-json` as a string with
  the same array shape; `watch` is long-running and has no MCP tool.
- `--consumer` and `--action` are strict names, not executable commands.
- Timeout, retries, rate, and concurrency are required and bounded.
- `--secret-ref` is an optional opaque identifier containing only ASCII
  letters, digits, dot, underscore, and hyphen. Never pass a credential or raw
  token value.
- Subscription rows contain no root, board path, shell text, adapter arguments,
  credentials, delivery acknowledgement, cursor, or dead-letter state.
- Add/pause/resume append audited board events; their payloads omit the secret
  reference. List/show are read-only request-response operations.
- Delivery identity is `(subscriptionID,eventID)`.

The first queue bridge is the Codex consumer `codex.queue` with action
`enqueue-turn`. The subscription row still stores only the normalized
predicates, the named consumer/action, and bounded policy. It does not store
an executable path, shell text, or arbitrary args. Host-local
`dispatchers.json` binds that consumer/action to the checked-in
`kanban-codex-queue-adapter`, the installed Codex executable, the exact
thread/session target, the required installed version, and the fixed host-local
Codex state directory argument `--codex-home /root/.codex` with matching
`CODEX_HOME=/root/.codex`. Every invocation must direct-exec the installed
Codex binary to verify the exact version and the `codex queue --help`
surface, and it must fail closed on drift. The adapter passes only that fixed
`CODEX_HOME` to child Codex processes. On the board home host, direct ingress is
`/root/.local/bin/codex queue --thread UUID_OR_EXACT_SESSION_NAME --message
TEXT` when `codex-cli 0.150.1` is installed. The separately named live
smoke receipt is the distinct runtime check for installed Codex support.

The optional Claude print bridge is consumer `claude.print`, action
`start-readonly-turn`, with capability `start`. Host-local `dispatchers.json`
binds those exact names to `kanban-claude-print-adapter` and fixed arguments
`--claude ABSOLUTE_PATH --home ABSOLUTE_PATH --cwd ABSOLUTE_PATH
--required-version VERSION`; keep executable, home, working-directory, and
version choices outside subscription rows and portable skill text. The
dispatcher serializes this consumer so one fresh worker owns each delivery.
The adapter starts Claude in safe-mode print operation with no tools and no
session persistence; it never resumes or drives an active TUI. Its child
environment contains exactly `HOME` and `PATH=/usr/bin:/bin`, and its configured
working directory is fixed.

Executable, home, working-directory, version/help-surface, authentication, or
response-contract drift fails closed; an invalid Claude response also fails
closed. Treat the compiled-process adapter-contract check and the separately
named installed-version live smoke as distinct evidence: the former proves
protocol and process containment, while the latter proves the pinned installed
Claude can authenticate and complete the real print turn. This bridge is
optional and ships with no active subscription
by default; an operator must deliberately add or resume a matching
subscription after both checks pass.

Run delivery through the separate compiled worker with exactly one explicit
board selector:

```bash
kanban-dispatcher --project NAME [--consumer consumer.name] [--once] [--json]
kanban-dispatcher --workspace /registered/root [--once] [--json]
kanban-dispatcher --db /exact/board.db [--once] [--json]
```

On the board home host use the fixed installed path `/root/.local/bin/kanban-dispatcher` after
the same host-boundary verification used for `$KB_EXEC`. The worker
is not a `kb-board` subcommand. `--consumer` restricts execution to one consumer
identity; `--once` performs one scheduler step; without `--once` it polls until
SIGINT/SIGTERM. Help and version do not open board or registry state.

The allow-list is the private host-local
`$KANBAN_DATA_DIR/dispatchers.json`, protocol version `1`. It maps strict
consumer/action names to a declared capability, an absolute executable, fixed
arguments, and optional secret-reference mappings from `sourceEnv` to one safe
adapter `targetEnv`. Put environment-variable names there, never credential
values. Keep the data root and config inaccessible to group/other users; the
executable must be a regular non-symlink with an execute bit and no group/other
write bit. The adapter starts with an empty environment and receives only the
configured target secret and fixed `CODEX_HOME` when the subscription names
that reference.

Startup validates configuration before the first materialization or claim. Each
scheduler step materializes and recovers work, resolves the candidate, then
serializes per consumer, reloads configuration under the lock, and claims for
`timeoutMs + 30 seconds`. It runs the adapter outside SQLite and finalizes only
the exact lease token. Failures retry deterministically then dead-letter;
pause/resume is rechecked before claim. A crash after adapter success but before
acknowledgement is retried after lease expiry, so adapters must treat
`(subscriptionID,eventID)` as an idempotency key: delivery is at-least-once,
never exactly-once.

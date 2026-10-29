# As an MCP server

Read when: using `kb mcp`.

## As an MCP server

```bash
kb mcp     # newline-delimited JSON-RPC over stdio
```

One tool per operation, generated from the command surface, so the tool list
cannot describe something the CLI does not have. Each call runs the real binary,
so validation and refusals are identical to the terminal. Every tool carries
`readOnlyHint`, true only when the operation writes nothing anywhere.

Two tools carry lists of other calls instead of arguments of their own.
`batch` collapses up to 32 **reads** into one request and keeps
`readOnlyHint: true`, so it refuses a writing entry by name and performs none
of them. `transact` is the writing counterpart described above: `{ "items":
[ {"name", "arguments"} ] }`, `readOnlyHint: false`, the binary run **once**
with the whole list, and the envelope returned as the result — marked
`isError` exactly when `ok` is `false`, because a rolled-back batch that read
as success would be a lie.

Updating is `install` over the binary — running servers pick it up without any
client reconnecting.

### From another machine: one persistent SSH channel

The board home host boundary applies to the MCP server exactly as it does to
the CLI, so the server runs *there* and the harness talks to it over stdio
through SSH. That gives an interactive harness a connection it holds for the
whole session instead of one handshake per read:

```bash
ssh "$BOARD_SSH_TARGET" "$KB_EXEC" mcp     # the whole server command
```

Register that command as a stdio MCP server in the harness. For Claude Code,
run `claude mcp add --scope user --transport stdio kb -- ssh "$BOARD_SSH_TARGET" "$KB_EXEC" mcp`.
For Codex, use an `[mcp_servers.kb]` block with `command = "ssh"` and
`args = ["BOARD_SSH_TARGET", "/absolute/path/to/kb", "mcp"]`. Replace both
placeholders with the routing table values: TOML argument strings do not expand
shell variables. Measured 2026-09-05 from a Mac to the home host over a 210 ms link:
connect 578 ms once, then `task_show` 249-253 ms and a `note` write 285 ms per
call — about one round trip plus the query — against 2.5 s per CLI one-shot
without a ControlMaster. Re-measured 2026-10-13 from @@mbp to @@hal with a
ControlMaster: connect 0.65 s once, then about 0.20 s per small read on the
channel against about 0.5 s per wrapper one-shot (table under **Runs of reads
do not go one-shot**). This is the agent API; there is no HTTP service.

What does not change: every tool still takes its own `project`, because the
server resolves a board per call and refuses `--project` on `kb mcp` itself
rather than let one session silently answer about a board it was not asked
about. The same rules, the same refusals, the same `readOnlyHint` — a tool
call is the real binary on the real ledger, with the installed identity, on the
board home host. If the host is unreachable the server fails to start and the harness
says so; that is the correct outcome. Never point the registration at a local
`kb` or a local board file to make the error go away.

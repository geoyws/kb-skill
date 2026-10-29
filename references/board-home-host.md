# Board home host and command routing

Read when: routing, SSH, the hosts table, selectors, or a run of reads.

## Board home host is the execution boundary

Every board's home host is `@@hal` since the P7 ledger cutover on 2026-10-03
(`hosts.tsv`; kb infra t-93c9468e). hal's `/root/.local/bin/kb` is the
installed kanban release binary and the ledger is `/root/.local/share/kanban`
there. Historical note (2026-10-03): hax held a fenced pre-cutover copy;
it is retired, never a board target. Route every board read and write,
including acies, to @@hal through `kb-board` (or `kb-host hal` for registry
commands). An unreachable @@hal blocks ledger operations; never fall back.

The consumer table is `board<TAB>home_host<TAB>ssh_target<TAB>expected_remote<TAB>kb_exec[<TAB>login]`.
Login is `ssh` (the five-field default, unchanged even with `KB_SSH_LOGIN`)
or `own`. For `own`, `kb-board` and `kb-group` select a nonempty
`KB_SSH_LOGIN` with `ssh -l LOGIN -- TARGET`, otherwise query `ssh -G TARGET`.
Root or an absent SSH user is refused before command transport; local effective
UID 0 is refused before the binary. Invalid policies and `own` executables
under `/root/` refuse at table load (exit 64). Group members must share the
registry route's normalized login policy as well as its other route fields.
No wrapper principal claim is forwarded: the remote kernel UID is the identity.
`kb-host` only consumes the extended table; its registry-only authority and
transport are unchanged. `kb-board` refuses `broker` pretransport. This format
support does not authorize account provisioning, installation or enforcement activation.

The authoritative Kanban registry and boards live on the board home host chosen
by the consumer table. `$KB_EXEC` below is the absolute installed `kb` path from that table; `$BOARD_HOME_HOST`, `$BOARD_SSH_TARGET`, and the selected remote hostname likewise come from the consumer's own table — substitute the consumer's values, never another estate's. Before any `/kb` read or write, check the current host
**before attempting SSH**:

```bash
hostname                   # if this prints exactly the selected board home host, stay here
test "$(command -v kb)" = "$KB_EXEC"
"$KB_EXEC" v
```

If `hostname` prints anything other than the selected board home host, enter
the routed SSH target and verify the remote boundary there:

```bash
ssh "$BOARD_SSH_TARGET"
hostname                   # must now print exactly the selected remote hostname
test "$(command -v kb)" = "$KB_EXEC"
"$KB_EXEC" v
```

An SSH one-shot does **not** load the interactive `PATH`, so it can report
`kb: command not found` even though the binary is installed. Do not rediscover
or re-quote this on every call. From outside the board home host, use the
bundled argv-preserving wrapper for one-shot commands:

```bash
<skill-dir>/scripts/kb-host BOARD_HOME_HOST r ls --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST v
<skill-dir>/scripts/kb-host BOARD_HOME_HOST audit verify --json
```

The wrapper verifies that the routed remote host matches the expected
hostname, invokes the fixed installed path `$KB_EXEC` from the routing table, and
preserves spaces and shell metacharacters as literal arguments. In an
interactive SSH shell, use the same exact fail-closed check and invocation as
above; any other `kb` resolution is a stale or shadowed PATH. Use an
interactive SSH session for a related series of commands or prose-heavy
mutations; use the wrapper for deterministic one-shots. Never fall back to a
local `kb` after either path fails.

Every `kb …` example below is a command to run **inside the verified board
home host shell**. Keep one SSH session open for related operations to save
connection overhead and tokens. Never run `ssh "$BOARD_SSH_TARGET"` from a
shell whose exact `hostname` already matches the selected board home host; that
shell is already at the required boundary.

From another machine, never invoke a local `kb` or read a local Kanban SQLite
file as a fallback. If SSH or the installed binary is unavailable, stop and report that boundary as blocked; do not run `kb init`, create a replacement board, or let local state diverge.

Outside the board home host, do not call `kb` directly.

- Use `skills/kb/scripts/kb-board PROJECT KB_COMMAND [ARGS...]` for every
  board-owned one-shot command. It injects exactly one board selector (the
  project, or for `--session-board` reads the file instead), rejects
  caller-supplied `--project` / `--workspace` / `--db` selectors, and refuses
  `r` / `rule` and the policy-registry `access`, `worker`, `link`, `scope`,
  `contrib`, `model` and `plugin` verbs so registry operations cannot be routed through a
  board helper. `board`, `sprint`, `batch`, `incident`, `worktree`, `message`,
  `milestone`, `cleanup`, `overlap`, `trunk`, `test` and `stats` are board-owned
  and route here; `kb-host` refuses each of them with this remedy.
  On `checkpoint`, `handoff create` and `sitrep post` it also forwards your
  checkout as `--repo` / `--branch` / `--head` / `--dirty`, because the binary
  would otherwise capture the board host's cwd, and adds `--git-captured` when
  it filled all four itself (see Provenance).
- Use `skills/kb/scripts/kb-host BOARD_HOME_HOST KB_COMMAND [ARGS...]` for raw
  registry-owned or non-board operations only. It resolves the host identity
  from the consumer table, verifies the routed SSH target and remote hostname,
  and preserves argv literally. Registry `rule`, `access`, `worker`, `link`,
  `scope`, `contrib`, `model` and `plugin` verbs stay on the raw registry routing path
  rather than `kb-board`.

```bash
<skill-dir>/scripts/kb-board BOARD_ID t ls --status todo --json
<skill-dir>/scripts/kb-host BOARD_HOME_HOST r ls --json
```

**Runs of reads do not go one-shot.** Every wrapper call is its own SSH exec on
the board home host, so three or more related reads — a resume (`ctx`, `r ls`,
`dash`), a queue measurement, a row and its ancestors — take one of two shapes
instead:

1. **The persistent MCP channel, when the harness has it registered** (`ssh
   "$BOARD_SSH_TARGET" "$KB_EXEC" mcp`, **As an MCP server**). One connection
   for the session; each read is then about one round trip plus the query, and
   registry reads (`rule_list`, `dashboard`) ride the same channel as board
   reads.
2. **Otherwise one `batch`**: `kb-board BOARD_ID batch --items-file /dev/stdin
   --json < read.json`, up to 32 board reads in one exec (**Working a task**).
   `rule_list` may sit in it. `dashboard` may not — it reads boards outside the
   batch and is refused with `names dashboard, which reads boards outside the
   batch: run it alone; nothing in it ran` — so it stays its own `kb-host` call.

Writes keep their shape: a single write is one wrapper call, and a unit's two
boundaries are one `transact` each. Measured 2026-10-13 ~07:30 MYT from @@mbp
to @@hal (kanban 0.3.1, SSH `ControlMaster auto`, `ControlPersist 600`, median of
five runs; kanban `t-bbe8d7cc`):

| path | one read | resume: `ctx` + `r ls` + `dash` |
|---|---|---|
| one-shot wrappers (`kb-board ctx`, `kb-host r ls`, `kb-host dash`) | `ctx` 0.52 s, `r ls` 0.50 s, `dash` 1.3–1.9 s | 2.31 s |
| one `kb-board batch` (`context` + `rule_list`), then `kb-host dash` | 0.70 s for both reads | 2.23 s |
| persistent MCP channel, three `tools/call` | `context` 0.20 s, `rule_list` 0.19–0.23 s, `dashboard` 1.17–1.25 s | 1.63 s, after a 0.65 s connect once |

The dashboard's own server time dominates a resume, so the gain there is
modest; the gain grows with the run: N small reads cost about 0.5 N s as
one-shots, about 0.2 N s on the channel, and about 0.7 s flat in one batch.

Inside the verified board home host shell, every board-owned command must use
an explicit project selector. Registry rule commands must not receive board
selectors. Use `--workspace PATH` only with a path verified to exist and be
registered by the consumer table. For one-shot automation, shell-quote the
entire remote command and every dynamic value safely; an interactive SSH
session is preferred for prose mutations so titles and bodies cannot be split
or expanded by an intermediate shell.

Selector rule: board-owned commands such as `task`, `tag`, `search`, `claim`,
and `attention` should normally use `--project NAME` remotely. Registry-owned
`rule` commands must not receive `--project`, `--workspace`, or `--db`; rules
live once in the registry and select boards through `ALL`, `ONLY:<board>`, and
`EXCEPT:<board>` tags. Registry watch helpers also reject board selectors and
`--all`. In particular, use `kb-host BOARD_HOME_HOST r ls --board kanban --json`
(the rule verb's own board scope), never `kb-host BOARD_HOME_HOST r ls --project kanban`.

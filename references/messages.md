# Messages

Read when: sending or reading a lane message (`m-` row).

## Messages — addressed lane correspondence, never a handoff

A message is one addressed row (`m-` id) from a lane actor to a named
recipient: a question, request, report, or blocker the recipient pulls from
its inbox. The row lives on the sender's board and nowhere else — queues,
wakes, and notices are views over it, never second stores. Messages never
carry leases and never move claims: no claim, lease, handoff-create, or
handoff-accept verb takes an `m-` id, and a handoff still carries the work,
the lease, and the tree facts. A message reply is correspondence, never an
owner verdict: attention stays the owner's channel, and pointing an
attention resolve path at an `m-` id is refused.

Board-owned: route every verb below through `kb-board BOARD`. The same
surface is generated as MCP tools (`message_send`, `message_inbox`,
`message_show`, `message_ack`, `message_answer`, `message_close`) under the
same actor, authz, and refusal rules. `message cat` reads as `message show`.

- Send: `kb message send --to NAME --kind question|request|report|blocker --as ACTOR --body TEXT [--task ID] [--in-reply-to m-ID] [--id m-ID] --json`. The recipient is a lane, the lead, or a registered role; anything else is refused naming the fix. The kind is written once and never edited. The body is bounded text (16 KiB); there is no edit verb, so a correction is a reply. `--task` links one task on the sender board. A reply is its own `m-` row carrying the original's id, addressed to the original's sender, landing in that sender's inbox.
- Pull: `kb message inbox --as ACTOR [--unanswered N] [--limit N] --json`. An array of `{id, from, kind, status, headline, board}` rows, open first, gathered across every board the caller may read — never the body. `board` names the project that holds the row: every later verb on that row (`show`, `ack`, `answer`, `close`) must run against that board (`kb-board <board> …`); the same verb on another board is refused as denied or not found. The headline is the body's first line truncated to 160 characters, so fetch bodies per id. `--unanswered N` keeps only rows still unanswered after N minutes.
- Read one: `kb message show m-ID --as ACTOR --json`. Inbox rows and the mail notice never carry a body; every single-row receipt does — `send`, `show`, `ack`, `answer` and `close` all print the whole row, body included, so treat those receipts as message content, never as headline-only logs.
- Move it: `kb message ack m-ID --as ACTOR --json` takes `open` to `acked`, recipient only; `kb message answer m-ID --as ACTOR --body TEXT --json` takes `acked` to `answered`, recipient only, the only move that takes `--body`; `kb message close m-ID --as ACTOR --json` takes `open`, `acked`, or `answered` to `closed`, sender or recipient. Any other move is refused quoting the id and both statuses, and the row keeps its status. Unread means not-yet-acked: every carrier below repeats a message until its recipient acks it.

Two views ride along with calls that know their caller (`--as`, else
`KANBAN_ACTOR`; a call with no identity carries neither):

- The unread-mail notice: object outputs gain a top-level
  `mail: {unread: [{id, from, kind, headline}, …], remaining: N}` — at most
  five entries, never bodies. Array listings pass through byte-identical, failures carry
  no notice, and a lookup that fails leaves no notice rather than failing
  the call. `watch --follow` heartbeat frames do not carry it yet (spec
  OB-15 is still planned), so a lane that only holds a watch stream must
  pull `message inbox` itself.
- The wake: an idle lane may be woken with a pointer — the `m-` id only,
  never the body, the headline, the kind, or any metadata beyond routing.
  A wake that reaches a pane follows the pane-agent discipline:
  capture-before-send, idle panes only unless the owner says otherwise in
  the thread or on the board. Content arrives only when the woken lane
  pulls its inbox under its own read authority; a denied row stays denied
  and wakes nothing.

# Attention

Read when: raising, answering or resolving an attention item.

## Attention — anything that needs the owner

**Raise it the moment you find it, every time.** A reply, a report and a commit
message are channels that scroll away: an item raised at 03:00 and never acted
on leaves no trace it was ever raised, so the same question gets asked again
three sessions later — or worse, quietly answered by an agent that had no
business deciding it.

**Raising an item is writing a decision card.** A card is a question, the
context needed to answer it, and two to four authored choices, exactly one of
them marked as your recommendation. The old convention — write the options into
the body as prose and let the owner reconstruct them — is over: options in
prose have to be parsed back out of English by whoever reads them, and the
free-text answer they get back carries no verdict a lane can branch on. Author
the choices as flags and the answer comes back machine-readable. The body is
untouched by all of this and stays the long form — receipts, SHA256s, absolute
paths and the `RESOLVE-WHEN` line — read through `/kb-att`, which re-measures
current state before asking George (ADR-042).

```bash
kb att raise "<verdict-first body — receipts, paths, the concrete next action>" \
  --as "<your callsign>" --lane <lane> --kind blocking --task <ID if it is about one> \
  --question "<the decision, one sentence, ending in ?>" \
  --context "<what is true now, what is blocked, what waiting costs>" \
  --choice "<key>=<verb-phrase label>|approve" \
  --consequence "<key>=<what happens if it is picked, and what it costs>" \
  --choice "<key>=<verb-phrase label>|reject" \
  --consequence "<key>=<what happens if it is picked, and what it costs>" \
  --recommend <key> \
  --check "<the fact this decision turns on, as one question ending in ?>" \
  --check-choice "<key>=<plain statement>" \
  --check-choice "<key>=<plain statement>" \
  --check-answer <key> \
  --check-explain "<why the answer is true, and what changes under the others>" \
  --check-about <subject> --json
```

| flag | what goes in it |
|---|---|
| `--question` | One sentence, present tense, ending in `?`, at most 160 characters, in his terms. It names the thing being decided, never the row: "Will you unlock the hal recovery key, defer the drill, or cancel it?", not "please decide on a-347ff24c". A question only one choice answers is an approval request wearing a question mark. |
| `--context` | Two to five plain sentences, at most 800 characters, in this order: what is true now, what is blocked and how much waits on it, what waiting costs. If waiting costs nothing, say so — that is a legitimate answer and it changes the decision. |
| `--choice KEY=LABEL\|OUTCOME` | Two to four, repeatable, one token so the three parts cannot arrive mismatched. The key is a slug `[a-z0-9][a-z0-9-]{0,31}`, unique within the item, and never shown to him. The label is the button text: a verb phrase starting with the verb, at most 60 characters, carrying no `|`. The outcome is one of `approve`, `reject`, `defer`, `other` — the machine-readable verdict a lane acts on, where the label is for the human. |
| `--consequence KEY=TEXT` | One per choice, required on every one: a single sentence, at most 200 characters, saying what happens and what it costs, in that order. "Approved" is not a consequence; "the receipt is retried the same day, about ten minutes of your time plus the seat's monthly cost" is. |
| `--recommend KEY` | Exactly one choice, and always one. It is your opinion. An agent that cannot pick one has not finished thinking about the question and should raise a smaller one. |

`--question` and `--context` are one card: give both or neither.

**Write about the world, not about the board.** "The lane", "the row", "the
executor", "the driver", "the item" and every other word for the machinery are
banned from the question and the context — he is deciding about the world, not
about the ledger. Typed ids (`a-*`, `t-*`, `e-*`, `d-*`) belong in a trailing
`References:` clause and never mid-sentence. Required instead: numbers with
units (`ten minutes`, `43 items`, `HTTP 401`), absolute dates (`2026-09-05`,
never "last week"), full nouns wherever a pronoun could drift, and second
person for anything only he can do — "only you can unlock the recovery key".

A `defer` consequence must name **what brings the question back**: a date, an
event, or a task that will be filed. "Later" with no trigger is how an item is
deferred into oblivion. And never put a credential value in a card; name the
store entry.

**Do not invent choices.** If the honest answer set really is "do it / do not
do it", author none — pass `--question` and `--context` alone and let the
default pair below serve. Two choices that are approve and reject wearing new
labels are worse than the pair nobody claimed to have authored.

**The free-text answer is always offered, and it carries a verdict.** `custom`
is reserved for it: it is never one of your choices (`--choice custom=…` is
refused) and it never has to be declared. Taking it costs him both an
`--outcome` and a `--note`, which is the whole point — nothing closes an
attention item without a verdict, so no lane inherits `Comment: do it after the
pin lands` and has to guess whether that was a yes.

**Every carded row carries an Active Comprehension Check (ACC) on its card**
(George, 2026-09-17: "I find myself not understanding the codebase
enough"). You are the one with the file open, so you write the check; a
walkthrough clerk never drafts one (George, 2026-09-19 — a clerk can only
quiz the row's own diagnosis, which "isn't helping my understanding of the
codebase but asking me to diagnose issues"; a row with no `check` field gets
its card with no check). Author it as flags, all or none — never as prose in
the body, where `/kb-att` would reveal the answer before asking the check:

| flag | what goes in it |
|---|---|
| `--check` | One question, present tense, ending in `?`: the fact this decision turns on, in his terms. |
| `--check-choice KEY=LABEL` | Two to four, repeatable, one token so key and label cannot arrive mismatched. The key is a slug `[a-z0-9][a-z0-9-]{0,31}`, unique within the check, and never shown to him; the label is a plain statement, at most 60 characters, carrying no `\|`. |
| `--check-answer KEY` | Exactly one, naming a declared choice key. It is the fact, not your opinion. |
| `--check-explain TEXT` | At most 400 characters, two sentences: why the answer is true, naming the component, file, host or tier; what changes if he believed the others. |
| `--check-about SUBJECT` | The durable subject this teaches: a file path (with `/` or an extension), an `@@host` or `@_tier` sigil, an `UPPER_SNAKE` setting, or a `--flag`. |

Two to four `--check-choice` entries, exactly one `--check-answer` naming a
declared key, `--check-explain` under 400 characters. Ask about **how the system works** — which component owns the
behaviour and where it lives, which host or tier a thing runs on and why, what
a flag or default controls — a fact he could reuse on the next row. Never ask
about the row: not what you measured today, not what your sweep proved, not
what the leaked thing signs. Test: if the answer is only knowable by having
read this row, it is your diagnosis read back as a quiz — drop it. The answer
is a fact you verified in the code or on the host, cited in the body's
receipts, not your opinion; the recommendation is what the card's
`--recommend` is for.

**George's bar, 2026-09-24 ("ACC is asking stupid questions"; "how would I
know what 00164 is? don't expect me to know!"):** a check is asked of someone
who has NOT read the ADR, the Acies card, the gap register or this row. So:

- Never name a document by number or id in the question (`ADR-GLOBAL-00164`,
  `D-05`, `HR-GAP-06`, `PAY-GAP-07`, `business.md:4329`). If the question needs
  the reference to make sense, it is about the document, not the system.
- Never ask what a proposal, card or register *says* ("Under the acies-hr
  card, where does X live?", "Does this ADR set the numbers itself?"). Those are
  reading-comprehension questions about text he has not read. Ask instead
  what the running system does today, in the code or on the host, which he
  can reason about from how the product works.
- The subject is Unum or Acies as George uses it: a behaviour he can see, a
  place data lives, a host or tier, a flag. Good: "Who fills in an employee's
  gross, deductions and net pay in Unum HR today?" (`a-user`/`the-system`).
  Bad: "What happens if acies-hr tries to lock payroll inputs with no provider
  adapter?" — that is the card's rule, invisible until you read the card.
- Both wrong answers must be plausible to someone who knows the product; a
  question whose wrong option is absurd teaches nothing.
- If no such question exists for the decision, raise the card **with no
  check**. A missing check is reported as debt; a document-trivia check is a
  defect the clerk skips at read time and names in the report.

A clerk walking cards (`/kb-att`, `/kb-acc`) applies the same test at read
time: a check that names a document id or asks what a card says is not asked,
the card goes up without it, and the row is counted under "trivia checks
skipped" in the report.
Only the raiser may author or update the check (`t-1227a592`: an update carrying any
`--check*` flag from another actor is refused naming the raiser, and `geoyws` gets no
exception), and once an answer is recorded
the definition is closed to edits. Every pre-answer read carries the check
redacted — question, choices and about, never the answer or the explanation —
whether the row is open or resolved; only the raise receipt echoes the full
definition.
The `ACC:` body block this replaces is retired: never write one, and never
parse one back out.

**The check is asked by `/kb-acc`, not `/kb-att`** (George, 2026-09-24: "when
i'm in a hurry to clear atts i don't want to do accs"). A resolve no longer
needs it: `att resolve` on a row whose check is unanswered succeeds and leaves
the check pending — still redacted, still answerable (kanban t-1aa9f553).
`/kb-acc` later asks it blind and records the key he picked on its own:

```bash
kb att check <id> --as geoyws --key <key> --json   # geoyws or the raiser; open or resolved row
```

It goes through the same answer law as the `/kb-att` check: a check is answered
exactly once, on an open or a resolved row, and a second answer is refused;
the row's status does not change, and `att reopen` clears the result. The
`--json` receipt is the row in its post-answer projection, whose `check` now
carries `answer` (the right key), `explanation`, `answered` (the key he
picked), `correct` and `answeredAt` beside `question`, `choices` and `about`.
Without `--json` it prints three lines: `ACC: pass` or `ACC: miss on <key>`,
then `answer: <key> — <label>`, then `why: <explanation>`. A pending check reads as
`.check != null and .check.answered == null`.

```bash
kb att list --status open --limit 200 --json              # what is waiting on the owner
kb att list --status open --fields id,priority,question,choices --limit 200 --json   # the cards, without the bodies
kb att list --status open --lane driver-2 --limit 200 --json   # stored lane, raiser suffix, or task lane
kb att list --status resolved --fields id,decision,resolution --limit 200 --json     # what he decided, and how

kb att resolve <id> --as geoyws --choice keep-parked --json                        # an authored choice
kb att resolve <id> --as geoyws --choice custom --outcome defer --note "…" --json  # the free-text answer
kb att check <id> --as geoyws --key sign-server --json                            # answer the row's comprehension check
```

`--choice` is required on `resolve`. `--note` is optional for an authored
choice, because the label and its consequence are already the record, and
required for `custom`; `--outcome` applies to `custom` alone. `/kb-att`
re-measures the current card before asking George; a lane reading `decision.note`
beside an authored `choice` reads what he added to the verdict and should
act on it before the consequence text. A `--choice` naming a key the row no
longer carries is refused naming its current keys, not silently mapped onto
the old card's position.

**`decision` is what a lane reads back**, not the prose:
`{"choice": "keep-parked", "outcome": "defer", "note": null, "by": "geoyws",
"at": 1788805112431}`. Branch on `outcome`, quote the `choice` when you report,
and treat `resolution` as derived — the writer composes it as
`Decision: <label>. <consequence>`, plus a second `Note: <note>` line when a
note was given, so no caller can leave a different trail. `Comment: ` is the
pre-2026-09-08 spelling and now appears only on rows settled before then. Every
choice settles the item, `defer` included: a deferral is a verdict, and
`kb att reopen` is the way back.

**An item with no card reads as the default pair.** A row that authored no
choices is served — CLI, MCP and `/kb-att` alike — as `approve` ("Approve - proceed")
and `reject` ("Reject - do not proceed") with **no recommendation**, because
nobody authored that pair and nothing may claim it was recommended, and its
body serves as both question and context. That is the only shape in the model
with zero recommendations. `kb att update <id> --as "<your callsign>"` takes the
same five card flags, so an item still open can be given a card later, and
`--clear-card` returns it to the default pair. A resolved item's card is
history and is refused.

**A card, written out (illustrative, not a live incident).** Suppose the
ledger backup restore drill on hal needs George to unlock the recovery key.
The row records the receipt path and its resolve condition; the card gives
three actual decisions with a trigger on deferral:

```bash
kb att raise "BLOCKED — The hal ledger backup at /root/.local/share/kanban cannot complete a restore drill until George unlocks the recovery key in the approved vault. Resolve only after a restore on hal is verified; do not copy the ledger to another host." \
  --as "@:geoyws/infra/driver/executor" --lane driver --kind blocking --priority 0 --task t-12345678 --tag geoyws/infra \
  --question "Will you unlock the recovery key for the hal ledger restore drill, defer it until the next maintenance window, or cancel the drill?" \
  --context "The backup is present on hal, but the recovery key is locked and the restore drill cannot proceed. Only you can unlock it; one backup verification is waiting. Deferral delays proof of recovery, but no board reads or writes depend on the drill. References: t-12345678." \
  --choice "unlock-key=Unlock the recovery key for the restore drill|approve" \
  --consequence "unlock-key=You unlock the key in the approved vault; the restore drill runs on hal and takes about ten minutes of your time." \
  --choice "defer-window=Defer the drill to the next maintenance window|defer" \
  --consequence "defer-window=Recovery remains unverified until the next maintenance window, when a task re-raises this decision." \
  --choice "cancel-drill=Cancel this restore drill|reject" \
  --consequence "cancel-drill=The restore drill is cancelled and recovery remains unverified; the task closes without a restore receipt." \
  --recommend unlock-key --json
```

The question is in the operator's terms, the context names what waits, each
choice has a consequence, and exactly one is recommended. `defer-window`
settles this decision as `defer`; the next maintenance window explicitly
triggers the new task instead of leaving a parked row with no return path.

**An explicit `--limit` that cuts is named, not hidden.** `kb ev --limit N`
keeps stdout at exactly N rows and writes one line to stderr - `events: showing
N of more than N; pass --limit above N for the rest (ceiling 1000000)` - so a
page of history that stops at the limit never reads as the whole history.
Exit status stays 0; the rows you asked for are the rows you get.

**Say how many you want.** Without `--limit` the listing is capped at 100, and
a board holding more than that **refuses** rather than handing back a page that
reads as the whole; the refusal names `--limit N`. On a busy board
`kb att list` with no `--limit` fails, and that is the right answer — pass a
bound above the count you expect and check the length came back under it
(ADR-037).

`--lane LANE` on raise stores its routing lane. On list, `--lane LANE` keeps rows
whose stored lane is `LANE`, whose raiser is a legacy `…@LANE` actor or a typed
callsign of any length whose third segment is `LANE` (seats and deeper segments
included; kb kanban `t-2b8ab9f7`), or whose linked task has lane `LANE`.
`--fields k,k,…` keeps only those keys on each row; a key the rows do not carry
is refused naming the ones they do. `--no-body` drops the body alone, which is
the cheap way to read cards in bulk.

`--kind` is a closed set:

| kind | use for |
|---|---|
| `blocking` | work cannot resume until he calls it |
| `decision` | a design or scope call that is his |
| `approval` | production-tier action, `master`/`main` or production-ref push (`prod`, `production`, `*-prod`, `*-production`), destructive op, scope expansion, spend |
| `review` | a deployed tier waiting on his eyes — put the URL in the text |
| `risk` | failed gate, flaky tier, expired credential, half-written file |

There is deliberately no `info`: something that needs nobody is a note, and
`kb n` already holds those.

**Raise, do not resolve.** Agents raise and read; only the owner resolves. The
owner's actor is `geoyws` in the current binary (written `$OWNER` in examples):
the binary gates `resolve` and `reopen` on that identity; it is not configurable. The
refusal names it. `geo` is the pre-2026-09-05 spelling — rows settled then keep
`resolvedBy: geo` as a record, and `--as geo` today is refused like any other
non-raiser. The one exception is an item this same session raised and has since
made moot — retire that with `--choice custom --outcome other --note` saying
why, so the record shows it was withdrawn rather than answered. Check
`kb att list --status open --limit N` before raising and add to an existing item
rather than duplicating one already waiting.

Items are **resolved, never deleted**, and resolving twice is refused: that
would overwrite who settled it and when, which is the part worth keeping. Open
items list **oldest first** — an unanswered question does not get less urgent by
being ignored.

A reference that arrives **after** an item is resolved — an external issue key,
a receipt, a later commit — is not written onto the card, and `att resolve` on
a resolved item is refused rather than reopened for it. Record it as a note on
the task the item was raised for (or on the task the receipt belongs to),
citing the item by id: `kb note <task-id> "PAI-246 is the verified receipt for
a-9ae089d1" --as "$AGENT" --kind evidence --json`. The note is searchable by
the id, the card keeps its decision, actor and timestamps untouched, and
`kb att list --status resolved` still reads as what was decided when. There is
no annotation verb on resolved attention, on purpose (decided by George,
2026-09-14).

Still surface the item in your reply as well. The board makes it survive; the
reply makes the owner see it now. In one and not the other is a bug.

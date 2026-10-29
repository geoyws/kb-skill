# Reading

Read when: doing context, dashboard, events, doctor or review-visibility reads.

## Reading

```bash
kb ctx <id> --json              # the bounded cold-start packet for a resuming agent
kb dash --json                  # per-board counts, incl. openAttention + pendingHandoffs
kb ev --task <id> --json        # the durable audit trail
kb ev --task <id> --after START_MS --before END_MS --json
kb ev --task <id> --all --after START_MS --before END_MS --json
kb ev --registry --json         # registry rules and workspace lifecycle
kb stale --json                 # work that overran its stale budget
kb doctor --json                # integrity plus advisory unreachable-root hints
kb audit verify --json          # all hash chains, including archived history
kb archive --older-than-days 90 --as system@archive --json
kb w repoint --json             # after moving a repo: point its registered roots at it
```

`ev` is machine-written and append-only — `task_created`, `task_moved`,
`lease_seized`, `handoff_created`, `attention_raised`, `attention_resolved` and
so on. It records **what happened**; `att` records **what needs the owner**. Use
`ev` to reconstruct history, `att` to find open questions.

`ev` time windows are board-only and half-open in milliseconds:
`[after,before)`. SQL filters are applied before `--limit`, `--all` includes
archived history, and registry/rule scopes reject `--after` and `--before`.

`ctx` is bounded and says so: `truncated` is computed, never assumed, and the
marker survives the truncation it describes.

`doctor.unreachableRoots` is advisory discovery maintenance. Non-empty root
hints do not make `healthy` false; missing board files, failed integrity/audit,
schema defects, orphaned rows, future-dated tasks, and search-index drift still
do. Repoint or retire a hint when useful, but never treat a disposable checkout
as the board's identity.

`--limit` must be zero or more. A negative one reads as *no limit* in SQL, so it
is refused rather than silently handing back everything you asked to bound.

**A capped listing refuses a default it would exceed** (ADR-037). Without
`--limit`, `ev` returns up to 50, `sr ls` 20, `search` 10, `att ls`,
`h ls`, `deploy list`, `sprint list` and `claim --candidates` 100, and
`t cat` 100 notes, 20 checkpoints and 100 handoffs. When more rows exist than
command fails and names `--limit N` instead of passing the first page off as
the whole; a board holding exactly the default lists all of it. An explicit
`--limit N` is honoured as-is with no marker — ask for one more than you need
if you want to know whether your own bound was hit.

### Review visibility — original evidence, not a second review (DG-28..DG-30)

`doctor` and `dashboard` (`dash`) expose read-only review diagnostics on each
authorized board/project in existing single-board, estate and group results.
These are diagnostic fields, not new CLI verbs or aliases. Preserve existing
board ordering, archive defaults, gate-off behavior, health and exit status.
Only visible, nonarchived task-type rows in `review` are candidates; stories,
epics and other statuses are not. Authorization precedes note parsing and
projection: denied tasks expose no IDs, notes, ages or counts, and denied or
omitted boards retain the existing omission/refusal rules.

- `unreviewedReviewTasks` retains its existing membership: candidates without
  an attested pass covering the current head. A launch or free-text verdict
  note is not a pass and cannot open the done gate.
- `originalReviewLaunchMissingTasks` is the subset of `unreviewedReviewTasks`
  without valid original-launch evidence matching the current head: no current
  attested pass **and** no matching launch. An existing current-head attested
  pass excludes the task from both lists, even without a launch note; its
  original verdict is sufficient. Missing both appears in both lists; a matching
  launch without a pass appears only in `unreviewedReviewTasks`. Any matching
  launch suffices; no launch proves a verdict.
- Each readable board/project carries integer `reviewObservedAt`, captured once
  per command result and shared across all boards. Both arrays retain `taskID`,
  nullable/string `headSha`, integer `createdAt`, and ascending numeric
  `freeTextVerdictNoteSeqs` (active notes only); they add integer `taskAgeMs` and
  array `originalReviewLaunches`. Empty lists are arrays, not absent fields.
- Both arrays sort by task `createdAt` ascending, then typed task ID, regardless
  of priority, review-entry, note or launch time. All timestamps are epoch
  milliseconds; `taskAgeMs` is the nonnegative saturating whole-millisecond
  difference `max(0, reviewObservedAt - createdAt)`. Label it **task age**, never
  time in review. Repeated reads may change age, not creation ordering.

**Original-launch evidence uses the ordinary existing `evidence` note kind.**
Its complete body, apart from JSON whitespace, must be exactly one JSON object:

```json
{"reviewLaunchVersion":1,"reviewer":"lane-r","launchRef":"agent-17","headSha":"1111111111111111111111111111111111111111"}
```

The four keys are required and unique, with no extra keys.
`reviewLaunchVersion` must be the JSON integer `1`; `reviewer` and `launchRef`
must be strings containing a non-whitespace character, with `launchRef`
identifying the original launched reviewer. `headSha` must be a string of
exactly 40 ASCII hexadecimal characters. No type coercion is permitted.
Duplicate, extra or missing keys, unknown versions, blank strings, malformed
JSON, surrounding prose and Markdown fences are invalid records: ignored for
launch matching, not failures of the diagnostic read. This payload creates no
new note kind, schema or write verb, and is not an instruction to launch a
reviewer or invent evidence.

`originalReviewLaunches` includes every valid active **and archived** evidence
record on the authorized candidate, sorted by numeric note sequence. Each
record is `{noteSeq, noteArchived, reviewer, launchRef, headSha, matchesCurrentHead}`:
integer sequence, boolean archive flag, the three payload strings, and boolean
match flag. Retain historical records, including duplicate launches and stale
heads; expose provenance, not note bodies or unrelated evidence. A launch
matches only when the existing current head is full-length and equals its
`headSha` byte-for-byte. Never expand a short head, normalize case, infer it
from prose or use a launch as the task head. Null/short heads cannot match.
Changing H1 to H2 retains H1 records as nonmatching; returning to H1 makes
them match again. Archival changes provenance only, not matching, and does
not change the active-only `freeTextVerdictNoteSeqs` contract.

**Consumer ownership and owner routing.** The existing watcher is skills-root
`kb/kb-watch`, with `scripts/kb-watch.py`; this package documents its contract
and must not grow a duplicate watcher. It is distinct from the `kb watch`
ledger subscription below. The watcher must consume the real authorized
diagnostic, show oldest-first task age and note provenance, and deduplicate a
task appearing in both arrays without losing either missing reason. Reuse the
original pinned verdict when present. Missing original launch/verdict evidence
or a current-head mismatch belongs on the existing task-owner work path for
reconciliation, **never a SECOND review**. A diagnostic read, including repeated
watcher reads, must not spawn reviewers, write verdicts, mutate the ledger,
erase historical evidence or change the done gate. Delivery requires real
compiled-binary-to-existing-watcher E2E evidence, including owner routing and
zero second-review launches/diagnostic writes; mock JSON or prose checks do
not prove that integration.

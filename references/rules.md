# Registry rules, workspace adoption and rule transfer

Read when: reading or changing registry rules, adopting a board, or moving rules.

## Tag-scoped rules — what frames work

Put short, non-secret operating constraints in the one registry-owned rules
document. A board owns work; it is a selector tag on a rule, not a rule scope.
Before project work, read that board's chaptered index. Bare `kb r ls` stays
registry-wide and is for registry work only — never the project-work read.

```bash
kb r ls --board kanban --json
# wrappers: kb-host <home> r ls --board kanban

kb r new "Universal rule." --title "Universal rule" --as "$AGENT" --json   # tags: ALL; --load defaults to lazy
kb r new --title "From a file" --body-file /tmp/non-secret-rule.md --load always --as "$AGENT" --json
kb r cat r-12345678 --json             # rule show: one lazy or long body
kb r up r-12345678 --title "Revised title" --body "Revised rule" --as "$AGENT" --json
kb r up r-12345678 --title "Named legacy" --load lazy --as "$AGENT" --json
kb rule retire r-12345678 --as "$AGENT" --json
kb r ls --all --full --json            # retired rows gain archived; --full adds bodies
kb ev --rule r-12345678 --json          # audited history

# ALL is the default; includes/exclusions are repeatable selector tags.
kb r new "Kanban only." --title "Kanban only" --board kanban --as "$AGENT" --json
kb r new "All except project-a." --title "Except project-a" --except-board project-a --as "$AGENT" --json
kb r up r-12345678 --board kanban --as "$AGENT" --json

# Namespaced subsystem tags intersect the board selector.
kb r new "Queuer only." --title "Queuer only" --tag acme/queuer --as "$AGENT" --json
kb r up r-12345678 --clear-tags --as "$AGENT" --json
```

`kb r ls --board NAME ... [--task ID] [--chapter NAME] [--all] [--full] --json`
reads the board-scoped chaptered index. A chapter is the first namespaced
subsystem tag on the rule, or `general` when there is none. Each entry is
`id`, `title`, `titleMissing`, `bytes`, `hasMore`, `load`, and `tags`.
`--all` adds retired rows with `archived` true. `--full` adds each body.

Always-tier bodies already arrive inline on claim, `kb ctx`, and handoff
packets (`rulesIndex` and `alwaysRules`). Do not re-fetch those. Fetch a page
lazily only when needed: `kb r cat ID` for a lazy or long body. Flat claim
entries keep `headline` and also carry `title`, `titleMissing`, `load`, and
`chapter`. Other commands do not repeat rules—the injection boundary is
claim/resume, which saves tokens. A stored claim deliberately does not pretend
it re-read current rules.

An untitled legacy rule projects a first-sentence fallback as `title` with
`titleMissing` true. Name that honestly. A coordinator titles it with
`kb r up ID --title T [--load always|lazy]`. `kb r new` requires `--title`;
add refuses without it. `--load` is `always` or `lazy` and defaults to lazy.
One board's always tier is at most 6144 bytes. The refusal names the board and
the bytes already applicable:
`rule cannot load always on board {board}: {used} of 6144 always-tier bytes already applicable`.

Rules live once in `registry.db` and are **audited and retire-only**. Updates
retain the previous body; retirement removes a rule from active injection
without deleting history. There is no `rm` alias. `--global` is retired and
explicitly refused; `g-*` remains valid only as a historical ID.

This is not the secret or long-form memory store. Keep credentials, secrets,
long explanations and cross-machine knowledge in the versioned/git-crypt'd
dotfiles, and let a short rule point there when needed. **Never put a secret
value in the plaintext board database.**

Every rule carries one `tags` array. `ALL` is explicit and default,
`ONLY:<name>` is a named include, and `EXCEPT:<name>` subtracts from `ALL`.
Repeatable `--board`/`--except-board` flags validate exact board names.
Namespaced `--tag` selectors must exist on an active board; several are an OR
set intersected with the board selector. Task claim/context/handoff injection
requires a matching task tag. Taskless session handoffs omit
subsystem-scoped rules. See ADR-027.

## Workspace adoption and rule transfer

`workspace adopt` copies an existing board into registry-owned storage. Use it
when the source board already exists and you want the registry to own the copy;
it is not a rename, and it does not mutate the source board file.

```bash
kb workspace adopt --from-board PATH --name NAME (--workspace ROOT | --rootless) --as ACTOR
```

Rule transfer stays on the registry side. `rule export` produces a bundle for a
named source board, and `rule import` consumes that bundle into the destination
registry with fresh destination rule IDs. These are registry rule verbs, so use
`kb-host` or the raw registry routing path rather than `kb-board`.

```bash
kb rule export --board NAME ... --as ACTOR [--output PATH]
kb rule import PATH --as ACTOR
```

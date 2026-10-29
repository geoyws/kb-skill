# Tags

Read when: tagging rows or a tag refusal.

## Tags — which part of the system this is about

**Tag your rows.** A board that cannot say whether a task is `acme/infra`,
`acme/queuer` or `acme/askie` makes you read titles to find out, and you are
the one who knows.

Tags are namespaced `<estate>/<subsystem>` in storage and CLI
(`--tag estate/subsystem`) — slash spelling only, per map rule r-98ff7ad2. The
hyphen form (`acme-orchestration`) is superseded; never use it. Estate-neutral
examples below use `acme/`: the package ships estate-neutral, so examples need
a concrete estate, and `acme` is a placeholder illustration — not a
default the consumer inherits; substitute your own estate. Prose renders a registered tag as
`:estate/subsystem` (e.g. `:acme/infra`); the colon is only presentation
notation, do not create another sigil namespace inside KB tags. A tag already in
use moves to its namespaced name with `kb tag rename`.

```bash
kb tag ls --json                                   # the vocabulary, with use counts
kb tag new acme/infra --description "hosts, containers, deploys" --as "$AGENT" --json
kb t new "Retry backoff" --tag acme/queuer --tag acme/infra --json
kb t up <id> --tag acme/queuer --as "$AGENT" --json     # replaces, does not append
kb t up <id> --clear-tags --as "$AGENT" --json     # the only way to say "none"
kb t ls --status todo --tag acme/queuer --json          # open work in one subsystem
```

**Read `kb tag ls` before you tag.** The vocabulary is a per-board **master
file**: only a registered tag can be attached, and attaching an unregistered one
is refused naming the nearest match. That refusal is the feature — it is what
stops `acme/infra`, `acme/Infra` and `acme/infrastructure` becoming three
answers to one question.

**If nothing fits, register it** with a description, then use it. Do not leave
the row unfiled and do not smuggle the subject into the title. Registering is one
command and it is paid once per concept, by whoever names it first.

Names are `<estate>/<subsystem>`: each segment is lowercase letters, digits and
inner hyphens, joined by one `/`. `acme/Infra` is refused rather than folded
— folding would decide for you which spelling you meant.

Tags go on **every row type**, drafts and epics included: a plan belongs to a
subsystem as much as the task it produces does.

**Tags are not lanes.** `lane` is *who picks this up* and `claim --next` routes
on it; a tag is *what part of the system this touches*. Putting a subsystem in
`lane` silently changes which driver receives the work.

`@:team` is atmux routing identity, not a tag. Do not encode board, lane, team,
host, tier, actor, priority, or typed row IDs as tags. In particular,
`:acme/module` means the registered KB tag `acme/module`, while `@:team`
names an atmux team; they are different types and must never be normalized into
one another.

Retiring a tag rows still carry is refused and says how many; `--force` strips it
from them and records the count in the trail.

# Aliases

Read when: a short command form is unclear.

## Aliases

Aliases resolve by **exact match**. Prefix inference is refused in both
directions — `task li` is not `task list`, and `--proj` is not `--project`. A
near-miss flag is *suggested* in the error, never accepted.

| Short | Full |
|---|---|
| `t` | `task` |
| `s` | `story` |
| `h` | `handoff` |
| `att`, `attn` | `attention` |
| `sr` | `sitrep` |
| `w`, `ws` | `workspace` |
| `cp` | `checkpoint` |
| `hb` | `heartbeat` |
| `rel` | `release` |
| `ctx` | `context` |
| `ev` | `events` |
| `dash` | `dashboard` |
| `n` | `note` |
| `r` | `rule` |
| `v` | `version` |

Scoped to their group:

| Group | Short forms |
|---|---|
| `task` | `ls`=list `mv`=move `rm`=remove `new`=add `up`=update `meta`=metadata `cat`=show |
| `story` | `adv`=advance |
| `handoff` | `ls`=list `new`=create `acc`=accept |
| `message` | `cat`=show |
| `workspace` | `ls`=list `att`=attach `det`=detach |
| `attention` | `ls`=list `up`=update `new`=raise |
| `tag` | `ls`=list `rm`=remove `new`=add |
| `rule` | `ls`=list `new`=add `up`=update `cat`=show |
| `sitrep` | `ls`=list `new`=post |
| `deploy` | `ls`=list `cat`=show |
| `sprint` | `ls`=list `cat`=show |
| `subscription` | `ls`=list `new`=add `cat`=show |

⚠ `att` means **attach** inside `workspace` and **attention** at the top level.
Both are exact-match and scoped, so they never collide — but read
`kb ws att` as attach and `kb att` as attention.

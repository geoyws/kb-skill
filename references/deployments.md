# Deployment attempts

Read when: recording a deployment (`kb deploy`).

## Deployment attempts — exact release receipts

```bash
kb deploy start --repo OWNER/REPO --commit FULL_40_CHAR_SHA --tier @_p \
  --environment production --host "$BOARD_HOME_HOST" --url "$SERVICE_URL" \
  --task TASK_ID --operation-id OPERATION_ID --as "$AGENT" --json

kb deploy finish DEPLOYMENT_ID --token CAPABILITY_TOKEN --result succeeded \
  --phase verification --served-commit FULL_40_CHAR_SHA \
  --receipt "what was checked live" --as "$AGENT" --json

kb deploy current --json
kb deploy list --status failed --json
kb deploy list --all --json
```

Canonical tiers are `@_bdt`, `@_bd`, `@_bst`, `@_bs`, `@_s`, `@_uat`,
`@_preview` (PX's shared trunk tier, from board schema 54), and `@_p`. A board
below schema 54 refuses only `@_preview`, naming its owner's
`kanban board upgrade`. Deployment commands only record attempts and evidence; they neither
perform a deployment nor inspect its target. Deploy through the real release
path, independently observe the live target, then record the full pushed
commit and what was actually served. `succeeded` is refused unless the served
commit matches exactly and the phase is `verification` with a non-empty live
receipt. Keep the start receipt's capability token only in private ephemeral
state until finishing; never put it in task or sprint notes, checkpoints,
handoffs, receipts, chat, or logs. A retry starts a new row with `--retry-of`;
never rewrite the old attempt. Use `deploy abandon --token … --note …` when no
failure was observed; `--force` is an explicit audited recovery override. See
ADR-030.

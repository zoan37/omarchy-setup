# Claude Code: local session retention (and there is no "never")

**Applied 2026-09-17.** Claude Code deletes local session transcripts after
**30 days** by default, which silently loses resumable sessions. The knob is
`cleanupPeriodDays` in `~/.claude/settings.json`.

## There is no sentinel for "never expire"

This is the part worth writing down, because the obvious guess is wrong:

- **`0` is invalid** and fails validation — it does **not** mean "keep forever".
  The schema is `exclusiveMinimum: 0`, so the minimum accepted value is 1 day.
- `-1`, `null`, `false`: none are documented or accepted.
- The only way to effectively disable expiry is **a very large number.**

```json
{
  "cleanupPeriodDays": 10950
}
```

10950 days ≈ 30 years. The upstream description says as much: *"Use a large
value for long retention; use `--no-session-persistence` to disable transcript
writes entirely."* Those are opposite ends — the flag stops transcripts being
written at all, which is not what we want here.

## What the sweep actually deletes

Not just transcripts. When the period elapses, Claude Code removes, from
`~/.claude/`: `projects/<project>/<session>.jsonl` and that session's
`subagents/` and `tool-results/`, `file-history/`, `plans/`, `debug/`,
`paste-cache/`, `image-cache/`, `uploads/`, `session-env/`, `tasks/`,
`shell-snapshots/`, `backups/`, `feedback-bundles/`, and `usage-data/`.

**Not** swept: `~/.claude/history.jsonl`, `~/.claude/agent-memory/`,
`projects/<project>/memory/`, and state files like `.credentials.json`.

## This is local-only — it does not touch server retention

`cleanupPeriodDays` governs the plaintext cache in `~/.claude/projects/` and
nothing else. Anthropic-side retention is a separate, independent policy (for a
consumer account: 30 days, or 5 years if data is used for training) that this
setting cannot change in either direction. Don't read a large value here as a
privacy setting — it's the opposite, it keeps *more* on disk, in plaintext, for
longer.

Scope: the key is accepted in any settings file — user
(`~/.claude/settings.json`), project (`.claude/settings.json`), local
(`.claude/settings.local.json`), or managed policy. User scope is the right one
for a machine-wide preference.

## Verify

```sh
jq -e '.cleanupPeriodDays' ~/.claude/settings.json    # -> 10950
```

Note this file survives `omarchy update` untouched (it isn't Omarchy's), but it
is **per machine** — set it on each new install. The mise-managed Claude Code
upgrade path is unrelated and covered in
[post-update-checklist.md](post-update-checklist.md) §5.

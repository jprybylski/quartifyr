# Contributing

## Git hooks

```bash
git config core.hooksPath .githooks
```

One-time, per clone. Currently just `.githooks/pre-commit`: a reminder
(not a hard requirement) that warns when a commit touches a file whose
CLI output feeds one of `docs/assets/img/*.gif` -- e.g. `r/render.R` for
`render-pipeline.gif` -- without also touching that GIF or its
`docs/assets/tapes/*.tape` recipe. See the hook script itself for the
exact trigger list, and each tape's own header comment for how to
re-record it. Skip a false positive (a comment or refactor with
identical printed output, say) with `SKIP_DOCS_ASSET_CHECK=1 git commit`
or `git commit --no-verify`.

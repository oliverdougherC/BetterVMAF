# Legacy branch archive

Review date: 2026-09-13. Baseline main: `209921cd525e4331b361bf78c428787fe3e6f946`.

| Former branch | Reviewed tip | Archive tag |
|---|---|---|
| `nano` | `a54900b67584c8cfd805fbbd4b10e0081232570d` | `archive/nano-2026-09-13` |
| `test` | `3419928342353a047e5c76a219698003748ab39f` | `archive/test-2026-09-13` |

Both branches diverged from the early app: each has two commits outside main, while main has thirteen commits outside each branch. Their tracked source contents are identical to each other; their only difference is Xcode user interface state. They use the old `.Nano` bundle identifier and precede graph/export/batch/4K development on main. The useful self-contained FFmpeg refactor was independently incorporated into later main development. Merging these snapshots would reintroduce obsolete project configuration without advancing the current app.

The archive workflow verifies the exact reviewed tips, creates and verifies both archive tags, then deletes only `nano` and `test`. Git's expected-tip lease prevents deleting a branch that changed concurrently. It is idempotent and stops if a branch or archive tag differs from the reviewed value. Main and release tags are untouched.

The workflow must complete successfully before treating the branch cleanup as finished. Verify the live branches and tags in GitHub after its run. Tags preserve the old experiments without keeping active development branches around.

To inspect an archived experiment locally:

```bash
git fetch origin --tags
git switch --detach archive/nano-2026-09-13
```

To resume it intentionally on a new branch:

```bash
git switch -c experiment/nano-revisit archive/nano-2026-09-13
```

# Current Work (Session 2026-05-19 #2 — roborev backlog sweep, ENDED)

**Last updated:** session end after round-3 merge + bulk closure of round-4 false positives
**Previous sessions:** 2026-05-19 #1 (Nix segfault chain + #208 narrative), 2026-05-18→19 (Round 3 cluster sweep)

## Final state

`main` at `c60edd1` (Merge roborev #3130 — AST-based metrics extractor + 3 latent bug fixes). **21 commits ahead of `origin/main` — UNPUSHED.** Working tree clean. 0 open roborev findings. 1 roborev job queued (in-flight verdict for c60edd1).

## Session totals

- **33 roborev verdicts closed**: 9 round-1 + 5 round-2 + 1 round-3 (#3130) + 2 round-3 lows closed-with-reasoning (#3131 #3129) + 20 round-4 false-positive duplicates
- **20 commits added on top of d24b632**: 12 fix commits + 7 merge commits (`--no-ff`) + 1 round-3 merge
- **13 agents spawned in parallel worktrees** across 3 rounds (7 + 5 + 1)
- **3 latent bugs surfaced beyond what reviewers flagged** (test strsplit perl=FALSE; qa_summary missing 2 multi-line targets; RcppRoll added to wrong DESCRIPTION)
- **0 pushes, 0 PRs opened**

## Branches still present (delete after push if not needed)

All round-1 and round-2 branches were merged via `--no-ff` and the worktrees removed. The branch refs themselves still exist locally:
- `fix/roborev-2756-postpath`, `fix/roborev-2763-rcpproll`, `fix/roborev-2786-fetch-metadata`
- `fix/roborev-3113-yieldtype-precedence`, `fix/roborev-3114-aslogical-generic`, `fix/roborev-3115-qadeps-autocheck`, `fix/roborev-3116-prose-alpha`, `fix/roborev-3118-rcpproll-arch`
- `fix/roborev-3130-multiline-parse`
- 4 `worktree-agent-*` branches from round-1 (B, C, E, F agents)

All are reachable from `main`, so deleting them is purely cosmetic.

## Key technical findings (for next session)

### The `as.logical("1")` trap
R's `as.logical()` does **not** parse numeric strings: `as.logical("1") = NA`, not `TRUE`. `VIGNETTE_STRICT=1` silently disables strict mode under `isTRUE(as.logical(Sys.getenv("VIGNETTE_STRICT", "false")))`. Memory: `feedback_as-logical-numeric-strings.md`. If you want `=1` to work, the parser needs a custom helper.

### The roborev DB text vs `roborev show` text divergence
`roborev_project_backlog.sh` excerpts are from `reviews.output` keyed by `reviews.id`. `roborev show <number>` accepts both `review_id` and `job_id` but resolves to different content (and the show output sometimes references files that don't exist in the project — looks like cross-project hallucination from auto-refine sessions). For real findings, query the DB directly:
```sql
SELECT rv.id, rv.output, rj.git_ref
FROM reviews rv JOIN review_jobs rj ON rv.job_id = rj.id
WHERE rj.repo_id = 16 AND rv.closed = 0 AND rv.verdict_bool = 0;
```

### Agent isolation pitfalls
- `quick-fix` (haiku) agents have no Bash. With `isolation: "worktree"` set, they still edit files in the orchestrator's cwd (not the worktree), and can't `git commit`. **Use `fixer` (sonnet) for anything that must commit.** Reserve quick-fix for trivial single-line edits that the orchestrator will commit on the agent's behalf.
- `fixer` agents with Bash can still commit straight to `main` if the worktree path isn't explicit in the prompt. Always state the worktree path AND the branch name.

### `--no-ff` merge topology is auditable
7 round-1 branches merged with `--no-ff -m "Merge roborev #..."` produced a fan-out topology that's readable in `git log --oneline --graph`. Better than fast-forward when the merging is automation-generated.

## Next session candidates

- **Push the 21 commits** (or open a single PR consolidating them).
- **Run `tar_make()`** to verify the fixes don't break the pipeline. None should — the changes are test infra, prose, scripts, and Nix — but it hasn't been verified.
- **Decide whether to add `1`/`0` parsing to VIGNETTE_STRICT** (custom helper) or leave the current case-insensitive-logical-literals-only semantics now that the docstring is honest.
- **Python test infra** — `tests/test_fetch_*.py` with pytest + responses/mock would make scripts/ behaviour testable. Would address the deferred #3129 ask.
- **Drain the 1 queued roborev review** on c60edd1 — likely fine, but check before next session.

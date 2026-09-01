---
name: lofiatc-issue-delivery
description: Deliver a LofiATC GitHub issue from project-board selection through branch, implementation, pull request, CI, merge, issue closure, and final project status. Use when asked to pick up a Ready issue, start or finish an issue, create its branch or PR, rerun its checks, merge it into test, or report its delivery state.
---

# Deliver a LofiATC issue

Use the repository's GitHub tooling and applicable GitHub skills. Never guess project field IDs or issue state; query current GitHub data.

## Start

1. Read `AGENTS.md` and inspect the worktree before switching branches.
2. Read the selected issue and acceptance criteria. If choosing work, list current Ready items and recommend a bounded issue.
3. Use `test` as the development base unless the user specifies another branch.
4. Create one dedicated issue-linked branch, preferably with `gh issue develop`.
5. Move a Ready issue to **In progress** only after work begins.

## Deliver

1. Keep one logical change on the branch.
2. Implement and validate according to the applicable repo skill.
3. Commit only intended files and push the issue branch.
4. Open a draft PR against the requested base, normally `test`. Include impact, checks, and `Closes #<issue>`.
5. Move the issue to **In review** while the PR is open.
6. Monitor every Windows, Ubuntu, macOS, Windows PowerShell 5.1, and syntax check. Inspect logs before changing code when a job fails.
7. Do not merge without explicit user approval.

## Finish

1. Confirm the PR is mergeable and all required checks pass.
2. Mark a draft ready and merge using the repository's established merge method.
3. Remember that merging into non-default `test` may not automatically close the issue. Close it as completed when necessary.
4. Move the project item to **Done** only after merge and verify both PR and issue states.
5. Report PR URL, base branch, merge commit, checks, issue state, and project status.

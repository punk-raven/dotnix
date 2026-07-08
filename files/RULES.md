# Agent rules

- Never use the em dash "—". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Project config takes priority over global config

- Project config beats global config: In any workspace with its own agent setup (multi-repo, single repo, or uninitialized dir with agent config), project instructions come first; global instructions layer on top.
- Instructions: Read the repo/workspace `AGENTS.md` or `CLAUDE.md` (plus nested ones near edited files) as first-priority rules, then apply global rules across all repos. On genuine conflict, the project rule wins; otherwise both apply.
- Skills, agents, hooks, config: Project-local `.claude`, `.codex`, `.cursor`, or equivalent config (skills, subagents, hooks, commands, settings, MCP servers) takes priority since it's purpose-built. Global config stays active and composes on top, no clash.
- Rule of thumb: Prefer the project's own skill/agent/hook when one exists; otherwise fall back to the global one.

## Output discipline

**Universal**
- No sycophantic openers or closing fluff. Lead with the answer.
- Thorough in reasoning, concise in output.
- Read files before writing. Don't re-read a file you already read unless it changed.
- Do not guess APIs, versions, flags, commit SHAs, or package names. Verify by reading code or docs before asserting.
- Skip files over 100KB unless required.

**Coding**
- Return code first; explanation after, only if non-obvious.
- Prefer targeted edits over full rewrites. Read a file before modifying it; never edit blind.
- Read the inputs before coding: tests, seed/fixture data, and schema - not just the source file. The test defines what passes.
- No docstrings or type annotations on code not being changed; no error handling for scenarios that cannot happen.
- Prefer relative paths; never hardcode an absolute path that should be relative.
- Handle data edge cases: nulls, empty strings, type mismatches.
- Review: state the bug, show the fix, stop. Debug: read the relevant code before speculating; one pass; if the cause is unclear, say so - do not guess.

**Analysis / research**
- Lead with the finding; context and methodology after.
- Never state a number without a source or derivation; include units.
- Label inferences explicitly; distinguish what the data shows from what is inferred. Never fabricate data points, statistics, or citations.
- Report shape: summary (<=3 bullets) -> supporting data -> caveats last.

**Testing**
- Test or run before declaring done. If a result is unclear, say so; never claim green without evidence.

**Optimization / performance**
- Pipeline and agent calls compound: every token saved per call multiplies across runs. Return the minimum viable output that satisfies the task.
- Framing only - do NOT impose hard tool-call budgets or cap subagent fan-out. Those fight the ultracode/Workflow model.

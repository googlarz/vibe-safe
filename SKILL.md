---
name: vibe-safe
description: Use when a non-technical contributor (PM, designer, researcher) is about to write, commit, or merge AI-assisted code in a shared codebase and wants to catch the specific ways vibecoding goes wrong before they become incidents.
---

# vibe-safe

## Overview

Active safety session for non-technical contributors. Claude reads your actual git state and scans real files — you don't self-report anything. Every flag cites the line and file.

**Core rule: "Claude said it's fine" is not a safety check. This skill is.**

## Auto-routing

You don't need to pick a mode. Just say `vibe-safe` and Claude will detect the right one:

```
git status shows no staged changes, you're describing a task → BEFORE mode
git diff --staged has content → COMMIT mode
git diff HEAD has unstaged changes → REVIEW mode
commits ahead of main, ready to open PR → PR mode
conflict markers in any file → CONFLICT mode
Claude just proposed something that feels big → ALARM mode
```

Or invoke directly: `vibe-safe before / review / commit / pr / conflict / alarm`

---

## Repo Configuration: `.vibesafe`

If a `.vibesafe` file exists in the repo root, all modes read it alongside the default Danger Zone list. Format:

```
# .vibesafe
danger_zone: src/payments/
danger_zone: infrastructure/
safe_zone: src/components/marketing/
safe_zone: public/images/
```

BEFORE mode generates this file. Once committed, every contributor gets the same custom rules automatically.

---

## Mode: BEFORE

Before Claude writes anything. Run this before you describe your task.

Claude runs:
- `git branch --show-current` — if main/master: **STOP and fix immediately**: Claude runs `git checkout -b feature/[3-word-description-from-task]`
- `git log --follow -- <your target files>` — establishes who owns this area
- File extension check against Danger Zones + `.vibesafe` custom zones
- `ls .git/hooks/pre-commit` — checks whether the mechanical safety hook is installed

**Output:**

1. **Scoped prompt** — limits what files Claude is allowed to touch. Use it verbatim.
2. **Hook installation** — if no pre-commit hook exists, Claude copies `~/.claude/skills/vibe-safe/hooks/pre-commit` to `.git/hooks/pre-commit` and makes it executable. This hook runs branch + credential + Danger Zone checks on every future `git commit`, without requiring you to remember vibe-safe.
3. **`.vibesafe` generation** — if no `.vibesafe` exists, Claude asks:
   - "What parts of this codebase should a developer always be consulted on?"
   - "What areas are definitely yours to edit freely (copy, images, marketing)?"
   Then writes the file and shows you what to commit.

---

## Mode: REVIEW

After Claude writes code, before you commit.

Claude runs:
- `git diff HEAD` for unstaged changes
- `git grep -nE "sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="` across ALL tracked files — credentials live in files you didn't intend to change and won't appear in your diff

**What gets flagged with evidence:**

| Signal | Example flag |
|--------|-------------|
| Credential pattern | `src/api/client.ts:14 — const API_KEY = "sk-proj-abc123"` ⛔ This key is now in git history permanently, even if deleted later |
| File deletion | `src/utils/helper.ts deleted` — Claude may be wrong that it's unused |
| Config file modified | `config/nginx.conf` — controls production traffic for everyone |
| Migration file present | `db/migrations/*.sql` — irreversible schema change |
| Auth-related file | `src/auth/session.ts` — security surface, needs developer eyes |
| Scope creep | Files modified that weren't in your original target |
| Quality gate weakening | `jest.config.ts: coverage threshold dropped from 80 to 60` ⛔ Claude fixed the check, not the bug |

Every flag ends with a plain-English explanation of the worst-case consequence and a specific action.

---

## Mode: COMMIT

Before `git commit`. For fixable problems, Claude executes the fix — you don't need to know the git commands.

Five automated checks, each with remediation:

1. **Credential scan** — `git grep -nE "sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="` on ALL tracked files
   - Staged file contains credential → Claude runs `git restore --staged <file>`, explains the key must be rotated even after removal
   - Untracked file contains credential → flag only (Claude cannot unstage what isn't staged)

2. **Danger Zone audit** — staged files vs. default list + `.vibesafe` custom zones
   - Danger Zone file staged → Claude runs `git restore --staged <file>` and tells you what to ask a developer to apply instead
   - Quality gate file staged → Claude reads the diff and checks whether any numeric threshold decreased: `git diff --cached <file> | grep -E "^\-.*[0-9]"`. If a number dropped (coverage %, error limit, score floor), flag as **quality gate weakening**: "Claude may have fixed the failing check by lowering the bar, not by fixing the code."

3. **Deletion audit** — any files being removed?
   - File deleted → flag: "Claude may be wrong that this is unused. Confirm with a developer before this commit."

4. **Branch check** — `git branch --show-current`
   - On main/master → Claude runs `git checkout -b feature/[3-word-slug-from-diff]`, then re-runs all checks on the new branch

5. **Scope check** — staged file list vs. your stated intent
   - Out-of-scope file → Claude runs `git restore --staged <file>` after your confirmation

**When all checks pass:** Claude generates the commit message from the diff + your one-line description. You confirm or edit, then Claude runs `git commit -m "..."` for you.

---

## Mode: PR

Before opening a pull request.

Claude reads `git diff main...HEAD` and asks one question: "Why are you making this change?"

Then generates a complete PR description:
- **What changed** — derived from the diff, plain English
- **Why** — your answer
- **What to test** — derived from file types and risk level
- **Flagged uncertainties** — unresolved review flags surface here
- **Who should review** — from git log of changed files

Also checks: are you targeting the right base branch? Is your branch up to date?

---

## Mode: CONFLICT

When merge conflict markers appear.

Claude reads `<<<<<<<` / `=======` / `>>>>>>>` and tells you:
- What the current version does (plain English)
- What your change does (plain English)
- What specifically is lost if you accept either side

Never recommends "accept all theirs/ours." If the conflict is in a Danger Zone file: **STOP — CALL A DEVELOPER**.

---

## Mode: ALARM

When Claude proposes something that feels big, irreversible, or outside scope.

Claude assesses three things:
- **Reversible?** Can this be undone with a single git revert?
- **Shared?** Does it affect infrastructure other teams depend on?
- **Expected review?** Would a developer expect to approve this first?

Output: **GO AHEAD / PAUSE AND CHECK / STOP — CALL A DEVELOPER**

---

## Escalation: When to Stop

### STOP — CALL A DEVELOPER (non-negotiable)
- Any file in `migrations/`, `schema/`, `db/` is in the diff
- Any CI/CD config (`.github/workflows/`, `Jenkinsfile`, `.circleci/`)
- Any environment config (`.env`, `docker-compose.*`, `nginx.conf`, `*.conf`)
- Any auth-related file (`auth`, `login`, `session`, `jwt`, `oauth`, `permissions`)
- Branch is `main` or `master`
- Claude proposed running a database command
- Credentials found anywhere in modified files

### PAUSE AND CHECK
- Diff is larger than you expected
- Files outside your intended scope appear
- A file you've never seen is being modified
- Claude said "this should be safe" but you don't understand why

### GO AHEAD
- Only your intended files in the diff
- No credential flags in any modified file
- You're on a feature branch
- A developer has seen the plan

---

## Danger Zones

Files that need developer involvement regardless of change size:

| Category | Patterns |
|----------|----------|
| Environment | `.env`, `.env.*` |
| Infrastructure | `nginx.conf`, `*.conf`, `Dockerfile`, `docker-compose.*` |
| CI/CD | `.github/workflows/`, `Jenkinsfile`, `.circleci/`, `.gitlab-ci.yml` |
| Database | `migrations/`, `schema/`, `*.sql` |
| Auth | files named: `auth`, `login`, `session`, `jwt`, `oauth`, `permission`, `role` |
| Build | `webpack.config.*`, `vite.config.*`, `tsconfig.json` |
| Quality gates | `jest.config.*`, `vitest.config.*`, `codecov.yml`, `.nycrc`, `.eslintrc.*`, `.stylelintrc.*`, `sonar-project.properties` |
| Dependencies | `package.json`, `Gemfile`, `requirements.txt` (version changes) |

---

## Common Rationalizations — Red Flags

| Thought | What it actually means |
|---------|----------------------|
| "Claude said it was fine" | Claude doesn't know your codebase's undocumented dependencies |
| "It's not in my diff" | Credentials can exist in files you didn't intend to change |
| "It's just a small change" | File type matters more than size — one line in nginx.conf hits production |
| "I'll fix it in the next commit" | Committed credentials are compromised permanently, even if deleted |
| "I accepted 'theirs' everywhere" | You may have silently reverted your own work |
| "The tests still pass" | Tests don't cover what they don't test |
| "It's just a config tweak" | Config files control production for everyone on the team |
| "I've done this before" | Past safety was luck, not process |
| "Claude made the failing checks pass" | Check what it changed to make them pass — lowering a threshold is not fixing a bug |

---

## Mode: VERIFY

**Invoke after any vibe-safe session to confirm the session is clean.**

Claude runs:
- `git branch --show-current` — confirms not on main/master
- `git diff main...HEAD --name-only` — lists every file that will be in the PR
- `git grep -nE "sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="` — final credential sweep
- `git log --oneline -3` — confirms commit messages are descriptive

Output: **CLEAN** or remaining flags with specific file:line evidence.

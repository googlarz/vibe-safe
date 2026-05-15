# vibe-safe

**Without this skill: 0/4 risks caught. With this skill: 4/4 caught.**

A Claude Code skill that acts as an active session guardian for non-technical contributors — PMs, designers, researchers — shipping AI-assisted code in shared codebases.

The difference from a checklist: **Claude reads your actual git state and scans real files. You don't self-report anything. Every flag cites the file and line.**

---

## What it guards against

| Risk | Without vibe-safe | With vibe-safe |
|------|------------------|----------------|
| Credential committed (not in diff) | Missed — not in staged files | Caught — full-repo grep, `src/api/client.ts:14` |
| Committing directly to main | No check | Stopped immediately |
| Config/auth/migration files in diff | No check | Flagged with escalation instruction |
| Merging conflict by accepting all "theirs" | No check | Both sides explained, Danger Zone → stop |

---

## Install

```bash
# Manual
git clone https://github.com/googlarz/vibe-safe ~/.claude/skills/vibe-safe
```

---

## Usage

Just say `vibe-safe` — Claude auto-detects the right mode from your git state:

```
No staged changes, describing a task      → BEFORE mode
git diff --staged has content             → COMMIT mode
Unstaged changes present                  → REVIEW mode
Commits ahead of main, about to open PR  → PR mode
Conflict markers in any file             → CONFLICT mode
Claude proposed something that feels big → ALARM mode
```

Or invoke directly: `vibe-safe commit` / `vibe-safe before` / etc.

After any session: `vibe-safe verify` — confirms the session is clean before you walk away.

---

## v1.1: Three new capabilities

### 1. Pre-commit hook — safety without memory

BEFORE mode now installs `hooks/pre-commit` into `.git/hooks/pre-commit` automatically. From that point, every `git commit` in that repo runs the mechanical checks (branch, credentials, Danger Zones) without you needing to think about it. Works without Claude — pure shell.

```bash
# Or install manually:
cp ~/.claude/skills/vibe-safe/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### 2. Agentic remediation — fix, don't just flag

COMMIT mode no longer just flags problems — it executes the fix for anything fixable:

| Problem | What Claude does |
|---------|-----------------|
| On `main`/`master` | `git checkout -b feature/[3-word-slug]`, then re-runs checks |
| Credential in staged file | `git restore --staged <file>`, explains key must be rotated |
| Danger Zone file staged | `git restore --staged <file>`, tells you what to ask a dev to apply |
| Out-of-scope file staged | `git restore --staged <file>` after your confirmation |
| All checks pass | Generates commit message, runs `git commit -m "..."` for you |

You confirm or edit — you don't need to know the git commands.

### 3. Repo-specific `.vibesafe` config

BEFORE mode generates a `.vibesafe` file for your repo. Once committed, every contributor (and the pre-commit hook) uses the same custom rules.

```
# .vibesafe
danger_zone: src/payments/
danger_zone: infrastructure/
safe_zone: src/components/marketing/
safe_zone: public/images/
```

BEFORE mode asks two questions to generate it: what's off-limits, and what's definitely yours to change.

---

## Modes

### BEFORE
Runs before Claude writes anything. Checks your branch (creates a feature branch if on main), traces who owns the target files via git log, installs the pre-commit hook if missing, generates `.vibesafe` if missing, and produces a scoped prompt that limits what files Claude is allowed to touch.

### REVIEW
After Claude writes code, before you commit. Runs `git diff HEAD` for unstaged changes **and** `git grep` across all tracked files for credential patterns. Credentials live in files you didn't intend to change and won't appear in your diff.

### COMMIT
Five automated checks, each with remediation (see above). When all pass: Claude generates the commit message and runs `git commit` for you.

### PR
Reads `git diff main...HEAD`, asks why you're making the change, generates a complete PR description with what changed, what to test, flagged uncertainties, and suggested reviewers from git log.

### CONFLICT
Reads conflict markers and explains both sides in plain English — what the current version does, what your change does, what's specifically lost if you accept either side. Never recommends "accept all theirs/ours." Danger Zone file in conflict → STOP — CALL A DEVELOPER.

### ALARM
When Claude proposes something that feels big. Assesses reversibility, shared-infra impact, and whether a developer would expect to review this. Output: GO AHEAD / PAUSE AND CHECK / STOP — CALL A DEVELOPER.

### VERIFY
Post-session clean check. Runs branch check, full file list for the PR, credential sweep, and commit message audit. Output: **CLEAN** or remaining flags with file:line evidence.

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
| Dependencies | `package.json`, `Gemfile`, `requirements.txt` (version changes) |

---

## Evidence

This skill was built with TDD: a baseline test first (RED), then the skill (GREEN), then loophole-closing (REFACTOR).

**Baseline test (no skill):** Subagent playing a non-technical PM with a planted test repo containing:
- A credential in `src/api/client.ts` (not in staged diff)
- `config/nginx.conf` (infrastructure, Danger Zone)
- `db/migrations/0043_add_user_role.sql` (irreversible migration)
- Scope creep file `src/hooks/useTheme.ts`

Result: **0/4 risks caught.** PM committed directly to main with a vague commit message.

**With skill:** Same scenario. Result: **4/4 risks caught** — credential flagged with file:line, main-branch commit stopped, migration and nginx.conf escalated to developer.

Additional mode tests passed: BEFORE mode (main-branch STOP), CONFLICT mode (auth file danger zone escalation).

---

## Why "not in my diff" is the most dangerous rationalization

Credentials live in files you didn't intend to change. If you search only your staged files, you'll miss them. vibe-safe runs `git grep` across **all tracked files** in every REVIEW and COMMIT check — the same command that would catch a secret committed three weeks ago by a different session.

---

## License

MIT

# vibe-safe

**For the non-technical contributor:** Claude wrote the code. You read the first two lines, it looked fine. The commit message says "update." You accepted "theirs" on all the merge conflicts. The test suite is green because Claude lowered the coverage threshold, not because the tests pass. The API key is in a file you never opened — it won't appear in your diff.

Run this before you commit. It reads your actual git state, not what you assume is in it.

**For the developer:** Everything above has already happened in your repo. Install this before it happens again.

---

**32 risk categories. Developer-defined contracts. Every flag cites file:line. Claude reads the actual git state — nothing is self-reported.**

---

## What it guards against

| Risk | Without vibe-safe | With vibe-safe |
|------|------------------|----------------|
| Credential committed (not in diff) | Missed — not in staged files | Caught — full-repo grep, `src/api/client.ts:14` |
| Committing directly to main | No check | Stopped — feature branch created automatically |
| Config/auth/migration/quality-gate files in diff | No check | Flagged with escalation instruction |
| Merging conflict by accepting all "theirs" | No check | Both sides explained, Danger Zone → stop |
| Claude lowered a quality threshold to pass CI | No check | Caught — diff scanned for numeric decreases in quality configs |
| `@ts-ignore` / `eslint-disable` added | No check | Flagged — suppressed error, not fixed |
| Failing test skipped with `.skip()` | No check | Flagged — bypassed test, not fixed |
| Test file deleted | No check | Flagged — suite passes by omission |
| `console.log` / `debugger` left in code | No check | Flagged — debug artifact in production |
| Empty `catch {}` block | No check | Flagged — errors silently swallowed |
| Lock file changed without `package.json` | No check | Flagged — undocumented dependency change |
| Binary file committed | No check | Flagged — permanent history bloat |
| PII in committed code | No check | Flagged — email/phone pattern on added lines |
| Internal hostname committed | No check | Flagged — infrastructure topology exposed |
| Claude proposes `git push --force` | No check | Auto-escalates to ALARM |
| `dangerouslySetInnerHTML` / `innerHTML =` added | No check | Flagged — XSS attack surface |
| `eval(` added | No check | Flagged — arbitrary code execution risk |
| SSL verification disabled | No check | STOP — TLS silently removed |
| CORS wildcard set | No check | Flagged — API open to any domain |
| `.gitignore` entries removed | No check | Flagged — previously ignored files now tracked |
| `setTimeout`/`sleep` with hardcoded value | No check | Flagged — timing hack, not a real fix |
| `: any` / `as any` proliferation (TypeScript) | No check | Flagged — type system escaped |
| `debug: true` in non-test config | No check | Flagged — debug mode in production |
| `throw new Error("TODO")` / `// TODO` in implementation | No check | Flagged — placeholder shipped instead of real code |
| Commented-out code blocks | No check | Flagged — Claude disabled working code, possibly uncertain |
| Private key / cert file staged | No check | STOP — binary credential, text grep misses it |
| `rm -rf` in committed script | No check | Flagged — destructive path without knowing prod layout |
| `throw "string"` without Error | No check | Flagged — stack trace lost, bugs undiagnosable in production |
| New env var, no `.env.example` update | No check | Flagged — next dev spinning up won't know to set it |
| Migration with no rollback | No check | Flagged — schema change that can't be undone automatically |
| New source code, no test changes | No check | Flagged (or hard-blocked via `require_tests`) |
| Claude changed more files than asked | No check | SCOPE mode — intent vs diff, file-by-file verdict |

---

## Install

```bash
git clone https://github.com/googlarz/vibe-safe ~/.claude/skills/vibe-safe
```

**Install the pre-commit hook** (runs locally on every `git commit`):

```bash
cp ~/.claude/skills/vibe-safe/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Install CI integration** (runs in GitHub Actions — catches `--no-verify` bypasses):

```bash
mkdir -p .github/vibe-safe .github/workflows
cp ~/.claude/skills/vibe-safe/ci/vibe-safe-ci.sh .github/vibe-safe/
cp ~/.claude/skills/vibe-safe/ci/workflow.yml .github/workflows/vibe-safe.yml
```

Or just run `vibe-safe` — BEFORE mode installs both automatically.

---

## Usage

Just say `vibe-safe` — Claude auto-detects the right mode from your git state:

```
No staged changes, describing a task      → BEFORE mode
git diff --staged has content             → COMMIT mode
Unstaged changes present                  → REVIEW mode
"did Claude change more than I asked?"   → SCOPE mode
Commits ahead of main, about to open PR  → PR mode
Conflict markers in any file             → CONFLICT mode
Claude proposed something that feels big → ALARM mode
"what does this flag mean?"              → EXPLAIN mode
Developer reviewing a vibe-coded PR      → REVIEWER mode
Checking whether past commits are clean  → HISTORY mode
```

Or invoke directly: `vibe-safe commit` / `vibe-safe explain ssl` / `vibe-safe reviewer` / etc.

After any session: `vibe-safe verify` — confirms the session is clean before you walk away.

---

## How it works

**Active, not passive.** Claude runs the actual shell commands — `git diff`, `git grep`, `git branch` — and reports what it finds. You don't fill out a form.

**Pre-commit hook runs without Claude.** BEFORE mode installs `hooks/pre-commit` into `.git/hooks/pre-commit`. From then on, 24 mechanical checks run on every `git commit` whether or not you remember to invoke the skill. Branch check, credential scan, Danger Zone audit, suppression patterns, security sinks, private key files, env var drift, migration rollback, developer contracts — all in pure shell.

**CI integration closes the bypass gap.** The hook can be skipped with `git commit --no-verify`. The GitHub Actions workflow cannot. BEFORE mode also installs `ci/vibe-safe-ci.sh` + `ci/workflow.yml` — the same checks run on every push and PR, with GitHub annotations for each finding. `--no-verify` is auto-escalated to ALARM if Claude proposes it.

**Agentic remediation.** COMMIT mode fixes what's fixable instead of just flagging:

| Problem | What Claude does |
|---------|-----------------|
| On `main`/`master` | `git checkout -b feature/[3-word-slug]`, then re-runs checks |
| Credential in staged file | `git restore --staged <file>`, explains key must be rotated |
| Danger Zone file staged | `git restore --staged <file>`, tells you what to ask a dev |
| Out-of-scope or too many files staged | SCOPE audit — file-by-file verdict, `git restore` for anything unexpected |
| All checks pass | Generates commit message, runs `git commit -m "..."` for you |

**Developer-defined contracts.** The developer sets the rules once in `.vibesafe`. vibe-safe enforces them for every PM contribution — no code review nagging required.

```
# .vibesafe
danger_zone: src/payments/
safe_zone: src/components/marketing/

require_tests: true          # New source files must have test changes
max_changed_files: 15        # Warn + SCOPE audit if exceeded
require_migration_rollback: true  # All migrations need a down/rollback
block_pattern: TODO          # Hard stop if TODO appears in implementation
require_reviewer: @alice     # Added to every PR description
```

Commit `.vibesafe` once. Every contributor — and the pre-commit hook and CI — gets the same rules automatically.

---

## Modes

### BEFORE
Runs before Claude writes anything. Checks your branch (creates a feature branch if on main), traces who owns the target files via git log, installs the pre-commit hook and CI workflow if missing, and produces a scoped prompt that limits what files Claude is allowed to touch.

If no `.vibesafe` exists: Claude scans the repo to discover rules (test file count, average commit size, migration rollback patterns, top committers), then generates a single document to paste into Slack or email — discovered rules with inline confirmation prompts, open questions below. PM sends it, pastes the answers back, Claude writes `.vibesafe`.

### REVIEW
After Claude writes code, before you commit. Runs `git diff HEAD` for unstaged changes **and** `git grep` across all tracked files for credential patterns. Credentials live in files you didn't intend to change and won't appear in your diff.

### SCOPE
When you think Claude changed more than you asked — or when `max_changed_files` fires. Claude asks what the original task was, then evaluates every changed file: **IN SCOPE / LIKELY NEEDED / SUSPICIOUS / OUT OF SCOPE**. Removes out-of-scope files with your confirmation.

### COMMIT
32 checks across credentials, Danger Zones, code health, security patterns, scope, env vars, migrations, and developer contracts — each with remediation. When all pass: Claude generates the commit message and runs `git commit` for you.

### PR
Reads `git diff main...HEAD`, asks why you're making the change, generates a complete PR description with what changed, what to test, flagged uncertainties, and suggested reviewers. Appends a **PR safety artifact** — a table showing what vibe-safe verified — so the reviewer sees the evidence without asking.

### CONFLICT
Reads conflict markers and explains both sides in plain English — what the current version does, what your change does, what's specifically lost if you accept either side. Never recommends "accept all theirs/ours." Danger Zone file in conflict → STOP — CALL A DEVELOPER.

### ALARM
When Claude proposes something that feels big. Assesses reversibility, shared-infra impact, and whether a developer would expect to review this. Auto-escalates for: `git push --force`, `git commit --no-verify`, direct database commands, CI check bypasses. Output: **GO AHEAD / PAUSE AND CHECK / STOP — CALL A DEVELOPER**.

### VERIFY
Post-session clean check. Runs branch check, full file list for the PR, credential sweep, and commit message audit. Output: **CLEAN** or remaining flags with file:line evidence.

### HISTORY
Scans recent git history for past mistakes needing active remediation. Finds commits that added credential patterns (even if later "deleted"), suspicious commit messages hinting at cleanup attempts, and recently deleted files. Distinguishes **active exposure** (still in HEAD) from **historical exposure** (removed but still in history — key rotation + `git filter-repo` required). Includes exact remediation steps.

### EXPLAIN
Deep plain-English explanation of any vibe-safe flag. `vibe-safe explain ssl` tells you what SSL verification is, why disabling it is dangerous, what it looks like when it goes wrong, what Claude should have done instead, and one sentence you can say to your developer. For when "flagged" isn't enough and you want to actually understand it.

### REVIEWER
For developers reviewing a PR opened by a non-technical contributor. Reads the full diff and produces: what the PM intended, what actually changed, which vibe-safe patterns are present, what to specifically test, and questions to ask if intent and implementation don't match.

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

## Evidence

Built with TDD: baseline test first (RED) → skill written (GREEN) → loopholes closed (REFACTOR).

**Baseline (no skill):** Subagent playing a non-technical PM, test repo with a credential outside the diff, `nginx.conf`, an irreversible migration, and a scope creep file. Result: **0/4 caught.** Committed directly to main with a vague message.

**With skill:** Same scenario. Result: **4/4 caught** — credential flagged with file:line, main-branch commit stopped, migration and nginx.conf escalated to developer.

Five additional mode tests passed: BEFORE (main-branch stop), CONFLICT (auth file Danger Zone), COMMIT (real-incident quality gate weakening from PM's own experience).

---

## Why "not in my diff" is the most dangerous rationalization

Credentials live in files you didn't intend to change. If you scan only staged files, you miss them. vibe-safe runs `git grep` across **all tracked files** in every REVIEW and COMMIT check — the same command that catches a secret committed three weeks ago in a different session.

---

## License

MIT

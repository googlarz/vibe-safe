# vibe-safe

**For non-technical contributors:** You didn't ask to become a software engineer. You just needed the button to say "Submit" instead of "Send." Claude wrote the code, it looked fine, and now there's a non-zero chance you're about to commit an API key directly to main with a commit message that says "update stuff." This catches that. Run it before you touch anything — Claude reads your actual git state and tells you exactly what to do next. You don't need to understand what any of it means.

**Your developer will still love you. Probably.**

**For developers:** Your PM is going to vibe-code into the codebase. This is not a hypothesis, it's already happening. Install this on their machine before your next vacation — 28 automated checks run on every `git commit` without Claude, without you, and without anyone having to remember anything. Credentials, main-branch commits, suppressed errors, skipped tests, SSL disabled, quality thresholds quietly lowered so CI goes green. All of it.

**You're welcome.**

---

**28 risk categories. Every flag cites file:line. Claude reads the actual git state — nothing is self-reported.**

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

---

## Install

```bash
git clone https://github.com/googlarz/vibe-safe ~/.claude/skills/vibe-safe
```

**Install the pre-commit hook in each repo you work in:**

```bash
cp ~/.claude/skills/vibe-safe/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Or just run `vibe-safe` — BEFORE mode installs it automatically.

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

## How it works

**Active, not passive.** Claude runs the actual shell commands — `git diff`, `git grep`, `git branch` — and reports what it finds. You don't fill out a form.

**Pre-commit hook runs without Claude.** BEFORE mode installs `hooks/pre-commit` into `.git/hooks/pre-commit`. From then on, 21 mechanical checks run on every `git commit` whether or not you remember to invoke the skill. Branch check, credential scan, Danger Zone audit, suppression patterns, security sinks, private key files — all in pure shell.

**Agentic remediation.** COMMIT mode fixes what's fixable instead of just flagging:

| Problem | What Claude does |
|---------|-----------------|
| On `main`/`master` | `git checkout -b feature/[3-word-slug]`, then re-runs checks |
| Credential in staged file | `git restore --staged <file>`, explains key must be rotated |
| Danger Zone file staged | `git restore --staged <file>`, tells you what to ask a dev |
| Out-of-scope file staged | `git restore --staged <file>` after your confirmation |
| All checks pass | Generates commit message, runs `git commit -m "..."` for you |

**Repo-specific config.** BEFORE mode generates a `.vibesafe` file from two questions. Commit it once and every contributor — and the hook — gets the same custom danger/safe zones.

```
# .vibesafe
danger_zone: src/payments/
safe_zone: src/components/marketing/
```

---

## Modes

### BEFORE
Runs before Claude writes anything. Checks your branch (creates a feature branch if on main), traces who owns the target files via git log, installs the pre-commit hook if missing, generates `.vibesafe` if missing, and produces a scoped prompt that limits what files Claude is allowed to touch.

### REVIEW
After Claude writes code, before you commit. Runs `git diff HEAD` for unstaged changes **and** `git grep` across all tracked files for credential patterns. Credentials live in files you didn't intend to change and won't appear in your diff.

### COMMIT
28 checks across credentials, Danger Zones, code health, security patterns, and scope — each with remediation. When all pass: Claude generates the commit message and runs `git commit` for you.

### PR
Reads `git diff main...HEAD`, asks why you're making the change, generates a complete PR description with what changed, what to test, flagged uncertainties, and suggested reviewers from git log.

### CONFLICT
Reads conflict markers and explains both sides in plain English — what the current version does, what your change does, what's specifically lost if you accept either side. Never recommends "accept all theirs/ours." Danger Zone file in conflict → STOP — CALL A DEVELOPER.

### ALARM
When Claude proposes something that feels big. Assesses reversibility, shared-infra impact, and whether a developer would expect to review this. Auto-escalates for: `git push --force`, direct database commands, CI check bypasses. Output: **GO AHEAD / PAUSE AND CHECK / STOP — CALL A DEVELOPER**.

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

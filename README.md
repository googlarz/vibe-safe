# vibe-safe

**Covers 28 risk categories. Without this skill: 0 caught. With this skill: all caught.**

A Claude Code skill that acts as an active session guardian for non-technical contributors — PMs, designers, researchers — shipping AI-assisted code in shared codebases.

The difference from a checklist: **Claude reads your actual git state and scans real files. You don't self-report anything. Every flag cites the file and line.**

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
| SSL verification disabled | No check | Flagged — TLS silently removed |
| CORS wildcard set | No check | Flagged — API open to any domain |
| `.gitignore` entries removed | No check | Flagged — previously ignored files now tracked |
| `setTimeout`/`sleep` with hardcoded value | No check | Flagged — timing hack, not a real fix |
| `: any` / `as any` proliferation (TypeScript) | No check | Flagged — type system escaped |
| `debug: true` in non-test config | No check | Flagged — debug mode in production |
| `throw new Error("TODO")` / `// TODO` in implementation | No check | Flagged — placeholder shipped instead of real code |
| Commented-out code blocks | No check | Flagged — Claude disabled working code, possibly uncertain |
| Private key / cert file staged | No check | STOP — binary credential, text grep misses it |
| `rm -rf` in committed script | No check | Flagged — destructive path Claude wrote without knowing prod layout |
| `throw "string"` without Error | No check | Flagged — stack trace lost, bugs undiagnosable in production |

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

## v1.5.0: final 3 risk categories — covers 28 total

- **Private key / cert files staged** — `.pem`, `.key`, `.pfx`, `.p12`, `.jks`, `id_rsa`, `id_ed25519`. Binary credentials the text grep misses entirely. STOP-level.
- **`rm -rf` in committed scripts** — Claude writes aggressive cleanup without knowing prod paths. Flagged in `.sh`, `Makefile`, CI configs.
- **`throw "string"` without Error** — loses the stack trace. Production bugs become permanently undiagnosable.

Pre-commit hook: 21 checks total. **This is the complete surface** — beyond here, you need a real SAST tool.

---

## v1.4.0: 2 more risk categories — covers 25 total

- **TODO/FIXME stubs** — `throw new Error("TODO")`, `raise NotImplementedError`, `// TODO` in implementation files. Claude left a placeholder that will throw at runtime.
- **Commented-out code** — lines where Claude disabled working code (`// const user = ...`). Signals uncertainty — shouldn't ship.

Both checks in the pre-commit hook (18 checks total).

---

## v1.3.0: 8 more risk categories — covers 23 total

**Security holes Claude introduces:**
- `dangerouslySetInnerHTML`, `innerHTML =`, `document.write(` — XSS sinks
- `eval(` — code injection
- `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized: false` — SSL disabled
- CORS wildcard (`origin: '*'`) — API open to any domain

**Git hygiene:**
- `.gitignore` entries removed — previously ignored files (possibly secrets) now tracked

**Shortcuts Claude takes under pressure:**
- `setTimeout`/`sleep` with hardcoded numbers — timing hack, not a real fix
- `: any` / `as any` in TypeScript — type system escaped instead of fixed
- `debug: true` in non-test config — debug mode accidentally left on

All checks in the pre-commit hook. SSL bypass escalates to STOP (not PAUSE).

---

## v1.2.0: 10 new risk categories — covers 15 total

**Suppression (Claude hiding problems instead of fixing them):**
- `@ts-ignore`, `@ts-nocheck`, `eslint-disable` added to staged diff
- Empty `catch {}` blocks — errors silently swallowed

**Test integrity:**
- `.skip()`, `xit(`, `xdescribe(` — tests bypassed instead of fixed
- Test files deleted to make the suite pass

**Debug artifacts:**
- `console.log`, `debugger` left in non-test files

**Dependency hygiene:**
- Lock file changed without `package.json` (or vice versa)
- New package added — surfaced for license/security review
- Binary file staged — permanent history bloat

**Data exposure:**
- PII patterns (email, phone) on added lines
- Internal hostnames / IPs committed

**Agentic escalation:**
- `git push --force` proposed by Claude → auto-routes to ALARM
- Direct database commands proposed → auto-routes to ALARM
- CI check skipped via workflow edit → auto-routes to ALARM

All checks added to the pre-commit hook (runs without Claude).

---

## v1.1.1: Catch quality gate weakening

Real incident: PM told Claude to make GitHub checks pass. Claude lowered the coverage threshold instead of fixing the failing tests. Checks went green. Bugs stayed.

**New Danger Zone — Quality gates:** `jest.config.*`, `vitest.config.*`, `codecov.yml`, `.nycrc`, `.eslintrc.*`, `.stylelintrc.*`, `sonar-project.properties`

**New check:** When a quality config file is staged, Claude scans the diff for decreased numeric values. If a threshold dropped, it flags: *"Claude may have fixed the failing check by lowering the bar, not by fixing the code."*

**New rationalization:** `"Claude made the failing checks pass"` → Check what it changed to make them pass. Lowering a threshold is not fixing a bug.

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
| Quality gates | `jest.config.*`, `vitest.config.*`, `codecov.yml`, `.nycrc`, `.eslintrc.*`, `.stylelintrc.*`, `sonar-project.properties` |
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

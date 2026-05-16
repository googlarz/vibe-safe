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
"what does this flag mean?" / need deeper explanation → EXPLAIN mode
developer reviewing a vibe-coded PR → REVIEWER mode
checking whether past commits contain mistakes → HISTORY mode
```

Or invoke directly: `vibe-safe before / review / commit / pr / conflict / alarm / history / explain / reviewer`

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
3. **CI installation** — if no `.github/workflows/vibe-safe.yml` exists, Claude copies `ci/vibe-safe-ci.sh` to `.github/vibe-safe/` and `ci/workflow.yml` to `.github/workflows/vibe-safe.yml`. This runs the same checks in GitHub Actions on every push and PR — closing the `git commit --no-verify` bypass gap. The hook can be skipped; CI cannot.
4. **`.vibesafe` generation** — if no `.vibesafe` exists, Claude asks:
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
| Credential pattern | `src/api/client.ts:14 — const API_KEY = "sk-proj-abc123"` ⛔ Permanent in git history even if deleted |
| File deletion | `src/utils/helper.ts deleted` — Claude may be wrong that it's unused |
| Config file modified | `config/nginx.conf` — controls production traffic for everyone |
| Migration file present | `db/migrations/*.sql` — irreversible schema change |
| Auth-related file | `src/auth/session.ts` — security surface, needs developer eyes |
| Scope creep | Files modified that weren't in your original target |
| Quality gate weakening | `jest.config.ts: threshold 80 → 60` ⛔ Claude fixed the check, not the bug |
| Error suppression | `src/api/client.ts:23 — // @ts-ignore` ⛔ Type error hidden, not fixed |
| Linter suppression | `src/Form.tsx:7 — // eslint-disable-next-line` ⛔ Lint error hidden, not fixed |
| Test bypass | `auth.test.ts:45 — it.skip("validates token"...)` ⛔ Failing test skipped, not fixed |
| Test deletion | `tests/payment.test.ts deleted` ⛔ Entire test file removed to make suite pass |
| Debug output | `src/Form.tsx:12 — console.log(userData)` ⛔ Logs production data, may expose PII |
| Empty catch block | `src/api/client.ts:67 — catch (e) {}` ⛔ Errors silently swallowed |
| Lock file drift | `package-lock.json changed, package.json unchanged` — undocumented dependency change |
| New dependency | `package.json: "lodash" added` — check license, security, bundle size |
| Binary/large file | `assets/video.mp4 staged` ⛔ Bloats git history permanently |
| PII in diff | `seeds/users.ts:4 — email: "john.doe@acme.com"` ⛔ Real data committed |
| Internal hostname | `config/api.ts:2 — baseURL: "http://api.internal:8080"` ⛔ Infrastructure exposed |
| Force push proposed | Claude suggested `git push --force` → ALARM immediately |
| XSS sink added | `dangerouslySetInnerHTML` added — direct XSS attack surface |
| Code injection | `eval(` added — arbitrary code execution risk |
| SSL disabled | `verify=False` / `NODE_TLS_REJECT_UNAUTHORIZED=0` / `rejectUnauthorized: false` — Claude "fixed" a cert error by disabling verification |
| CORS wildcard | `origin: '*'` / `Access-Control-Allow-Origin: *` — API open to any domain |
| `.gitignore` entries removed | Previously ignored files (possibly secrets) now tracked and will be committed |
| Timing hack | `setTimeout`/`sleep`/`time.sleep` with hardcoded value — Claude papered over a race condition |
| TypeScript type erasure | `: any` / `as any` added — Claude escaped the type system instead of fixing types |
| Debug mode in config | `DEBUG = True` / `debug: true` in non-test config — debug mode left on |
| TODO/FIXME stub | `throw new Error("TODO")` or `// TODO: implement` in new code — Claude left a placeholder |
| Commented-out code | `// const user = await getUser(id)` — working code disabled, Claude may have been unsure |
| Private key file staged | `server.pem`, `id_rsa`, `client.p12` staged ⛔ Binary credential — not caught by text grep |
| `rm -rf` in script | `rm -rf $DIR/*` in committed shell script ⛔ Aggressive cleanup Claude wrote without knowing prod paths |
| String thrown, not Error | `throw "something failed"` — loses stack trace, bugs become undiagnosable in production |

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

**Code health checks** — Claude runs these on the staged diff (`git diff --cached`), scanning only added lines (`grep "^+"`):

6. **Suppression scan** — `@ts-ignore`, `@ts-nocheck`, `eslint-disable`, `@ts-expect-error` added
   - Found → flag with line; Claude does not auto-remove (may be intentional), but requires explanation before proceeding

7. **Test bypass scan** — `.skip(`, `xit(`, `xdescribe(`, `x.test(` added
   - Found → flag: "Claude bypassed a failing test instead of fixing it"

8. **Debug artifact scan** — `console.log`, `console.error`, `console.warn`, `debugger` added
   - Found in non-test file → flag: "Debug output left in production code"

9. **Empty catch scan** — `catch\s*\(.*\)\s*\{\s*\}` or `catch\s*\{\s*\}` added
   - Found → flag: "Errors silently swallowed — failures invisible in production"

10. **Lock file drift** — `package-lock.json`/`yarn.lock`/`pnpm-lock.yaml` staged without `package.json`, or vice versa
    - Found → flag: "Manual lock file edits are almost always wrong"

11. **Binary/large file scan** — `git diff --cached --numstat` for lines showing `-	-	<filename>` (binary)
    - Found → flag: "Binary files bloat git history permanently and cannot be removed cleanly"

12. **PII scan** — added lines matching `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` (email) or `\+?[0-9]{10,}` (phone)
    - Found → flag: "Real personal data in committed code — check if this is test fixture or real user data"

13. **Internal hostname scan** — added lines matching `localhost:[0-9]+`, `192\.168\.`, `10\.[0-9]+\.`, `\.internal\b`, `\.corp\b`
    - Found → flag: "Internal infrastructure URL committed — exposes network topology"

14. **New dependency check** — `git diff --cached package.json` shows new entry in `dependencies` or `devDependencies`
    - Found → surface: name, check if it's a known package, flag for license and security review

15. **Force push guard** — if Claude ever proposes `git push --force` or `git push -f` at any point in the session: route immediately to ALARM mode

16. **XSS sink scan** — `dangerouslySetInnerHTML`, `innerHTML =`, `document.write(` added
    - Found → flag: "Direct XSS attack surface — any user-controlled input reaching this is a vulnerability"

17. **Code injection scan** — `eval(` added (JS/Python/Ruby)
    - Found → flag: "Arbitrary code execution risk — almost never the right solution"

18. **SSL bypass scan** — `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED`, `rejectUnauthorized: false`, `ssl_verify: false` added
    - Found → flag: "Claude disabled certificate verification to fix a cert error — this silently removes all TLS protection"

19. **CORS wildcard scan** — `origin: '*'`, `Access-Control-Allow-Origin: *`, `cors({ origin: true })` added
    - Found → flag: "API now accepts requests from any domain — check if this is intentional"

20. **`.gitignore` regression scan** — `git diff --cached .gitignore | grep "^-"` for removed entries
    - Lines removed → flag: "Previously ignored files are now tracked — if any are secrets, they'll be committed on the next add"

21. **Timing hack scan** — `setTimeout(`, `sleep(`, `time.sleep(`, `asyncio.sleep(` with a hardcoded numeric argument added
    - Found → flag: "Hardcoded delay — Claude may have papered over a race condition rather than fixing the root cause"

22. **Type erasure scan** — `: any` or `as any` added (TypeScript files only)
    - More than 2 occurrences in one diff → flag: "Claude may have escaped the type system to avoid fixing type errors"

23. **Debug mode scan** — `DEBUG = True`, `debug: true`, `APP_ENV=development` added in non-test config files
    - Found → flag: "Debug mode in a non-test file — check this isn't heading to production"

24. **TODO/FIXME stub scan** — `throw new Error("TODO")`, `raise NotImplementedError`, `// TODO`, `# FIXME` in implementation files (not `.md`, not test files)
    - Found → flag: "Claude left a placeholder instead of implementing — this will fail at runtime"

25. **Commented-out code scan** — added lines matching `// <code-keyword>` or `# <code-keyword>` where keyword is `const`, `let`, `var`, `function`, `return`, `import`, `export`, `if`, `for`, `while`, `class`, `def`, `async`
    - Found → flag: "Claude commented out working code — may indicate uncertainty about the change"

26. **Private key file scan** — `git diff --cached --name-only` for `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.jks`, `id_rsa`, `id_ed25519`, `*.crt`, `*.cer`
    - Found → **STOP**: "Binary credential file staged — not caught by text grep. Private keys in git history are compromised permanently."

27. **Destructive command scan** — `rm -rf` in staged `.sh`, `Makefile`, `.github/workflows/`, or any script file
    - Found → flag: "Claude wrote an aggressive delete command — verify the path is not production data before committing"

28. **String throw scan** — `throw "` or `throw '` (not `throw new`) in JavaScript/TypeScript files
    - Found → flag: "String thrown instead of Error object — stack trace is lost, this bug will be undiagnosable in production"

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

**Auto-escalate to ALARM — no questions needed:**
- Claude proposes `git push --force` or `git push -f` for any reason
- Claude proposes `git commit --no-verify` for any reason — this skips all 21 hook checks
- Claude proposes running a direct database command (`psql`, `rails db:`, `knex migrate`)
- Claude proposes modifying `.github/workflows/` to skip a failing check

---

## Mode: HISTORY

Scans recent git history for past mistakes that need active remediation — not just the current state.

Claude runs:
- `git log -S "sk-|pk_|ghp_|AKIA|api_key|secret|password" --oneline -50` — finds commits that added or removed credential patterns. A key "deleted" in commit B is still readable in commit A.
- `git log --grep="fix\|remove\|revert\|oops\|secret\|key\|credential\|token" --oneline -20` — finds commits whose messages hint at past cleanup attempts
- `git log --diff-filter=D --name-only --format="" -30` — finds files deleted in recent commits (possible sensitive data removal)

For each flagged commit, Claude distinguishes:
- **Active exposure** — credential still present in HEAD (STOP: rotate immediately)
- **Historical exposure** — removed in a later commit but still readable in history (requires key rotation + `git filter-repo` to scrub, plus force-push and re-clone for all team members)
- **Likely clean** — no pattern found

Historical exposure output includes exact remediation steps: rotate the key, run `git filter-repo`, force-push, notify anyone who cloned.

---

## Mode: EXPLAIN

When a vibe-safe flag fires and you don't understand what it means or what to do about it.

Invoke: `vibe-safe explain <topic>` — e.g., `vibe-safe explain credential`, `vibe-safe explain ssl`, `vibe-safe explain ts-ignore`, `vibe-safe explain empty catch`

Claude provides:
- **What it is** — plain English, no jargon
- **Why it matters** — concrete worst-case scenario in non-technical terms
- **What it looks like when it goes wrong** — a real example
- **The proper fix** — not just "don't do this" but what Claude should have done instead
- **One sentence for your developer** — how to communicate the risk without needing to explain the full technical detail yourself

---

## Mode: REVIEWER

For developers reviewing a pull request opened by a non-technical contributor.

Claude reads `git diff main...HEAD` and produces a developer-facing summary:

- **What the PM intended** — derived from branch name, commit messages, and file scope
- **What actually changed** — file-by-file summary in developer language
- **Risk surface** — which vibe-safe patterns are present in the diff, ranked by severity
- **What to specifically test** — derived from changed logic paths, file types, and risk level
- **Questions to ask the PM** — if stated intent and actual diff don't match, surfaces the discrepancy

Invoke as the developer before approving a PR: `vibe-safe reviewer`

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
| "It's just a ts-ignore, it'll be fine" | Suppressed errors accumulate into unfixable technical debt |
| "I'll remove the console.log later" | Later doesn't happen; debug logs leak data in production |
| "The test was probably out of date anyway" | Claude skipped it because it was failing, not because it was wrong |
| "It's just push --force on my branch" | If anyone else pulled that branch, their work is gone |
| "verify=False is just for testing" | It was in the diff — check if it's going to production |
| "The any type is fine for now" | Type debt compounds; Claude added it to avoid fixing the real error |
| "The sleep just makes it more reliable" | Timing hacks hide bugs and make tests slow and flaky |
| "I'll implement that part later" | Claude shipped a placeholder — it will throw at runtime |
| "That code was probably dead anyway" | Commented-out code means Claude wasn't sure — don't ship uncertainty |
| "The rm -rf is scoped to a temp dir" | Verify that before it runs in CI against a production path |
| "throw is throw, same thing" | String throws lose the stack trace — production bugs become invisible |
| "The hook keeps failing so I'll use --no-verify" | Skipping the hook skips all 21 checks — find out why it's failing instead |
| "It's fine, I checked git history and deleted it" | Deleted ≠ gone — run HISTORY mode to confirm and get remediation steps |

---

## Mode: VERIFY

**Invoke after any vibe-safe session to confirm the session is clean.**

Claude runs:
- `git branch --show-current` — confirms not on main/master
- `git diff main...HEAD --name-only` — lists every file that will be in the PR
- `git grep -nE "sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="` — final credential sweep
- `git log --oneline -3` — confirms commit messages are descriptive

Output: **CLEAN** or remaining flags with specific file:line evidence.

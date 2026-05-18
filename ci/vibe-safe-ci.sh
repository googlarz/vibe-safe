#!/bin/sh
# vibe-safe CI script — same checks as hooks/pre-commit, adapted for GitHub Actions
# Install: copy to .github/vibe-safe/vibe-safe-ci.sh in your repo
# Usage: BASE_BRANCH=main sh .github/vibe-safe/vibe-safe-ci.sh

BASE_BRANCH="${BASE_BRANCH:-${GITHUB_BASE_REF:-${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-${BITBUCKET_PR_DESTINATION_BRANCH:-main}}}}"
CRED_PATTERN="sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="
VIBESAFE_VERSION="1.9.0"

# Use GH_TOKEN or GITHUB_TOKEN (GitHub Actions sets GITHUB_TOKEN automatically)
GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

# Detect CI system
CI_SYSTEM="generic"
[ -n "$GITHUB_ACTIONS" ] && CI_SYSTEM="github"
[ -n "$GITLAB_CI" ] && CI_SYSTEM="gitlab"
[ -n "$BITBUCKET_BUILD_NUMBER" ] && CI_SYSTEM="bitbucket"

_annotation_error() {
  case "$CI_SYSTEM" in
    github) echo "::error::vibe-safe: $1" ;;
    gitlab) printf '\033[31mERROR\033[0m vibe-safe: %s\n' "$1" ;;
    *) echo "ERROR: vibe-safe: $1" ;;
  esac
}

_annotation_warn() {
  case "$CI_SYSTEM" in
    github) echo "::warning::vibe-safe: $1" ;;
    gitlab) printf '\033[33mWARN\033[0m  vibe-safe: %s\n' "$1" ;;
    *) echo "WARN:  vibe-safe: $1" ;;
  esac
}

FAILED=0
FINDINGS=""

fail() {
  _annotation_error "$1"
  printf '%s\n' "$2"
  echo ""
  echo "$3"
  echo ""
  FAILED=1
  FINDINGS="${FINDINGS}❌ **STOP** — $1
"
}

warn() {
  _annotation_warn "$1"
  printf '%s\n' "$2"
  echo ""
  FINDINGS="${FINDINGS}⚠️  $1
"
}

# Get changed files and diff vs base branch
git fetch origin "$BASE_BRANCH" --depth=1 2>/dev/null || true
CHANGED_FILES=$(git diff --name-only "origin/$BASE_BRANCH"...HEAD 2>/dev/null)
DIFF=$(git diff "origin/$BASE_BRANCH"...HEAD 2>/dev/null)
ADDED=$(echo "$DIFF" | grep "^+" | grep -v "^+++" 2>/dev/null)

# 1. Credential scan — ALL tracked files (not just changed)
CREDS=$(git grep -nE "$CRED_PATTERN" 2>/dev/null)
if [ -n "$CREDS" ]; then
  fail "STOP — credential pattern in tracked files" "$CREDS" \
    "Rotate this credential immediately — git history is permanent even after deletion."
fi

# ─── Optional tooling (graceful degradation when not installed) ────────────────

# T1. gitleaks — entropy-based credential detection (catches what grep misses)
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks detect --no-git --source . --quiet 2>/dev/null; then
    fail "STOP — gitleaks found high-entropy credential pattern" "" \
      "Run: gitleaks detect --verbose for details. Rotate any exposed secrets."
  fi
fi

# T2. semgrep — rule-based security analysis
if command -v semgrep >/dev/null 2>&1; then
  if ! semgrep --config=auto --quiet --error . 2>/dev/null; then
    fail "STOP — semgrep flagged a security issue" "" \
      "Run: semgrep --config=auto . for details."
  fi
fi

# T3. npm audit — known CVEs in dependencies
if [ -n "$PKG" ] && command -v npm >/dev/null 2>&1; then
  AUDIT_OUT=$(npm audit --audit-level=high --json 2>/dev/null)
  if echo "$AUDIT_OUT" | grep -q '"severity":"high"\|"severity":"critical"'; then
    fail "STOP — npm audit found high/critical vulnerability" "" \
      "Run: npm audit for details and upgrade paths."
  fi
fi

# 2. Danger zone files (warning in CI — PR review is the gate)
DANGER=""
for f in $CHANGED_FILES; do
  case "$f" in
    .env|.env.local|.env.production|.env.staging|.env.development|*.conf|Dockerfile|docker-compose*|\
    .github/workflows/*|Jenkinsfile|.circleci/*|.gitlab-ci.yml|\
    */migrations/*|*/schema/*|*.sql|\
    webpack.config.*|vite.config.*|tsconfig.json|\
    jest.config.*|vitest.config.*|codecov.yml|.nycrc|sonar-project.properties|\
    package.json|Gemfile|requirements.txt)
      DANGER="${DANGER:+$DANGER
}  $f"
      ;;
  esac
  BASENAME=$(basename "$f" | tr '[:upper:]' '[:lower:]')
  case "$BASENAME" in
    *auth*|*login*|*session*|*jwt*|*oauth*|*permission*|*role*)
      DANGER="${DANGER:+$DANGER
}  $f (auth/security)" ;;
    .eslintrc*|.stylelintrc*)
      DANGER="${DANGER:+$DANGER
}  $f (quality-gate)" ;;
  esac
  if [ -f ".vibesafe" ]; then
    while IFS= read -r line; do
      case "$line" in
        danger_zone:*)
          ZONE=$(echo "$line" | sed 's/^danger_zone:[[:space:]]*//')
          case "$f" in ${ZONE}*)
            DANGER="${DANGER:+$DANGER
}  $f (custom: $ZONE)" ;;
          esac ;;
      esac
    done < .vibesafe
  fi
done
[ -n "$DANGER" ] && warn "Danger Zone files changed — developer review required" "$DANGER"

# 3. Error suppression
SUPPRESS=$(echo "$ADDED" | grep -E "@ts-ignore|@ts-nocheck|@ts-expect-error|eslint-disable" 2>/dev/null)
[ -n "$SUPPRESS" ] && warn "Error suppression added (needs developer review)" "$SUPPRESS"

# 4. Test bypass — hard failure
SKIP=$(echo "$ADDED" | grep -E "\.skip\(|[^a-z]xit\(|[^a-z]xdescribe\(|[^a-z]xtest\(" 2>/dev/null)
[ -n "$SKIP" ] && fail "STOP — tests bypassed" "$SKIP" "Fix the failing tests instead of skipping them."

# 5. Debug artifacts
DEBUG=$(echo "$ADDED" | grep -E "console\.(log|error|warn|debug)|debugger;" 2>/dev/null)
[ -n "$DEBUG" ] && warn "Debug output in changes — remove before merge" "$DEBUG"

# 6. Empty catch — hard failure
EMPTY_CATCH=$(echo "$ADDED" | grep -E "catch\s*\(\w*\)\s*\{[[:space:]]*\}|catch\s*\{[[:space:]]*\}" 2>/dev/null)
[ -n "$EMPTY_CATCH" ] && fail "STOP — empty catch block" "$EMPTY_CATCH" "Errors silently swallowed. Handle or rethrow."

# 7. Lock file drift
LOCK=$(echo "$CHANGED_FILES" | grep -E "package-lock\.json|yarn\.lock|pnpm-lock\.yaml" 2>/dev/null)
PKG=$(echo "$CHANGED_FILES" | grep "^package\.json$" 2>/dev/null)
[ -n "$LOCK" ] && [ -z "$PKG" ] && fail "STOP — lock file changed without package.json" "$LOCK" "Manual lock edits are almost always wrong."

# 8. Binary files
BINARY=$(git diff --numstat "origin/$BASE_BRANCH"...HEAD 2>/dev/null | awk '$1 == "-" && $2 == "-" {print "  " $3}')
[ -n "$BINARY" ] && warn "Binary files added — verify intentional" "$BINARY"

# 9. XSS sinks — hard failure
XSS=$(echo "$ADDED" | grep -E "dangerouslySetInnerHTML|innerHTML\s*=|document\.write\(" 2>/dev/null)
[ -n "$XSS" ] && fail "STOP — XSS sink added" "$XSS" "Any user input reaching this is a vulnerability."

# 10. eval() — hard failure
EVAL=$(echo "$ADDED" | grep -E "\beval\(" 2>/dev/null)
[ -n "$EVAL" ] && fail "STOP — eval() added" "$EVAL" "Arbitrary code execution risk."

# 11. SSL bypass — hard failure
SSL=$(echo "$ADDED" | grep -E "verify=False|NODE_TLS_REJECT_UNAUTHORIZED|rejectUnauthorized:\s*false|ssl_verify:\s*false" 2>/dev/null)
[ -n "$SSL" ] && fail "STOP — SSL verification disabled" "$SSL" "Never disable TLS verification in production code."

# 12. CORS wildcard
CORS=$(echo "$ADDED" | grep -E "origin:\s*['\"]?\*['\"]?|Access-Control-Allow-Origin:\s*\*" 2>/dev/null)
[ -n "$CORS" ] && warn "CORS wildcard added — verify intentional" "$CORS"

# 13. Private key files — hard failure
KEY_EXT=$(echo "$CHANGED_FILES" | grep -iE "\.(pem|key|pfx|p12|jks|crt|cer)$|/(id_rsa|id_ed25519|id_dsa|id_ecdsa)$" 2>/dev/null)
[ -n "$KEY_EXT" ] && fail "STOP — private key or certificate file staged" "$KEY_EXT" "Never commit private keys. Rotate immediately if pushed."

# 14. rm -rf in scripts
SCRIPT_CHANGES=$(echo "$CHANGED_FILES" | grep -E "\.(sh|bash|zsh|mk)$|^Makefile$|\.github/workflows/" 2>/dev/null)
if [ -n "$SCRIPT_CHANGES" ]; then
  RMRF=$(echo "$ADDED" | grep -E "rm\s+-rf?\s+" 2>/dev/null)
  [ -n "$RMRF" ] && warn "rm -rf in script — verify path safety" "$RMRF"
fi

# 15. String throws in JS/TS
JS_CHANGES=$(echo "$CHANGED_FILES" | grep -E "\.(js|ts|jsx|tsx|mjs|cjs)$" 2>/dev/null)
if [ -n "$JS_CHANGES" ]; then
  STRING_THROW=$(echo "$ADDED" | grep -E "throw\s+['\"]" 2>/dev/null)
  [ -n "$STRING_THROW" ] && warn "String thrown instead of Error — loses stack trace" "$STRING_THROW"
fi

# 16. Quality gate weakening
QUALITY_CHANGES=$(echo "$CHANGED_FILES" | grep -E "jest\.config|vitest\.config|codecov\.yml|\.nycrc|sonar|pytest\.ini|setup\.cfg|pyproject\.toml|\.coveragerc" 2>/dev/null)
if [ -n "$QUALITY_CHANGES" ]; then
  THRESHOLD_DROP=$(echo "$DIFF" | grep "^-" | grep -v "^---" | grep -E "[0-9]" 2>/dev/null)
  [ -n "$THRESHOLD_DROP" ] && warn "Numeric value decreased in quality config — check for threshold lowering" "$THRESHOLD_DROP"
fi

# 16b. Coverage threshold drop — --cov-fail-under in any changed file (CI YAML, tox.ini, Makefile, etc.)
COV_DROP=$(echo "$DIFF" | grep "^-" | grep -v "^---" | grep -E "\-\-cov-fail-under[= ][0-9]|cov_fail_under[[:space:]]*=[[:space:]]*[0-9]|fail_under[[:space:]]*=[[:space:]]*[0-9]" 2>/dev/null)
[ -n "$COV_DROP" ] && warn "Coverage threshold lowered (--cov-fail-under decreased) — verify this wasn't done to make CI pass" "$COV_DROP"

# 17. .env.example drift
ENV_REFS=$(echo "$ADDED" | grep -E "process\.env\.|os\.environ\[|getenv\(|import\.meta\.env\." 2>/dev/null)
if [ -n "$ENV_REFS" ]; then
  ENV_EXAMPLE_CHANGED=$(echo "$CHANGED_FILES" | grep -E "^\.env\.example$|^\.env\.sample$" 2>/dev/null)
  if [ -z "$ENV_EXAMPLE_CHANGED" ]; then
    fail "STOP — new env variable without .env.example update" "$ENV_REFS" \
      "Other developers won't know to set this variable. Add it to .env.example first."
  fi
fi

# 18. Migration rollback check
MIGRATION_FILES=$(echo "$CHANGED_FILES" | grep -E "migrations/|db/migrate/|_migration\." 2>/dev/null)
REQ_ROLLBACK=$([ -f ".vibesafe" ] && grep "^require_migration_rollback:[[:space:]]*true" .vibesafe 2>/dev/null || true)
if [ -n "$MIGRATION_FILES" ]; then
  for mf in $MIGRATION_FILES; do
    if grep -q "from django.db import migrations" "$mf" 2>/dev/null; then
      continue
    fi
    if ! grep -qiE "def down|def downgrade|exports\.down|\.down\(|rollback\(|-- Down" "$mf" 2>/dev/null; then
      if [ -n "$REQ_ROLLBACK" ]; then
        fail "STOP — developer contract: migration without rollback" "$mf" \
          "Team requires all migrations to include a down/downgrade/rollback function."
      else
        warn "Migration without rollback — schema change cannot be undone automatically" "$mf"
      fi
    fi
  done
fi

# 19. Developer contracts from .vibesafe
if [ -f ".vibesafe" ]; then
  # max_changed_files
  MAX=$(grep "^max_changed_files:" .vibesafe 2>/dev/null | sed 's/.*:[[:space:]]*//' | head -1)
  if [ -n "$MAX" ]; then
    FILE_COUNT=0
    if [ -n "$CHANGED_FILES" ]; then
      FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
    fi
    if [ "$FILE_COUNT" -gt "$MAX" ]; then
      warn "Developer contract: max_changed_files=$MAX exceeded ($FILE_COUNT files changed)" "$CHANGED_FILES"
    fi
  fi
  # block_pattern — check per implementation file (skips test/md files)
  while IFS= read -r line; do
    case "$line" in
      block_pattern:*)
        PAT=$(echo "$line" | sed 's/^block_pattern:[[:space:]]*//')
        BLOCKED=""
        for cf in $CHANGED_FILES; do
          case "$cf" in
            *.test.*|*.spec.*|*__tests__*|*_test.*|*.md|*.txt|.vibesafe) continue ;;
          esac
          FILE_ADDED=$(git diff "origin/$BASE_BRANCH"...HEAD -- "$cf" 2>/dev/null | grep "^+" | grep -v "^+++" 2>/dev/null)
          MATCH=$(echo "$FILE_ADDED" | grep -F "$PAT" 2>/dev/null)
          if [ -n "$MATCH" ]; then
            BLOCKED="${BLOCKED:+$BLOCKED
}$cf: $MATCH"
          fi
        done
        [ -n "$BLOCKED" ] && fail "STOP — developer contract: blocked pattern '$PAT' in added code" "$BLOCKED" \
          "Team has blocked this pattern. Remove it before merging."
        ;;
    esac
  done < .vibesafe
  # require_tests
  REQ_TESTS=$(grep "^require_tests:[[:space:]]*true" .vibesafe 2>/dev/null)
  if [ -n "$REQ_TESTS" ]; then
    SRC_FILES=$(echo "$CHANGED_FILES" | grep -E "\.(js|ts|jsx|tsx|py|rb|go|rs|java|cs)$" | grep -v -E "\.(test|spec)\.|_test\." 2>/dev/null)
    TEST_FILES=$(echo "$CHANGED_FILES" | grep -E "\.(test|spec)\.|_test\.|/tests/|/__tests__/" 2>/dev/null)
    if [ -n "$SRC_FILES" ] && [ -z "$TEST_FILES" ]; then
      fail "STOP — developer contract: require_tests=true, no test files in PR" "$SRC_FILES" \
        "Team requires test changes alongside source changes."
    fi
  fi
fi

# 20. require_reviewer — enforced when GH_TOKEN + PR_NUMBER are available
if [ -f ".vibesafe" ]; then
  REQ_REVIEWER=$(grep "^require_reviewer:" .vibesafe 2>/dev/null | sed 's/^require_reviewer:[[:space:]]*//')
  if [ -n "$REQ_REVIEWER" ]; then
    if [ -n "$GH_TOKEN" ] && [ -n "$PR_NUMBER" ] && [ -n "$GITHUB_REPOSITORY" ] && [ "$CI_SYSTEM" = "github" ]; then
      REQUESTED=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/requested_reviewers" \
        --jq '.users[].login' 2>/dev/null)
      REVIEWED=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" \
        --jq '.[].user.login' 2>/dev/null)
      for reviewer in $REQ_REVIEWER; do
        login=$(echo "$reviewer" | tr -d '@')
        if ! printf '%s\n%s\n' "$REQUESTED" "$REVIEWED" | grep -qx "$login"; then
          fail "STOP — developer contract: required reviewer @${login} not assigned" "" \
            "Add @${login} as a reviewer before merging."
        fi
      done
    else
      warn "require_reviewer=${REQ_REVIEWER} — skipped (GitHub token or PR number not available)" ""
    fi
  fi
fi

# 21. Missing await on async calls (common Claude bug)
JS_CHANGES=$(echo "$CHANGED_FILES" | grep -E "\.(js|ts|jsx|tsx|mjs|cjs)$" 2>/dev/null)
if [ -n "$JS_CHANGES" ]; then
  MISSING_AWAIT=""
  for sf in $JS_CHANGES; do
    FILE_ADDED=$(git diff "origin/$BASE_BRANCH"...HEAD -- "$sf" 2>/dev/null | grep "^+" | grep -v "^+++")
    MATCH=$(echo "$FILE_ADDED" | grep -E "=[[:space:]]*(fetch|axios\.(get|post|put|delete|patch)|prisma\.[a-zA-Z]+\.(find|create|update|delete|upsert|count|findFirst|findMany|aggregate)|db\.(query|execute|run|all|get))\(" 2>/dev/null | grep -v "await")
    [ -n "$MATCH" ] && MISSING_AWAIT="${MISSING_AWAIT:+$MISSING_AWAIT
}$sf: $MATCH"
  done
  [ -n "$MISSING_AWAIT" ] && warn "Possible missing await on async call — result may be a Promise, not a value" "$MISSING_AWAIT"
fi

# 22. Math.random() in security-sensitive file
SEC_RAND=$(echo "$ADDED" | grep -E "Math\.random\(\)" 2>/dev/null)
if [ -n "$SEC_RAND" ]; then
  SEC_FILES=$(echo "$CHANGED_FILES" | grep -iE "auth|token|session|crypto|key|secret|password" 2>/dev/null)
  if [ -n "$SEC_FILES" ]; then
    fail "STOP — Math.random() in security-related file" "$SEC_RAND" \
      "Use crypto.randomBytes() or crypto.randomUUID() — Math.random() is not cryptographically secure."
  fi
fi

# 23. SQL string concatenation (injection risk)
SQLI=$(echo "$ADDED" | grep -v -E "^(\+[[:space:]]*)?(#|//|\*)" | grep -E "['\"]([[:space:]]*(SELECT|INSERT|UPDATE|DELETE|WHERE))[^'\"]*['\"][[:space:]]*\+|f['\x27](SELECT|INSERT|UPDATE|DELETE).*\{" 2>/dev/null)
[ -n "$SQLI" ] && fail "STOP — SQL string concatenation" "$SQLI" \
  "Use parameterized queries / prepared statements. String-built SQL is injectable."

# 24. Shell injection risk
SHELL_INJ=$(echo "$ADDED" | grep -E "shell:[[:space:]]*true|shell=True|subprocess.*shell=True" 2>/dev/null)
[ -n "$SHELL_INJ" ] && fail "STOP — shell:true passes command through /bin/sh — unsanitized input becomes code execution" "$SHELL_INJ" \
  "Pass command as an array instead of a string, and do not set shell:true."

# 25. Test file changed with no assertions
TEST_CHANGED=$(echo "$CHANGED_FILES" | grep -E "\.(test|spec)\.(js|ts|jsx|tsx)$|_test\.(js|ts|py|go|rb)$" 2>/dev/null)
if [ -n "$TEST_CHANGED" ]; then
  for tf in $TEST_CHANGED; do
    FILE_ADDED=$(git diff "origin/$BASE_BRANCH"...HEAD -- "$tf" 2>/dev/null | grep "^+" | grep -v "^+++")
    HAS_TEST=$(echo "$FILE_ADDED" | grep -E "it\(|test\(|describe\(" 2>/dev/null)
    HAS_ASSERT=$(echo "$FILE_ADDED" | grep -E "expect\(|assert\.|\.toBe|\.toEqual|\.toHaveBeenCalled|\.toThrow|\.toMatch" 2>/dev/null)
    [ -n "$HAS_TEST" ] && [ -z "$HAS_ASSERT" ] && \
      warn "Test added without assertions in $tf — test always passes regardless of behavior" "$tf"
  done
fi

# ─── Step summary + PR comment ────────────────────────────────────────────────

if [ "$FAILED" = "1" ]; then
  AUDIT_STATUS="❌ Failed"
  AUDIT_NOTE="**Fix blocking issues above before merging.**"
else
  AUDIT_STATUS="✅ Passed"
  AUDIT_NOTE="All checks passed — clear to merge."
fi

COMMENT_BODY="<!-- vibe-safe-audit -->
## vibe-safe audit — ${AUDIT_STATUS}

${FINDINGS:-No issues found.}
${AUDIT_NOTE}

---
*[vibe-safe](https://github.com/googlarz/vibe-safe) v${VIBESAFE_VERSION}*"

# Write to job summary (CI-system-aware)
if [ "$CI_SYSTEM" = "github" ] && [ -n "$GITHUB_STEP_SUMMARY" ]; then
  printf '%s\n' "$COMMENT_BODY" >> "$GITHUB_STEP_SUMMARY"
elif [ "$CI_SYSTEM" = "gitlab" ]; then
  # GitLab: write to job log section (no native step summary)
  echo "$COMMENT_BODY"
fi

# Post or update PR/MR comment
case "$CI_SYSTEM" in
  github)
    if [ -n "$GH_TOKEN" ] && [ -n "$PR_NUMBER" ] && [ -n "$GITHUB_REPOSITORY" ]; then
      EXISTING_ID=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
        --jq '.[] | select(.body | startswith("<!-- vibe-safe-audit -->")) | .id' 2>/dev/null | head -1)
      BODY_FILE=$(mktemp)
      printf '%s' "$COMMENT_BODY" > "$BODY_FILE"
      if [ -n "$EXISTING_ID" ]; then
        gh api "repos/$GITHUB_REPOSITORY/issues/comments/$EXISTING_ID" \
          -X PATCH --input "$BODY_FILE" >/dev/null 2>&1 \
          && echo "vibe-safe: PR comment updated" \
          || echo "vibe-safe: PR comment update skipped (fork PR — token is read-only)"
      else
        gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
          --input "$BODY_FILE" >/dev/null 2>&1 \
          && echo "vibe-safe: PR comment posted" \
          || echo "vibe-safe: PR comment post skipped (fork PR — token is read-only)"
      fi
      rm -f "$BODY_FILE"
    fi
    ;;
  gitlab)
    if [ -n "$GITLAB_TOKEN" ] && [ -n "$CI_MERGE_REQUEST_IID" ] && [ -n "$CI_PROJECT_ID" ]; then
      GL_BODY_FILE=$(mktemp)
      printf '%s' "$COMMENT_BODY" > "$GL_BODY_FILE"
      curl -s -X POST \
        "${CI_SERVER_URL:-https://gitlab.com}/api/v4/projects/$CI_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID/notes" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -F "body=<$GL_BODY_FILE" >/dev/null 2>&1 \
        && echo "vibe-safe: MR note posted" \
        || echo "vibe-safe: MR note post skipped"
      rm -f "$GL_BODY_FILE"
    fi
    ;;
  bitbucket)
    if [ -n "$BITBUCKET_TOKEN" ] && [ -n "$BITBUCKET_PR_ID" ] && [ -n "$BITBUCKET_REPO_FULL_NAME" ]; then
      BB_BODY_FILE=$(mktemp)
      printf '{"content":{"raw":"%s"}}' \
        "$(printf '%s' "$COMMENT_BODY" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n",$0}')" \
        > "$BB_BODY_FILE"
      curl -s -X POST \
        "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_REPO_FULL_NAME/pullrequests/$BITBUCKET_PR_ID/comments" \
        -H "Authorization: Bearer $BITBUCKET_TOKEN" \
        -H "Content-Type: application/json" \
        --data "@$BB_BODY_FILE" >/dev/null 2>&1 \
        && echo "vibe-safe: PR comment posted" \
        || echo "vibe-safe: PR comment post skipped"
      rm -f "$BB_BODY_FILE"
    fi
    ;;
esac

echo ""
if [ "$FAILED" = "1" ]; then
  echo "vibe-safe: FAILED — fix the issues above before merging"
  exit 1
else
  echo "vibe-safe: all checks passed"
fi

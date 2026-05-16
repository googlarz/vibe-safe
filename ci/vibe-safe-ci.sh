#!/bin/sh
# vibe-safe CI script — same checks as hooks/pre-commit, adapted for GitHub Actions
# Install: copy to .github/vibe-safe/vibe-safe-ci.sh in your repo
# Usage: BASE_BRANCH=main sh .github/vibe-safe/vibe-safe-ci.sh

BASE_BRANCH="${BASE_BRANCH:-${GITHUB_BASE_REF:-main}}"
CRED_PATTERN="sk-|pk_|ghp_|AKIA|api_key[[:space:]]*=|secret[[:space:]]*=|password[[:space:]]*=|Bearer |token[[:space:]]*="

# GitHub Actions annotation helpers
fail() {
  echo "::error::vibe-safe: $1"
  printf '%s\n' "$2"
  echo ""
  echo "$3"
  echo ""
  FAILED=1
}

warn() {
  echo "::warning::vibe-safe: $1"
  printf '%s\n' "$2"
  echo ""
}

FAILED=0

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

# 2. Danger zone files (warning in CI — PR review is the gate)
DANGER=""
for f in $CHANGED_FILES; do
  case "$f" in
    .env|.env.*|*.conf|Dockerfile|docker-compose*|\
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
QUALITY_CHANGES=$(echo "$CHANGED_FILES" | grep -E "jest\.config|vitest\.config|codecov\.yml|\.nycrc|sonar" 2>/dev/null)
if [ -n "$QUALITY_CHANGES" ]; then
  THRESHOLD_DROP=$(echo "$DIFF" | grep "^-" | grep -E "[0-9]" 2>/dev/null)
  [ -n "$THRESHOLD_DROP" ] && warn "Numeric value decreased in quality config — check for threshold lowering" "$THRESHOLD_DROP"
fi

# 17. .env.example drift
ENV_REFS=$(echo "$ADDED" | grep -E "process\.env\.|os\.environ\[|getenv\(|import\.meta\.env\." 2>/dev/null)
if [ -n "$ENV_REFS" ]; then
  ENV_EXAMPLE_CHANGED=$(echo "$CHANGED_FILES" | grep -E "^\.env\.example$|^\.env\.sample$" 2>/dev/null)
  if [ -z "$ENV_EXAMPLE_CHANGED" ]; then
    warn "New env variable referenced without .env.example update" "$ENV_REFS"
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
    FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c "." 2>/dev/null || echo 0)
    if [ "$FILE_COUNT" -gt "$MAX" ]; then
      warn "Developer contract: max_changed_files=$MAX exceeded ($FILE_COUNT files changed)" "$CHANGED_FILES"
    fi
  fi
  # block_pattern
  while IFS= read -r line; do
    case "$line" in
      block_pattern:*)
        PAT=$(echo "$line" | sed 's/^block_pattern:[[:space:]]*//')
        IMPL_ADDED=$(echo "$ADDED" | grep -v -iE "\.(md|txt)$|\.(test|spec)\.|__tests__" 2>/dev/null)
        BLOCKED=$(echo "$IMPL_ADDED" | grep -F "$PAT" 2>/dev/null)
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

echo ""
if [ "$FAILED" = "1" ]; then
  echo "vibe-safe: FAILED — fix the issues above before merging"
  exit 1
else
  echo "vibe-safe: all checks passed"
fi

#!/usr/bin/env bash
# tests/check_readme_links.sh
# Portable README validation focusing on links and structure introduced/changed in the PR diff.
# Framework: POSIX shell (no external test framework required). Uses curl/grep/sed/awk.
# To run: bash tests/check_readme_links.sh
# Env:
#   README_PATH=path/to/README.md   # override detection
#   SKIP_NETWORK=1                  # skip HTTP checks if network not allowed
#   REMOTE_LINK_TIMEOUT=20          # curl timeout seconds (default 20)

set -uo pipefail

FAILURES=0

info()  { echo "[INFO] $*"; }
pass()  { echo "[PASS] $*"; }
fail()  { echo "[FAIL] $*" >&2; FAILURES=$((FAILURES+1)); }

detect_readme() {
  if [ -n "${README_PATH:-}" ] && [ -f "$README_PATH" ]; then
    echo "$README_PATH"; return 0
  fi
  if [ -f "README.md" ]; then
    echo "README.md"; return 0
  fi
  # Search near the root as a fallback
  local cand
  cand="$(find . -maxdepth 2 -type f -iname "README*.md" | head -n1 || true)"
  if [ -n "$cand" ]; then
    echo "$cand"; return 0
  fi
  return 1
}

README="$(detect_readme)" || { echo "[ERROR] README not found."; exit 2; }
info "Using README: $README"

# ---------- Content assertions (structure, headings, and required text) ----------
assert_regex() {
  local pattern="$1"; local desc="$2"
  if grep -Eq "$pattern" "$README"; then pass "$desc"; else fail "$desc (missing: $pattern)"; fi
}

assert_contains() {
  local needle="$1"; local desc="$2"
  if grep -Fq "$needle" "$README"; then pass "$desc"; else fail "$desc (missing text)"; fi
}

# Sections from the diff
assert_regex '^# +Introduction to GitHub\b' 'H1 "Introduction to GitHub" present'
assert_regex '^## +Finish\b' 'H2 "Finish" section present'
assert_contains 'Get started using GitHub in less than an hour.' 'Intro short description present (emphasized)'

# HTML header/footer wrappers from the diff
assert_contains '<header>' 'Header tag present'
assert_contains '</header>' 'Header closing tag present'
assert_contains '<footer>' 'Footer tag present'
assert_contains '</footer>' 'Footer closing tag present'

# Image in Finish section (octodex collabocats)
assert_regex '<img[^>]*src=https://octodex\.github\.com/images/collabocats\.jpg' 'Finish image source is octodex collabocats'
assert_regex '<img[^>]*alt=' 'Finish image has alt text'
assert_regex '<img[^>]*width="?300"?[^>]*>' 'Finish image width is 300'
assert_regex '<img[^>]*align="?right"?[^>]*>' 'Finish image aligned right'

# Footer content and key links
assert_contains '&copy; 2024 GitHub' 'Footer copyright (© 2024 GitHub)'
assert_regex 'Get help: .*github\.com/orgs/skills/discussions/categories/introduction-to-github' 'Footer "Get help" discussion board link present'
assert_contains 'https://www.githubstatus.com/' 'Footer GitHub Status link present'
assert_regex 'contributor-covenant\.org/version/2/1/code_of_conduct/code_of_conduct\.md' 'Footer Code of Conduct v2.1 link present'
assert_contains 'https://gh.io/mit' 'Footer MIT License short link present'

# "What’s next?" resource links
assert_regex 'docs\.github\.com/account-and-profile/.*/managing-your-profile-readme' 'Managing your profile README docs link present'
assert_contains 'https://education.github.com/pack' 'Student Developer Pack link present'
assert_contains 'https://github.com/skills' 'GitHub Skills catalog link present'
assert_contains 'https://docs.github.com/en/get-started' 'GitHub Getting Started docs link present'
assert_contains 'https://github.com/explore' 'GitHub Explore link present'

# Also check that the "discussion board" link appears in the steps section
grep -Fq 'https://github.com/orgs/skills/discussions/categories/introduction-to-github' "$README" \
  && pass 'Discussion board link present in body' \
  || fail 'Discussion board link present in body'

# ---------- External link health checks ----------
if [ "${SKIP_NETWORK:-0}" != "1" ]; then
  if ! command -v curl >/dev/null 2>&1; then
    info "curl not found; skipping network checks."
  else
    info "Running external link checks (timeout: ${REMOTE_LINK_TIMEOUT:-20}s per URL)..."
    # Extract unique http(s) URLs from the README
    mapfile -t URLS < <(grep -Eo 'https?://[^") >]+' "$README" \
      | sed -E 's/[)>.,]+$//' \
      | sort -u)

    check_url() {
      local url="$1"
      local timeout="${REMOTE_LINK_TIMEOUT:-20}"
      # First try HEAD with redirects
      local code
      code="$(curl -sSIL -A 'readme-link-checker/1.0' -o /dev/null -m "$timeout" -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
      # Fallback to GET if HEAD not supported or failed
      if [[ "$code" -ge 400 || "$code" -eq 000 || "$code" -eq 405 || "$code" -eq 403 ]]; then
        code="$(curl -sSL -A 'readme-link-checker/1.0' -o /dev/null -m "$timeout" -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
      fi
      if [[ "$code" =~ ^[23][0-9][0-9]$ || "$code" =~ ^30[1-8]$ || "$code" == "200" || "$code" == "204" || "$code" == "206" ]]; then
        pass "URL OK ($code): $url"
      else
        fail "URL BAD ($code): $url"
      fi
    }

    for u in "${URLS[@]}"; do
      # Light rate limit to be kind to endpoints
      sleep 0.15
      check_url "$u"
    done
  fi
else
  info "SKIP_NETWORK=1 set; skipping external link checks."
fi

# ---------- Summary ----------
if [ "$FAILURES" -gt 0 ]; then
  echo "----------------------------------------"
  echo "[RESULT] README checks failed: $FAILURES issue(s) found."
  exit 1
else
  echo "----------------------------------------"
  echo "[RESULT] All README structure and link checks passed."
  exit 0
fi
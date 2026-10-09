#!/usr/bin/env bash

# Read-only repository audit. It reports file names and metadata, not matching
# secret values. Review the generated file before sharing it.

set -u

output_path="${1:-frappe-helpdesk-repository-audit.txt}"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: run this script from inside the repository." >&2
  exit 1
}

case "$output_path" in
  /*) ;;
  *) output_path="$PWD/$output_path" ;;
esac

temp_report="$(mktemp)" || exit 1
trap 'rm -f "$temp_report"' EXIT

section() {
  printf '\n## %s\n' "$1" >>"$temp_report"
}

run_metadata() {
  printf '\n$ %s\n' "$1" >>"$temp_report"
  shift
  "$@" >>"$temp_report" 2>&1 || printf '[command returned non-zero]\n' >>"$temp_report"
}

cd "$repo_root" || exit 1

{
  printf '# Frappe Ticketing System repository audit\n'
  printf 'Generated (UTC): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Repository root name: %s\n' "$(basename "$repo_root")"
  printf 'The report excludes matching secret values. Review it before sharing.\n'
} >"$temp_report"

section "Repository state"
run_metadata "git status --short --branch" git status --short --branch
run_metadata "git rev-parse HEAD" git rev-parse HEAD
run_metadata "git count-objects -v" git count-objects -v

section "Files in the current review set"
run_metadata "git ls-files --cached --others --exclude-standard" \
  git ls-files --cached --others --exclude-standard

review_files="$(mktemp)" || exit 1
git ls-files -z --cached --others --exclude-standard >"$review_files"

section "Potentially sensitive current-tree file names"
candidate_files="$(tr '\0' '\n' <"$review_files" | grep -Ei '(^|/)(\.env|[^/]*\.(pem|key|p12|pfx|sql|sqlite|db|bak|dump|log|kdbx))$' || true)"
if [ -n "$candidate_files" ]; then
  printf '%s\n' "$candidate_files" >>"$temp_report"
else
  printf 'No matching current-tree file names found.\n' >>"$temp_report"
fi

section "Environment variable names referenced by Compose"
if [ -f docker-compose.yml ]; then
  grep -Eo '\$\{[A-Za-z_][A-Za-z0-9_]*' docker-compose.yml \
    | sed 's/^${//' \
    | sort -u >>"$temp_report" || true
else
  printf 'docker-compose.yml is absent.\n' >>"$temp_report"
fi

section "Files containing installation-specific identifiers"
identifier_file="${REPOSITORY_AUDIT_IDENTIFIERS_FILE:-.audit-identifiers}"
if [ -f "$identifier_file" ]; then
  privacy_files="$(xargs -0 grep -Il -F -f "$identifier_file" <"$review_files" 2>/dev/null || true)"
  if [ -n "$privacy_files" ]; then
    printf '%s\n' "$privacy_files" >>"$temp_report"
  else
    printf 'No current-tree files matched the local identifier list.\n' >>"$temp_report"
  fi
else
  printf 'Skipped: %s is absent. Add one literal private identifier per line.\n' "$identifier_file" >>"$temp_report"
fi

section "Files containing credential-like assignments"
secret_pattern='(api[_-]?(key|secret)|password|passwd|token|private[_-]?key|client[_-]?secret)[[:space:]]*[:=]'
secret_files="$(xargs -0 grep -Il -E "$secret_pattern" <"$review_files" 2>/dev/null || true)"
if [ -n "$secret_files" ]; then
  printf '%s\n' "$secret_files" >>"$temp_report"
  printf 'These are candidates only. Inspect them locally; do not paste values into an issue.\n' >>"$temp_report"
else
  printf 'No matching current-tree files found.\n' >>"$temp_report"
fi

section "History containing installation-specific identifiers"
if [ -f "$identifier_file" ]; then
  history_matches="$(mktemp)" || exit 1
  while IFS= read -r identifier || [ -n "$identifier" ]; do
    case "$identifier" in
      ''|'#'*) continue ;;
    esac
    git log --all -S "$identifier" --format='%H' 2>/dev/null >>"$history_matches" || true
  done <"$identifier_file"
  if [ -s "$history_matches" ]; then
    sort -u "$history_matches" >>"$temp_report"
  else
    printf 'No commits matched the local identifier list.\n' >>"$temp_report"
  fi
  rm -f "$history_matches"
else
  printf 'Skipped: %s is absent.\n' "$identifier_file" >>"$temp_report"
fi

section "Compose validation"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if [ -f env.example ]; then
    run_metadata "docker compose --env-file env.example -f docker-compose.yml config --quiet" \
      docker compose --env-file env.example -f docker-compose.yml config --quiet
  else
    printf 'Skipped: env.example is absent.\n' >>"$temp_report"
  fi
else
  printf 'Skipped: Docker Compose v2 is unavailable.\n' >>"$temp_report"
fi

section "Secret scanner"
if command -v gitleaks >/dev/null 2>&1; then
  printf '$ gitleaks git --redact --no-banner --log-opts="--all" .\n' >>"$temp_report"
  if gitleaks git --redact --no-banner --log-opts="--all" . >>"$temp_report" 2>&1; then
    printf 'Gitleaks history scan completed without findings.\n' >>"$temp_report"
  else
    printf 'Gitleaks history scan reported findings or an execution error. Review locally.\n' >>"$temp_report"
  fi
  printf '$ gitleaks dir --redact --no-banner .\n' >>"$temp_report"
  if gitleaks dir --redact --no-banner . >>"$temp_report" 2>&1; then
    printf 'Gitleaks working-tree scan completed without findings.\n' >>"$temp_report"
  else
    printf 'Gitleaks working-tree scan reported findings or an execution error. Review locally.\n' >>"$temp_report"
  fi
else
  printf 'Not run: Gitleaks is unavailable. Install it from its official release, then run:\n' >>"$temp_report"
  printf 'gitleaks git --redact --no-banner --log-opts="--all" .\n' >>"$temp_report"
  printf 'gitleaks dir --redact --no-banner .\n' >>"$temp_report"
fi

section "Manual review still required"
{
  printf '%s\n' '- Inspect every candidate file locally without sharing secret values.'
  printf '%s\n' '- Review GitHub Actions, upstream refs, image tags, and base-image digests.'
  printf '%s\n' '- Confirm env.example contains placeholders only.'
  printf '%s\n' '- Confirm the repository contains only files intended for public release.'
  printf '%s\n' '- Confirm a repository license and third-party notices are present.'
  printf '%s\n' '- Run a container vulnerability scan on the built release image.'
} >>"$temp_report"

rm -f "$review_files"

if [ -e "$output_path" ]; then
  echo "ERROR: refusing to overwrite existing file: $output_path" >&2
  exit 1
fi

if ! cp "$temp_report" "$output_path"; then
  echo "ERROR: could not create audit report: $output_path" >&2
  exit 1
fi
if ! chmod 0600 "$output_path"; then
  echo "ERROR: could not restrict audit report permissions: $output_path" >&2
  exit 1
fi
printf 'Audit report created: %s\n' "$output_path"
printf 'Review it before sharing. It is owner-readable only (mode 0600).\n'

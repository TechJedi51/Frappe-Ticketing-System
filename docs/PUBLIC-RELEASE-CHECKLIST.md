# Public-release checklist

Complete this checklist before publishing each repository or image release. The
checks are read-only unless a step explicitly says to edit or rotate something.

## Current release posture

The public template now requires a database password and release image tag,
keeps application ports off the host, excludes the unreviewed submission
prototype, uses project-scoped networks and configurable container names, pins
the reviewed Frappe Docker revision and GitHub Actions, and includes an explicit
license. Reconfirm those properties during every release review.

The Helpdesk version is pinned in `apps.json`. Telephony is an upstream
Helpdesk dependency but does not publish release tags; its `develop` ref can
move. Before each image release, record and review the exact Telephony commit
resolved by the build. A successful build is not a substitute for that review.

## 1. Work from the intended revision

```sh
git status --short --branch
git remote -v
git fetch --prune
git log --oneline --decorate -10
```

Do not audit an old ZIP and assume it represents GitHub. Confirm that the local
commit matches the revision that will be made public. Preserve unrelated local
changes.

## 2. Inventory every tracked file

```sh
git ls-files
git status --short
git ls-files | grep -Ei '(^|/)(\.env|.*\.(pem|key|p12|pfx|sql|sqlite|db|bak|dump|log))$'
```

An example file such as `env.example` may be tracked only when it contains
placeholder values. Populated environment files, exports, archives, logs,
certificates, and backups must not be committed.

## 3. Run the shareable audit

From the repository root:

```sh
chmod +x scripts/audit-repository.sh
./scripts/audit-repository.sh frappe-helpdesk-repository-audit.txt
```

The report intentionally lists matching file names rather than matching secret
values. Read it before sharing it. The script reports missing optional tools;
install and run Gitleaks separately when it is unavailable.

## 4. Scan the entire Git history for secrets

Use Gitleaks from its official release or package. Run it from the repository
root:

```sh
gitleaks git --redact --no-banner --log-opts="--all" .
gitleaks dir --redact --no-banner .
```

A clean current tree is not enough; deleted secrets remain in Git history. A
scanner can miss unusual identifiers. Before running the repository audit,
create a local `.audit-identifiers` file containing one known company name,
domain, address, user name, hostname, or machine-specific path per line. Do not
use regular expressions and do not commit this file:

```sh
umask 077
nano .audit-identifiers
./scripts/audit-repository.sh frappe-helpdesk-repository-audit.txt
```

The script searches the working tree and every Git ref for each literal value,
but only writes matching file names and commit hashes to the report. Review
each result manually. A domain is not normally a secret, but it can disclose a
client relationship or internal naming convention.

## 5. Validate the Compose configuration

Confirm all of the following:

1. Require `FRAPPE_SITE_NAME_HEADER` and use it in both HTTP health checks.
2. Use `127.0.0.1` for in-container checks.
3. Require a non-empty database password; do not provide `changeme`.
4. The public GHCR namespace is intentional and examples require a versioned
   tag rather than `latest`.
5. The frontend has no host-published port; Caddy reaches its alias over the
   external `proxy` network.
6. The optional submission prototype remains absent from the core stack.
7. Container names are configurable and the internal network is project-scoped.
8. MariaDB, Redis, backend, and WebSocket have no public host ports.
9. Test first-install and existing-site behavior separately. The configurator
   must skip migration before the site exists and migrate after site creation.

Recommended health-check form:

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - >-
      curl -fsS -H "Host: ${FRAPPE_SITE_NAME_HEADER:?Set FRAPPE_SITE_NAME_HEADER}"
      http://127.0.0.1:8000/api/method/frappe.handler.ping || exit 1
```

Use port 8080 for the frontend check. Test Compose interpolation because the
container shell and Compose use different dollar-sign escaping rules.

## 6. Review the build supply chain

- Pin `frappe_docker` to a reviewed commit or versioned tag.
- Pin each GitHub Action to a full commit SHA and retain a comment showing its
  human-readable release.
- Pin base images by digest for reproducible releases where practical.
- Build a versioned image for each release and retain its digest.
- Keep workflow permissions at least privilege.
- Confirm the GHCR package is public before documenting unauthenticated pulls.
- Enable GitHub dependency review, Dependabot, code scanning, secret scanning,
  and push protection when available for the repository plan.
- Review the generated image with a container vulnerability scanner before
  publishing a release.

## 7. Review privacy and authentication

- Replace real company names, domains, email addresses, paths, tickets, and
  screenshots with fictional examples.
- Confirm the optional submission prototype is absent. If a future release adds
  a replacement, complete the separate security requirements before merging it.

## 8. Check licensing and public documentation

- Add a license for this repository's original files after choosing it
  deliberately.
- Retain required notices for Frappe Helpdesk, Telephony, images, and copied
  build resources.
- Confirm that the README matches the actual file layout and supported process.
- Confirm `env.example` contains placeholders only.
- Enable GitHub private vulnerability reporting and review `SECURITY.md`.

## 9. Test safely before changing visibility

1. Export the current Dockhand Compose definition and environment through its
   approved backup method.
2. Record running image digests and application versions.
3. Take and verify a DBackup backup.
4. Deploy the candidate configuration to a disposable or restored test stack.
5. Test first installation, upgrade, email send/receive, routing, agent access,
   ticket visibility, WebSockets, background jobs, backup, and restore.
6. Review `git diff`, `git status`, and the audit report before publication.

Changing repository visibility does not alter a running Docker stack. Changing
the Compose file or image used by that stack can. Apply and verify runtime
changes independently, one group at a time, with a rollback point.

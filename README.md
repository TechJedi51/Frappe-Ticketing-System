# Frappe Ticketing System

This repository builds and deploys Frappe Helpdesk for a Docker host that
already runs [Dockhand](https://dockhand.pro/) and Caddy. It provides a custom
Frappe v16 image, a production-oriented Compose stack, and a complete setup
guide for a new organization.

The examples use Pretend Co, `pretendco.com`, `support.pretendco.com`, and the
licensed Microsoft 365 mailbox `support@pretendco.com`. Replace those fictional
values during deployment.

## Start here

Follow [the step-by-step setup guide](docs/SETUP.md).

Do not deploy a moving `latest` image. Select a published release tag, record
the resulting image digest, and use that tag in Dockhand.

Release images are published as
`ghcr.io/techjedi51/frappe-ticketing-system:<release-tag>`.

## What this repository contains

| Path | Purpose |
|---|---|
| `apps.json` | Upstream applications included in the custom image |
| `Containerfile` | Multi-stage Frappe image build |
| `docker-compose.yml` | Runtime services, storage, health checks, and networks |
| `.github/workflows/build-image.yml` | Tag-driven image build and GHCR publication |
| `env.example` | Non-secret environment-variable template |
| `docs/SETUP.md` | New-company deployment and configuration walkthrough |
| `scripts/audit-repository.sh` | Read-only repository and history audit |

## Architecture

```text
Internet
   |
   v
Caddy (TLS)
   |
   `-- frontend --> backend --> MariaDB
          |            |-----> Redis cache
          `--> WebSocket ----> Redis queue

Background services: scheduler, short worker, long worker
Persistent data: sites, logs, MariaDB, and Redis queue
```

Only Caddy should accept Internet traffic. MariaDB, Redis, the backend, and
WebSocket stay on private Docker networks. The deployment expects an existing
external Caddy network named `proxy` by default.

## Included software

- Frappe Framework v16
- Frappe Helpdesk v1.30.1
- Frappe Telephony from its `develop` branch
- MariaDB 11.8 by default
- Redis 8.6 Alpine by default

Telephony is included because it is part of the proven image configuration. No
calling provider is configured. Its upstream repository does not currently
publish release tags, so maintainers must review the resolved Telephony commit
before each image release.

## Build and release model

Pushing a version tag such as `v1.0.0`, or manually running the **Build release
image** workflow with a valid tag, publishes one image tag to GitHub Container
Registry. The workflow does not publish `latest`. It pins the reviewed Frappe
Docker source and GitHub Actions, passes `apps.json` as a BuildKit secret, emits
provenance and an SBOM, and verifies that Helpdesk and Telephony are present.

Before directing users to the image, make the GHCR package public or document
read-only authentication. Use the digest shown in the workflow summary as the
release record.

## Customer ticket submission

Customers can submit tickets through the licensed support mailbox or the
authenticated Helpdesk customer portal. This repository does not include a
separate public submission form.

## Security and privacy

Copy `env.example` to a local untracked `.env` file or enter its values directly
in Dockhand. Never commit passwords, OAuth secrets, API keys, customer data,
ticket content, production logs, backups, or populated Frappe site files.

Run the repository audit before every public release:

```sh
./scripts/audit-repository.sh frappe-helpdesk-repository-audit.txt
```

The report is created with owner-only permissions and is ignored by Git. Review
it locally before sharing. See [SECURITY.md](SECURITY.md) for vulnerability
reporting and incident guidance.

## Updates and rollback

Before an update, verify a current DBackup backup and an isolated restore,
record the running image digest and application versions, and test migrations
against a restored copy. A database migration can make image-only rollback
unsafe; preserve the previous image and its compatible database and site-files
backup together.

## License

The original material in this repository is licensed under the
[GNU Affero General Public License v3.0](LICENSE). Upstream components retain
their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

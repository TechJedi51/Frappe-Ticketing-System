# Security policy

## Supported versions

Only the most recent published release tag is supported. Moving branches and
untagged images are development artifacts, not supported production releases.
Each release record should identify its container-image digest.

## Reporting a vulnerability

Do not disclose a suspected vulnerability, credential, customer name, domain,
email address, ticket, log, database export, or configuration dump in a public
issue.

Use GitHub's private vulnerability reporting feature for this repository. If it
is unavailable, contact the maintainer through a previously established private
channel and ask for a secure reporting method. Do not include a working secret
in the first message.

Include only the information needed to reproduce and assess the issue:

- affected release tag or commit;
- affected component and configuration;
- reproduction steps using fictional data;
- observed and expected behavior;
- likely impact;
- suggested remediation, if known.

The maintainer should acknowledge the report privately, validate the affected
versions, coordinate remediation, rotate exposed credentials, and publish a
security advisory when users need to take action.

## Secrets and personal information

This repository must not contain populated `.env` files, passwords, API keys,
OAuth client secrets, private keys, certificates, database dumps, backups,
access tokens, customer information, ticket content, production logs, or
machine-specific operator paths.

If sensitive data is committed:

1. Revoke or rotate the credential immediately. Deleting the file is not
   sufficient because Git retains history.
2. Determine where the credential was used and review relevant access logs.
3. Remove the data from the current tree.
4. Decide whether the repository's history must be rewritten. Coordinate this
   disruptive action with every collaborator before doing it.
5. Re-run secret scanning across the full history.
6. Document the incident through the organization's private process.

## Deployment boundary

Only the reverse proxy should accept Internet traffic. Do not publish MariaDB,
Redis, backend, or WebSocket ports. Store production secrets in Dockhand or an
approved secret-management system, restrict administrative access, and use a
dedicated least-privilege integration user for optional submission services.

Backups contain sensitive application and ticket data. Encrypt them, restrict
access, set an approved retention period, and regularly test restoration.

# Set up Frappe Helpdesk for Pretend Co

This guide walks a new organization through deploying Frappe Helpdesk with the
public Frappe Ticketing System repository. It uses **Pretend Co** as the example company,
`pretendco.com` as its domain, `support.pretendco.com` as the Helpdesk site, and
`support@pretendco.com` as a licensed Microsoft 365 user mailbox.

The Docker VM already has Dockhand and Caddy running. Complete the steps in
order. Replace Pretend Co's sample values with the new organization's values
when performing a real deployment.

## 1. Record the deployment values

Write down the approved values before creating the stack. Store passwords and
tokens in an approved password manager, not in this worksheet.

| Setting | Pretend Co example |
|---|---|
| Company | `Pretend Co` |
| Public domain | `pretendco.com` |
| Helpdesk site | `support.pretendco.com` |
| Support mailbox | `support@pretendco.com` |
| Configuration repository | `https://github.com/TechJedi51/Frappe-Ticketing-System` |
| Container image | `ghcr.io/techjedi51/frappe-ticketing-system` |
| Docker data root | `/opt/docker/data/frappe-helpdesk` |
| Caddy network | `proxy` |

The deployment uses these services:

```text
Internet
   |
   v
Caddy (HTTPS)
   |
   `-- frappe-helpdesk-frontend --> frappe-helpdesk-backend --> MariaDB
             |                  |            Redis cache
             `--> WebSocket     `----------> Redis queue

Background services: scheduler, short worker, long worker
Persistent data: /opt/docker/data/frappe-helpdesk
```

Telephony is included in the application image because Helpdesk uses it as a
dependency. Do not configure Twilio, Exotel, or another calling provider unless
the organization has an approved requirement for telephony.

## 2. Confirm the prerequisites

Before starting, confirm all of the following:

- Dockhand is connected to the intended Docker VM.
- Caddy is running and attached to an external Docker network named `proxy`.
- The Docker VM is `amd64`, or the image has been tested with amd64 emulation.
- Docker Compose v2 is available on the Docker VM.
- The administrator can read the configuration repository and container image.
- Public DNS can be changed for `support.pretendco.com`.
- Inbound TCP ports 80 and 443 reach Caddy.
- Pretend Co owns the licensed Microsoft 365 user mailbox
  `support@pretendco.com`.
- A Microsoft Entra administrator can register an application and grant consent.
- DBackup has an approved destination, retention policy, and encryption method.

The Microsoft 365 authorization flow requires HTTPS. Finish DNS and Caddy before
authorizing the mailbox.

## 3. Select the repository release and image

Dockhand will pull the stack directly from the public repository:

```text
https://github.com/TechJedi51/Frappe-Ticketing-System
```

Select an approved repository release or commit. Do not configure a production
stack to follow an unreviewed moving branch automatically. Review the release
notes and the matching `docker-compose.yml`, `env.example`, and image digest.

Select the same versioned image tag published by the repository's **Build
release image** workflow. Do not use the moving `latest` tag. Pull the image
on the Docker VM and record its immutable digest:

```sh
docker pull ghcr.io/techjedi51/frappe-ticketing-system:<approved-release-tag>
docker image inspect ghcr.io/techjedi51/frappe-ticketing-system:<approved-release-tag> \
  --format '{{index .RepoDigests 0}}'
```

The GHCR package should be public. If it is not, use a dedicated GitHub token
with only `read:packages`, enter it through `docker login`, and keep it out of
Dockhand Compose text, Git, shell history, screenshots, and support reports.
Keep the repository revision, image tag, and digest together in the deployment
record.

## 4. Prepare DNS, storage, and networking

Create a public DNS record for `support.pretendco.com` that points to the public
address serving Caddy. If an IPv6 record is published, verify that inbound IPv6
also reaches Caddy.

Create the persistent directories on the Docker VM:

```sh
sudo mkdir -p \
  /opt/docker/data/frappe-helpdesk/sites \
  /opt/docker/data/frappe-helpdesk/logs \
  /opt/docker/data/frappe-helpdesk/db \
  /opt/docker/data/frappe-helpdesk/redis-queue
```

Do not make these directories world-writable. Confirm the runtime user IDs from
the approved images before changing ownership:

```sh
docker run --rm ghcr.io/techjedi51/frappe-ticketing-system:<approved-release-tag> id frappe
docker run --rm mariadb:11.8 id mysql
docker run --rm redis:8.6-alpine id redis
```

Verify the existing Caddy network and record its subnet:

```sh
docker network inspect proxy --format '{{json .IPAM.Config}}'
```

Use the returned subnet for `UPSTREAM_REAL_IP_ADDRESS`. Pretend Co's sample
value might be `172.19.0.0/16`, but the actual value must come from the Docker
VM. Never use `0.0.0.0/0`.

## 5. Create the Dockhand stack

In Dockhand, create a stack named **Frappe Helpdesk** and use the repository's
approved `docker-compose.yml`. A generic core template is also available as
[the repository Compose file](../docker-compose.yml).

Add these environment values in Dockhand. Replace the release tag, database
password, and proxy subnet with the approved values:

```dotenv
COMPOSE_PROJECT_NAME=frappe-helpdesk
CONTAINER_PREFIX=frappe-helpdesk
CUSTOM_IMAGE=ghcr.io/techjedi51/frappe-ticketing-system
CUSTOM_TAG=<approved-release-tag>
DOCKER_PLATFORM=linux/amd64
PULL_POLICY=always
RESTART_POLICY=unless-stopped
FRAPPE_SITE_NAME_HEADER=support.pretendco.com
CLIENT_MAX_BODY_SIZE=50m
PROXY_READ_TIMEOUT=120
ROOT=/opt/docker/data
PROXY_NETWORK_NAME=proxy
FRONTEND_NETWORK_ALIAS=frappe-helpdesk-frontend
UPSTREAM_REAL_IP_ADDRESS=<proxy-network-subnet>
UPSTREAM_REAL_IP_HEADER=X-Forwarded-For
UPSTREAM_REAL_IP_RECURSIVE=on
DB_PASSWORD=SET_A_LONG_RANDOM_VALUE_IN_DOCKHAND
MARIADB_TAG=11.8
REDIS_TAG=8.6-alpine
```

Do not place the populated environment in Git. Dockhand and Docker-host
administrators can inspect container environment variables, so both roles are
privileged.

Before deploying, use Dockhand's Compose validation or run the following from a
separate checkout on the Docker VM with an untracked populated `.env` file:

```sh
docker compose --env-file .env -f docker-compose.yml config --quiet
```

Resolve every interpolation or syntax error, then deploy the stack. During this
first deployment, the backend can start before the
site exists, but the backend and frontend health checks may report unhealthy.
That is expected only until the next section creates the site.

Confirm that the containers exist:

```sh
docker ps -a --filter 'name=frappe-helpdesk-'
```

The core deployment should contain:

- `frappe-helpdesk-configurator`
- `frappe-helpdesk-backend`
- `frappe-helpdesk-frontend`
- `frappe-helpdesk-websocket`
- `frappe-helpdesk-queue-short`
- `frappe-helpdesk-queue-long`
- `frappe-helpdesk-scheduler`
- `frappe-helpdesk-db`
- `frappe-helpdesk-redis-cache`
- `frappe-helpdesk-redis-queue`

## 6. Create the Frappe site

Run the following command from the Docker VM. Bench prompts for the MariaDB root
password and a new Frappe `Administrator` password. Enter the same database root
password stored in Dockhand, then create a unique Administrator password.

```sh
docker exec -it frappe-helpdesk-backend bash -lc '
  cd /home/frappe/frappe-bench &&
  bench new-site support.pretendco.com \
    --db-type mariadb \
    --db-host db \
    --db-port 3306 \
    --db-root-username root \
    --mariadb-user-host-login-scope="%"
'
```

The MariaDB account must accept connections from changing container addresses.
MariaDB is isolated on the internal Docker network and is not published to the
host or Internet.

Install the applications contained in the image:

```sh
docker exec frappe-helpdesk-backend bash -lc '
  cd /home/frappe/frappe-bench &&
  bench --site support.pretendco.com install-app telephony &&
  bench --site support.pretendco.com install-app helpdesk &&
  bench --site support.pretendco.com enable-scheduler &&
  bench --site support.pretendco.com clear-cache
'
```

In Dockhand, redeploy the stack. The configurator now detects the site and runs
its migration before the dependent services start.

Verify the site and installed applications:

```sh
docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench list-sites'

docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench --site support.pretendco.com list-apps --format json'
```

The application list should include `frappe`, `telephony`, and `helpdesk`.

## 7. Configure Caddy and HTTPS

Add this site block to the working Caddy configuration:

```caddyfile
support.pretendco.com {
    reverse_proxy frappe-helpdesk-frontend:8080 {
        header_up X-Real-IP {client_ip}
    }
}
```

Use the hostname by itself. Writing `http://support.pretendco.com` disables
Caddy's automatic HTTPS for that site.

Do not redirect `/` to `/helpdesk`. That redirect can interfere with the
two-factor authentication one-time-password POST. Let Frappe handle its root
route.

Validate and reload Caddy using the method established for the Docker VM. Then
test the public endpoint:

```sh
curl -fsS https://support.pretendco.com/api/method/frappe.handler.ping
```

A successful response confirms DNS, TLS, Caddy, the frontend, and the backend
path. MariaDB, Redis, backend port 8000, WebSocket port 9000, and frontend port
8080 must not be directly accessible from the Internet.

## 8. Complete the first login

Open `https://support.pretendco.com` and sign in as `Administrator` with the
password created in section 6.

1. Complete the initial Frappe setup for Pretend Co.
2. Open Helpdesk and complete its onboarding.
3. Set the organization name, logo, favicon, time zone, language, and date
   format.
4. Create a named administrator account for routine administration.
5. Test the named account, then stop using the built-in Administrator account
   for daily work.
6. Keep the built-in Administrator credential in approved recovery storage.

Do not enable a Telephony provider during onboarding unless the organization has
approved the provider, data handling, telephone numbers, recording policy, and
credentials.

## 9. Configure agents, teams, and routing

### Invite agents

In Helpdesk, open **Settings → Invite Agents**. Invite each support worker with
the minimum appropriate role:

- **Agent** works on tickets and manages personal views.
- **Agent Manager** works on tickets and manages team operations.
- **Admin** controls all Helpdesk settings and should be assigned sparingly.

Confirm each invited user has an HD Agent record. Test at least one ordinary
Agent account separately from an administrator.

### Create Pretend Co teams

Open **Settings → Teams** and create this sample structure:

| Team | Purpose |
|---|---|
| General Support | Default destination for uncategorized requests |
| Technical Support | Product, device, software, and service incidents |
| Billing | Invoices, payments, subscriptions, and account questions |

Add at least two agents to a team before testing automatic rotation. Helpdesk
creates a basic assignment rule for each team. Verify that a ticket assigned to
a team rotates to an eligible team member.

### Configure ticket types and priorities

Create or confirm these Pretend Co ticket types:

- Technical Issue
- Billing Question
- Account Request
- General Question

Helpdesk includes the priority levels Urgent, High, Medium, and Low. Set Medium
as the normal default. Document what qualifies as Urgent so customers and agents
do not use it for routine requests.

### Route tickets

Use team assignment rules for normal distribution. If ticket type should select
the team automatically, create a reviewed HD Ticket server script using this
Pretend Co example:

```python
if doc.ticket_type == "Billing Question":
    doc.agent_group = "Billing"
elif doc.ticket_type == "Technical Issue":
    doc.agent_group = "Technical Support"
else:
    doc.agent_group = "General Support"
```

Test every branch before enabling the script for customer traffic. Routing
scripts are production code: keep them small, do not embed credentials, and
review them after Helpdesk upgrades.

### Protect internal ticket fields

Open **Customize Form**, select **HD Ticket**, and review every customer-facing
and internal field. Helpdesk uses these important permission levels:

| Level | Intended visibility |
|---|---|
| 0 | Everyone |
| 7 | Customers and agents |
| 8 | Agents only |

In the Default HD Ticket Template, set **Visible to** appropriately and clear
**Editable after creation** for fields a customer must not change later. A field
that must never reach a customer also needs an agent-only permission level;
hiding it in the template alone does not hide it from the API.

## 10. Configure service levels and notifications

Create Pretend Co's business hours and holiday calendar before enabling an SLA.
The following table is a sample starting point, not a contractual commitment:

| Priority | First response | Resolution target |
|---|---:|---:|
| Urgent | 30 minutes | 2 hours |
| High | 1 hour | 4 hours |
| Medium | 8 hours | 24 hours |
| Low | 24 hours | 72 hours |

In **Settings → SLA Policies**:

1. Create a default Pretend Co SLA.
2. Add every active priority to the policy.
3. Set Resolved and Closed as fulfilled states.
4. Select the status that pauses the resolution timer while waiting for the
   customer, if that matches Pretend Co's policy.
5. Attach the business-hours and holiday schedule.
6. Create a test ticket at each priority and verify its response and resolution
   deadlines.

Review Helpdesk email notifications, saved replies, and the automatic status
setting. Enable only the messages Pretend Co intends customers and agents to
receive.

## 11. Connect Microsoft 365 email

Use OAuth, not the mailbox password or an app password. This guide assumes
`support@pretendco.com` is a licensed Microsoft 365 user mailbox.

### Register the Microsoft Entra application

1. In Microsoft Entra admin center, create an app registration named
   `Pretend Co Frappe Helpdesk`.
2. Add delegated permissions for IMAP receive and SMTP send, then grant tenant
   admin consent. The protocol scopes are:
   - `https://outlook.office.com/IMAP.AccessAsUser.All`
   - `https://outlook.office.com/SMTP.Send`
   - `offline_access`
3. Create a client secret with the shortest practical lifetime.
4. Store the secret value immediately in approved secret storage. The value is
   shown only once.
5. Record the application ID, tenant ID, secret owner, and expiry date.

The OpenID configuration URL follows this format:

```text
https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
```

### Create the Frappe Connected App

1. In Frappe, open `/app/connected-app/new`.
2. Paste the OpenID configuration URL and choose **Get OpenID Configuration**.
3. Set the provider name, client ID, and client secret.
4. Follow the current Helpdesk Outlook article for the Connected App scopes. At
   the time of this guide, it specifies:
   - `https://outlook.office365.com/.default`
   - `offline_access`
5. Save the Connected App.
6. Copy the redirect URI generated by Frappe.
7. In the Entra app registration, add that exact URI as a **Web** redirect URI.

### Create the Frappe Email Account

Sign in to Frappe as the actual mailbox user before authorizing the connection.
Do not authorize it while signed in as Administrator.

| Setting | Value |
|---|---|
| Email address | `support@pretendco.com` |
| Authentication | OAuth |
| Incoming server | `outlook.office365.com` |
| Incoming port/security | `993`, SSL |
| Outgoing server | `smtp.office365.com` |
| Outgoing port/security | `587`, TLS |
| Incoming | Enabled and default |
| Outgoing | Enabled and default |

Link the Connected App, save the Email Account, and choose **Authorize API
Access**. Sign in as `support@pretendco.com` and approve the requested access.

Enable IMAP for the mailbox. SMTP AUTH must also be allowed for this mailbox
even though authentication uses OAuth. Prefer a mailbox-specific exception
instead of enabling SMTP AUTH for the whole tenant. If Microsoft Entra Security
Defaults blocks the protocol, have the identity administrator review the
security and Conditional Access effects before changing the tenant.

### Test email threading

1. Send a new message from an external test mailbox to
   `support@pretendco.com`.
2. Confirm one ticket is created with the correct sender, subject, body, and
   attachment.
3. Reply from Helpdesk and verify delivery and the expected sender address.
4. Reply again from the external mailbox and confirm the reply joins the same
   ticket.
5. Confirm scheduled email pulling continues without an interactive login.
6. Verify SPF, DKIM, and DMARC alignment for the outgoing message.
7. Schedule renewal of the Entra client secret before it expires.

## 12. Configure customer ticket submission

Pretend Co accepts new tickets through `support@pretendco.com` and the
authenticated Helpdesk customer portal. No separate public form is required.

1. Create a test customer contact using a fictional or approved test address.
2. Invite that contact to the customer portal.
3. Sign in as the test customer and create a ticket with an attachment.
4. Confirm the ticket reaches the intended team and assignment rule.
5. Confirm the customer can see and reply to their own tickets but cannot see
   another customer's tickets or agent-only fields.
6. Sign out and confirm that the portal requires authentication before showing
   ticket data or allowing a ticket to be created.

## 13. Configure DBackup and recovery

DBackup is the backup orchestrator for this deployment. Its job must protect:

- A consistent MariaDB logical backup or application-consistent snapshot.
- `/opt/docker/data/frappe-helpdesk/sites`, including public and private files.
- The approved Compose configuration and encrypted Dockhand environment export.
- Caddy configuration and required DNS recovery information.
- The deployed image tag and digest, or a recoverable copy of the image.

Copying the live MariaDB data directory by itself is not evidence of a
restorable database backup. Configure monitoring, retention, encryption, and an
off-host copy.

Perform an isolated restore test before the service is accepted. Disable
outbound email in the restored environment, then verify:

- Administrator and named-agent login
- Ticket and attachment access
- Installed application versions
- Scheduler and workers
- Database integrity
- The documented recovery time

## 14. Verify the deployment

Run these read-only checks from the Docker VM:

```sh
docker ps -a --filter 'name=frappe-helpdesk-'

docker image inspect ghcr.io/techjedi51/frappe-ticketing-system:<approved-release-tag> \
  --format '{{json .RepoDigests}}'

docker network inspect proxy --format '{{json .IPAM.Config}}'

docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench version'

docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench list-sites'

docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench --site support.pretendco.com list-apps --format json'

docker exec frappe-helpdesk-backend bash -lc \
  'cd /home/frappe/frappe-bench && bench --site support.pretendco.com doctor'

curl -fsS https://support.pretendco.com/api/method/frappe.handler.ping
```

Do not share unfiltered `docker inspect`, container environment output,
`site_config.json`, or `bench --site ... show-config`. They can reveal database
passwords, API credentials, and other secrets. Review logs locally before
sharing because they may contain addresses, message text, IP addresses, or
request data.

## 15. Updates and rollback

Before an update:

1. Verify a recent DBackup job and successful restore test.
2. Take a fresh database-aware backup.
3. Record the running image tag, digest, and application versions.
4. Build or obtain an immutable candidate image.
5. Test its migration against a restored copy with outbound email disabled.
6. Schedule downtime when the migration or rollback plan requires it.
7. Deploy the candidate through Dockhand.
8. Verify login, tickets, email, attachments, routing, scheduler, workers, and
   WebSocket updates.

Do not run `bench update` inside these containers. Do not run
`bench build --hard-link` in production. Mount the full Frappe log directory,
not an individual rotating log file.

Rollback after a schema migration normally requires both the previous image
digest and a compatible database/files backup. Changing only the image tag may
not be safe.

## 16. Troubleshooting

### `no configuration file provided: not found`

The shell is not in the repository directory. Change to the directory containing
the Compose file or provide its full path:

```sh
cd /opt/docker/stacks/frappe-helpdesk
docker compose -f docker-compose.yml images
```

### `actual-site-name: No such file or directory`

Angle brackets indicate a placeholder, but the shell interprets `<` as input
redirection. Run `bench list-sites`, then type the returned site name without
angle brackets.

### Backend or frontend is unhealthy

Confirm the health check uses `127.0.0.1`, sends
`Host: support.pretendco.com`, and matches the site directory returned by
`bench list-sites`. Using `localhost` can select IPv6 loopback and fail when the
service listens only on IPv4.

### Login or two-factor authentication loops

Remove any Caddy redirect from `/` to `/helpdesk`, reload Caddy, and retest the
one-time-password submission.

### Email receives but does not send

Verify the OAuth token, SMTP server and port, the mailbox's Authenticated SMTP
setting, and the tenant authentication policy. Do not enable password-based
legacy authentication.

### Static files fail after an update

Confirm every Frappe service uses the same approved image digest. The deployment
does not require a separate named assets volume.

## 17. Final checklist

- [ ] DNS resolves `support.pretendco.com` to Caddy.
- [ ] HTTPS has a valid public certificate and HTTP redirects to HTTPS.
- [ ] Direct Frappe, MariaDB, Redis, and WebSocket ports are not public.
- [ ] All core containers are running or healthy; configurator exited successfully.
- [ ] `bench list-apps` shows Frappe, Helpdesk, and Telephony.
- [ ] The deployed release tag and digest are recorded.
- [ ] A named administrator and ordinary Agent account were tested.
- [ ] Teams, ticket types, priorities, assignment rules, and permissions were tested.
- [ ] SLA deadlines match Pretend Co's approved policy.
- [ ] Microsoft 365 receive, send, reply threading, and token refresh work.
- [ ] The Entra secret owner and expiry date are recorded.
- [ ] DBackup completed successfully and an isolated restore was verified.
- [ ] The previous image and compatible backup form a documented rollback path.

## Sources

- [Frappe Docker custom image build](https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md)
- [Frappe Helpdesk installation](https://docs.frappe.io/helpdesk/installation)
- [Frappe Helpdesk first steps](https://docs.frappe.io/helpdesk/your-first-steps-with-frappe-helpdesk)
- [Frappe Helpdesk agents and teams](https://docs.frappe.io/helpdesk/lesson-3-agents-teams)
- [Frappe Helpdesk ticket routing](https://docs.frappe.io/helpdesk/ticket-routing)
- [Frappe Helpdesk assignment rules](https://docs.frappe.io/helpdesk/assignment-rule)
- [Frappe Helpdesk service-level agreements](https://docs.frappe.io/helpdesk/service-level-agreement)
- [Frappe Helpdesk ticket field visibility](https://docs.frappe.io/helpdesk/customization/perm-levels-in-helpdesk)
- [Frappe Helpdesk Outlook setup](https://docs.frappe.io/helpdesk/faq/setting-up-outlook-for-frappe)
- [Frappe Microsoft 365 Email OAuth](https://docs.frappe.io/framework/user/en/microsoft-email-oauth)
- [Microsoft OAuth for IMAP and SMTP](https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth)
- [Microsoft SMTP AUTH controls](https://learn.microsoft.com/en-us/Exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission)

The linked services and interfaces can change. Recheck the current vendor
documentation before a production deployment.

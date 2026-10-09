# Optional embedded ticket-submission service

Do not add or deploy the supplied `frappe-submit` archive as-is. The reviewed
archive is a useful prototype, but it is not ready for a public repository or
production use.

## Findings in the supplied archive

- It contains production-specific hostnames and a support email address.
- It contains `.DS_Store` and `__MACOSX` metadata that should not be committed.
- The PHP page and Nginx configuration do not authenticate a visitor.
- There is no CSRF control or request throttling.
- Required text fields do not have server-side length limits.
- A visitor-supplied company name can create an arbitrary `HD Customer`.
- A visitor-supplied email address can create a `Contact`.
- The server-side Frappe API credentials can therefore be exercised by anyone
  who can reach the form, even though the credentials are not sent to the
  browser.

An authenticated page containing the form in an iframe is not an authentication
boundary. A visitor can request the iframe's `/submit` URL directly unless that
route independently checks authentication.

## Decide whether the package is needed

Use the authenticated Frappe Helpdesk customer portal when it meets the
requirement. That avoids maintaining a second authentication and ticket-creation
path.

Keep this package only when an embedded form is required and the organization
has an authentication service that can protect `/submit` directly. Put it in
the same repository only if the package will be versioned and released with the
Compose deployment. Otherwise, a separate repository gives it an independent
review and release lifecycle.

## Secure implementation sequence

1. **Test the actual boundary.** Sign out, use a private browser window, and
   open the direct `/submit` URL rather than the page that embeds it. A `200`
   response with the form means it is anonymously reachable.
2. **Choose one identity source.** Prefer the native Frappe portal. If the
   organization uses a separate identity system, place an authentication
   gateway in front of `/submit` and have Caddy use `forward_auth`. Do not infer
   identity merely from a browser-supplied email, company, or header.
3. **Bind the request to the authenticated user.** Obtain the submitter's email
   and organization from trusted identity claims. Do not let a form field
   override those values.
4. **Narrow the operation.** Create only an `HD Ticket` with server-controlled
   type, priority, team, and status. Do not allow this path to create arbitrary
   customers, agents, teams, users, or other master records. Use an approved
   customer mapping when tenant association is required.
5. **Use a dedicated integration user.** Grant only the permissions required by
   the reviewed server-side operation. Never use Administrator credentials.
   Store its API key and secret in Dockhand or the approved secret store, not in
   Git or browser code.
6. **Validate on the server.** Set allowlists and length limits; reject control
   characters and unexpected markup; validate email and attachment type, size,
   and count; and return generic errors to the browser.
7. **Prevent cross-site and automated abuse.** Require a CSRF token tied to the
   authenticated session, check the request origin, throttle by user and source
   address, set an overall request-size limit, and log rejected requests without
   recording secrets or unnecessary ticket content.
8. **Constrain framing.** Use a Content Security Policy `frame-ancestors`
   allowlist for the exact approved origins. Do not use
   `X-Frame-Options: ALLOWALL`.
9. **Make deployment explicit.** Put both submission services behind a Compose
   profile or override. The core Helpdesk stack must start successfully without
   the package or its credentials.
10. **Test both paths.** Verify that an unauthenticated direct request is
    rejected, an authenticated valid request creates exactly one ticket, forged
    identity and CSRF attempts fail, throttling works, oversized inputs fail,
    and the integration user cannot create unrelated records.

## Direct-access check

Run this from a computer that does not already have an authenticated session:

```sh
curl -sS -o /dev/null -D - https://support.example.com/submit
```

Interpret the first status line and any `Location` header:

- `401` or `403`: the route rejected the unauthenticated request.
- `302` or `303` to the approved sign-in service: authentication is being
  enforced, but test that the return URL cannot redirect to an arbitrary site.
- `200`: the form is directly reachable; an authenticated parent page is not
  protecting it.

After the route is protected, test the POST endpoint separately. Do not treat a
protected GET with an unprotected POST as secure.

## Release requirements

Before the package is added to this repository:

- replace all production-specific values with required environment variables;
- add automated tests for authentication, authorization, validation, and abuse
  controls;
- add a package-specific README and data-flow description;
- add `.DS_Store` and `__MACOSX` to `.gitignore`;
- scan the package and its Git history for secrets and personal information;
- document credential rotation and package rollback;
- complete a security review in a non-production deployment.

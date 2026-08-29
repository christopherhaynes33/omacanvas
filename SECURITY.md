# Security Policy

## Supported versions

Security fixes are provided for the latest released version of Omacanvas.

| Release | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Do not publish vulnerability details in a GitHub issue. Until a private
reporting channel is listed here, open an issue titled `Security contact
request` containing only a request for the maintainer to arrange private
contact. Do not describe the vulnerability in that issue. If GitHub Private
Vulnerability Reporting becomes available for this repository, it may be used
instead.

Include enough information to reproduce and assess the issue, such as the
affected version, relevant configuration, expected behavior, observed
behavior, and reproducible steps. Never include a Canvas API token, password,
session cookie, or other credential in a report, screenshot, log, or example.

Security concerns include, but are not limited to:

- Exposure of Canvas API tokens or other sensitive data.
- Authenticated requests being sent somewhere other than the configured Canvas
  installation.
- Bypasses of Canvas base URL validation.
- Command, argument, or configuration injection.
- Insecure system-keyring handling.
- Sensitive information being written to logs or plain-text configuration.

Please use regular GitHub issues for feature requests, usability problems, and
bugs that do not have a security impact.

## Exposed credentials

If a Canvas API token may have been exposed, revoke it immediately in Canvas,
generate a replacement, and save the replacement with Omacanvas's `set-token`
command. Do not wait for a vulnerability report to be reviewed before rotating
a potentially compromised token.

Omacanvas stores tokens in the desktop Secret Service keyring and sends them
only to the user-configured Canvas installation. Because Omarchy plugins run as
unsandboxed user code, users should review plugin source and updates before
installing them.

## Disclosure

Please allow the maintainer a reasonable opportunity to investigate and
release a fix before publicly disclosing a vulnerability. Receipt of a report
will be acknowledged when possible, but no guaranteed response or remediation
timeline is offered.

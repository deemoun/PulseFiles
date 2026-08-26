# Security Policy

## Supported versions

PulseFiles is currently a prerelease project. Security fixes are provided for
the latest published prerelease and are carried forward on the `main` branch.
Older prereleases, development snapshots, forks, and locally modified builds
are not supported.

| Version | Supported |
| --- | --- |
| 1.0.0-beta.1 (latest prerelease) | Yes |
| Older prereleases | No |
| Unreleased development builds or forks | No |

If a report affects an unsupported version, please confirm whether it also
affects the latest published prerelease before reporting it when that can be
done safely.

## What to report privately

Treat a report as security-sensitive when it could let an attacker, malicious
file, or untrusted location:

- read, disclose, alter, move, overwrite, or delete files without the user's
  informed intent;
- bypass `SandboxFileAccessPolicy`, macOS permission checks, explicit folder
  grants, destructive-operation confirmations, or conflict handling;
- execute commands or code unexpectedly, including through the experimental
  terminal, file previews, filenames, metadata, or crafted filesystem content;
- expose credentials, private file contents, filesystem paths, diagnostics, or
  other sensitive user information;
- cause a privilege-boundary escape, unsafe link traversal, unauthorized access
  across panes or locations, or a denial of service with meaningful security
  impact; or
- undermine release integrity, signing, update or distribution security, or a
  dependency in an exploitable way.

Ordinary crashes without a security consequence, usability problems, feature
requests, and non-sensitive bugs can use the public
[issue chooser](https://github.com/deemoun/PulseFiles/issues/new/choose).
When uncertain, report privately and let the maintainers triage it.

## Report a vulnerability privately

Use GitHub
[Private Vulnerability Reporting](https://github.com/deemoun/PulseFiles/security/advisories/new)
to send a confidential report to the maintainers. Include the affected
PulseFiles and macOS versions, impact, prerequisites, and the smallest safe set
of reproduction steps. A minimal proof of concept may be included privately if
it does not contain real user data.

**Do not put credentials, private files or file contents, diagnostics bundles,
or exploitable details in a public GitHub issue, discussion, pull request,
screenshot, or log.** Redact tokens, account names, personal paths, volume
names, and unrelated diagnostic data. Use disposable test data, and do not test
against systems or data you do not own or have permission to assess.

Please submit one vulnerability per report when practical. Do not publicly
disclose the issue until the maintainers have investigated it and coordinated
a remediation or disclosure plan with you.

## What to expect

- Maintainers aim to acknowledge a private report within **3 business days**.
- They aim to provide an initial severity and scope assessment within **7
  business days**, although complex reports may take longer.
- While investigation or remediation remains active, maintainers aim to provide
  a status update at least every **14 days**.
- Maintainers may ask for clarification or a reduced, sanitized reproducer and
  will coordinate validation, remediation, release timing, and any public
  advisory with the reporter.
- Response and fix timing depend on severity, complexity, maintainer
  availability, and release safety. These targets are goals, not guarantees.

Good-faith reports will be handled confidentially to the extent practical.
Reporter credit is optional and will be discussed before publication.

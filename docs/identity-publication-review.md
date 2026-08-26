# Identity publication review

## Current decision

Publication consent for associating the name **Dmitry Yarygin** with the
GitHub account **`deemoun`** is **not confirmed by evidence in this
repository**. Commit authorship, a GitHub noreply address, copyright notices,
repository URLs, and an account publishing or merging changes all establish
that the association is already present; they are not a substitute for the
person's explicit consent to publish that association.

Do not represent consent as confirmed, and do not publish a new release on
that basis, until the release owner retains an explicit confirmation from the
person concerned. The confirmation should identify the name, account, intended
public uses, and date. Store the confirmation in an access-controlled project
record rather than committing private correspondence to this public
repository.

## Audit performed

The review covered the locations where the name or account association is
published or can be inferred:

- `NOTICE`, `Package.swift`, and copyright headers throughout source, test,
  script, and QA files identify Dmitry Yarygin as author or rightsholder.
- `docs/asset-provenance.md` and `docs/release-provenance.json` identify Dmitry
  Yarygin as creator and rightsholder of the application icon.
- English and Russian `Localizable.strings` files, together with
  `PulseFiles/App/AppDelegate.swift`, show the name in the About window.
- `README.md`, `CONTRIBUTING.md`, `PRIVACY.md`, `RELEASE_NOTES.md`, the app's
  support/privacy/source URLs, and related tests point to the `deemoun`
  repository or its issue tracker.
- Every currently reachable commit and ref was inspected. Reachable commit
  metadata repeatedly pairs the name with the
  `deemoun@users.noreply.github.com` address, and merge subjects name branches
  under `deemoun`. At review time the local clone had only `refs/heads/work`
  and no configured remote; therefore it cannot prove the state of hosted
  forks, mirrors, caches, releases, or other already-published copies.

No repository record explicitly grants consent to publish the combined
name/account association.

## If anonymity is requested

Treat an anonymity request as a coordinated legal, release, and hosting task,
not a search-and-replace exercise:

1. Ask the rightsholder which public attribution must remain and agree on a
   replacement attribution that preserves GPL notices, copyright ownership,
   asset provenance, and any other legally required authorship.
2. Update all audited working-tree locations consistently, including About UI
   localization, support/source URLs, tests, provenance records, and the header
   validation script. Do not delete required notices merely to remove a name.
3. Obtain licensing review before rewriting commits. Rewriting metadata does
   not transfer copyright, revoke an existing GPL grant, or remove copies
   already received; changing provenance or attribution may also make release
   evidence inaccurate.
4. After approval, rewrite every affected local ref, expire obsolete local
   objects as appropriate, and repeat both a tracked-file scan and an
   object/ref scan. Review tags, notes, replace refs, reflogs, stashes, commit
   messages, author/committer fields, trees, and blobs rather than checking only
   the current branch.
5. Inventory and contact the operators of the canonical host, forks, mirrors,
   package indexes, release archives, documentation sites, CI artifacts, and
   caches. Coordinate replacement or removal under each host's policies and
   record unavoidable retained copies. A force-push alone does not remove
   already-published history.


# Asset and component provenance

This record is the repository's source of truth for the provenance and reuse
status of distributable, non-source assets. The machine-readable review
allowlist used by the release gate is
[`release-provenance.json`](release-provenance.json).

## PulseFiles application icon

| File | Creator and rightsholder | Creation or source method | License | Redistribution and modification |
| --- | --- | --- | --- | --- |
| `PulseFiles/Resources/PulseFilesAppIconSource.png` | Dmitry Yarygin | Original digital artwork created for PulseFiles. This PNG is the editable, repository-owned source for the application icon. | GPL-3.0-or-later, as part of PulseFiles; see the repository `LICENSE`. | The rightsholder confirms that redistribution and modification are permitted under GPL-3.0-or-later. |
| `PulseFiles/Resources/AppIcon.icns` | Dmitry Yarygin | Generated from `PulseFilesAppIconSource.png` as the macOS multi-resolution application-icon container. It does not incorporate a third-party icon or other artwork. | GPL-3.0-or-later, as part of PulseFiles; see the repository `LICENSE`. | The rightsholder confirms that redistribution and modification are permitted under GPL-3.0-or-later. |

No separate attribution or license-text requirement applies to these two
first-party assets beyond the PulseFiles copyright and GPL notices already
distributed with the application.

## Review requirements for additions

Every distributable non-source asset must be added to
`release-provenance.json` before release. Every future third-party SwiftPM
dependency or other third-party component must also be added there and record:

- its name;
- its exact version and source;
- its license;
- all attribution requirements (use `None` when there are none); and
- whether its license text must be bundled with the application.

The release inventory check rejects dependencies and assets which have not
received that review. When a component requires attribution or a bundled
license, the release owner must also add the required material to the packaged
application and `NOTICE`; an allowlist entry alone is not fulfillment.

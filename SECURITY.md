# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's private vulnerability reporting:
<https://github.com/lukegalea/ash_versions/security/advisories/new>. Do not open a public
issue or pull request for a suspected vulnerability. You will get an acknowledgement, and we
will agree a disclosure date with you once the fix is ready.

## Supported versions

Only the latest release tag and `main` receive fixes.

## Scope

The areas where a flaw is most likely to matter:

- **Reads as the viewer.** Every registry and history read passes the caller's actor and tenant
  to the resource's own policies. Anything that returns a version, or a fact about one, that the
  viewer's policies would not return is in scope.
- **The one system read.** `AshVersions.Registry.previous/4` asks, without authorization and
  inside the viewer's tenant and scope, only whether an earlier version exists. Anything that
  lets that read reveal what the earlier version holds, or reach another tenant, is in scope.
- **Doors.** A type behind a door the viewer does not pass is neither listed nor read.

Flaws in your own policies, doors or publisher lookup are out of scope.

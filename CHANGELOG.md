# Changelog

## Unreleased

- First extraction, from a host application where it had been the version pages' framework:
  - `AshVersions.Registry`: a behaviour a host module `use`s, declaring its entries and how it
    resolves the tenant, the doors, who published and labels. The reads are discovery, `get`,
    `previous`, the header, who published, `used_by`, the semantic diff, validation and the
    lifecycle.
  - `AshVersions.Artifact`, `AshVersions.Differ` and `AshVersions.Change`.
  - `AshVersions.TemporalHistory`: every version of a temporal record through as-of reads.
- An entry's `door` has no default. A column-scoped type is `scope: {:attribute, name}`.

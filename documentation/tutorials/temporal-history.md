# Temporal history

Ash reads a temporal resource at one instant: you get the one version of each record that was
valid then. There is no read that returns all of history. `AshVersions.TemporalHistory`
recovers it from ordinary as-of reads.

## How it walks

A version is valid over a half-open period `[lower, upper)`. The version before it is the one
valid a microsecond before `lower`, and the version after it is the one valid at `upper`. From
each record you give it, `versions/3` reads backwards and forwards, one read per version, until a
read finds nothing. That is where the record's history starts, ends or has a gap.

```elixir
current = Ash.get!(MyApp.Subscription, id, actor: actor, tenant: tenant)
then = Ash.get!(MyApp.Subscription, id, actor: actor, tenant: tenant, as_of: ~U[2026-01-15 00:00:00Z])

%{^id => versions} =
  AshVersions.TemporalHistory.versions(MyApp.Subscription, [current, then], actor: actor, tenant: tenant)

for version <- versions do
  {version.name, AshVersions.TemporalHistory.starts_at(version),
   AshVersions.TemporalHistory.ends_at(version)}
end
```

The result is keyed by primary key, with each record's versions oldest first. Seeds of the same
version count once.

## Options

- `:actor`, `:tenant`, `:authorize?` go to every read. `authorize?` defaults to `true`.
- `:max_versions` caps the versions walked per record, per direction (default 50).
- `:load` is loaded on every version read.

## What it will not do

- **Cross a gap.** A record destroyed and created again has two histories. Seed both sides to
  see both.
- **Read past a policy.** Every step is a read as the caller. A version the caller may not read
  ends the walk, so a reader who cannot read a record cannot recover its past.
- **Scan a table.** It costs one read per version. Use it for the records one page shows.

# AshVersions

Versions of Ash records, read the way a person reviews them.

- **A version registry** (`AshVersions.Registry`). Declare each versioned resource once, as an
  `AshVersions.Artifact`: which attribute is the version, how a version finds its predecessor,
  its lifecycle, its content hash, what it references, how it is checked and how two versions
  are compared. From that entry the type gets discovery, a header, a semantic diff and
  validation. Every read is the viewer's, through the resource's own policies, and anything that
  could not be read, compared or checked says so. It is never shown as unchanged or valid.
- **Temporal history** (`AshVersions.TemporalHistory`). Ash reads a temporal resource at one
  instant. A version's period is half-open, so its neighbours are one as-of read away, and
  `versions/3` walks both ways from the versions you hold until history starts, ends or has a
  gap.

## Installation

```elixir
def deps do
  [
    {:ash_versions, github: "lukegalea/ash_versions"}
  ]
end
```

It needs Ash 3.37 or later. Temporal history needs a data layer that supports temporal
resources (`AshPostgres` on PostgreSQL 18+, or `Ash.DataLayer.Ets`).

## A registry in brief

```elixir
defmodule MyApp.Versions do
  use AshVersions.Registry

  @impl true
  def artifacts do
    [
      %AshVersions.Artifact{
        type: :process,
        label: "Process definition",
        resource: MyApp.Processes.Definition,
        identity: :key,
        version: :version,
        lineage: [key: :key, order: :version],
        lifecycle: {:status, %{draft: :draft, published: :current, retired: :past}},
        scope: :tenant,
        content_hash: :content_hash,
        published: [:publish],
        differ: MyApp.Versions.ProcessDiffer,
        door: :signed_in
      }
    ]
  end

  @impl true
  def tenant(actor), do: actor.organization_id

  @impl true
  def open?(door, actor), do: MyApp.Doors.open?(door, actor)

  @impl true
  def publisher(entry, record, actor), do: MyApp.Audit.who_published(entry, record, actor)

  @impl true
  def translate(label), do: Gettext.dgettext(MyAppWeb.Gettext, "versions", label)
end

entry = MyApp.Versions.fetch(:process)
{:ok, v2} = MyApp.Versions.get(entry, id, actor)
MyApp.Versions.diff(entry, MyApp.Versions.previous(entry, v2, actor), v2, actor: actor)
#=> {:changes, [%AshVersions.Change{aspect: :routing, kind: :changed, ...}]}
```

The package has no pages. The host renders the header, the diff and the validation in its own
words.

## Documentation

- [A version registry](documentation/tutorials/a-version-registry.md)
- [Temporal history](documentation/tutorials/temporal-history.md)
- [Usage rules](usage-rules.md), for agents and people writing code against the package

## License

MIT. See [LICENSE](https://github.com/lukegalea/ash_versions/blob/main/LICENSE).

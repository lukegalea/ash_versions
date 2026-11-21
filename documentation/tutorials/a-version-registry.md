# A version registry

This tutorial declares a registry for one versioned resource and walks through what each read
returns.

## The resource

Any Ash resource whose rows are versions of something will do. The registry needs:

- an attribute that names the thing across its versions (`:key`);
- an attribute that orders its versions (`:version`, or `:inserted_at` for freely labelled
  revisions);
- optionally, a lifecycle attribute, a content hash and a parent id.

## The entry

```elixir
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
  references: &MyApp.Versions.Facets.process_references/1,
  validate: &MyApp.Versions.Facets.process_problems/1,
  differ: MyApp.Versions.Differs.Process,
  door: :signed_in
}
```

`references` and `validate` re-read what the stored version says about itself. Neither should
query. A check returns `{:ok, problems}` (an empty list meaning it ran and found none) or
`{:error, reason}` when there is nothing to check yet.

`runs: {MyApp.Runs.Run, :definition_id}` names rows that pin a version by id. With it,
`used_by/4` tells a page opened from one of those rows whether this is the version that row
used, so a draft can never pass for it.

## The host module

```elixir
defmodule MyApp.Versions do
  use AshVersions.Registry

  @impl true
  def artifacts, do: [...]

  @impl true
  def tenant(actor), do: actor.organization_id

  @impl true
  def open?(door, actor), do: MyApp.Doors.open?(door, actor)

  @impl true
  def publisher(entry, record, actor) do
    # Read your audit trail as the viewer: the newest event of one of `entry.published`
    # for `record.id`. :unreadable when the viewer may not read the trail at all.
  end

  @impl true
  def translate(label), do: Gettext.dgettext(MyAppWeb.Gettext, "versions", label)
end
```

## Reading

| Call | Returns |
|---|---|
| `discover(actor)` | `[%{artifact:, items: {:ok, records} \| {:error, reason}}]`, only for doors the actor passes |
| `list(entry, actor, limit \\ 20)` | the newest versions the actor may read |
| `get(entry, id, actor)` | `{:ok, record}` or `:unreadable` |
| `previous(entry, record, actor)` | `{:ok, record}`, `:first`, `:unchained` or `{:unreadable, :from}` |
| `diff(entry, from, to, opts)` | see below |
| `header(entry, record, actor)` | identity, version, lifecycle, hash, parent, references, who published |
| `validation(entry, record)` | `{:ok, problems}`, `:undeclared` or `{:failed, reason}` |
| `used_by(entry, record, run_id, actor)` | `{:this, run}`, `{:other, run}`, `:unreadable` or `nil` |

`diff/4` takes the result of `previous/3` or `get/3` as `from`, so a page can pass it straight
through:

| Result | Meaning |
|---|---|
| `{:changes, changes}` | what the differ found |
| `{:unchanged, :same_content}` | nothing found, and the content hashes match |
| `{:unchanged, :compared}` | nothing found, and there is no hash to check |
| `:uncovered` | nothing found that the differ covers, but the hashes differ |
| `:no_differ` | the type has no semantic diff |
| `:first`, `:unchained`, `{:unreadable, :from}` | nothing to compare against |
| `{:failed, reason}` | the differ could not compare, raised, or got versions of another type |

## When no predecessor is readable

`previous/3` reads as the viewer. When it finds nothing, a version numbered `1` is first and a
higher number has a predecessor the viewer cannot see. A freely labelled version says nothing by
its label, so the registry asks, as the system and inside the viewer's tenant and scope, whether
an earlier row exists. It uses only the yes or no.

defmodule AshVersions.Test.Versions do
  @moduledoc false
  # A host registry. The actor is a map: `org` is its tenant, `doors` the doors it
  # passes, `audit?` whether it may read who published.
  use AshVersions.Registry

  alias AshVersions.Artifact
  alias AshVersions.Test.{Note, NoteDiffer, Revision, Run}

  @impl true
  def artifacts do
    [
      %Artifact{
        type: :note,
        label: "Note",
        resource: Note,
        identity: :key,
        version: :version,
        lineage: [key: :key, order: :version],
        lifecycle: {:status, %{draft: :draft, published: :current, retired: :past}},
        scope: :tenant,
        content_hash: :content_hash,
        parent: :baseline_id,
        published: [:publish],
        references: &references/1,
        validate: &problems/1,
        differ: NoteDiffer,
        runs: {Run, :note_id},
        door: :signed_in
      },
      %Artifact{
        type: :revision,
        label: "Revision",
        resource: Revision,
        identity: :name,
        version: :revision,
        lineage: [key: :name, order: :inserted_at],
        lifecycle: {:status, %{draft: :draft, active: :current, retired: :past}},
        scope: {:attribute, :org},
        door: :auditor
      }
    ]
  end

  @impl true
  def tenant(actor), do: actor.org

  @impl true
  def open?(door, actor), do: door in actor.doors

  @impl true
  def publisher(entry, record, actor) do
    send(self(), {:publisher, entry.type, record.id})
    if actor[:audit?], do: {:ok, "someone@example.test"}, else: :unreadable
  end

  @impl true
  def translate(label), do: String.upcase(label)

  def references(note), do: for(name <- Map.keys(note.body), do: {:field, name})

  def problems(%{body: body}) when map_size(body) == 0, do: {:error, :empty}
  def problems(%{body: body}), do: {:ok, for({name, nil} <- body, do: "#{name} is blank")}
end

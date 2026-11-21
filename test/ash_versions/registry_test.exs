defmodule AshVersions.RegistryTest do
  @moduledoc """
  A version registry (`AshVersions.Registry`): one entry is all a type needs for
  discovery, a header, a diff and validation; every read is the viewer's, behind the
  entry's door; a draft never passes for the version a run used; and nothing that could
  not be compared, read or checked is ever reported as unchanged or valid.
  """

  # The ETS tables are private to this process, so every test seeds its own rows.
  use ExUnit.Case, async: true

  alias AshVersions.{Change, Registry}
  alias AshVersions.Test.{Note, Revision, Run, Versions}

  defp entry(type), do: Versions.fetch(type)

  defp viewer(org, attrs \\ %{}),
    do: Map.merge(%{id: Ash.UUID.generate(), org: org, doors: [:signed_in]}, attrs)

  defp org, do: "org-#{System.unique_integer([:positive])}"

  defp note!(org, version, attrs \\ %{}) do
    Ash.Seed.seed!(
      Note,
      Map.merge(
        %{
          org: org,
          key: "intake",
          version: version,
          body: %{"title" => "v#{version}"},
          content_hash: "h#{version}"
        },
        attrs
      ),
      tenant: org
    )
  end

  defp revision!(org, name, revision, attrs \\ %{}) do
    Ash.Seed.seed!(Revision, Map.merge(%{org: org, name: name, revision: revision}, attrs))
  end

  defp at(seconds), do: DateTime.add(~U[2026-01-01 00:00:00.000000Z], seconds, :second)

  describe "the registry" do
    test "lists its entries in order and finds one by type, name or resource" do
      assert Enum.map(Versions.all(), & &1.type) == [:note, :revision]
      assert Versions.fetch(:note).resource == Note
      assert Versions.fetch("revision").resource == Revision
      assert Versions.fetch(:missing) == nil
      assert Versions.fetch("missing") == nil
      assert Versions.fetch(nil) == nil
      assert Versions.for_resource(Revision).type == :revision
      assert Versions.for_resource(Run) == nil
    end

    test "the host's functions are the package's, with the host as the registry" do
      assert Versions.all() == Registry.all(Versions)
      assert Versions.aspects(entry(:note)) == [fields: "Fields"]
      assert Versions.aspects(entry(:revision)) == []
    end

    test "an entry must name its door" do
      assert_raise ArgumentError, ~r/door/, fn ->
        Code.eval_string(
          "%AshVersions.Artifact{type: :t, label: \"T\", resource: R, identity: :key, scope: :tenant}"
        )
      end
    end
  end

  describe "one entry gives a type" do
    setup do
      org = org()
      v1 = note!(org, 1, %{status: :published, inserted_at: at(1)})
      v2 = note!(org, 2, %{body: %{"title" => "v2", "owner" => nil}, inserted_at: at(2)})
      %{org: org, viewer: viewer(org, %{audit?: true}), v1: v1, v2: v2}
    end

    test "discovery, newest first, read as the viewer", %{viewer: viewer, v1: v1, v2: v2} do
      assert [%{artifact: %{type: :note}, items: {:ok, listed}}] = Versions.discover(viewer)
      assert Enum.map(listed, & &1.id) == [v2.id, v1.id]
      assert {:ok, [only]} = Versions.list(entry(:note), viewer, 1)
      assert only.id == v2.id
    end

    test "a header", %{viewer: viewer, v1: v1, v2: v2} do
      assert {:ok, %{id: id}} = Versions.get(entry(:note), v2.id, viewer)
      assert id == v2.id

      assert %{
               type: :note,
               label: "NOTE",
               identity: "intake",
               version: 2,
               lifecycle: {:draft, :draft},
               content_hash: "h2",
               parent: nil,
               references: [{:field, "owner"}, {:field, "title"}],
               published_by: {:ok, "someone@example.test"}
             } = Versions.header(entry(:note), v2, viewer)

      assert %{lifecycle: {:published, :current}} = Versions.header(entry(:note), v1, viewer)
    end

    test "a diff against the version before", %{viewer: viewer, v1: v1, v2: v2} do
      note = entry(:note)
      assert {:ok, %{id: id}} = Versions.previous(note, v2, viewer)
      assert id == v1.id
      assert Versions.previous(note, v1, viewer) == :first

      assert {:changes, changes} =
               Versions.diff(note, Versions.previous(note, v2, viewer), v2, [])

      assert changes == [
               %Change{aspect: :fields, kind: :added, subject: "owner", to: nil},
               %Change{aspect: :fields, kind: :changed, subject: "title", from: "v1", to: "v2"}
             ]
    end

    test "validation", %{v1: v1, v2: v2} do
      assert Versions.validation(entry(:note), v1) == {:ok, []}
      assert Versions.validation(entry(:note), v2) == {:ok, ["owner is blank"]}
      assert Versions.validation(entry(:note), %{v1 | body: %{}}) == {:failed, :empty}
      assert Versions.validation(entry(:revision), v1) == :undeclared
    end
  end

  describe "reading is the viewer's" do
    setup do
      org = org()
      %{org: org, v1: note!(org, 1), v2: note!(org, 2)}
    end

    test "a version in another tenant is unreadable, and so is its predecessor", ctx do
      stranger = viewer(org())
      assert Versions.get(entry(:note), ctx.v2.id, stranger) == :unreadable
      assert Versions.previous(entry(:note), ctx.v2, stranger) == {:unreadable, :from}
      assert {:ok, _v1} = Versions.previous(entry(:note), ctx.v2, viewer(ctx.org))
    end

    test "an id that is not one is unreadable", ctx do
      assert Versions.get(entry(:note), "not-a-uuid", viewer(ctx.org)) == :unreadable
      assert Versions.get(entry(:note), nil, viewer(ctx.org)) == :unreadable
      assert Versions.get(entry(:note), Ash.UUID.generate(), viewer(ctx.org)) == :unreadable
    end

    test "a type behind a closed door is not listed, and none of its versions is read", ctx do
      no_doors = viewer(ctx.org, %{doors: []})
      assert Versions.discover(no_doors) == []
      assert Versions.get(entry(:note), ctx.v1.id, no_doors) == :unreadable
    end

    test "who published is the host's answer, asked only when the type records it", ctx do
      assert Versions.published_by(entry(:note), ctx.v1, viewer(ctx.org)) == :unreadable
      assert_received {:publisher, :note, id}
      assert id == ctx.v1.id

      unrecorded = %{entry(:note) | published: []}
      assert Versions.published_by(unrecorded, ctx.v1, viewer(ctx.org)) == :not_recorded
      refute_received {:publisher, _type, _id}
    end
  end

  describe "a column-scoped type" do
    test "reads the tenant's rows and the ones every tenant shares, never another's" do
      {mine, theirs} = {org(), org()}
      own = revision!(mine, "baseline", "a")
      shared = revision!(nil, "baseline", "shared")
      _other = revision!(theirs, "baseline", "b")

      viewer = viewer(mine, %{doors: [:auditor]})
      assert [%{artifact: %{type: :revision}, items: {:ok, listed}}] = Versions.discover(viewer)
      assert Enum.sort(Enum.map(listed, & &1.id)) == Enum.sort([own.id, shared.id])
    end

    test "a first revision labelled other than 1 is first, not hidden" do
      org = org()
      first = revision!(org, "labelled", "v1", %{inserted_at: at(1)})
      assert Versions.previous(entry(:revision), first, viewer(org)) == :first
    end

    test "a later revision whose predecessor the viewer cannot read is hidden, never first" do
      org = org()
      retired = revision!(org, "labelled", "v1", %{status: :retired, inserted_at: at(1)})
      later = revision!(org, "labelled", "2026.2", %{inserted_at: at(2)})

      assert Versions.previous(entry(:revision), later, viewer(org)) == {:unreadable, :from}

      assert {:ok, %{id: id}} =
               Versions.previous(entry(:revision), later, viewer(org, %{sees_retired?: true}))

      assert id == retired.id
    end

    test "another tenant's earlier revision does not make one hidden" do
      {mine, theirs} = {org(), org()}
      _theirs = revision!(theirs, "labelled", "v1", %{inserted_at: at(1)})
      first = revision!(mine, "labelled", "2026.2", %{inserted_at: at(2)})
      assert Versions.previous(entry(:revision), first, viewer(mine)) == :first
    end
  end

  describe "a draft is not the version a run used" do
    setup do
      org = org()
      published = note!(org, 1, %{status: :published})
      draft = note!(org, 2)
      run = Ash.Seed.seed!(Run, %{org: org, note_id: published.id}, tenant: org)
      %{org: org, published: published, draft: draft, run: run}
    end

    test "the run's version is its own, the draft is a draft and another", ctx do
      note = entry(:note)
      viewer = viewer(ctx.org)

      assert {:this, %{id: id}} = Versions.used_by(note, ctx.published, ctx.run.id, viewer)
      assert id == ctx.run.id
      assert {:other, _run} = Versions.used_by(note, ctx.draft, ctx.run.id, viewer)
      assert Versions.lifecycle(note, ctx.draft) == {:draft, :draft}
      assert Versions.lifecycle(note, ctx.published) == {:published, :current}
    end

    test "a run that cannot be read never says which version it used", ctx do
      note = entry(:note)
      viewer = viewer(ctx.org)

      assert Versions.used_by(note, ctx.published, ctx.run.id, viewer(org())) == :unreadable
      assert Versions.used_by(note, ctx.published, Ash.UUID.generate(), viewer) == :unreadable
      assert Versions.used_by(note, ctx.published, "not-a-uuid", viewer) == :unreadable
      assert Versions.used_by(note, ctx.published, nil, viewer) == nil
      assert Versions.used_by(entry(:revision), ctx.published, ctx.run.id, viewer) == nil
    end
  end

  # --- nothing missing reads as unchanged or valid ------------------------------------

  defmodule Raises do
    @moduledoc false
    @behaviour AshVersions.Differ
    def aspects, do: [content: "Content"]
    def diff(_old, _new, _opts), do: raise("the differ broke")
  end

  defmodule Errors do
    @moduledoc false
    @behaviour AshVersions.Differ
    def aspects, do: [content: "Content"]
    def diff(_old, _new, _opts), do: {:error, :could_not_compare}
  end

  defmodule Garbage do
    @moduledoc false
    @behaviour AshVersions.Differ
    def aspects, do: [content: "Content"]
    def diff(_old, _new, _opts), do: :ok
  end

  defmodule FindsNothing do
    @moduledoc false
    @behaviour AshVersions.Differ
    def aspects, do: [content: "Content"]
    def diff(_old, _new, _opts), do: {:ok, []}
  end

  defp with_differ(differ), do: %{entry(:note) | differ: differ}

  defp pair do
    {struct(Note, key: "k", version: 1, body: %{"a" => 1}),
     struct(Note, key: "k", version: 2, body: %{"a" => 2})}
  end

  describe "what is never read as no changes" do
    test "a differ that raises, errors or answers nonsense has failed" do
      {old, new} = pair()
      assert {:failed, "the differ broke"} = Versions.diff(with_differ(Raises), old, new, [])
      assert {:failed, :could_not_compare} = Versions.diff(with_differ(Errors), old, new, [])
      assert {:failed, {:unexpected, :ok}} = Versions.diff(with_differ(Garbage), old, new, [])
    end

    test "a version that cannot be read, or a missing prior, is not compared" do
      {_old, new} = pair()
      note = entry(:note)
      assert Versions.diff(note, :unreadable, new, []) == {:unreadable, :from}
      assert Versions.diff(note, {:unreadable, :from}, new, []) == {:unreadable, :from}
      assert Versions.diff(note, :first, new, []) == :first
      assert Versions.diff(note, :unchained, new, []) == :unchained
      assert {:failed, :unreadable} = Versions.diff(note, new, :unreadable, [])
      assert {:failed, {:unexpected, nil}} = Versions.diff(note, nil, new, [])
    end

    test "two different types are not compared" do
      {_old, new} = pair()
      other = struct(Revision, name: "k", revision: "1")
      assert {:failed, {:unexpected, _}} = Versions.diff(entry(:note), other, new, [])
    end

    test "a type with no differ has no semantic diff" do
      {old, new} = pair()
      assert Versions.diff(with_differ(nil), old, new, []) == :no_differ
      assert Versions.diff(with_differ(nil), :first, new, []) == :no_differ
    end

    test "a differ that finds nothing while the content hashes differ is uncovered" do
      {old, _new} = pair()
      differ = with_differ(FindsNothing)

      assert Versions.diff(differ, %{old | content_hash: "a"}, %{old | content_hash: "b"}, []) ==
               :uncovered

      assert Versions.diff(differ, %{old | content_hash: "a"}, %{old | content_hash: "a"}, []) ==
               {:unchanged, :same_content}

      assert Versions.diff(differ, old, old, []) == {:unchanged, :compared}

      assert Versions.diff(%{differ | content_hash: nil}, old, old, []) ==
               {:unchanged, :compared}
    end

    test "a type that keeps no versions is unchained" do
      {_old, new} = pair()
      assert Versions.previous(%{entry(:note) | lineage: nil}, new, viewer(org())) == :unchained
    end

    test "a predecessor numbered after 1 that is not there is hidden, not first" do
      org = org()
      assert Versions.previous(entry(:note), note!(org, 3), viewer(org)) == {:unreadable, :from}

      assert Versions.previous(entry(:note), note!(org, 1, %{key: "lone"}), viewer(org)) ==
               :first
    end
  end

  describe "what is never read as valid" do
    test "a check that raises, errors or answers nonsense has not been checked" do
      {_old, new} = pair()
      note = entry(:note)

      assert {:failed, "boom"} =
               Versions.validation(%{note | validate: fn _ -> raise "boom" end}, new)

      assert Versions.validation(%{note | validate: fn _ -> {:error, :no} end}, new) ==
               {:failed, :no}

      assert Versions.validation(%{note | validate: fn _ -> :ok end}, new) ==
               {:failed, {:unexpected, :ok}}

      assert Versions.validation(%{note | validate: fn _ -> {:ok, [:named]} end}, new) ==
               {:ok, ["named"]}
    end

    test "a state the lifecycle does not name is unknown, never current" do
      {_old, new} = pair()
      assert Versions.lifecycle(entry(:note), %{new | status: :archived}) == {:archived, :unknown}
      assert Versions.lifecycle(%{entry(:note) | lifecycle: nil}, new) == nil
    end
  end
end

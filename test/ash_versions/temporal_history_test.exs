defmodule AshVersions.TemporalHistoryTest do
  @moduledoc """
  `AshVersions.TemporalHistory`: every version of a temporal record, both ways from the
  ones a caller holds, through as-of reads the resource's policies decide.
  """

  # The ETS tables are private to this process, so every test seeds its own rows.
  use ExUnit.Case, async: true

  alias AshVersions.TemporalHistory
  alias AshVersions.Test.Status

  defp at(day), do: DateTime.add(~U[2026-01-01 00:00:00.000000Z], day, :day)

  defp create!(id, name, day, attrs \\ %{}) do
    Status
    |> Ash.Changeset.for_create(:create, Map.merge(%{id: id, name: name}, attrs), as_of: at(day))
    |> Ash.create!(authorize?: false)
  end

  defp update!(record, attrs, day) do
    record
    |> Ash.Changeset.for_update(:update, attrs, as_of: at(day))
    |> Ash.update!(authorize?: false)
  end

  defp destroy!(record, day) do
    record
    |> Ash.Changeset.for_destroy(:destroy, %{}, as_of: at(day))
    |> Ash.destroy!(authorize?: false)
  end

  defp read_at!(id, day), do: Ash.get!(Status, id, as_of: at(day), authorize?: false)

  defp names(history), do: Enum.map(history, & &1.name)

  test "walks back and forward from any version it is given, oldest first" do
    one = create!(1, "first", 0)
    two = update!(one, %{name: "second"}, 10)
    update!(two, %{name: "third"}, 20)

    seed = read_at!(1, 15)
    assert seed.name == "second"

    assert %{1 => history} = TemporalHistory.versions(Status, [seed])
    assert names(history) == ["first", "second", "third"]

    assert Enum.map(history, &TemporalHistory.starts_at/1) == [at(0), at(10), at(20)]
    assert Enum.map(history, &TemporalHistory.ends_at/1) == [at(10), at(20), nil]
  end

  test "keys histories by primary key, and seeds of one version count once" do
    create!(1, "one", 0) |> update!(%{name: "one again"}, 5)
    create!(2, "two", 0)

    histories =
      TemporalHistory.versions(Status, [
        read_at!(1, 1),
        read_at!(1, 2),
        read_at!(1, 6),
        read_at!(2, 1)
      ])

    assert names(histories[1]) == ["one", "one again"]
    assert names(histories[2]) == ["two"]
  end

  test "a gap ends the walk: history is what is contiguous with the seeds" do
    one = create!(1, "before the gap", 0)
    destroy!(one, 10)
    create!(1, "after the gap", 20)

    assert names(TemporalHistory.versions(Status, [read_at!(1, 25)])[1]) == ["after the gap"]
    assert names(TemporalHistory.versions(Status, [read_at!(1, 5)])[1]) == ["before the gap"]

    # Seeds on both sides of the gap recover both.
    both = TemporalHistory.versions(Status, [read_at!(1, 5), read_at!(1, 25)])
    assert names(both[1]) == ["before the gap", "after the gap"]
  end

  test "a version the reader may not read ends the walk there" do
    one = create!(1, "public", 0)
    two = update!(one, %{name: "hidden", secret: true}, 10)
    update!(two, %{name: "public again", secret: false}, 20)

    assert names(TemporalHistory.versions(Status, [read_at!(1, 25)])[1]) == ["public again"]

    assert names(TemporalHistory.versions(Status, [read_at!(1, 25)], authorize?: false)[1]) ==
             ["public", "hidden", "public again"]
  end

  test "the walk is capped per record, per direction" do
    record =
      Enum.reduce(1..5, create!(1, "v0", 0), fn n, record ->
        update!(record, %{name: "v#{n}"}, n)
      end)

    assert record.name == "v5"
    seed = read_at!(1, 3)

    assert names(TemporalHistory.versions(Status, [seed], max_versions: 1)[1]) ==
             ["v2", "v3", "v4"]

    assert names(TemporalHistory.versions(Status, [seed], max_versions: 0)[1]) == ["v3"]
  end

  test "loads what the caller asks for on every version it reads" do
    create!(1, "quiet", 0) |> update!(%{name: "loud"}, 10)

    history = TemporalHistory.versions(Status, [read_at!(1, 15)], load: [:shout])[1]
    assert [%{name: "quiet", shout: "quiet!"}, _seed] = history
  end

  test "no seeds, no history" do
    assert TemporalHistory.versions(Status, []) == %{}
  end
end

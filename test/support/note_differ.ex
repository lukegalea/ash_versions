defmodule AshVersions.Test.NoteDiffer do
  @moduledoc false
  @behaviour AshVersions.Differ

  alias AshVersions.Change

  @impl true
  def aspects, do: [fields: "Fields"]

  @impl true
  def diff(old, new, _opts), do: {:ok, Change.keyed(:fields, old.body, new.body)}
end

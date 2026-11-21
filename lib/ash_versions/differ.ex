defmodule AshVersions.Differ do
  @moduledoc """
  A semantic differ: compares two versions of one artifact type by what they
  mean, never by their text.

  `aspects/0` says what it compares, in the order a diff page shows them, each
  with a label in the host's words; the page lists them, so a reader knows what
  a short diff covers. `diff/3` returns the changes between the older and the
  newer version. It may read, and does so as the viewer, through `opts`
  (`:actor`, `:tenant`).

  When a package owns the format being compared, the comparison belongs to that
  package. A host differ then labels the aspects and wraps the package's change
  maps into `AshVersions.Change`s; it never re-implements the comparison.

  A differ returns `{:ok, []}` only when it compared both versions and found
  nothing it covers that changed; `AshVersions.Registry.diff/4` still checks the
  content hashes, so a change the differ does not cover is reported as such and
  not as "no changes". It returns `{:error, reason}` when it could not compare,
  and that is shown as a failure.
  """

  alias AshVersions.Change

  @callback aspects() :: [{atom(), String.t()}]
  @callback diff(old :: struct(), new :: struct(), opts :: keyword()) ::
              {:ok, [Change.t()]} | {:error, term()}
end

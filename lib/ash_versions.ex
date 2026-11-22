defmodule AshVersions do
  @moduledoc """
  Versions of Ash records.

    * `AshVersions.Registry`: a registry of versioned artifacts. Each type is declared
      once (`AshVersions.Artifact`) and gets discovery, a header, a semantic diff
      (`AshVersions.Differ`, `AshVersions.Change`) and validation, every read made as the
      viewer.
    * `AshVersions.TemporalHistory`: every version of a temporal record, recovered
      through ordinary as-of reads.
  """
end

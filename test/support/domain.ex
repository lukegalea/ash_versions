defmodule AshVersions.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshVersions.Test.Note
    resource AshVersions.Test.Revision
    resource AshVersions.Test.Run
    resource AshVersions.Test.Status
  end
end

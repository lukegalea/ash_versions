defmodule AshVersions.Test.Run do
  @moduledoc false
  # A row that pins the note version it used.
  use Ash.Resource,
    domain: AshVersions.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  multitenancy do
    strategy :attribute
    attribute :org
  end

  attributes do
    uuid_primary_key :id
    attribute :org, :string, allow_nil?: false, public?: true
    attribute :note_id, :uuid, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end
  end
end

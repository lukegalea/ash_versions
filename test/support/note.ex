defmodule AshVersions.Test.Note do
  @moduledoc false
  # Numbered versions in the data layer's tenant: the common case.
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
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      default: :draft,
      public?: true,
      constraints: [one_of: [:draft, :published, :retired]]

    attribute :content_hash, :string, public?: true
    attribute :baseline_id, :uuid, public?: true
    attribute :body, :map, default: %{}, public?: true

    attribute :inserted_at, :utc_datetime_usec,
      allow_nil?: false,
      default: &DateTime.utc_now/0,
      public?: true
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

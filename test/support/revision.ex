defmodule AshVersions.Test.Revision do
  @moduledoc false
  # Freely labelled revisions that carry their tenant in a column, `nil` meaning every
  # tenant. A viewer without `sees_retired?` cannot read a retired revision.
  use Ash.Resource,
    domain: AshVersions.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :org, :string, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :revision, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      default: :draft,
      public?: true,
      constraints: [one_of: [:draft, :active, :retired]]

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
      authorize_if expr(status != :retired)
      authorize_if actor_attribute_equals(:sees_retired?, true)
    end
  end
end

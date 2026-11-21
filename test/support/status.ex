defmodule AshVersions.Test.Status do
  @moduledoc false
  # A temporal record. A version marked `secret` is unreadable, so a walk stops at it.
  use Ash.Resource,
    domain: AshVersions.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  temporal do
    strategy :context
    attribute :valid_at
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :secret, :boolean, allow_nil?: false, default: false, public?: true
  end

  calculations do
    calculate :shout, :string, expr(name <> "!")
  end

  actions do
    defaults [:read, :destroy, create: [:id, :name, :secret], update: [:name, :secret]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end
  end
end

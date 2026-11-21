defmodule AshVersions.Registry do
  @moduledoc """
  A version registry: every versioned thing a person authors, reviews or releases,
  declared once as an `AshVersions.Artifact`, and the reads a version page needs.

  From an entry alone a type gets:

    * **discovery**: its newest versions, read as the viewer (`discover/2`, `list/4`);
    * **a header**: identity, version, lifecycle, content hash, provenance, what it
      references and who published it (`header/4`), with the row it was opened from, so
      a draft cannot pass for the version that row used (`used_by/5`);
    * **a semantic diff** against its predecessor (`previous/4`) or any other version
      (`diff/4`);
    * **validation**: the stored version checked again (`validation/2`).

  ## What the host declares

  A host module `use`s this one and implements the callbacks:

      defmodule MyApp.Versions do
        use AshVersions.Registry

        @impl true
        def artifacts, do: [%AshVersions.Artifact{type: :process, ...}]

        @impl true
        def tenant(actor), do: actor.organization_id

        @impl true
        def open?(door, actor), do: MyApp.Doors.open?(door, actor)

        @impl true
        def publisher(entry, record, actor), do: MyApp.Audit.who_published(entry, record, actor)

        @impl true
        def translate(label), do: Gettext.dgettext(MyAppWeb.Gettext, "versions", label)
      end

  `use` defines the reads on the host module, each the function of the same name here
  with the host as the registry: `all/0`, `fetch/1`, `for_resource/1`, `discover/1`,
  `list/2,3`, `get/3`, `previous/3`, `header/3`, `published_by/3`, `used_by/4`,
  `aspects/1`, `diff/4`, `validation/2` and `lifecycle/2`, and the type `state/0`.

  ## Reading is always as the viewer

  Every read goes through the resource's own policies with the viewer's actor and the
  tenant `tenant/1` names, behind the entry's door (`open?/2`). A version the viewer may
  not read is `:unreadable`, which a page must never show as missing, unchanged or valid.
  One read is made as the system: `previous/4` asks whether an earlier version exists at
  all when the viewer can read none, and uses only that it exists, never what it holds.
  """

  require Ash.Query

  import Ash.Expr, only: [expr: 1, ref: 1]

  alias Ash.Resource.Info
  alias AshVersions.{Artifact, Change}

  @recent 20

  @typedoc "What `diff/4` found. Only `{:unchanged, _}` means no changes."
  @type state ::
          {:changes, [Change.t()]}
          | {:unchanged, :same_content | :compared}
          | :uncovered
          | :no_differ
          | :first
          | :unchained
          | {:unreadable, :from}
          | {:failed, term()}

  @typedoc "Who published a version."
  @type publisher :: {:ok, String.t()} | :not_recorded | :unreadable

  @doc "Every entry, in the order pages list them. Types are unique."
  @callback artifacts() :: [Artifact.t()]

  @doc "The tenant every read is made in, for `actor`."
  @callback tenant(actor :: term()) :: term()

  @doc "Whether `actor` may see the types behind `door` at all."
  @callback open?(door :: term(), actor :: term()) :: boolean()

  @doc """
  Who published `record`, from the host's record of the entry's `published` actions:
  `{:ok, name}`, `:not_recorded` when nothing records it, or `:unreadable` when the viewer
  may not read that record (which is not "none recorded"). Called only for an entry whose
  `published` is not empty.
  """
  @callback publisher(Artifact.t(), record :: struct(), actor :: term()) :: publisher()

  @doc "An entry's `label` in the viewer's words."
  @callback translate(label :: String.t()) :: String.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour AshVersions.Registry

      @type state :: AshVersions.Registry.state()

      @doc "Every entry, in registry order."
      def all, do: AshVersions.Registry.all(__MODULE__)

      @doc "The entry for `type` (an atom or its name), or `nil`."
      def fetch(type), do: AshVersions.Registry.fetch(__MODULE__, type)

      @doc "The entry whose versions are rows of `resource`, or `nil`."
      def for_resource(resource), do: AshVersions.Registry.for_resource(__MODULE__, resource)

      @doc "Every type the viewer's doors admit, each with its newest versions (`AshVersions.Registry.discover/2`)."
      def discover(actor), do: AshVersions.Registry.discover(__MODULE__, actor)

      @doc "The newest versions of `entry` the viewer may read (`AshVersions.Registry.list/4`)."
      def list(entry, actor, limit \\ 20),
        do: AshVersions.Registry.list(__MODULE__, entry, actor, limit)

      @doc "One version by id, read as the viewer, or `:unreadable` (`AshVersions.Registry.get/4`)."
      def get(entry, id, actor), do: AshVersions.Registry.get(__MODULE__, entry, id, actor)

      @doc "The version `record` follows (`AshVersions.Registry.previous/4`)."
      def previous(entry, record, actor),
        do: AshVersions.Registry.previous(__MODULE__, entry, record, actor)

      @doc "What a header shows of `record` (`AshVersions.Registry.header/4`)."
      def header(entry, record, actor),
        do: AshVersions.Registry.header(__MODULE__, entry, record, actor)

      @doc "Who published `record` (`AshVersions.Registry.published_by/4`)."
      def published_by(entry, record, actor),
        do: AshVersions.Registry.published_by(__MODULE__, entry, record, actor)

      @doc "Whether the row `run_id` used `record` (`AshVersions.Registry.used_by/5`)."
      def used_by(entry, record, run_id, actor),
        do: AshVersions.Registry.used_by(__MODULE__, entry, record, run_id, actor)

      @doc "What `entry`'s differ compares (`AshVersions.Registry.aspects/1`)."
      defdelegate aspects(entry), to: AshVersions.Registry

      @doc "What changed between two versions (`AshVersions.Registry.diff/4`)."
      defdelegate diff(entry, from, to, opts), to: AshVersions.Registry

      @doc "`record` checked again (`AshVersions.Registry.validation/2`)."
      defdelegate validation(entry, record), to: AshVersions.Registry

      @doc "`record`'s lifecycle state and class (`AshVersions.Registry.lifecycle/2`)."
      defdelegate lifecycle(entry, record), to: AshVersions.Registry
    end
  end

  # --- the registry -----------------------------------------------------------------

  @doc "Every entry of `registry`, in registry order."
  @spec all(module()) :: [Artifact.t()]
  def all(registry), do: registry.artifacts()

  @doc "The entry for `type` (an atom or its name), or `nil`."
  @spec fetch(module(), atom() | String.t() | nil) :: Artifact.t() | nil
  def fetch(_registry, nil), do: nil
  def fetch(registry, type) when is_atom(type), do: Enum.find(all(registry), &(&1.type == type))

  def fetch(registry, name) when is_binary(name),
    do: Enum.find(all(registry), &(Atom.to_string(&1.type) == name))

  @doc "The entry whose versions are rows of `resource`, or `nil`."
  @spec for_resource(module(), module()) :: Artifact.t() | nil
  def for_resource(registry, resource), do: Enum.find(all(registry), &(&1.resource == resource))

  @doc "What `entry`'s differ compares, as `[{aspect, label}]`; `[]` with no differ."
  @spec aspects(Artifact.t()) :: [{atom(), String.t()}]
  def aspects(%Artifact{differ: nil}), do: []
  def aspects(%Artifact{differ: differ}), do: differ.aspects()

  # --- reading, as the viewer -------------------------------------------------------

  @doc """
  Every type the viewer's doors admit, each with its newest versions the viewer may read:
  `[%{artifact:, items: {:ok, [record]} | {:error, reason}}]`. A type behind a closed
  door is left out, rather than listed empty.
  """
  @spec discover(module(), term()) :: [
          %{artifact: Artifact.t(), items: {:ok, [struct()]} | {:error, term()}}
        ]
  def discover(registry, actor) do
    for entry <- all(registry), registry.open?(entry.door, actor) do
      %{artifact: entry, items: list(registry, entry, actor)}
    end
  end

  @doc """
  The newest versions of `entry` the viewer may read, or `{:error, reason}`. Newest is by
  the lineage's order when it is `:inserted_at`, otherwise by `created_on` when the
  resource has it and `inserted_at` when it does not.
  """
  @spec list(module(), Artifact.t(), term(), pos_integer()) ::
          {:ok, [struct()]} | {:error, term()}
  def list(registry, entry, actor, limit \\ @recent) do
    registry
    |> query(entry, actor)
    |> Ash.Query.sort([{at(entry), :desc}])
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  @doc "One version of `entry` by id, read as the viewer behind its door, or `:unreadable`."
  @spec get(module(), Artifact.t(), String.t(), term()) :: {:ok, struct()} | :unreadable
  def get(registry, entry, id, actor) do
    with true <- registry.open?(entry.door, actor),
         {:ok, id} when is_binary(id) <- Ash.Type.cast_input(Ash.Type.UUID, id, []),
         {:ok, %{} = record} <-
           registry |> query(entry, actor) |> Ash.Query.filter(id == ^id) |> Ash.read_one() do
      {:ok, record}
    else
      _unreadable -> :unreadable
    end
  end

  @doc """
  The version `record` follows: `{:ok, predecessor}`, `:first` when it has none,
  `:unchained` when the type keeps no versions, or `{:unreadable, :from}` when the
  predecessor could not be read.

  When the viewer can read no predecessor, a version numbered `1` is first and one
  numbered after `1` has a predecessor the viewer cannot see, never "first". A version
  labelled freely says nothing by its label, so whether an earlier row exists at all is
  asked as the system, in the viewer's tenant and scope: only that it exists is used.
  """
  @spec previous(module(), Artifact.t(), struct(), term()) ::
          {:ok, struct()} | :first | :unchained | {:unreadable, :from}
  def previous(_registry, %Artifact{lineage: nil}, _record, _actor), do: :unchained

  def previous(registry, %Artifact{} = entry, record, actor) do
    registry
    |> query(entry, actor)
    |> earlier_than(entry, record)
    |> Ash.Query.sort([{Keyword.fetch!(entry.lineage, :order), :desc}])
    |> Ash.Query.limit(1)
    |> Ash.read()
    |> case do
      {:ok, [predecessor]} -> {:ok, predecessor}
      {:ok, []} -> first_or_hidden(registry, entry, record, actor)
      {:error, _error} -> {:unreadable, :from}
    end
  end

  defp first_or_hidden(registry, %Artifact{version: version} = entry, record, actor)
       when not is_nil(version) do
    case Map.get(record, version) do
      label when label in [1, "1"] ->
        :first

      number when is_integer(number) ->
        {:unreadable, :from}

      _label ->
        if earlier?(registry, entry, record, actor), do: {:unreadable, :from}, else: :first
    end
  end

  defp first_or_hidden(_registry, _entry, _record, _actor), do: :first

  defp earlier?(registry, %Artifact{resource: resource, scope: scope} = entry, record, actor) do
    tenant = registry.tenant(actor)

    resource
    |> Ash.Query.for_read(:read, %{}, authorize?: false, tenant: tenant)
    |> scoped(scope, tenant)
    |> earlier_than(entry, record)
    |> Ash.exists?(authorize?: false)
  end

  defp earlier_than(query, %Artifact{lineage: lineage}, record) do
    key = Keyword.fetch!(lineage, :key)
    order = Keyword.fetch!(lineage, :order)
    key_value = Map.fetch!(record, key)
    order_value = Map.fetch!(record, order)

    Ash.Query.do_filter(
      query,
      expr(^ref(key) == ^key_value and ^ref(order) < ^order_value and id != ^record.id)
    )
  end

  @doc """
  What changed between two versions of `entry`. `from` is a record, or the result of
  `previous/4` or `get/4`:

    * `{:changes, changes}`: what the differ found;
    * `{:unchanged, :same_content}`: the differ found nothing and the content hashes
      match; `{:unchanged, :compared}`: it found nothing and there is no hash to check;
    * `:uncovered`: the differ found nothing it covers, but the content hashes differ;
    * `:no_differ`: the type has no semantic diff;
    * `:first`, `:unchained` and `{:unreadable, :from}`: nothing to compare against;
    * `{:failed, reason}`: the differ could not compare, raised, or was handed versions
      of another type.

  Only `{:unchanged, _}` means "no changes".
  """
  @spec diff(Artifact.t(), term(), struct() | :unreadable, keyword()) :: state()
  def diff(entry, from, to, opts)
  def diff(_entry, _from, :unreadable, _opts), do: {:failed, :unreadable}
  def diff(%Artifact{differ: nil}, _from, _to, _opts), do: :no_differ
  def diff(entry, {:ok, from}, to, opts), do: diff(entry, from, to, opts)
  def diff(_entry, :unreadable, _to, _opts), do: {:unreadable, :from}
  def diff(_entry, {:unreadable, :from} = state, _to, _opts), do: state
  def diff(_entry, state, _to, _opts) when state in [:first, :unchained], do: state

  def diff(
        %Artifact{differ: differ, resource: resource} = entry,
        %{__struct__: resource} = from,
        %{__struct__: resource} = to,
        opts
      ) do
    case differ.diff(from, to, opts) do
      {:ok, [_ | _] = changes} -> {:changes, changes}
      {:ok, []} -> unchanged(entry, from, to)
      {:error, reason} -> {:failed, reason}
      other -> {:failed, {:unexpected, other}}
    end
  rescue
    error -> {:failed, Exception.message(error)}
  end

  def diff(_entry, other, _to, _opts), do: {:failed, {:unexpected, other}}

  defp unchanged(%Artifact{content_hash: nil}, _from, _to), do: {:unchanged, :compared}

  defp unchanged(%Artifact{content_hash: hash}, from, to) do
    case {Map.get(from, hash), Map.get(to, hash)} do
      {same, same} when is_binary(same) -> {:unchanged, :same_content}
      {old, new} when is_binary(old) and is_binary(new) -> :uncovered
      _no_hash -> {:unchanged, :compared}
    end
  end

  @doc """
  `record` checked again: `{:ok, []}` (checked, nothing wrong), `{:ok, problems}`,
  `:undeclared` (the type declares no check) or `{:failed, reason}` (it could not be
  checked, raised or answered something else). Only `{:ok, []}` is valid.
  """
  @spec validation(Artifact.t(), struct()) ::
          {:ok, [String.t()]} | :undeclared | {:failed, term()}
  def validation(%Artifact{validate: nil}, _record), do: :undeclared

  def validation(%Artifact{validate: validate}, record) do
    case validate.(record) do
      {:ok, problems} when is_list(problems) -> {:ok, Enum.map(problems, &to_string/1)}
      {:error, reason} -> {:failed, reason}
      other -> {:failed, {:unexpected, other}}
    end
  rescue
    error -> {:failed, Exception.message(error)}
  end

  @doc """
  `record`'s lifecycle: `{state, class}`, the class `:draft`, `:current`, `:past` or
  `:unknown` for a state the entry does not name; `nil` when the type has none.
  """
  @spec lifecycle(Artifact.t(), struct()) :: {atom(), Artifact.class()} | nil
  def lifecycle(%Artifact{lifecycle: nil}, _record), do: nil

  def lifecycle(%Artifact{lifecycle: {attribute, classes}}, record) do
    state = Map.get(record, attribute)
    {state, Map.get(classes, state, :unknown)}
  end

  @doc """
  What a header shows of `record`: `%{type, label, identity, version, lifecycle,
  content_hash, parent, references, published_by}`, the label in the viewer's words
  (`translate/1`).
  """
  @spec header(module(), Artifact.t(), struct(), term()) :: map()
  def header(registry, entry, record, actor) do
    %{
      type: entry.type,
      label: registry.translate(entry.label),
      identity: Map.get(record, entry.identity),
      version: entry.version && Map.get(record, entry.version),
      lifecycle: lifecycle(entry, record),
      content_hash: entry.content_hash && Map.get(record, entry.content_hash),
      parent: entry.parent && Map.get(record, entry.parent),
      references: if(entry.references, do: entry.references.(record), else: []),
      published_by: published_by(registry, entry, record, actor)
    }
  end

  @doc """
  Who published `record`: `:not_recorded` for a type with no `published` actions,
  otherwise what the registry's `publisher/3` says.
  """
  @spec published_by(module(), Artifact.t(), struct(), term()) :: publisher()
  def published_by(_registry, %Artifact{published: []}, _record, _actor), do: :not_recorded
  def published_by(registry, entry, record, actor), do: registry.publisher(entry, record, actor)

  @doc """
  Whether the row `run_id` (of the entry's `runs` resource) used `record`: `{:this, run}`
  when it pinned this version, `{:other, run}` when it pinned another, `:unreadable` when
  the row cannot be read, and `nil` when there is no row or the type has no `runs`.
  """
  @spec used_by(module(), Artifact.t(), struct(), String.t() | nil, term()) ::
          {:this | :other, struct()} | :unreadable | nil
  def used_by(_registry, _entry, _record, nil, _actor), do: nil
  def used_by(_registry, %Artifact{runs: nil}, _record, _run_id, _actor), do: nil

  def used_by(registry, %Artifact{runs: {resource, attribute}}, record, run_id, actor) do
    with {:ok, id} when is_binary(id) <- Ash.Type.cast_input(Ash.Type.UUID, run_id, []),
         {:ok, %{} = run} <-
           resource
           |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: registry.tenant(actor))
           |> Ash.Query.filter(id == ^id)
           |> Ash.read_one() do
      if Map.get(run, attribute) == record.id, do: {:this, run}, else: {:other, run}
    else
      _unreadable -> :unreadable
    end
  end

  defp query(registry, %Artifact{resource: resource, scope: scope}, actor) do
    tenant = registry.tenant(actor)

    resource
    |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
    |> scoped(scope, tenant)
  end

  # Rows carrying the tenant in an attribute rather than the data layer's tenancy: the
  # tenant's own rows and the ones that hold for every tenant.
  defp scoped(query, {:attribute, attribute}, tenant),
    do: Ash.Query.do_filter(query, expr(is_nil(^ref(attribute)) or ^ref(attribute) == ^tenant))

  defp scoped(query, :tenant, _tenant), do: query

  defp at(%Artifact{lineage: [key: _, order: :inserted_at]}), do: :inserted_at

  defp at(%Artifact{resource: resource}) do
    if Info.attribute(resource, :created_on), do: :created_on, else: :inserted_at
  end
end

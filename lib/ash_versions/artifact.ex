defmodule AshVersions.Artifact do
  @moduledoc """
  One entry in a version registry (`AshVersions.Registry`): a versioned resource, and
  what a version page needs to know about its rows.

  | Field | Meaning |
  |---|---|
  | `type` | Unique atom, the registry's key |
  | `label` | Human name of the type. The registry's `translate/1` puts it into the viewer's words |
  | `resource` | The Ash resource whose rows are the versions |
  | `identity` | The attribute that names the artifact across its versions (`:key`, `:name`) |
  | `version` | The attribute holding the version number or label, or `nil` when the type keeps no versions |
  | `lineage` | How to find a version's predecessor: `[key: attribute, order: attribute]` (the same `key`, the greatest `order` below this one's), or `nil` when versions are not chained |
  | `lifecycle` | `{state_attribute, %{state => class}}`, each class `:draft` (not in use), `:current` (what work uses now) or `:past` (no longer used). A state the map does not name is `:unknown`, never `:current`. `nil` when the type has no lifecycle |
  | `scope` | Where versions live: `:tenant` (read in the viewer's tenant, the data layer's tenancy and the resource's policies deciding the rest) or `{:attribute, name}` (rows carry the tenant in `name`, `nil` meaning a row that holds for every tenant) |
  | `content_hash` | The attribute holding the content digest, or `nil` |
  | `parent` | The attribute naming the version this one was copied from, or `nil` |
  | `published` | The actions whose record says who published a version (`[:publish]`); the registry's `publisher/3` reads it |
  | `references` | `fun(record) -> [{kind, name}]`: what the version names, or `nil` |
  | `validate` | `fun(record) -> {:ok, [problem]} \\| {:error, reason}`: re-checks the stored version, or `nil` when the type declares no check |
  | `differ` | A module implementing `AshVersions.Differ`, or `nil`: the type then has no semantic diff, never an empty one |
  | `runs` | `{resource, attribute}`: rows that pin a version by its id, so a page opened from one can say whether this is the version it used; `nil` when none do |
  | `door` | What the viewer must pass to see the type at all. The registry's `open?/2` decides it; the package never reads it |

  `door` has no default: every entry says who may see it.
  """

  @enforce_keys [:type, :label, :resource, :identity, :scope, :door]
  defstruct [
    :type,
    :label,
    :resource,
    :identity,
    :version,
    :lineage,
    :lifecycle,
    :scope,
    :content_hash,
    :parent,
    :references,
    :validate,
    :differ,
    :runs,
    :door,
    published: []
  ]

  @type class :: :draft | :current | :past | :unknown

  @type scope :: :tenant | {:attribute, atom()}

  @type t :: %__MODULE__{
          type: atom(),
          label: String.t(),
          resource: module(),
          identity: atom(),
          version: atom() | nil,
          lineage: [key: atom(), order: atom()] | nil,
          lifecycle: {atom(), %{atom() => class()}} | nil,
          scope: scope(),
          content_hash: atom() | nil,
          parent: atom() | nil,
          published: [atom()],
          references: (struct() -> [{atom(), String.t()}]) | nil,
          validate: (struct() -> {:ok, [String.t()]} | {:error, term()}) | nil,
          differ: module() | nil,
          runs: {module(), atom()} | nil,
          door: term()
        }
end

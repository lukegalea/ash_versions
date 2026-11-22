defmodule AshVersions.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lukegalea/ash_versions"

  def project do
    [
      app: :ash_versions,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Versions of Ash records: a registry of versioned artifacts with semantic diffs, " <>
          "and every version of a temporal record through as-of reads.",
      package: package(),
      docs: &docs/0,
      dialyzer: [plt_local_path: "priv/plts", plt_core_path: "priv/plts", plt_add_apps: [:mix]]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      files:
        ~w(lib documentation mix.exs README.md CHANGELOG.md LICENSE usage-rules.md .formatter.exs),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/a-version-registry.md",
        "documentation/tutorials/temporal-history.md",
        "usage-rules.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r"documentation/tutorials",
        "About AshVersions": ["usage-rules.md", "CHANGELOG.md"]
      ],
      groups_for_modules: [
        Registry: [
          AshVersions.Registry,
          AshVersions.Artifact,
          AshVersions.Differ,
          AshVersions.Change
        ],
        "Temporal history": [AshVersions.TemporalHistory]
      ]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.37"},
      {:jason, "~> 1.4"},
      {:simple_sat, "~> 0.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end

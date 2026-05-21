defmodule L2E.MixProject do
  use Mix.Project

  def project do
    [
      app: :l2e,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {L2E.Application, []}
    ]
  end

  defp deps do
    [
      {:thousand_island, "~> 1.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:pbkdf2_elixir, "~> 2.2"},
      {:sweet_xml, "~> 0.7"}
    ]
  end
end

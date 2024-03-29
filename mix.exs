defmodule Lacca.MixProject do
  use Mix.Project

  def project do
    [
      app: :lacca,
      version: "0.2.2",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      package: package(),

      # ex_doc config
      name: "Lacca",
      source_url: "https://github.com/drbawb/shellac",
      docs: [
        main: "Lacca",
        extras: ["README.md"],
      ],

    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:msgpax, "~> 2.0"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:elixir_make, "~> 0.4", runtime: false},
      {:ex_doc, "~> 0.24.0", only: :dev, runtime: :false},
    ]
  end

  defp package do
    [
      description: "Library to manage OS processes from the Elixir runtime.",

      files: [
        "lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*", "Makefile",
        "resin/*.toml", "resin/*.lock", "resin/src/*"
      ],

      licenses: ["BSD-3-Clause"],
      links: %{"GitHub" => "https://github.com/drbawb/shellac"},
    ]
  end
end

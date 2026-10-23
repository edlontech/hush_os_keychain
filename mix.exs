defmodule HushOsKeychain.MixProject do
  use Mix.Project

  @source_url "https://github.com/edlontech/hush_os_keychain"

  def project do
    [
      app: :hush_os_keychain,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      description: "A Hush configuration provider backed by operating system keychains.",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => @source_url},
        files: [
          "lib",
          "native/hush_os_keychain/.cargo",
          "native/hush_os_keychain/src",
          "native/hush_os_keychain/Cargo*",
          "checksum-*.exs",
          "mix.exs",
          "README.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      docs: [main: "readme", extras: ["README.md"]],
      deps: deps()
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: :dev},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:hush, "~> 1.3"},
      {:mimic, "~> 2.0", only: :test},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:recode, "~> 0.8", only: [:dev], runtime: false},
      {:rustler, "~> 0.38.0", optional: true},
      {:rustler_precompiled, "~> 0.10"}
    ]
  end
end

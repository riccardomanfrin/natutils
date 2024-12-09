defmodule NatUtils.MixProject do
  use Mix.Project

  def project do
    [
      app: :natutils,
      description: description(),
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:nif] ++ Mix.compilers(),
      aliases: aliases()
    ]
  end

  defp description(), do:
  "NAT Utilities for (p2p) network management"

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package(), do:
    [
      name: "natutils",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/riccardomanfrin/natutils"}
    ]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:stun, "~>1.2.15"},
      # Non prod
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases() do
    [
      "compile.nif": ["cmd make -C c_src #"]
    ]
  end
end

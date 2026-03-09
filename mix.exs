defmodule DevPortAllocator.MixProject do
  use Mix.Project

  def project do
    [
      app: :dev_port_allocator,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
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
    []
  end

  defp description do
    "Allocate development ports dynamically with explicit env var precedence."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tillitio/dev_port_allocator"}
    ]
  end
end

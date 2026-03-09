# DevPortAllocator

Allocate development ports dynamically, while still honoring explicit env vars
like `PORT`.

Useful for Phoenix apps where port `4000` may already be taken.

## Production Warning

`DevPortAllocator` is for local development servers only.
It must not be used in production.
Use explicit, deterministic production port configuration instead.

## Installation

Add `dev_port_allocator` to your dependencies:

```elixir
def deps do
  [
    {:dev_port_allocator, git: "https://github.com/tillitio/dev_port_allocator.git", tag: "v0.1.0"}
  ]
end
```

## Usage

These examples are for development configuration only (for example in
`config/dev.exs` or `config/runtime.exs` guarded to dev).

### Single endpoint

```elixir
port_result = DevPortAllocator.resolve_port()

if port_result.source == :fallback do
  IO.puts("Default dev port 4000 is in use. Using #{port_result.port} instead.")
end

config :my_app, MyAppWeb.Endpoint, http: [port: port_result.port]
```

### Multi-endpoint contiguous block

```elixir
result =
  DevPortAllocator.resolve_block(System.get_env(),
    env_vars: ["PORT", "PORT_2", "PORT_3"],
    default_port: 4000,
    block_size: 3
  )

[primary_port, second_port, third_port] = result.ports
```

`env_vars` accepts any env var names.
If `PORT`/`PORT_2`/`PORT_3` are set, those explicit values are used.
Otherwise the allocator probes for the first available contiguous block.

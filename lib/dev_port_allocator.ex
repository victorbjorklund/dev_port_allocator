defmodule DevPortAllocator do
  @moduledoc """
  Resolve development ports dynamically while preserving explicit environment
  configuration.

  This library is framework-agnostic and can be used from `config/runtime.exs`
  in Phoenix (or any Elixir app that needs predictable local port allocation).
  WARNING: This library is intended for development servers only.
  Do not use it in production deployments.

  Typical behavior:

  - If a relevant env var is present, explicit values win.
  - If no explicit env vars are present, probe from a starting port.
  - When the default is busy, return the next available port (or contiguous
    block).
  """

  @default_port 4000
  @min_port 1
  @max_port 65_535

  @type source :: :explicit | :default | :fallback

  @type single_result :: %{port: pos_integer(), source: source()}
  @type block_result :: %{ports: [pos_integer()], source: source()}

  @doc """
  Resolve a single port.

  ## Options

  - `:env_var` - env var key used for explicit value (default: `"PORT"`)
  - `:default_port` - default preferred port (default: `4000`)
  - `:start_port` - first port to probe when no explicit env var exists
  - `:port_available?` - custom availability function for testing
  - `:ip` - bind address for availability checks (default: `{127, 0, 0, 1}`)

  ## Examples

      iex> DevPortAllocator.resolve_port(%{}, default_port: 4000, port_available?: fn p -> p == 4000 end)
      %{port: 4000, source: :default}

      iex> DevPortAllocator.resolve_port(%{"PORT" => "5050"})
      %{port: 5050, source: :explicit}
  """
  @spec resolve_port(map(), keyword()) :: single_result()
  def resolve_port(env \\ System.get_env(), opts \\ []) do
    env_var = Keyword.get(opts, :env_var, "PORT")
    default_port = Keyword.get(opts, :default_port, @default_port)

    result =
      resolve_block(env,
        env_vars: [env_var],
        default_port: default_port,
        start_port: Keyword.get(opts, :start_port, default_port),
        port_available?: Keyword.get(opts, :port_available?, &port_available?/1),
        ip: Keyword.get(opts, :ip, {127, 0, 0, 1}),
        block_size: 1
      )

    %{port: hd(result.ports), source: result.source}
  end

  @doc """
  Resolve a contiguous block of ports.

  ## Options

  - `:env_vars` - ordered env var keys for explicit ports
  - `:default_port` - default base port for the first entry (default: `4000`)
  - `:start_port` - first base port to probe (defaults to `:default_port`)
  - `:block_size` - number of contiguous ports to allocate
  - `:port_available?` - custom availability function for testing
  - `:ip` - bind address for availability checks (default: `{127, 0, 0, 1}`)

  If any `:env_vars` key is present, allocation is explicit and probing is
  skipped. Missing explicit keys use implied defaults based on the first port.
  """
  @spec resolve_block(map(), keyword()) :: block_result()
  def resolve_block(env \\ System.get_env(), opts \\ []) do
    env_vars = Keyword.get(opts, :env_vars, ["PORT"])
    default_port = Keyword.get(opts, :default_port, @default_port)
    block_size = Keyword.get(opts, :block_size, length(env_vars))
    start_port = Keyword.get(opts, :start_port, default_port)
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})

    port_available? =
      Keyword.get(opts, :port_available?, fn port -> port_available?(port, ip: ip) end)

    validate_env_vars!(env_vars)
    validate_block_size!(block_size)
    validate_port!(default_port, ":default_port")
    validate_port!(start_port, ":start_port")

    if explicit_port_env?(env, env_vars) do
      ports = explicit_ports!(env, env_vars, default_port, block_size)
      %{ports: ports, source: :explicit}
    else
      find_contiguous_ports!(start_port, block_size, default_port, port_available?)
    end
  end

  @doc """
  Check if a TCP port is available on localhost.
  """
  @spec port_available?(pos_integer(), keyword()) :: boolean()
  def port_available?(port, opts \\ []) when is_integer(port) do
    ip = Keyword.get(opts, :ip, {127, 0, 0, 1})

    case :gen_tcp.listen(port, [:binary, active: false, ip: ip, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp validate_env_vars!(env_vars) do
    if env_vars == [] or not Enum.all?(env_vars, &is_binary/1) do
      raise ArgumentError, ":env_vars must be a non-empty list of strings"
    end
  end

  defp validate_block_size!(block_size) do
    if not (is_integer(block_size) and block_size > 0) do
      raise ArgumentError, ":block_size must be a positive integer"
    end
  end

  defp explicit_port_env?(env, env_vars) do
    Enum.any?(env_vars, &Map.has_key?(env, &1))
  end

  defp explicit_ports!(env, env_vars, default_port, block_size) do
    first_env_var = hd(env_vars)
    first_port = parse_port!(Map.get(env, first_env_var), default_port, first_env_var)

    ports_from_env_vars =
      env_vars
      |> Enum.with_index()
      |> Enum.map(fn {env_var, index} ->
        parse_port!(Map.get(env, env_var), first_port + index, env_var)
      end)

    ports =
      if block_size > length(ports_from_env_vars) do
        extra =
          length(ports_from_env_vars)..(block_size - 1)
          |> Enum.map(fn offset ->
            validate_port!(first_port + offset, "implied explicit port")
          end)

        ports_from_env_vars ++ extra
      else
        Enum.take(ports_from_env_vars, block_size)
      end

    validate_unique_ports!(ports)
    ports
  end

  defp parse_port!(nil, default, env_name), do: validate_port!(default, env_name)

  defp parse_port!(value, _default, env_name) do
    case Integer.parse(value) do
      {port, ""} when port in @min_port..@max_port ->
        port

      _ ->
        raise ArgumentError, "Invalid #{env_name}: #{inspect(value)}"
    end
  end

  defp validate_unique_ports!(ports) do
    if Enum.uniq(ports) != ports do
      raise ArgumentError, "Configured ports must be unique"
    end
  end

  defp validate_port!(port, _name) when is_integer(port) and port in @min_port..@max_port,
    do: port

  defp validate_port!(port, name) do
    raise ArgumentError, "Invalid #{name}: #{inspect(port)}"
  end

  defp find_contiguous_ports!(start_port, block_size, default_port, port_available?) do
    max_base_port = @max_port - (block_size - 1)

    if start_port > max_base_port do
      raise ArgumentError,
            "Unable to find #{block_size} contiguous open ports starting from #{start_port}"
    end

    start_port..max_base_port
    |> Enum.find_value(fn base_port ->
      ports = Enum.to_list(base_port..(base_port + block_size - 1))

      if Enum.all?(ports, port_available?) do
        source = if base_port == default_port, do: :default, else: :fallback
        %{ports: ports, source: source}
      end
    end)
    |> case do
      nil ->
        raise ArgumentError,
              "Unable to find #{block_size} contiguous open ports starting from #{start_port}"

      result ->
        result
    end
  end
end

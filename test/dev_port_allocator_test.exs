defmodule DevPortAllocatorTest do
  use ExUnit.Case, async: true

  doctest DevPortAllocator

  test "resolve_port/2 uses default port when available" do
    checker = fn port -> port == 4000 end

    assert %{port: 4000, source: :default} =
             DevPortAllocator.resolve_port(%{}, default_port: 4000, port_available?: checker)
  end

  test "resolve_port/2 falls back when default is unavailable" do
    checker = fn
      4000 -> false
      4001 -> true
      _ -> false
    end

    assert %{port: 4001, source: :fallback} =
             DevPortAllocator.resolve_port(%{}, default_port: 4000, port_available?: checker)
  end

  test "resolve_port/2 uses explicit PORT when provided" do
    assert %{port: 5050, source: :explicit} =
             DevPortAllocator.resolve_port(%{"PORT" => "5050"})
  end

  test "resolve_block/2 uses default contiguous ports when available" do
    checker = fn port -> port in 4000..4002 end

    assert %{ports: [4000, 4001, 4002], source: :default} =
             DevPortAllocator.resolve_block(%{},
               env_vars: ["PORT", "PORT_2", "PORT_3"],
               block_size: 3,
               default_port: 4000,
               port_available?: checker
             )
  end

  test "resolve_block/2 finds next contiguous block when default is busy" do
    checker = fn
      port when port in 4000..4002 -> false
      port when port in 4003..4005 -> true
      _ -> false
    end

    assert %{ports: [4003, 4004, 4005], source: :fallback} =
             DevPortAllocator.resolve_block(%{},
               env_vars: ["PORT", "PORT_2", "PORT_3"],
               block_size: 3,
               default_port: 4000,
               port_available?: checker
             )
  end

  test "resolve_block/2 applies implied defaults for missing explicit vars" do
    assert %{ports: [5010, 5011, 5012], source: :explicit} =
             DevPortAllocator.resolve_block(
               %{"PORT" => "5010"},
               env_vars: ["PORT", "PORT_2", "PORT_3"],
               block_size: 3
             )
  end

  test "resolve_block/2 uses explicit overrides when all env vars are present" do
    assert %{ports: [5010, 6101, 6102], source: :explicit} =
             DevPortAllocator.resolve_block(
               %{
                 "PORT" => "5010",
                 "PORT_2" => "6101",
                 "PORT_3" => "6102"
               },
               env_vars: ["PORT", "PORT_2", "PORT_3"],
               block_size: 3
             )
  end

  test "resolve_block/2 raises when explicit ports are duplicated" do
    assert_raise ArgumentError, ~r/must be unique/, fn ->
      DevPortAllocator.resolve_block(
        %{"PORT" => "4000", "PORT_2" => "4000"},
        env_vars: ["PORT", "PORT_2", "PORT_3"],
        block_size: 3
      )
    end
  end

  test "resolve_port/2 raises for invalid explicit values" do
    assert_raise ArgumentError, ~r/Invalid PORT/, fn ->
      DevPortAllocator.resolve_port(%{"PORT" => "abc"})
    end
  end

  test "resolve_block/2 raises when implied explicit ports exceed TCP range" do
    assert_raise ArgumentError, ~r/Invalid/, fn ->
      DevPortAllocator.resolve_block(
        %{"PORT" => "65535"},
        env_vars: ["PORT", "PORT_2"],
        block_size: 2
      )
    end
  end

  test "resolve_block/2 raises when start_port cannot fit requested block size" do
    assert_raise ArgumentError,
                 ~r/Unable to find 2 contiguous open ports starting from 65535/,
                 fn ->
                   DevPortAllocator.resolve_block(%{},
                     start_port: 65535,
                     block_size: 2,
                     port_available?: fn _ -> true end
                   )
                 end
  end

  test "resolve_port/2 raises when default_port or start_port are out of range" do
    assert_raise ArgumentError, ~r/Invalid :default_port/, fn ->
      DevPortAllocator.resolve_port(%{}, default_port: 0)
    end

    assert_raise ArgumentError, ~r/Invalid :start_port/, fn ->
      DevPortAllocator.resolve_port(%{}, default_port: 4000, start_port: 0)
    end
  end
end

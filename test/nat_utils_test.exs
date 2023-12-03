defmodule NatUtilsTest do
  use ExUnit.Case
  doctest NatUtils

  test "greets the world" do
    assert NatUtils.hello() == :world
  end
end

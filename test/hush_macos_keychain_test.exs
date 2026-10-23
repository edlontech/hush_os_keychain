defmodule HushMacosKeychainTest do
  use ExUnit.Case
  doctest HushMacosKeychain

  test "greets the world" do
    assert HushMacosKeychain.hello() == :world
  end
end

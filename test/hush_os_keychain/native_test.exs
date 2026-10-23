defmodule HushOsKeychain.NativeTest do
  use ExUnit.Case, async: true

  alias HushOsKeychain.Native

  test "module loads and exports the NIF functions" do
    assert Code.ensure_loaded?(Native)
    assert function_exported?(Native, :fetch, 2)
    assert function_exported?(Native, :put, 3)
    assert function_exported?(Native, :delete, 2)
  end
end

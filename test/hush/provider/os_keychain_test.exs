defmodule Hush.Provider.OsKeychainTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Hush.Provider.OsKeychain
  alias HushOsKeychain.Store

  @moduletag capture_log: true

  setup do
    stub(Store)
    Logger.put_process_level(self(), :debug)
    :ok
  end

  test "returns the stored value" do
    stub(Store, :fetch, fn "svc", nil -> {:ok, "value"} end)

    assert OsKeychain.fetch("svc") == {:ok, "value"}
    assert Hush.Provider.fetch(OsKeychain, "svc") == {:ok, "value"}
  end

  test "a missing item is :not_found" do
    stub(Store, :fetch, fn _, _ -> {:error, :not_found} end)

    assert OsKeychain.fetch("svc") == {:error, :not_found}
  end

  test "an unavailable store is :not_found and logged at debug" do
    stub(Store, :fetch, fn _, _ -> {:error, {:unavailable, "no credential store"}} end)

    log =
      capture_log([level: :debug], fn ->
        assert OsKeychain.fetch("svc") == {:error, :not_found}
      end)

    assert log =~ ~s("svc")
    assert log =~ "no credential store"
  end

  test "refusing or broken stores fail loudly with a message" do
    for error <- [
          {:access_denied, "locked"},
          {:ambiguous, 2},
          {:native_not_loaded, "native library failed to load: x"}
        ] do
      stub(Store, :fetch, fn _, _ -> {:error, error} end)
      expected = {:error, HushOsKeychain.format_error(error, "svc")}

      assert OsKeychain.fetch("svc") == expected
      assert Hush.Provider.fetch(OsKeychain, "svc") == expected
    end
  end
end

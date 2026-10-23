defmodule HushOsKeychain.IntegrationTest do
  use ExUnit.Case, async: false

  alias Hush.Provider.OsKeychain

  @moduletag :integration

  setup context do
    service = "hush_os_keychain_test.#{System.unique_integer([:positive])}"
    accounts = Map.get(context, :accounts, ["hush"])
    previous_config = Application.fetch_env(:hush, OsKeychain)

    on_exit(fn ->
      case previous_config do
        {:ok, config} -> Application.put_env(:hush, OsKeychain, config)
        :error -> Application.delete_env(:hush, OsKeychain)
      end
    end)

    Application.delete_env(:hush, OsKeychain)

    on_exit(fn ->
      for account <- accounts do
        case HushOsKeychain.delete(service, account: account) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          error -> flunk("Cleanup failed for #{service}, account #{account}: #{inspect(error)}")
        end
      end
    end)

    {:ok, service: service}
  end

  test "stored values are available through the public API and Hush", %{service: service} do
    assert :ok = HushOsKeychain.put(service, "integration-value")
    assert HushOsKeychain.fetch(service) == {:ok, "integration-value"}
    assert Hush.Provider.fetch(OsKeychain, service) == {:ok, "integration-value"}
  end

  test "a missing service is not found through either interface", %{service: service} do
    assert HushOsKeychain.fetch(service) == {:error, :not_found}
    assert Hush.Provider.fetch(OsKeychain, service) == {:error, :not_found}
  end

  test "deleting an item makes it unavailable", %{service: service} do
    assert :ok = HushOsKeychain.put(service, "delete-value")
    assert :ok = HushOsKeychain.delete(service)
    assert HushOsKeychain.fetch(service) == {:error, :not_found}
  end

  @tag accounts: ["a", "b"]
  @tag skip: match?({:win32, _}, :os.type())
  test "accounts disambiguate multiple items under one service", %{service: service} do
    assert :ok = HushOsKeychain.put(service, "value-a", account: "a")
    assert :ok = HushOsKeychain.put(service, "value-b", account: "b")
    assert HushOsKeychain.fetch(service, account: "b") == {:ok, "value-b"}
    assert HushOsKeychain.fetch(service) == {:error, {:ambiguous, 2}}
  end

  @tag accounts: ["a"]
  @tag skip: not match?({:win32, _}, :os.type())
  test "Windows isolates credentials by account", %{service: service} do
    assert :ok = HushOsKeychain.put(service, "windows-value", account: "a")
    assert HushOsKeychain.fetch(service, account: "b") == {:error, :not_found}
    assert HushOsKeychain.fetch(service, account: "a") == {:ok, "windows-value"}
  end

  @tag accounts: ["a", "b"]
  test "the provider honors the configured account", %{service: service} do
    assert :ok = HushOsKeychain.put(service, "value-a", account: "a")
    assert :ok = HushOsKeychain.put(service, "value-b", account: "b")
    Application.put_env(:hush, OsKeychain, account: "b")

    assert Hush.Provider.fetch(OsKeychain, service) == {:ok, "value-b"}
  end
end

defmodule HushOsKeychainTest do
  use ExUnit.Case, async: false
  use Mimic

  alias HushOsKeychain.Store

  setup do
    stub(Store)
    on_exit(fn -> Application.delete_env(:hush, Hush.Provider.OsKeychain) end)
  end

  describe "account resolution" do
    test "fetch and delete pass nil when no account is configured" do
      expect(Store, :fetch, fn "svc", nil -> {:ok, "value"} end)
      expect(Store, :delete, fn "svc", nil -> :ok end)

      assert HushOsKeychain.fetch("svc") == {:ok, "value"}
      assert HushOsKeychain.delete("svc") == :ok
    end

    test "put falls back to the hush account" do
      expect(Store, :put, fn "svc", "hush", "value" -> :ok end)

      assert HushOsKeychain.put("svc", "value") == :ok
    end

    test "configured account is used when opts have none" do
      Application.put_env(:hush, Hush.Provider.OsKeychain, account: "config")
      expect(Store, :fetch, fn "svc", "config" -> {:ok, "value"} end)
      expect(Store, :put, fn "svc", "config", "value" -> :ok end)
      expect(Store, :delete, fn "svc", "config" -> :ok end)

      assert HushOsKeychain.fetch("svc") == {:ok, "value"}
      assert HushOsKeychain.put("svc", "value") == :ok
      assert HushOsKeychain.delete("svc") == :ok
    end

    test "opts account wins over config" do
      Application.put_env(:hush, Hush.Provider.OsKeychain, account: "config")
      expect(Store, :fetch, fn "svc", "opts" -> {:error, :not_found} end)
      expect(Store, :put, fn "svc", "opts", "value" -> :ok end)
      expect(Store, :delete, fn "svc", "opts" -> :ok end)

      assert HushOsKeychain.fetch("svc", account: "opts") == {:error, :not_found}
      assert HushOsKeychain.put("svc", "value", account: "opts") == :ok
      assert HushOsKeychain.delete("svc", account: "opts") == :ok
    end
  end

  describe "validation" do
    test "rejects an empty or non-string service before reaching the store" do
      reject(Store, :fetch, 2)
      reject(Store, :put, 3)
      reject(Store, :delete, 2)
      error = {:error, {:invalid, "service must be a non-empty string"}}

      assert HushOsKeychain.fetch("") == error
      assert HushOsKeychain.put(nil, "value") == error
      assert HushOsKeychain.delete(:svc) == error
    end

    test "rejects an empty or non-UTF-8 secret without echoing it" do
      reject(Store, :put, 3)
      error = {:error, {:invalid, "secret must be a non-empty string"}}

      assert HushOsKeychain.put("svc", "") == error
      assert HushOsKeychain.put("svc", <<0xFF, 0xFE>>) == error
    end

    test "rejects a non-string account" do
      reject(Store, :fetch, 2)
      reject(Store, :put, 3)

      assert HushOsKeychain.fetch("svc", account: :ygor) ==
               {:error, {:invalid, "account must be a non-empty string"}}

      assert HushOsKeychain.put("svc", "value", account: "") ==
               {:error, {:invalid, "account must be a non-empty string"}}
    end
  end

  describe "native library not loaded" do
    test "an undefined native module becomes :native_not_loaded" do
      stub(Store, :fetch, fn _, _ ->
        raise UndefinedFunctionError, module: HushOsKeychain.Native, function: :fetch, arity: 2
      end)

      assert {:error, {:native_not_loaded, "native library failed to load: " <> _}} =
               HushOsKeychain.fetch("svc")
    end

    test ":nif_not_loaded becomes :native_not_loaded" do
      stub(Store, :delete, fn _, _ -> :erlang.nif_error(:nif_not_loaded) end)

      assert {:error, {:native_not_loaded, "native library failed to load: " <> _}} =
               HushOsKeychain.delete("svc")
    end
  end

  describe "unexpected native exceptions" do
    test "become :platform errors that never carry the secret" do
      secret = "s3cret-value"

      exceptions = [
        %ErlangError{original: :nif_panicked},
        %ArgumentError{message: "badarg: " <> secret},
        %UndefinedFunctionError{module: SomeOther, function: :put, arity: 3}
      ]

      for exception <- exceptions do
        stub(Store, :put, fn _, _, _ -> raise exception end)

        assert {:error, {:platform, message} = error} =
                 HushOsKeychain.put("svc", secret, [])

        assert message == "native call failed: " <> inspect(exception.__struct__)
        refute HushOsKeychain.format_error(error, "svc") =~ secret
      end
    end
  end

  describe "format_error/2" do
    test "names the store and the service" do
      message = HushOsKeychain.format_error({:access_denied, "user canceled"}, "svc")

      assert message =~ ~r/^(macOS Keychain|Secret Service|Windows Credential Manager): /
      assert message =~ ~s(access denied: user canceled (service "svc"\))
    end

    test "tells the user to set an account when several items match" do
      message = HushOsKeychain.format_error({:ambiguous, 2}, "svc")

      assert message =~ "2 items match"
      assert message =~ ~s(config :hush, Hush.Provider.OsKeychain, account: "...")
    end

    test "never contains the secret for any error kind" do
      secret = "s3cret-value"

      errors = [
        :not_found,
        {:unavailable, "no credential store"},
        {:ambiguous, 3},
        {:access_denied, "locked"},
        {:invalid, "stored value is not UTF-8 text"},
        {:platform, "boom"}
      ]

      returned =
        for error <- errors do
          stub(Store, :put, fn "svc", "hush", ^secret -> {:error, error} end)
          HushOsKeychain.put("svc", secret)
        end

      stub(Store, :put, fn _, _, _ -> :erlang.nif_error(:nif_not_loaded) end)
      nif_error = HushOsKeychain.put("svc", secret)

      stub(Store, :put, fn _, _, _ ->
        raise UndefinedFunctionError, module: HushOsKeychain.Native, function: :put, arity: 3
      end)

      undefined_error = HushOsKeychain.put("svc", secret)

      for {:error, error} <-
            returned ++
              [nif_error, undefined_error, HushOsKeychain.put("svc", <<0xFF>> <> secret)] do
        refute inspect(error) =~ secret
        refute HushOsKeychain.format_error(error, "svc") =~ secret
      end
    end
  end
end

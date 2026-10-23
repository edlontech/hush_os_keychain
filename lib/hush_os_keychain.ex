defmodule HushOsKeychain do
  @moduledoc """
  Stores, fetches, and deletes generic passwords in macOS Keychain, Linux Secret
  Service, and Windows Credential Manager.

  The service is the Hush key. The account comes from the `:account` option, then
  `config :hush, Hush.Provider.OsKeychain, account: ...`. Writes default to the
  account `"hush"`; reads and deletes without an account search by service alone.

  See the [README](readme.html) for installation, Hush setup, OS tools, lookup
  rules, and platform and security limitations.
  """

  alias HushOsKeychain.Store

  @type error ::
          :not_found
          | {:unavailable, String.t()}
          | {:ambiguous, pos_integer()}
          | {:access_denied, String.t()}
          | {:invalid, String.t()}
          | {:platform, String.t()}
          | {:native_not_loaded, String.t()}

  @default_put_account "hush"

  @doc """
  Fetches the secret stored under `service`.

  Without an account, exactly one item with that service must exist.

  ## Options

    * `:account` - the account of the item

  ## Examples

      HushOsKeychain.fetch("myapp.db_password")
      #=> {:ok, "s3cret"}

      HushOsKeychain.fetch("myapp.db_password", account: "ygor")
      #=> {:error, :not_found}
  """
  @spec fetch(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def fetch(service, opts \\ []) do
    with :ok <- validate(service, "service"),
         {:ok, account} <- account(opts) do
      call(fn -> Store.fetch(service, account) end)
    end
  end

  @doc """
  Stores `secret` under `service`, replacing an existing item for the same account.

  The account falls back to `"hush"` when none is configured.

  ## Options

    * `:account` - the account of the item

  ## Examples

      HushOsKeychain.put("myapp.db_password", "s3cret")
      #=> :ok
  """
  @spec put(String.t(), String.t(), keyword()) :: :ok | {:error, error()}
  def put(service, secret, opts \\ []) do
    with :ok <- validate(service, "service"),
         :ok <- validate(secret, "secret"),
         {:ok, account} <- account(opts) do
      call(fn -> Store.put(service, account || @default_put_account, secret) end)
    end
  end

  @doc """
  Deletes the item stored under `service`, resolved the same way as `fetch/2`.

  ## Options

    * `:account` - the account of the item

  ## Examples

      HushOsKeychain.delete("myapp.db_password")
      #=> :ok
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, error()}
  def delete(service, opts \\ []) do
    with :ok <- validate(service, "service"),
         {:ok, account} <- account(opts) do
      call(fn -> Store.delete(service, account) end)
    end
  end

  @doc """
  Formats an error returned by this module, naming the OS store and the service.

  ## Examples

      HushOsKeychain.format_error({:access_denied, "user canceled"}, "myapp.db_password")
      #=> "macOS Keychain: access denied: user canceled (service \\"myapp.db_password\\")"
  """
  @spec format_error(error(), String.t()) :: String.t()
  def format_error({:ambiguous, _} = error, service) do
    base_message(error, service) <>
      "; set config :hush, Hush.Provider.OsKeychain, account: \"...\" to pick one"
  end

  def format_error(error, service), do: base_message(error, service)

  defp base_message(error, service),
    do: "#{store_name()}: #{reason(error)} (service #{inspect(service)})"

  defp reason(:not_found), do: "item not found"
  defp reason({:unavailable, message}), do: "store unavailable: #{message}"
  defp reason({:ambiguous, count}), do: "#{count} items match"
  defp reason({:access_denied, message}), do: "access denied: #{message}"
  defp reason({:invalid, message}), do: "invalid: #{message}"
  defp reason({:platform, message}), do: "platform error: #{message}"
  defp reason({:native_not_loaded, message}), do: message

  defp store_name do
    case :os.type() do
      {:unix, :darwin} -> "macOS Keychain"
      {:win32, _} -> "Windows Credential Manager"
      _ -> "Secret Service"
    end
  end

  defp account(opts) do
    case Keyword.get(opts, :account) ||
           Application.get_env(:hush, Hush.Provider.OsKeychain, [])[:account] do
      nil -> {:ok, nil}
      account -> with :ok <- validate(account, "account"), do: {:ok, account}
    end
  end

  # String.valid? keeps non-UTF-8 binaries away from the NIF, whose badarg stacktrace would carry the arguments.
  defp validate(value, name) do
    if is_binary(value) and value != "" and String.valid?(value),
      do: :ok,
      else: {:error, {:invalid, "#{name} must be a non-empty string"}}
  end

  defp call(fun) do
    fun.()
  rescue
    error ->
      case error do
        %UndefinedFunctionError{module: HushOsKeychain.Native} -> not_loaded(error)
        %ErlangError{original: :nif_not_loaded} -> not_loaded(error)
        _ -> {:error, {:platform, "native call failed: " <> inspect(error.__struct__)}}
      end
  end

  defp not_loaded(exception) do
    {:error,
     {:native_not_loaded, "native library failed to load: #{Exception.message(exception)}"}}
  end
end

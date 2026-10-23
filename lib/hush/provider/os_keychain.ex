defmodule Hush.Provider.OsKeychain do
  @moduledoc """
  Provider to read secrets from the operating system keychain.

  The key is the service of a generic password item:

      config :app, MyApp.Repo,
        password: {:hush, Hush.Provider.OsKeychain, "myapp.db_password"}

      # optional, required when several items share a service
      config :hush, Hush.Provider.OsKeychain, account: "ygor"

  A missing item, or a machine without a usable store, returns `{:error, :not_found}`
  so Hush applies `default` or `optional`. Any other failure returns an error message.
  """

  @behaviour Hush.Provider

  require Logger

  @impl true
  @spec load(keyword()) :: :ok
  def load(_config), do: :ok

  @impl true
  @spec fetch(String.t()) :: {:ok, String.t()} | {:error, :not_found} | {:error, String.t()}
  def fetch(key) do
    case HushOsKeychain.fetch(key) do
      {:ok, value} ->
        {:ok, value}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:unavailable, message}} ->
        Logger.debug("OS keychain unavailable for service #{inspect(key)}: #{message}")
        {:error, :not_found}

      {:error, error} ->
        {:error, HushOsKeychain.format_error(error, key)}
    end
  end
end

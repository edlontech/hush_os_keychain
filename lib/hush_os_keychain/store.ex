defmodule HushOsKeychain.Store do
  @moduledoc false

  # Mimic cannot copy HushOsKeychain.Native: the renamed copy re-runs @on_load and the NIF rejects it.

  alias HushOsKeychain.Native

  defdelegate fetch(service, account), to: Native
  defdelegate put(service, account, secret), to: Native
  defdelegate delete(service, account), to: Native
end

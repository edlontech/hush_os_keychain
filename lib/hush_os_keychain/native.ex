defmodule HushOsKeychain.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  targets =
    ~w(aarch64-apple-darwin x86_64-apple-darwin aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu x86_64-pc-windows-msvc)

  force_build? =
    System.get_env("HUSH_OS_KEYCHAIN_BUILD") in ["1", "true"] or Mix.env() in [:dev, :test]

  supported? =
    case RustlerPrecompiled.target() do
      {:ok, "nif-" <> rest} -> List.last(String.split(rest, "-", parts: 2)) in targets
      {:error, _} -> false
    end

  @spec fetch(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  @spec put(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  @spec delete(String.t(), String.t() | nil) :: :ok | {:error, term()}

  if force_build? or supported? do
    use RustlerPrecompiled,
      otp_app: :hush_os_keychain,
      crate: "hush_os_keychain",
      base_url: "#{Mix.Project.config()[:source_url]}/releases/download/v#{version}",
      version: version,
      targets: targets,
      nif_versions: ["2.17"],
      force_build: force_build?

    def fetch(_service, _account), do: :erlang.nif_error(:nif_not_loaded)
    def put(_service, _account, _secret), do: :erlang.nif_error(:nif_not_loaded)
    def delete(_service, _account), do: :erlang.nif_error(:nif_not_loaded)
  else
    @reason "no precompiled native library for this platform"
    def fetch(_service, _account), do: {:error, {:unavailable, @reason}}
    def put(_service, _account, _secret), do: {:error, {:unavailable, @reason}}
    def delete(_service, _account), do: {:error, {:unavailable, @reason}}
  end
end

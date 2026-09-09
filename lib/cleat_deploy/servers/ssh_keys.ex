defmodule CleatDeploy.Servers.SshKeys do
  @moduledoc false

  def generate do
    base = Path.join(System.tmp_dir!(), "paas-ssh-#{System.unique_integer([:positive])}")

    try do
      case System.cmd(
             "ssh-keygen",
             ["-t", "ed25519", "-N", "", "-f", base, "-q", "-C", "cleat-deploy"],
             stderr_to_stdout: true
           ) do
        {_out, 0} ->
          private = File.read!(base)
          public = File.read!(base <> ".pub") |> String.trim()
          {:ok, %{private: private, public: public}}

        {err, _} ->
          {:error, err}
      end
    after
      File.rm(base)
      File.rm(base <> ".pub")
    end
  end

  def public_from_private(pem) when is_binary(pem) and pem != "" do
    path = Path.join(System.tmp_dir!(), "paas-ssh-#{System.unique_integer([:positive])}")

    try do
      File.write!(path, String.trim(pem) <> "\n")
      File.chmod!(path, 0o600)

      case System.cmd("ssh-keygen", ["-y", "-f", path], stderr_to_stdout: true) do
        {out, 0} -> {:ok, String.trim(out)}
        {err, _} -> {:error, err}
      end
    after
      File.rm(path)
    end
  end

  def public_from_private(_), do: {:error, :missing_ssh_key}
end

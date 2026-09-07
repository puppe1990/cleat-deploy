defmodule PhoenixPaas.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :phoenix_paas

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          PhoenixPaas.Seeds.run()
        end)
    end

    :ok
  end

  @doc """
  Re-encrypts and stores an SSH private key for a deploy server.

  Use when a Lightsail key was missing or corrupt in the panel database:

      bin/phoenix_paas eval 'PhoenixPaas.Release.fix_server_ssh("gestaobem-cx33", "/home/ubuntu/lightsail-key.pem")'
  """
  def fix_server_ssh(server_name, key_path)
      when is_binary(server_name) and is_binary(key_path) do
    load_app()
    import Ecto.Query

    {:ok, _, _} =
      Ecto.Migrator.with_repo(PhoenixPaas.Repo, fn _repo ->
        {:ok, _} = PhoenixPaas.Vault.start_link()
        key = File.read!(key_path)

        server =
          PhoenixPaas.Repo.one!(
            from s in PhoenixPaas.Servers.Server, where: s.name == ^server_name, limit: 1
          )

        server
        |> PhoenixPaas.Servers.Server.changeset(%{ssh_private_key: key})
        |> PhoenixPaas.Repo.update!()

        IO.puts("SSH key updated for #{server_name}")
      end)

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

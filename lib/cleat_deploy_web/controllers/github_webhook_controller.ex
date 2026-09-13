defmodule CleatDeployWeb.GithubWebhookController do
  use CleatDeployWeb, :controller

  require Logger

  alias CleatDeploy.{Apps, Deployments, Github}

  def create(conn, _params) do
    raw_body = conn.private[:raw_body] || ""
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()

    result =
      with {:ok, payload} <- decode_payload(raw_body),
           repo when is_binary(repo) <- Github.repo_full_name(payload) || :missing_repo,
           %{} = app <- find_app_by_repo_and_signature(repo, raw_body, signature),
           {:ok, attrs} <- normalize_push_attrs(payload, app),
           true <- app.auto_deploy || :auto_deploy_off,
           {:ok, job} <- Deployments.enqueue(app, attrs) do
        {:queued, app, job}
      end

    case result do
      {:queued, app, job} ->
        Logger.info(
          "github webhook queued deploy app=#{app.slug} job=#{job.id} repo=#{app.github_repo}"
        )

        send_resp(conn, :accepted, "queued")

      :not_found ->
        Logger.warning("github webhook unknown repo")
        send_resp(conn, :not_found, "unknown repo")

      :missing_repo ->
        Logger.warning("github webhook payload missing repository.full_name")
        send_resp(conn, :bad_request, "missing repository")

      {:ignore, app, {:wrong_branch, ref}} ->
        Logger.info(
          "github webhook ignored app=#{app.slug} ref=#{ref} expected_branch=#{app.branch}"
        )

        send_resp(
          conn,
          :ok,
          "ignored: push to #{ref}, app #{app.slug} auto-deploys #{app.branch}"
        )

      {:ignore, app, reason} ->
        Logger.info("github webhook ignored app=#{app.slug} reason=#{inspect(reason)}")
        send_resp(conn, :ok, "ignored")

      :auto_deploy_off ->
        Logger.info("github webhook auto_deploy disabled")
        send_resp(conn, :ok, "auto deploy disabled")

      false ->
        # legacy path if auto_deploy check returns false without atom
        send_resp(conn, :ok, "auto deploy disabled")

      :error ->
        Logger.warning("github webhook invalid signature")
        send_resp(conn, :unauthorized, "invalid signature")

      {:error, reason} ->
        Logger.error("github webhook enqueue failed: #{inspect(reason)}")
        send_resp(conn, :bad_request, "invalid payload")
    end
  end

  defp find_app_by_repo_and_signature(repo, raw_body, signature) do
    apps = Apps.list_apps_by_repo(repo)

    cond do
      apps == [] ->
        :not_found

      signature in [nil, ""] ->
        :error

      true ->
        Enum.find_value(apps, :error, fn app ->
          case Github.verify_signature(raw_body, signature, app.webhook_secret) do
            :ok -> app
            :error -> nil
          end
        end)
    end
  end

  defp decode_payload(raw_body) when is_binary(raw_body) and raw_body != "" do
    case Jason.decode(raw_body) do
      {:ok, payload} -> {:ok, payload}
      _ -> {:error, :invalid_json}
    end
  end

  defp decode_payload(_), do: {:error, :empty_body}

  defp normalize_push_attrs(payload, app) do
    case Github.push_deploy_attrs(payload, app.branch) do
      {:ok, attrs} -> {:ok, attrs}
      {:ignore, reason} -> {:ignore, app, reason}
    end
  end
end

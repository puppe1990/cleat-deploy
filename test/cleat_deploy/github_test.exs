defmodule CleatDeploy.GithubTest do
  use ExUnit.Case, async: true

  alias CleatDeploy.Github

  test "verify_signature/3 accepts valid signature" do
    secret = "webhook-secret"
    body = ~s({"ref":"refs/heads/main"})

    signature =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    assert :ok = Github.verify_signature(body, signature, secret)
  end

  test "verify_signature/3 rejects invalid signature" do
    assert :error = Github.verify_signature("{}", "sha256=bad", "secret")
  end

  test "push_deploy_attrs/2 for matching branch" do
    payload = %{
      "ref" => "refs/heads/main",
      "after" => "abc123"
    }

    assert {:ok, attrs} = Github.push_deploy_attrs(payload, "main")
    assert attrs.git_sha == "abc123"
    assert attrs.triggered_by == "webhook"
  end

  test "push_deploy_attrs/2 ignores other branches with the received ref" do
    payload = %{"ref" => "refs/heads/main", "after" => "abc123"}

    assert {:ignore, {:wrong_branch, "main"}} =
             Github.push_deploy_attrs(payload, "deploy-cleat")
  end

  test "push_deploy_attrs/2 ignores deleted refs" do
    payload = %{"ref" => "refs/heads/main", "after" => String.duplicate("0", 40)}
    assert {:ignore, :deleted_ref} = Github.push_deploy_attrs(payload, "main")
  end

  test "list_repos/0 returns a list when token is missing" do
    assert Github.list_repos() == []
  end
end

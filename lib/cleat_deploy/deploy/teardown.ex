defmodule CleatDeploy.Deploy.Teardown do
  @moduledoc """
  Best-effort remote cleanup when an app is deleted from the panel.
  """

  alias CleatDeploy.Apps.App
  alias CleatDeploy.Deploy.Ssh
  alias CleatDeploy.Deploy.SshRunner

  def run(%App{} = app) do
    if remote_enabled?() do
      remote(app)
    else
      :ok
    end
  end

  def script(%App{} = app) do
    config = App.deploy_config(app)
    unit = config.systemd_unit
    release_path = config.release_path
    env_file = config.env_file
    host = app.host

    """
    set -u
    UNIT=#{sh_quote(unit)}
    RELEASE=#{sh_quote(release_path)}
    ENVFILE=#{sh_quote(env_file)}
    HOST=#{sh_quote(host)}

    sudo systemctl stop "$UNIT" 2>/dev/null || true
    sudo systemctl disable "$UNIT" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${UNIT}.service"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo rm -rf "$RELEASE"
    sudo rm -f "$ENVFILE"

    if [[ -f /etc/caddy/Caddyfile ]]; then
      TEARDOWN_HOST="$HOST" sudo -E python3 - <<'PY'
    import os
    from pathlib import Path

    host = os.environ.get("TEARDOWN_HOST", "")
    path = Path("/etc/caddy/Caddyfile")
    if not host or not path.exists():
        raise SystemExit(0)

    text = path.read_text()
    needle = host + " {"
    out = []
    i = 0
    changed = False
    while i < len(text):
        idx = text.find(needle, i)
        if idx == -1:
            out.append(text[i:])
            break
        if idx > 0 and text[idx - 1] not in "\\n":
            out.append(text[i:idx + len(needle)])
            i = idx + len(needle)
            continue
        out.append(text[i:idx])
        brace = text.find("{", idx)
        depth = 0
        j = brace
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    if j < len(text) and text[j] == "\\n":
                        j += 1
                    i = j
                    changed = True
                    break
            j += 1
        else:
            i = len(text)
    new = "".join(out)
    if changed and new != text:
        path.write_text(new)
    PY
      sudo systemctl reload caddy 2>/dev/null || true
    fi
    """
  end

  defp remote(%App{} = app) do
    server = app.server

    if is_nil(server) do
      {:error, :missing_server}
    else
      Ssh.run(server, app, ["bash", "-lc", script(app)])
    end
  end

  defp remote_enabled? do
    Application.get_env(:cleat_deploy, :deploy_runner, CleatDeploy.Deploy.FakeRunner) ==
      SshRunner
  end

  defp sh_quote(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end

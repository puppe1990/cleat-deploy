defmodule CleatDeploy.Deploy.RuntimePackagesTest do
  use ExUnit.Case, async: true

  alias CleatDeploy.Apps.App
  alias CleatDeploy.Deploy.RuntimePackages

  test "merges slug profile, app packages, and repo manifest" do
    tmp = System.tmp_dir!() |> Path.join("runtime_packages_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, ".cleat_deploy"))
    File.write!(Path.join(tmp, ".cleat_deploy/runtime-packages"), "curl\n# comment\njq\n")

    app = %App{slug: "rapid-tools", runtime_apt_packages: ["unzip"]}

    assert %{packages: packages} = RuntimePackages.resolve(app, tmp)
    assert "zip" in packages
    assert "ffmpeg" in packages
    assert "jq" in packages
    assert "curl" in packages
    assert "unzip" in packages
    refute "#" in packages

    File.rm_rf!(tmp)
  end

  test "loads post-install script from repo manifest directory" do
    tmp = System.tmp_dir!() |> Path.join("runtime_post_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, ".cleat_deploy"))
    File.write!(Path.join(tmp, ".cleat_deploy/post-install.sh"), "echo post-install\n")

    app = %App{slug: "my-app", runtime_apt_packages: []}

    assert %{post_install: steps} = RuntimePackages.resolve(app, tmp)
    assert "echo post-install" in steps

    File.rm_rf!(tmp)
  end

  test "unknown slug with no manifest returns empty packages" do
    app = %App{slug: "trip-planner", runtime_apt_packages: []}
    assert %{packages: []} = RuntimePackages.resolve(app, nil)
  end

  test "reads legacy .phoenix_paas manifest directory" do
    tmp = System.tmp_dir!() |> Path.join("runtime_legacy_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, ".phoenix_paas"))
    File.write!(Path.join(tmp, ".phoenix_paas/runtime-packages"), "curl\n")
    File.write!(Path.join(tmp, ".phoenix_paas/post-install.sh"), "echo legacy\n")

    app = %App{slug: "my-app", runtime_apt_packages: []}

    assert %{packages: packages, post_install: steps} = RuntimePackages.resolve(app, tmp)
    assert "curl" in packages
    assert "echo legacy" in steps

    File.rm_rf!(tmp)
  end
end

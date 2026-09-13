defmodule CleatDeploy.Repo.Migrations.RetargetPratoAiDeployBranch do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE apps SET branch = 'main' WHERE github_repo = 'gestao-bem/prato-ai' AND branch = 'deploy-cleat'",
      "UPDATE apps SET branch = 'deploy-cleat' WHERE github_repo = 'gestao-bem/prato-ai' AND branch = 'main'"
    )
  end
end

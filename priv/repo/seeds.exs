alias CleatDeploy.Seeds

{:ok, %{user: user, scope: scope}} = Seeds.run()

IO.puts("Seeded #{user.email} → tenant #{scope.tenant.slug} with Trip Planner app")

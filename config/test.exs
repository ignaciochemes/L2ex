import Config

config :l2e, L2E.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "l2e_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

import Config

config :l2e, L2E.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "l2e_dev",
  pool_size: 10

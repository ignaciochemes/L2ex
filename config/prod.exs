import Config

# In production, configure the DB via DATABASE_URL or environment variables.
# Example using a URL:
#
#   config :l2e, L2E.Repo, url: System.get_env("DATABASE_URL")
#
config :l2e, L2E.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASS", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "l2e_prod"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

config :l2e, dev_auto_create_accounts: false
config :logger, level: :info

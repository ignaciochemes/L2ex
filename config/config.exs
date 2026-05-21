import Config

config :l2e,
  game_port: 7777,
  login_port: 2106,
  server_id: 1,
  dev_auto_create_accounts: true

config :l2e, ecto_repos: [L2E.Repo]

config :logger, level: :debug

import_config "#{config_env()}.exs"

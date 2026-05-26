import Config

config :l2e,
  game_port: 7777,
  login_port: 2106,
  server_id: 1,
  dev_auto_create_accounts: true,
  flood_protectors: [
    game_server: [
      move_to_location: [opcode: 0x01, threshold: 10, window_secs: 10],
      request_action: [opcode: 0x0A, threshold: 50, window_secs: 60],
      use_skill: [opcode: 0x2C, threshold: 50, window_secs: 60]
    ],
    login_server: [
      auth_login: [threshold: 5, window_secs: 300]
    ]
  ]

config :l2e, ecto_repos: [L2E.Repo]

config :logger, level: :debug

import_config "#{config_env()}.exs"

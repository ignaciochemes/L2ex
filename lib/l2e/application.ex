defmodule L2E.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Ecto repository — must start first so DB is available to all game processes
      L2E.Repo,

      # Broadcast bus — must start before any process that publishes/subscribes
      {Phoenix.PubSub, name: L2E.PubSub},

      # ETS-backed read-only tables — start before any game logic
      L2E.Game.ClassTemplates,
      L2E.NPC.TemplateTable,
      L2E.Item.TemplateTable,
      L2E.Skill.TemplateTable,

      # Registry for looking up PlayerSession pids by char_id
      {Registry, keys: :unique, name: L2E.Session.Registry},

      # DynamicSupervisor for player session processes
      L2E.Session.Supervisor,

      # WorldSupervisor owns RegionRegistry + RegionSupervisor (rest_for_one)
      L2E.World.Supervisor,

      # Per-player inventory processes
      L2E.Inventory.Supervisor,

      # NPC infrastructure: supervisor for instances, then spawn table
      L2E.NPC.Supervisor,
      L2E.NPC.SpawnTable,

      # Party supervisor — manages active party processes
      L2E.Party.Supervisor,

      # Clan supervisor — manages active clan processes
      L2E.Clan.Supervisor,

      # Login Server — must start before game server so AccountStore is ready
      L2E.LoginServer.Supervisor,

      # TCP acceptor pool — starts last so everything is ready before clients connect
      L2E.Network.Supervisor
    ]

    opts = [strategy: :one_for_one, name: L2E.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        port = Application.get_env(:l2e, :game_port, 7777)
        login_port = Application.get_env(:l2e, :login_port, 2106)
        Logger.info("[L2E] Game server started on port #{port}")
        Logger.info("[L2E] Login server started on port #{login_port}")
        {:ok, pid}

      error ->
        error
    end
  end
end

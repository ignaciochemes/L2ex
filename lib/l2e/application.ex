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
      L2E.Data.BuyListTable,
      L2E.Data.TeleporterTable,
      L2E.Data.EnchantData,
      L2E.Data.DropTable,
      L2E.Zone.ZoneTable,
      L2E.Data.HtmCache,
      L2E.Data.SkillLearnTable,
      L2E.Data.ClassAdvancementTable,
      L2E.Data.HennaTable,
      L2E.Data.RecipeTable,
      L2E.Data.OptionTable,
      L2E.Data.ExperienceLossData,
      L2E.Data.ArmorSetData,
      L2E.Data.MultisellTable,

      # M68: Sub-class data
      L2E.Data.SubclassData,

      # Clan skill unlock table (ETS-backed)
      L2E.Data.ClanSkillData,

      # M72-B: Pet template data
      L2E.Data.PetDataTable,

      # M104: Pet combat stats table (max_hp, max_mp, p_atk per npc_id)
      {L2E.Data.PetTable, []},

      # GlobalVariables: server-wide persistent KV store — before any system that reads world state
      L2E.World.GlobalVariables,

      # M69: Duel system
      {Registry, keys: :unique, name: L2E.Duel.Registry},
      L2E.Duel.Manager,
      L2E.Duel.Supervisor,

      # M70: Olympiad
      L2E.Olympiad.Supervisor,

      # M72: Pet system
      L2E.Pet.Supervisor,

      # M71: Siege system
      L2E.Siege.Supervisor,

      # M74: Castle door entities (DynamicSupervisor for door GenServers)
      L2E.World.DoorSupervisor,

      # M105: Cursed Weapons — Registry + GenServer pair (Zariche & Akamanah)
      {Registry, keys: :unique, name: L2E.Item.CursedWeapon.Registry},
      L2E.Item.CursedWeapon.Supervisor,

      # M61-A: Grand Boss respawn window tracking
      L2E.GrandBoss.Supervisor,

      # RaidBossManager: respawn windows for regular raid-class bosses
      L2E.NPC.RaidBossManager,

      # M73-B: In-game day/night cycle broadcaster
      L2E.World.DayNightManager,

      # M61-B: Seven Signs Quest state machine (period/cycle/seal tracking)
      L2E.SevenSigns.Supervisor,

      # M115: Castle Manor System — seed/crop economy cycle
      L2E.Manor.Supervisor,

      # M50: Quest script registry — ETS-backed, must start before any player session
      L2E.Quest.Registry,

      # Instance zone infrastructure: supervisor first, then manager
      L2E.Instance.Supervisor,
      L2E.Instance.Manager,

      # Registry for looking up PlayerSession pids by char_id
      {Registry, keys: :unique, name: L2E.Session.Registry},

      # DynamicSupervisor for player session processes
      L2E.Session.Supervisor,

      # M55: Geodata — ETS-backed binary region loader (stub-safe, must start before World)
      L2E.Geodata,

      # WorldSupervisor owns RegionRegistry + RegionSupervisor (rest_for_one)
      L2E.World.Supervisor,

      # Per-player inventory processes
      L2E.Inventory.Supervisor,

      # NPC infrastructure: supervisor for instances, then spawn table
      L2E.NPC.Supervisor,
      L2E.NPC.SpawnTable,

      # Party supervisor — manages active party processes
      L2E.Party.Supervisor,

      # M83: Command Channel supervisor — manages multi-party command channel processes
      L2E.CommandChannel.Supervisor,

      # Clan supervisor — manages active clan processes
      L2E.Clan.Supervisor,

      # M85/M125: Clan hall subsystem — Registry + HallSupervisor + AuctionManager
      L2E.ClanHall.Supervisor,

      # Warehouse supervisor — manages per-character warehouse processes
      L2E.Warehouse.Supervisor,

      # Trade supervisor — manages ephemeral player-to-player trade processes
      L2E.Trade.Supervisor,

      # M41: IP Rate Limiter for login server flood protection
      L2E.LoginServer.IpRateLimiter,

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

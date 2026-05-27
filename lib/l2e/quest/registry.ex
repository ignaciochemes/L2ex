defmodule L2E.Quest.Registry do
  use GenServer
  require Logger

  @table :quest_registry

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load_quests()
    {:ok, %{}}
  end

  def register(module) do
    quest_id = module.quest_id()
    :ets.insert(@table, {{:by_quest_id, quest_id}, module})
    Logger.debug("[Quest.Registry] Registered #{module} (quest_id=#{quest_id})")
    :ok
  end

  # Returns list of {quest_id, module} for quests that care about this npc_id kill
  def modules_for_kill(npc_id) do
    :ets.tab2list(@table)
    |> Enum.map(fn {_, mod} -> mod end)
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :npc_kill_ids, 0) and
        npc_id in mod.npc_kill_ids()
    end)
    |> Enum.map(fn mod -> {mod.quest_id(), mod} end)
  end

  # Returns list of {quest_id, module} for quests that care about talking to this npc_id
  def modules_for_npc(npc_id) do
    :ets.tab2list(@table)
    |> Enum.map(fn {_, mod} -> mod end)
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :npc_ids, 0) and
        npc_id in mod.npc_ids()
    end)
    |> Enum.map(fn mod -> {mod.quest_id(), mod} end)
  end

  def get(quest_id) do
    case :ets.lookup(@table, {:by_quest_id, quest_id}) do
      [{{:by_quest_id, _}, mod}] -> {:ok, mod}
      [] -> {:error, :not_found}
    end
  end

  defp load_quests do
    quest_modules = [
      # Add quest script modules here as they are created, e.g.:
      # L2E.Quest.Scripts.NewAdventurer,
      L2E.Quest.Scripts.InSearchOfKnowledge,
      L2E.Quest.Scripts.PathOfDestiny,
      L2E.Quest.Scripts.LeafOnTheWater,
      L2E.Quest.Scripts.TrialOfTheSeeker,
      L2E.Quest.Scripts.NewbieHelper,
      # M103 — Class Transfer Quests
      L2E.Quest.Scripts.Human1stClass,
      L2E.Quest.Scripts.Human2ndClass,
      L2E.Quest.Scripts.Elf1stClass,
      L2E.Quest.Scripts.Elf2ndClass,
      # M108 — Class Transfer Quests (Dark Elf, Orc, Dwarf)
      L2E.Quest.Scripts.DarkElf1stClass,
      L2E.Quest.Scripts.DarkElf2ndClass,
      L2E.Quest.Scripts.Orc1stClass,
      L2E.Quest.Scripts.Orc2ndClass,
      L2E.Quest.Scripts.Dwarf1stClass
    ]

    Enum.each(quest_modules, &register/1)
  end
end

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
    ]

    Enum.each(quest_modules, &register/1)
  end
end

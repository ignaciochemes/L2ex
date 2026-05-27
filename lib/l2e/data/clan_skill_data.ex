defmodule L2E.Data.ClanSkillData do
  @moduledoc """
  ETS-backed store for clan (pledge) skill definitions.

  Data sourced from:
    L2J_Mobius_CT_0_Interlude/dist/game/data/stats/players/skillTrees/pledgeSkillTree.xml

  Clan skills are learned by the clan leader via reputation/SP. Each skill has a
  clan level requirement (`clan_level_req`), max learnable level, and SP cost per level.

  The `getLevel` field in the XML corresponds to the minimum clan level required.
  """

  use GenServer

  @table :clan_skill_data

  # Sourced from pledgeSkillTree.xml — unique skill_id → {name, max_level, clan_level_req, sp_cost}
  # sp_cost is the levelUpSp from the XML (per level).
  @skills [
    # Clan Level 5
    {370, "Clan Vitality", 3, 5, 500},
    {391, "Clan Imperium", 1, 5, 0},
    {373, "Clan Lifeblood", 3, 5, 500},
    {379, "Clan Magic Protection", 3, 5, 500},
    # Clan Level 6
    {376, "Clan Might", 3, 6, 1000},
    {374, "Clan Morale", 3, 6, 900},
    {377, "Clan Aegis", 3, 6, 1000},
    {383, "Clan Shield Defense", 3, 6, 800},
    {371, "Clan Spirit", 3, 6, 800},
    # Clan Level 7
    {390, "Clan Luck", 3, 7, 2200},
    {386, "Clan Fortitude", 3, 7, 1000},
    {387, "Clan Freedom", 3, 7, 1800},
    {380, "Clan Guidance", 3, 7, 1900},
    {385, "Clan Magmatic Resistance", 3, 7, 1800},
    {384, "Clan Cyclonic Resistance", 3, 7, 1800},
    {382, "Clan Withstand-Attack", 3, 7, 800},
    {388, "Clan Vigilance", 3, 7, 1800},
    # Clan Level 8
    {381, "Clan Agility", 3, 8, 4000},
    {375, "Clan Clarity", 3, 8, 3900},
    {378, "Clan Empowerment", 3, 8, 3900},
    {389, "Clan March", 3, 8, 3800},
    {372, "Clan Essence", 3, 8, 3900}
  ]

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns the clan skill definition map for skill_id, or nil if not found."
  @spec get(pos_integer()) :: map() | nil
  def get(skill_id) do
    case :ets.lookup(@table, skill_id) do
      [{_, d}] -> d
      [] -> nil
    end
  end

  @doc "Returns all clan skill definitions."
  @spec all() :: [map()]
  def all do
    :ets.tab2list(@table) |> Enum.map(fn {_id, d} -> d end)
  end

  @doc "Returns clan skills available at the given clan level (clan_level_req <= clan_level)."
  @spec available_at(non_neg_integer()) :: [map()]
  def available_at(clan_level) do
    all() |> Enum.filter(fn d -> d.clan_level_req <= clan_level end)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    populate()
    {:ok, %{}}
  end

  defp populate do
    Enum.each(@skills, fn {id, name, max_lvl, clan_lvl, sp} ->
      :ets.insert(
        @table,
        {id,
         %{
           skill_id: id,
           name: name,
           max_level: max_lvl,
           clan_level_req: clan_lvl,
           sp_cost: sp
         }}
      )
    end)
  end
end

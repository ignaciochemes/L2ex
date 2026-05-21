defmodule L2E.NPC.TemplateTable do
  @moduledoc """
  ETS-backed store for NPC type templates.
  Loaded from L2J Mobius XML files at startup.
  All NPC.Instance processes look up their template here at spawn time.
  """

  use GenServer
  require Logger

  import SweetXml

  alias L2E.NPC.Template

  @table :npc_templates

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @spec get(pos_integer()) :: Template.t() | nil
  def get(npc_id) do
    case :ets.lookup(@table, npc_id) do
      [{_id, template}] -> template
      [] -> nil
    end
  end

  @spec all() :: [Template.t()]
  def all do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  end

  # -----------------------------------------------------------------------
  # GenServer
  # -----------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    templates = load_all()
    Enum.each(templates, fn t -> :ets.insert(table, {t.npc_id, t}) end)
    Logger.info("[NPC.TemplateTable] Loaded #{length(templates)} NPC templates from XML")
    {:ok, %{table: table}}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_root do
    Path.join([File.cwd!(), "L2J_Mobius_CT_0_Interlude", "dist", "game", "data"])
  end

  defp npc_files do
    base = Path.join(data_root(), "stats/npcs")

    Path.wildcard(Path.join(base, "**/*.xml"))
    |> Enum.reject(&(String.contains?(&1, "/custom/") or String.contains?(&1, "\\custom\\")))
  end

  defp load_all do
    npc_files()
    |> Enum.flat_map(&load_file/1)
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} ->
        try do
          content
          |> parse()
          |> xpath(
            ~x"//npc"l,
            id: ~x"./@id"i,
            level: ~x"./@level"i,
            name: ~x"./@name"s,
            title: ~x"./@title"s,
            hp: ~x"./stats/vitals/@hp"f,
            mp: ~x"./stats/vitals/@mp"f,
            p_atk: ~x"./stats/attack/@physical"f,
            m_atk: ~x"./stats/attack/@magical"f,
            atk_speed: ~x"./stats/attack/@attackSpeed"f,
            crit: ~x"./stats/attack/@critical"f,
            accuracy: ~x"./stats/attack/@accuracy"f,
            atk_range: ~x"./stats/attack/@range"f,
            p_def: ~x"./stats/defence/@physical"f,
            m_def: ~x"./stats/defence/@magical"f,
            run_speed: ~x"./stats/speed/run/@ground"f,
            walk_speed: ~x"./stats/speed/walk/@ground"f,
            exp: ~x"./acquire/@exp"i,
            sp: ~x"./acquire/@sp"i,
            aggro_range: ~x"./ai/@aggroRange"i,
            is_aggressive: ~x"./ai/@isAggressive"s
          )
          |> Enum.map(&build_template/1)
        rescue
          e ->
            Logger.warning("[NPC.TemplateTable] Failed to parse #{path}: #{inspect(e)}")
            []
        end

      {:error, reason} ->
        Logger.warning("[NPC.TemplateTable] Cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  defp build_template(row) do
    %Template{
      npc_id: row.id,
      name: row.name,
      title: row.title || "",
      level: row.level || 1,
      p_atk: trunc(row.p_atk || 0),
      m_atk: trunc(row.m_atk || 0),
      p_def: trunc(row.p_def || 0),
      m_def: trunc(row.m_def || 0),
      atk_speed: trunc(row.atk_speed || 253),
      cast_speed: 333,
      accuracy: trunc(row.accuracy || 0),
      evasion: 4,
      crit_rate: trunc(row.crit || 4),
      run_speed: trunc(row.run_speed || 100),
      walk_speed: trunc(row.walk_speed || 60),
      max_hp: trunc(row.hp || 100),
      max_mp: trunc(row.mp || 0),
      aggro_range: row.aggro_range || 0,
      is_aggressive: row.is_aggressive == "true",
      leash_range: 500,
      respawn_ms: 30_000,
      attack_range: trunc(row.atk_range || 40),
      exp_reward: row.exp || 0,
      sp_reward: row.sp || 0
    }
  end
end

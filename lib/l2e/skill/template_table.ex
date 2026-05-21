defmodule L2E.Skill.TemplateTable do
  @moduledoc """
  ETS-backed read-only store for skill templates.
  Keyed by {skill_id, level}. Loaded from L2J Mobius XML files at startup.
  """

  use GenServer
  require Logger

  import SweetXml

  alias L2E.Skill.Template

  @table :skill_templates

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Look up a skill template by id + level. Returns nil if not found."
  @spec get(pos_integer(), pos_integer()) :: Template.t() | nil
  def get(skill_id, level) do
    case :ets.lookup(@table, {skill_id, level}) do
      [{_key, template}] -> template
      [] -> nil
    end
  end

  @doc "Return all templates as a list."
  @spec all() :: [Template.t()]
  def all do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    templates = load_all()

    for s <- templates do
      :ets.insert(table, {{s.skill_id, s.level}, s})
    end

    Logger.info("[Skill.TemplateTable] Loaded #{:ets.info(table, :size)} skill entries from XML")
    {:ok, %{table: table}}
  end

  # -----------------------------------------------------------------------
  # XML loading
  # -----------------------------------------------------------------------

  defp data_root do
    Path.join([File.cwd!(), "L2J_Mobius_CT_0_Interlude", "dist", "game", "data"])
  end

  defp skill_files do
    base = Path.join(data_root(), "stats/skills")

    Path.wildcard(Path.join(base, "**/*.xml"))
    |> Enum.reject(&(String.contains?(&1, "/custom/") or String.contains?(&1, "\\custom\\")))
  end

  defp load_all do
    skill_files()
    |> Enum.flat_map(&load_file/1)
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} ->
        try do
          content
          |> parse()
          |> xpath(
            ~x"//skill"l,
            id: ~x"./@id"i,
            levels: ~x"./@levels"i,
            name: ~x"./@name"s,
            tables: [
              ~x"./table"l,
              name: ~x"./@name"s,
              values: ~x"./text()"s
            ],
            operate_type: ~x"./operateType/text()"s,
            target_type: ~x"./targetType/text()"s,
            hit_time: ~x"./hitTime/text()"s,
            reuse_delay: ~x"./reuseDelay/text()"s,
            cast_range: ~x"./castRange/text()"s,
            mp_consume: ~x"./mpConsume/text()"s,
            power: ~x"./power/text()"s,
            is_magic: ~x"./isMagic/text()"s
          )
          |> Enum.flat_map(&expand_levels/1)
        rescue
          e ->
            Logger.warning("[Skill.TemplateTable] Failed to parse #{path}: #{inspect(e)}")
            []
        end

      {:error, reason} ->
        Logger.warning("[Skill.TemplateTable] Cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  # Each <skill levels="N"> expands into N Template structs, one per level.
  defp expand_levels(%{id: id, levels: levels, name: name} = row) when levels > 0 do
    # Build a lookup map: "#varname" => [val_level_1, val_level_2, ...]
    table_map =
      Map.new(row.tables, fn %{name: n, values: v} ->
        vals = v |> String.split(~r/\s+/, trim: true)
        {n, vals}
      end)

    for lvl <- 1..levels do
      idx = lvl - 1

      %Template{
        skill_id: id,
        level: lvl,
        name: name,
        type: parse_operate_type(row.operate_type),
        target_type: parse_target_type(row.target_type),
        effect_type: :p_damage,
        power: resolve_int(row.power, table_map, idx, 0),
        mp_cost: resolve_int(row.mp_consume, table_map, idx, 0),
        cast_time_ms: parse_int(row.hit_time, 1000),
        reuse_ms: parse_int(row.reuse_delay, 3000),
        range: parse_int(row.cast_range, 600),
        is_magic: row.is_magic == "1",
        buff_duration_ms: 0,
        stat_bonus: %{}
      }
    end
  end

  defp expand_levels(_), do: []

  # Resolve a value that may be a literal integer or a "#tableName" reference.
  defp resolve_int(raw, table_map, idx, default) do
    cond do
      is_nil(raw) or raw == "" ->
        default

      String.starts_with?(raw, "#") ->
        case Map.get(table_map, raw) do
          nil ->
            default

          vals ->
            Enum.at(vals, idx, List.last(vals) || "#{default}")
            |> parse_float_to_int(default)
        end

      true ->
        parse_float_to_int(raw, default)
    end
  end

  defp parse_float_to_int(s, default) do
    case Float.parse(s) do
      {f, _} -> trunc(f)
      :error -> parse_int(s, default)
    end
  end

  defp parse_int(s, default) do
    case Integer.parse(s || "") do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_operate_type("A1"), do: :active
  defp parse_operate_type("A2"), do: :active
  defp parse_operate_type("P"), do: :passive
  defp parse_operate_type("T"), do: :toggle
  defp parse_operate_type(_), do: :active

  defp parse_target_type("ONE"), do: :one
  defp parse_target_type("SELF"), do: :self
  defp parse_target_type(t) when t in ["AURA", "FRONT_AURA", "BEHIND_AURA"], do: :aoe
  defp parse_target_type("CORPSE"), do: :corpse
  defp parse_target_type(_), do: :one
end

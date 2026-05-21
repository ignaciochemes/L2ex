defmodule L2E.Game.ClassTemplates do
  @moduledoc """
  ETS-backed store for character class template data.

  Each entry defines the base stats for a starting class.
  Loaded once at startup; read-only during gameplay.

  HP/MP growth is approximated linearly here.
  When XML data files are available (M9), this will be replaced
  by a proper per-level table loaded from gamedata/stats/chars/.
  """

  use GenServer
  require Logger

  @table :class_templates

  # Class IDs matching L2J Interlude PlayerClass enum
  @templates [
    # Human Fighter
    %{
      class_id: 0,
      base_str: 40,
      base_dex: 30,
      base_con: 43,
      base_int: 21,
      base_wit: 11,
      base_men: 25,
      base_hp: 45.0,
      hp_per_level: 23.0,
      base_mp: 24.0,
      mp_per_level: 3.5,
      base_cp: 45.0,
      cp_per_level: 23.0,
      base_p_atk: 11.0,
      base_m_atk: 2.5,
      base_p_def: 57.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Human Wizard (Mystic)
    %{
      class_id: 11,
      base_str: 27,
      base_dex: 30,
      base_con: 34,
      base_int: 40,
      base_wit: 25,
      base_men: 34,
      base_hp: 27.0,
      hp_per_level: 16.0,
      base_mp: 50.0,
      mp_per_level: 12.0,
      base_cp: 27.0,
      cp_per_level: 16.0,
      base_p_atk: 3.0,
      base_m_atk: 11.0,
      base_p_def: 33.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Elven Fighter
    %{
      class_id: 18,
      base_str: 38,
      base_dex: 38,
      base_con: 37,
      base_int: 24,
      base_wit: 19,
      base_men: 24,
      base_hp: 38.0,
      hp_per_level: 21.0,
      base_mp: 28.0,
      mp_per_level: 4.0,
      base_cp: 38.0,
      cp_per_level: 21.0,
      base_p_atk: 10.0,
      base_m_atk: 3.0,
      base_p_def: 57.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Elven Mage
    %{
      class_id: 25,
      base_str: 24,
      base_dex: 38,
      base_con: 29,
      base_int: 38,
      base_wit: 34,
      base_men: 29,
      base_hp: 26.0,
      hp_per_level: 14.0,
      base_mp: 52.0,
      mp_per_level: 13.0,
      base_cp: 26.0,
      cp_per_level: 14.0,
      base_p_atk: 2.5,
      base_m_atk: 13.0,
      base_p_def: 33.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Dark Elf Fighter
    %{
      class_id: 31,
      base_str: 41,
      base_dex: 38,
      base_con: 35,
      base_int: 28,
      base_wit: 14,
      base_men: 24,
      base_hp: 35.0,
      hp_per_level: 20.0,
      base_mp: 25.0,
      mp_per_level: 4.0,
      base_cp: 35.0,
      cp_per_level: 20.0,
      base_p_atk: 12.0,
      base_m_atk: 4.0,
      base_p_def: 54.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Dark Elf Mage
    %{
      class_id: 38,
      base_str: 28,
      base_dex: 38,
      base_con: 26,
      base_int: 38,
      base_wit: 24,
      base_men: 26,
      base_hp: 22.0,
      hp_per_level: 13.0,
      base_mp: 52.0,
      mp_per_level: 13.0,
      base_cp: 22.0,
      cp_per_level: 13.0,
      base_p_atk: 3.0,
      base_m_atk: 14.0,
      base_p_def: 33.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Orc Fighter
    %{
      class_id: 44,
      base_str: 40,
      base_dex: 21,
      base_con: 48,
      base_int: 18,
      base_wit: 11,
      base_men: 32,
      base_hp: 48.0,
      hp_per_level: 25.0,
      base_mp: 22.0,
      mp_per_level: 2.5,
      base_cp: 48.0,
      cp_per_level: 25.0,
      base_p_atk: 12.0,
      base_m_atk: 2.0,
      base_p_def: 59.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Orc Shaman
    %{
      class_id: 49,
      base_str: 26,
      base_dex: 21,
      base_con: 38,
      base_int: 26,
      base_wit: 26,
      base_men: 38,
      base_hp: 38.0,
      hp_per_level: 19.0,
      base_mp: 38.0,
      mp_per_level: 8.0,
      base_cp: 38.0,
      cp_per_level: 19.0,
      base_p_atk: 7.0,
      base_m_atk: 9.0,
      base_p_def: 45.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    },
    # Dwarven Fighter
    %{
      class_id: 53,
      base_str: 40,
      base_dex: 28,
      base_con: 49,
      base_int: 16,
      base_wit: 12,
      base_men: 25,
      base_hp: 49.0,
      hp_per_level: 26.0,
      base_mp: 22.0,
      mp_per_level: 2.5,
      base_cp: 49.0,
      cp_per_level: 26.0,
      base_p_atk: 12.0,
      base_m_atk: 2.0,
      base_p_def: 60.0,
      base_m_def: 21.0,
      run_speed: 120,
      walk_speed: 80,
      atk_speed: 253,
      cast_speed: 333,
      base_crit: 4,
      base_accuracy: 0,
      base_evasion: 0,
      base_attack_range: 40
    }
  ]

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @spec get(non_neg_integer()) :: map() | nil
  def get(class_id) do
    case :ets.lookup(@table, class_id) do
      [{_id, template}] -> template
      [] -> nil
    end
  end

  # Returns the first template (class 0) when class_id is unknown/nil.
  @spec get_or_default(non_neg_integer() | nil) :: map()
  def get_or_default(nil), do: get(0)
  def get_or_default(class_id), do: get(class_id) || get(0)

  # -----------------------------------------------------------------------
  # GenServer
  # -----------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    Enum.each(@templates, fn t -> :ets.insert(table, {t.class_id, t}) end)
    Logger.info("[ClassTemplates] Loaded #{length(@templates)} class templates into ETS")
    {:ok, %{table: table}}
  end
end

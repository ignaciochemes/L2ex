defmodule L2E.Data.SubclassData do
  @moduledoc """
  ETS-backed sub-class availability data.

  Maps each class ID to the list of valid 3rd-tier sub-class IDs that class can take.
  Rule: cannot sub-class within own race lineage.

  Class ID reference (L2J CT0 Interlude, from admin setclass HTML):
    Human Fighter tree (0-9):  0=Fighter, 1=Warrior, 2=Gladiator, 3=Warlord,
      4=Knight, 5=Paladin, 6=Dark Avenger, 7=Rogue, 8=Treasure Hunter, 9=Hawkeye
    Human Mage tree (10-17):   10=Mystic, 11=Wizard, 12=Sorcerer, 13=Necromancer,
      14=Warlock, 15=Cleric, 16=Bishop, 17=Prophet
    Elf Fighter (18-24):       18=Fighter, 19=Knight, 20=Temple Knight, 21=Swordsinger,
      22=Scout, 23=Plains Walker, 24=Silver Ranger
    Elf Mage (25-30):          25=Mystic, 26=Wizard, 27=SpellSinger, 28=Elem.Summoner,
      29=Oracle, 30=Elder
    DE Fighter (31-37):        31=Fighter, 32=Palus Knight, 33=Shillien Knight,
      34=BladeDancer, 35=Assassin, 36=Abyss Walker, 37=Phantom Ranger
    DE Mage (38-43):           38=Mystic, 39=Wizard, 40=SpellHowler, 41=Phantom Summoner,
      42=Shillien Oracle, 43=Shillien Elder
    Orc Fighter (44-48):       44=Fighter, 45=Raider, 46=Destroyer, 47=Monk, 48=Tyrant
    Orc Mage (49-52):          49=Mystic, 50=Shaman, 51=Overlord, 52=Warcryer
    Dwarf (53-57):             53=Fighter, 54=Scavenger, 55=Bounty Hunter,
      56=Artisan, 57=Warsmith
  """

  use GenServer

  @table :subclass_data

  # --- Race family ranges (all class IDs per race, 1st through 3rd tier) ---
  @human_classes Enum.to_list(0..17)
  @elf_classes Enum.to_list(18..30)
  @dark_elf_classes Enum.to_list(31..43)
  @orc_classes Enum.to_list(44..52)
  @dwarf_classes Enum.to_list(53..57)

  # --- Valid 3rd-tier subclass pool per race (Interlude, pre-Gracia classes only) ---
  @human_3rd [2, 3, 5, 6, 8, 9, 12, 13, 14, 16, 17]
  @elf_3rd [20, 21, 23, 24, 27, 28, 30]
  @dark_elf_3rd [33, 34, 36, 37, 40, 41, 43]
  @orc_3rd [46, 48, 51, 52]
  @dwarf_3rd [55, 57]

  @all_3rd @human_3rd ++ @elf_3rd ++ @dark_elf_3rd ++ @orc_3rd ++ @dwarf_3rd

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns list of valid 3rd-tier sub-class IDs for a given base class_id."
  def get_available(class_id) do
    case :ets.lookup(@table, class_id) do
      [{_, classes}] -> classes
      [] -> []
    end
  end

  @doc "Returns list of valid sub-class IDs for a given class_id (alias for get_available/1)."
  def available_for(class_id), do: get_available(class_id)

  @doc "Is chosen_class_id a valid sub-class choice for the given current class?"
  def valid_subclass?(current_class_id, chosen_class_id) do
    chosen_class_id in get_available(current_class_id)
  end

  @impl GenServer
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    populate()
    {:ok, %{}}
  end

  # Build per-class ETS entries. For each race, available subclasses = all 3rd-tier
  # classes except those belonging to the same race.
  defp populate() do
    race_pools = [
      {@human_classes, @all_3rd -- @human_3rd},
      {@elf_classes, @all_3rd -- @elf_3rd},
      {@dark_elf_classes, @all_3rd -- @dark_elf_3rd},
      {@orc_classes, @all_3rd -- @orc_3rd},
      {@dwarf_classes, @all_3rd -- @dwarf_3rd}
    ]

    Enum.each(race_pools, fn {class_ids, available} ->
      Enum.each(class_ids, fn class_id ->
        :ets.insert(@table, {class_id, available})
      end)
    end)
  end
end

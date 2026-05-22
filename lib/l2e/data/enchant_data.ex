defmodule L2E.Data.EnchantData do
  @moduledoc """
  ETS-backed GenServer that loads enchant scroll definitions from XML.

  Success rates for Interlude:
    - Weapons: 66% base for +4→+16 (below +4 always succeeds in client but we track anyway)
    - Armors: 66% base for +4→+16
    - Blessed scrolls: 100% on success (no crystal on fail, item stays)
    - Crystal scrolls: bonusRate=100 → always succeed
    - Rate degradation by grade: not in the XML; Interlude uses flat 66% for regular scrolls

  Reference:
    - data/EnchantItemData.xml
    - gameserver/model/EnchantItemData.java

  ETS table: :enchant_scroll_data
    key: scroll_item_id
    value: %{target_grade, max_enchant, bonus_rate, blessed}
  """

  use GenServer
  require Logger

  import SweetXml

  @table :enchant_scroll_data

  # Base success rate per-mille for regular scrolls (+4 and above)
  @base_success_rate 660

  # Items below this enchant level always succeed (enchant 0→3)
  @safe_enchant 3

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the enchant scroll data for the given scroll item_id, or nil if not found."
  @spec get(pos_integer()) :: map() | nil
  def get(scroll_item_id) do
    case :ets.lookup(@table, scroll_item_id) do
      [{_, data}] -> data
      [] -> nil
    end
  end

  @doc """
  Compute the enchant result for applying scroll `scroll_id` to an item at `current_enchant`.

  Returns:
    - `:success` — enchant increased by 1
    - `:fail` — item lost (non-blessed) or item kept at current level (blessed)
    - `:max` — already at max enchant, cannot enchant further
    - `:unknown_scroll` — scroll_id not in the table

  Note: The caller is responsible for applying the result to the inventory.
  """
  @spec try_enchant(pos_integer(), non_neg_integer()) ::
          :success | :fail | :max | :unknown_scroll
  def try_enchant(scroll_item_id, current_enchant) do
    case get(scroll_item_id) do
      nil ->
        :unknown_scroll

      %{max_enchant: max_e} when current_enchant >= max_e ->
        :max

      %{bonus_rate: bonus} ->
        # Crystal scrolls: 100% success
        # Regular: safe enchant level is always success; above that use base rate
        success_rate =
          if current_enchant <= @safe_enchant do
            1000
          else
            min(@base_success_rate + bonus * 10, 1000)
          end

        roll = :rand.uniform(1000)

        if roll <= success_rate do
          :success
        else
          :fail
        end
    end
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    load_data()
    {:ok, %{}}
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  defp load_data do
    path = "L2J_Mobius_CT_0_Interlude/dist/game/data/EnchantItemData.xml"

    case File.read(path) do
      {:ok, xml} ->
        enchants =
          xpath(xml, ~x"//enchant"l,
            id: ~x"./@id"i,
            target_grade: ~x"./@targetGrade"s,
            max_enchant: ~x"./@maxEnchant"I,
            bonus_rate: ~x"./@bonusRate"I,
            blessed: ~x"./@isBlessed"s
          )

        Enum.each(enchants, fn e ->
          data = %{
            target_grade: e.target_grade,
            max_enchant: if(e.max_enchant == 0, do: 16, else: e.max_enchant),
            bonus_rate: e.bonus_rate,
            blessed: e.blessed == "true"
          }

          :ets.insert(@table, {e.id, data})
        end)

        Logger.info("[EnchantData] Loaded #{length(enchants)} enchant scroll definitions")

      {:error, reason} ->
        Logger.warning("[EnchantData] Could not read #{path}: #{inspect(reason)}")
    end
  end
end

defmodule L2E.Warehouse.ClanWarehouse do
  @moduledoc """
  Shared clan warehouse GenServer.

  One process per clan with an active member viewing the clan warehouse.
  Registered as `{:clan, clan_id}` in `L2E.Warehouse.Registry`.

  Mirrors the design of `L2E.Warehouse` (personal warehouse) but
  operates on the `clan_warehouse_items` table and is keyed by `clan_id`.

  Multiple clan members may call `list/1`, `deposit/4`, and `withdraw/3`
  concurrently — all calls are serialised through this GenServer.
  """

  use GenServer, restart: :temporary
  require Logger

  import Ecto.Query, only: [from: 2]

  alias L2E.{Repo, DB.ClanWarehouseItem}

  # Registry key format: {:clan, clan_id}
  def via_tuple(clan_id), do: {:via, Registry, {L2E.Warehouse.Registry, {:clan, clan_id}}}

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(clan_id: clan_id) do
    GenServer.start_link(__MODULE__, clan_id, name: via_tuple(clan_id))
  end

  @doc "Returns all items in the clan warehouse."
  @spec list(pos_integer()) :: [map()]
  def list(clan_id) do
    ensure_started(clan_id)
    GenServer.call(via_tuple(clan_id), :list)
  end

  @doc "Deposits `count` of `item_id` into the clan warehouse."
  @spec deposit(pos_integer(), pos_integer(), pos_integer(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, term()}
  def deposit(clan_id, item_id, count, enchant_level \\ 0) do
    ensure_started(clan_id)
    GenServer.call(via_tuple(clan_id), {:deposit, item_id, count, enchant_level})
  end

  @doc "Withdraws `count` of item `instance_id` from the clan warehouse."
  @spec withdraw(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def withdraw(clan_id, instance_id, count) do
    ensure_started(clan_id)
    GenServer.call(via_tuple(clan_id), {:withdraw, instance_id, count})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(clan_id) do
    items =
      Repo.all(from(w in ClanWarehouseItem, where: w.clan_id == ^clan_id))
      |> Map.new(fn row ->
        {row.id,
         %{
           id: row.id,
           item_id: row.item_id,
           count: row.count,
           enchant_level: row.enchant_level
         }}
      end)

    Logger.debug("[ClanWarehouse] clan_id=#{clan_id} loaded #{map_size(items)} items")
    {:ok, %{clan_id: clan_id, items: items}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.items), state}
  end

  @impl true
  def handle_call({:deposit, item_id, count, enchant_level}, _from, state) do
    case Repo.insert(
           ClanWarehouseItem.changeset(%ClanWarehouseItem{}, %{
             clan_id: state.clan_id,
             item_id: item_id,
             count: count,
             enchant_level: enchant_level
           })
         ) do
      {:ok, row} ->
        entry = %{
          id: row.id,
          item_id: row.item_id,
          count: row.count,
          enchant_level: row.enchant_level
        }

        {:reply, {:ok, row.id}, %{state | items: Map.put(state.items, row.id, entry)}}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:withdraw, instance_id, count}, _from, state) do
    case Map.get(state.items, instance_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      item when item.count < count ->
        {:reply, {:error, :insufficient_count}, state}

      item ->
        if item.count == count do
          Repo.delete!(%ClanWarehouseItem{id: instance_id})
          {:reply, {:ok, item}, %{state | items: Map.delete(state.items, instance_id)}}
        else
          new_count = item.count - count
          db_row = Repo.get!(ClanWarehouseItem, instance_id)
          Repo.update!(Ecto.Changeset.change(db_row, count: new_count))
          updated = %{item | count: new_count}

          {:reply, {:ok, %{item | count: count}},
           %{state | items: Map.put(state.items, instance_id, updated)}}
        end
    end
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  defp ensure_started(clan_id) do
    case Registry.lookup(L2E.Warehouse.Registry, {:clan, clan_id}) do
      [{pid, _}] ->
        pid

      [] ->
        {:ok, pid} = L2E.Warehouse.Supervisor.start_clan_warehouse(clan_id)
        pid
    end
  end
end

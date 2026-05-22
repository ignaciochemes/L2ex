defmodule L2E.Warehouse do
  @moduledoc """
  Per-character private warehouse GenServer.

  One process per online character, started on demand when the character
  opens the warehouse NPC dialog. Stopped when the character closes the
  warehouse or goes offline.

  Supports:
    - List warehouse contents
    - Deposit items from inventory → warehouse
    - Withdraw items from warehouse → inventory

  Supervised by `L2E.Warehouse.Supervisor` (DynamicSupervisor).
  Registered by `char_id` in `L2E.Warehouse.Registry`.

  Reference: model/itemcontainer/PcWarehouse.java
  """

  use GenServer, restart: :temporary
  require Logger

  import Ecto.Query, only: [from: 2]

  alias L2E.{Repo, DB.WarehouseItem}

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(char_id: char_id) do
    GenServer.start_link(__MODULE__, char_id, name: via_tuple(char_id))
  end

  def via_tuple(char_id), do: {:via, Registry, {L2E.Warehouse.Registry, char_id}}

  @doc "Returns all items in the warehouse."
  @spec list(pos_integer()) :: [map()]
  def list(char_id) do
    case Registry.lookup(L2E.Warehouse.Registry, char_id) do
      [{pid, _}] -> GenServer.call(pid, :list)
      [] -> ensure_started(char_id) |> then(&GenServer.call(&1, :list))
    end
  end

  @doc "Deposits `count` of `item_id` into the warehouse. Returns {:ok, instance_id} or {:error, reason}."
  @spec deposit(pos_integer(), pos_integer(), pos_integer(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, term()}
  def deposit(char_id, item_id, count, enchant_level \\ 0) do
    ensure_started(char_id)
    GenServer.call(via_tuple(char_id), {:deposit, item_id, count, enchant_level})
  end

  @doc "Withdraws `count` of item `instance_id` from the warehouse."
  @spec withdraw(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def withdraw(char_id, instance_id, count) do
    ensure_started(char_id)
    GenServer.call(via_tuple(char_id), {:withdraw, instance_id, count})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(char_id) do
    items =
      Repo.all(from(w in WarehouseItem, where: w.char_id == ^char_id))
      |> Map.new(fn row ->
        {row.id,
         %{
           id: row.id,
           item_id: row.item_id,
           count: row.count,
           enchant_level: row.enchant_level
         }}
      end)

    Logger.debug("[Warehouse] char_id=#{char_id} loaded #{map_size(items)} items")
    {:ok, %{char_id: char_id, items: items}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.items), state}
  end

  @impl true
  def handle_call({:deposit, item_id, count, enchant_level}, _from, state) do
    case Repo.insert(
           WarehouseItem.changeset(%WarehouseItem{}, %{
             char_id: state.char_id,
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

        new_items = Map.put(state.items, row.id, entry)
        {:reply, {:ok, row.id}, %{state | items: new_items}}

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
          Repo.delete!(%WarehouseItem{id: instance_id})
          new_items = Map.delete(state.items, instance_id)
          {:reply, {:ok, item}, %{state | items: new_items}}
        else
          new_count = item.count - count
          db_row = Repo.get!(WarehouseItem, instance_id)
          Repo.update!(Ecto.Changeset.change(db_row, count: new_count))
          updated = %{item | count: new_count}
          new_items = Map.put(state.items, instance_id, updated)
          {:reply, {:ok, %{item | count: count}}, %{state | items: new_items}}
        end
    end
  end

  # -----------------------------------------------------------------------
  # Private
  # -----------------------------------------------------------------------

  defp ensure_started(char_id) do
    case Registry.lookup(L2E.Warehouse.Registry, char_id) do
      [{pid, _}] ->
        pid

      [] ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            L2E.Warehouse.DynamicSupervisor,
            {__MODULE__, char_id: char_id}
          )

        pid
    end
  end
end

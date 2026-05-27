defmodule L2E.Pet.Inventory do
  @moduledoc """
  Per-pet inventory process.

  Started by L2E.Pet.Session on summon. Loads items from DB on init,
  provides add/remove/get API, persists each write immediately.

  NOT supervised separately — linked to Pet.Session via start_link.
  When Pet.Session exits, this process receives an EXIT signal and
  cleans up via terminate/2.
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.DB.PetInventoryItem

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Get all items carried by the pet."
  def get_items(pid), do: GenServer.call(pid, :get_items)

  @doc "Add an item to the pet inventory. Persists immediately."
  def add_item(pid, char_id, item_id, object_id, count \\ 1) do
    GenServer.call(pid, {:add_item, char_id, item_id, object_id, count})
  end

  @doc "Remove an item by object_id from pet inventory. Persists immediately."
  def remove_item(pid, object_id) do
    GenServer.call(pid, {:remove_item, object_id})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    pet_item_obj_id = Keyword.fetch!(opts, :pet_item_obj_id)
    items = PetInventoryItem.load_for_pet(pet_item_obj_id)

    {:ok,
     %{
       pet_item_obj_id: pet_item_obj_id,
       items: items
     }}
  end

  @impl GenServer
  def handle_call(:get_items, _from, state) do
    {:reply, state.items, state}
  end

  def handle_call({:add_item, char_id, item_id, object_id, count}, _from, state) do
    case PetInventoryItem.add_item(state.pet_item_obj_id, char_id, item_id, object_id, count) do
      {:ok, item} ->
        {:reply, {:ok, item}, %{state | items: [item | state.items]}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_item, object_id}, _from, state) do
    PetInventoryItem.remove_item(object_id)
    new_items = Enum.reject(state.items, fn i -> i.object_id == object_id end)
    {:reply, :ok, %{state | items: new_items}}
  end

  # Handle EXIT from linked Pet.Session — stop cleanly
  @impl GenServer
  def handle_info({:EXIT, _from, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("[Pet.Inventory] Shutting down inventory for pet #{state.pet_item_obj_id}")
    :ok
  end
end

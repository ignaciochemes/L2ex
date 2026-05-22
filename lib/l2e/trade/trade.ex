defmodule L2E.Trade do
  @moduledoc """
  Ephemeral GenServer managing a player-to-player trade session.

  Lifecycle:
    1. Player A sends `RequestStartTrade` → Trade process started, invite sent to B.
    2. Player B accepts (`RequestTradeAccept`) → both see the trade window.
    3. Both players add items (`RequestAddTradeItem` / `RequestRemoveTradeItem`).
    4. Both players confirm (`RequestTradeDone` with lock=true) → items exchanged.
    5. Either player cancels (`RequestCancelTrade`) → trade aborted, no item movement.

  The process dies after completion or cancellation.
  Supervised under `L2E.Trade.Supervisor` (DynamicSupervisor).
  Registered by `{:trade, min(id_a, id_b), max(id_a, id_b)}` in `L2E.Trade.Registry`.

  Reference: gameserver/model/TradeList.java, gameserver/handler/PacketHandler — trade packets
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.{Inventory, Packet.Server}

  @trade_timeout_ms 60_000

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @doc "Start a new trade between char_a (initiator) and char_b (recipient)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    char_a = Keyword.fetch!(opts, :char_a)
    char_b = Keyword.fetch!(opts, :char_b)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(char_a, char_b))
  end

  def via_tuple(a, b) do
    key = {min(a, b), max(a, b)}
    {:via, Registry, {L2E.Trade.Registry, key}}
  end

  @doc "Add an item to the trade from the perspective of `char_id`."
  @spec add_item(pid(), pos_integer(), pos_integer(), pos_integer()) ::
          :ok | {:error, term()}
  def add_item(pid, char_id, object_id, count) do
    GenServer.call(pid, {:add_item, char_id, object_id, count})
  end

  @doc "Remove an item from the trade offer of `char_id`."
  @spec remove_item(pid(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def remove_item(pid, char_id, object_id) do
    GenServer.call(pid, {:remove_item, char_id, object_id})
  end

  @doc "Player confirms/locks their side of the trade."
  @spec confirm(pid(), pos_integer()) :: :ok | {:error, term()}
  def confirm(pid, char_id) do
    GenServer.call(pid, {:confirm, char_id})
  end

  @doc "Cancel the trade — both players get their offer items back."
  @spec cancel(pid(), pos_integer()) :: :ok
  def cancel(pid, char_id) do
    GenServer.cast(pid, {:cancel, char_id})
  end

  @doc "Accept the incoming trade invite (player B accepts)."
  @spec accept(pid(), pos_integer()) :: :ok
  def accept(pid, char_id) do
    GenServer.cast(pid, {:accept, char_id})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(opts) do
    char_a = Keyword.fetch!(opts, :char_a)
    char_b = Keyword.fetch!(opts, :char_b)
    pid_a = Keyword.fetch!(opts, :pid_a)
    pid_b = Keyword.fetch!(opts, :pid_b)

    # Auto-cancel if no activity
    timer = Process.send_after(self(), :timeout, @trade_timeout_ms)

    state = %{
      char_a: char_a,
      char_b: char_b,
      pid_a: pid_a,
      pid_b: pid_b,
      # :pending | :open | :a_confirmed | :b_confirmed | :done
      phase: :pending,
      offer_a: %{},
      offer_b: %{},
      timer: timer
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:accept, char_id}, %{phase: :pending} = state) when char_id == state.char_b do
    notify_both(state, %Server.TradeOtherAdd{side: :accepted})
    {:noreply, %{state | phase: :open}}
  end

  def handle_cast({:accept, _}, state), do: {:noreply, state}

  @impl true
  def handle_cast({:cancel, _char_id}, state) do
    broadcast_cancel(state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_call({:add_item, char_id, object_id, count}, _from, %{phase: :open} = state) do
    {offer_key, _other_key} = offer_keys(state, char_id)
    offer = Map.get(state, offer_key, %{})

    updated_offer = Map.put(offer, object_id, count)
    new_state = Map.put(state, offer_key, updated_offer)

    # Notify both players of updated offer
    broadcast_offer(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:add_item, _, _, _}, _from, state) do
    {:reply, {:error, :invalid_phase}, state}
  end

  @impl true
  def handle_call({:remove_item, char_id, object_id}, _from, %{phase: :open} = state) do
    {offer_key, _} = offer_keys(state, char_id)
    offer = Map.get(state, offer_key, %{})
    updated_offer = Map.delete(offer, object_id)
    new_state = Map.put(state, offer_key, updated_offer)
    broadcast_offer(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:remove_item, _, _}, _from, state) do
    {:reply, {:error, :invalid_phase}, state}
  end

  @impl true
  def handle_call({:confirm, char_id}, _from, state) do
    cond do
      char_id == state.char_a and state.phase == :open ->
        new_state = %{state | phase: :a_confirmed}
        broadcast_confirm(new_state, :a)
        {:reply, :ok, new_state}

      char_id == state.char_b and state.phase == :open ->
        new_state = %{state | phase: :b_confirmed}
        broadcast_confirm(new_state, :b)
        {:reply, :ok, new_state}

      char_id == state.char_a and state.phase == :b_confirmed ->
        execute_trade(state)
        {:reply, :ok, %{state | phase: :done}}

      char_id == state.char_b and state.phase == :a_confirmed ->
        execute_trade(state)
        {:reply, :ok, %{state | phase: :done}}

      true ->
        {:reply, {:error, :invalid_state}, state}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("[Trade] #{state.char_a}<>#{state.char_b} timed out")
    broadcast_cancel(state)
    {:stop, :normal, state}
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp offer_keys(state, char_id) do
    if char_id == state.char_a,
      do: {:offer_a, :offer_b},
      else: {:offer_b, :offer_a}
  end

  defp broadcast_cancel(state) do
    pkt = %Server.TradeCancelled{}
    send(state.pid_a, {:send_packet, pkt})
    send(state.pid_b, {:send_packet, pkt})
  end

  defp broadcast_offer(state) do
    # Send updated offer lists to both sides
    pkt_a = %Server.TradeOwnAdd{items: Map.to_list(state.offer_a)}
    pkt_b = %Server.TradeOtherAdd{items: Map.to_list(state.offer_b)}
    send(state.pid_a, {:send_packet, pkt_a})
    send(state.pid_a, {:send_packet, pkt_b})
    send(state.pid_b, {:send_packet, pkt_a})
    send(state.pid_b, {:send_packet, pkt_b})
  end

  defp broadcast_confirm(state, side) do
    pkt = %Server.TradeConfirm{side: side}
    send(state.pid_a, {:send_packet, pkt})
    send(state.pid_b, {:send_packet, pkt})
  end

  defp notify_both(state, pkt) do
    send(state.pid_a, {:send_packet, pkt})
    send(state.pid_b, {:send_packet, pkt})
  end

  defp execute_trade(state) do
    Process.cancel_timer(state.timer)

    # Transfer A's offer items from A's inventory to B's inventory
    Enum.each(state.offer_a, fn {obj_id, count} ->
      case Inventory.remove_item(state.char_a, obj_id, count) do
        {:ok, _change_type, {inst, _tmpl}} ->
          Inventory.add_item(state.char_b, inst.item_id, count)

        {:error, reason} ->
          Logger.warning("[Trade] remove A item #{obj_id} failed: #{inspect(reason)}")
      end
    end)

    # Transfer B's offer items from B's inventory to A's inventory
    Enum.each(state.offer_b, fn {obj_id, count} ->
      case Inventory.remove_item(state.char_b, obj_id, count) do
        {:ok, _change_type, {inst, _tmpl}} ->
          Inventory.add_item(state.char_a, inst.item_id, count)

        {:error, reason} ->
          Logger.warning("[Trade] remove B item #{obj_id} failed: #{inspect(reason)}")
      end
    end)

    pkt = %Server.TradeDone{result: :success}
    send(state.pid_a, {:send_packet, pkt})
    send(state.pid_b, {:send_packet, pkt})

    Logger.info("[Trade] #{state.char_a}<>#{state.char_b} completed successfully")
    GenServer.stop(self())
  end
end

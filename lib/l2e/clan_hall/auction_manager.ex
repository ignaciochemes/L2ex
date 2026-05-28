defmodule L2E.ClanHall.AuctionManager do
  @moduledoc """
  Manages clan hall auctions. Runs a weekly cycle:
  - Auctions open on Sunday 00:00
  - Auctions close the following Sunday 00:00
  - Highest bid wins; adena is deducted from clan warehouse (TODO: full adena flow)
  - Loser bids are returned to clan warehouses (TODO: full adena flow)
  """
  use GenServer
  import Ecto.Query
  require Logger

  @one_week_ms 7 * 24 * 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  @doc "Place or update a bid for a clan on a clan hall."
  def place_bid(hall_id, clan_id, bidder_char_id, amount) do
    GenServer.call(__MODULE__, {:place_bid, hall_id, clan_id, bidder_char_id, amount})
  end

  @doc "Get all bids for a given hall, sorted by highest bid first."
  def get_bids(hall_id) do
    GenServer.call(__MODULE__, {:get_bids, hall_id})
  end

  @doc "Return the DB record for a hall (read-only query, not routed through GenServer)."
  def get_hall_info(hall_id) do
    L2E.Repo.get_by(L2E.DB.ClanHall, hall_id: hall_id)
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(_opts) do
    schedule_next_resolution()
    {:ok, %{}, {:continue, :spawn_halls}}
  end

  @impl true
  def handle_continue(:spawn_halls, state) do
    halls = L2E.Repo.all(L2E.DB.ClanHall)

    Enum.each(halls, fn hall ->
      DynamicSupervisor.start_child(
        L2E.ClanHall.HallSupervisor,
        {L2E.ClanHall.Hall, [hall_id: hall.hall_id]}
      )
    end)

    Logger.info("[ClanHallAuction] Spawned #{length(halls)} hall processes")
    {:noreply, state}
  end

  @impl true
  def handle_call({:place_bid, hall_id, clan_id, bidder_char_id, amount}, _from, state) do
    hall = L2E.Repo.get_by(L2E.DB.ClanHall, hall_id: hall_id)

    cond do
      is_nil(hall) ->
        {:reply, {:error, :hall_not_found}, state}

      hall.clan_id != 0 ->
        {:reply, {:error, :hall_already_owned}, state}

      amount < hall.min_bid ->
        {:reply, {:error, :bid_too_low}, state}

      true ->
        existing_bid = L2E.Repo.get_by(L2E.DB.ClanHallBid, hall_id: hall_id, clan_id: clan_id)

        attrs = %{
          hall_id: hall_id,
          clan_id: clan_id,
          bid_amount: amount,
          bidder_char_id: bidder_char_id,
          bid_date: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        result =
          if existing_bid do
            L2E.DB.ClanHallBid.changeset(existing_bid, attrs) |> L2E.Repo.update()
          else
            L2E.DB.ClanHallBid.changeset(%L2E.DB.ClanHallBid{}, attrs) |> L2E.Repo.insert()
          end

        {:reply, result, state}
    end
  end

  @impl true
  def handle_call({:get_bids, hall_id}, _from, state) do
    bids =
      L2E.Repo.all(
        from(b in L2E.DB.ClanHallBid,
          where: b.hall_id == ^hall_id,
          order_by: [desc: b.bid_amount]
        )
      )

    {:reply, bids, state}
  end

  @impl true
  def handle_info(:resolve_auctions, state) do
    Logger.info("[ClanHallAuction] Resolving weekly auctions")
    resolve_all_auctions()
    schedule_next_resolution()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp schedule_next_resolution do
    Process.send_after(self(), :resolve_auctions, @one_week_ms)
  end

  defp resolve_all_auctions do
    halls = L2E.Repo.all(from(h in L2E.DB.ClanHall, where: h.clan_id == 0))

    Enum.each(halls, fn hall ->
      bids =
        L2E.Repo.all(
          from(b in L2E.DB.ClanHallBid,
            where: b.hall_id == ^hall.hall_id,
            order_by: [desc: b.bid_amount],
            limit: 1
          )
        )

      case bids do
        [winning_bid | _] ->
          award_hall(hall, winning_bid)
          return_losing_bids(hall.hall_id, winning_bid.clan_id)
          L2E.Repo.delete_all(from(b in L2E.DB.ClanHallBid, where: b.hall_id == ^hall.hall_id))

        [] ->
          :ok
      end
    end)
  end

  defp award_hall(hall, winning_bid) do
    paid_until =
      DateTime.utc_now()
      |> DateTime.add(7 * 24 * 3600, :second)
      |> DateTime.truncate(:second)

    hall
    |> L2E.DB.ClanHall.changeset(%{
      clan_id: winning_bid.clan_id,
      paid_until: paid_until,
      is_paid: true
    })
    |> L2E.Repo.update()

    # Notify the winning clan's GenServer
    case Registry.lookup(L2E.Session.Registry, {:clan, winning_bid.clan_id}) do
      [{clan_pid, _}] ->
        GenServer.cast(clan_pid, {:set_clan_hall, hall.hall_id})

      [] ->
        :ok
    end

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:announcements",
      {:announcement,
       "Clan hall #{hall.hall_name} has been awarded to clan id #{winning_bid.clan_id}."}
    )

    Logger.info(
      "[ClanHallAuction] Hall #{hall.hall_name} (id=#{hall.hall_id}) awarded to clan #{winning_bid.clan_id}"
    )
  end

  defp return_losing_bids(hall_id, winning_clan_id) do
    losing_bids =
      L2E.Repo.all(
        from(b in L2E.DB.ClanHallBid,
          where: b.hall_id == ^hall_id and b.clan_id != ^winning_clan_id
        )
      )

    Enum.each(losing_bids, fn bid ->
      Logger.info(
        "[ClanHall Auction] Returning #{bid.bid_amount} adena to clan #{bid.clan_id}"
      )

      L2E.Repo.delete(bid)

      Phoenix.PubSub.broadcast(
        L2E.PubSub,
        "world:clan_hall",
        {:bid_returned, bid.clan_id, bid.bid_amount}
      )
    end)
  end
end

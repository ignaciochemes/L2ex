defmodule L2E.DB do
  @moduledoc """
  Database query helpers for the L2E game server.

  Most game logic is implemented as GenServers (ClanWarehouse, Warehouse, etc.).
  These functions provide direct DB access for reporting, admin tools, and backups.
  """

  import Ecto.Query, only: [from: 2]

  alias L2E.{Repo, DB.ClanWarehouseItem}

  # -----------------------------------------------------------------------
  # Clan Warehouse Queries
  # -----------------------------------------------------------------------

  @doc """
  Query all warehouse items for a clan, excluding soft-deleted rows.

  ## Examples

      iex> L2E.DB.warehouse_items_for_clan(1)
      [%ClanWarehouseItem{...}, ...]

      iex> L2E.DB.warehouse_items_for_clan(1, :with_deleted)
      [%ClanWarehouseItem{...}, ...]  # includes soft-deleted
  """
  def warehouse_items_for_clan(clan_id, mode \\ :active) do
    q =
      from(w in ClanWarehouseItem,
        where: w.clan_id == ^clan_id,
        select: w
      )

    q =
      case mode do
        :active -> from(w in q, where: is_nil(w.soft_deleted_at))
        :with_deleted -> q
      end

    Repo.all(q)
  end

  @doc """
  Insert a warehouse item or increment count if it already exists.

  Returns {:ok, item} on success, or {:error, reason} on failure.

  ## Examples

      iex> L2E.DB.add_warehouse_item(1, 100, 5, enchant: 0)
      {:ok, %ClanWarehouseItem{...}}
  """
  def add_warehouse_item(clan_id, item_id, count, opts \\ []) do
    enchant_level = Keyword.get(opts, :enchant, 0)

    case Repo.get_by(ClanWarehouseItem, clan_id: clan_id, item_id: item_id) do
      # Item already exists: increment count
      %ClanWarehouseItem{} = existing ->
        new_count = existing.count + count
        Ecto.Changeset.change(existing, count: new_count) |> Repo.update()

      # Item doesn't exist: create new
      nil ->
        %ClanWarehouseItem{}
        |> ClanWarehouseItem.changeset(%{
          clan_id: clan_id,
          item_id: item_id,
          count: count,
          enchant_level: enchant_level
        })
        |> Repo.insert()
    end
  end

  @doc """
  Soft-delete a warehouse item by setting soft_deleted_at.

  Returns {:ok, item} on success, or {:error, reason} on failure.

  ## Examples

      iex> L2E.DB.remove_warehouse_item(1, 100, 5)
      {:ok, %ClanWarehouseItem{...}}
  """
  def remove_warehouse_item(clan_id, item_id, count) do
    case Repo.get_by(ClanWarehouseItem, clan_id: clan_id, item_id: item_id) do
      %ClanWarehouseItem{count: current_count} = item ->
        if current_count > count do
          # Reduce count
          Ecto.Changeset.change(item, count: current_count - count) |> Repo.update()
        else
          # Soft-delete
          item
          |> Ecto.Changeset.change(soft_deleted_at: DateTime.utc_now())
          |> Repo.update()
        end

      nil ->
        {:error, :not_found}
    end
  end
end

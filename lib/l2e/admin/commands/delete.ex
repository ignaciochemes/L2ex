defmodule L2E.Admin.Commands.Delete do
  @moduledoc """
  Remove item(s) from a player's inventory.

  Usage: admin_delete <item_id> <count>

  Example: admin_delete 1234 5 — removes 5 of item 1234
  If count is higher than player has, removes all of that item.
  """

  require Logger

  @doc """
  Execute the delete command.
  Args: [item_id_str, count_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [item_id_str, count_str] <- args,
         {item_id, ""} <- Integer.parse(item_id_str),
         {count, ""} <- Integer.parse(count_str),
         true <- item_id > 0,
         true <- count > 0 do
      remove_from_player_inventory(player_pid, item_id, count)
    else
      _ -> {:error, "admin_delete <item_id> <count>"}
    end
  end

  defp remove_from_player_inventory(player_pid, item_id, count) do
    try do
      GenServer.call(player_pid, {:admin_delete_item, item_id, count})
    catch
      :exit, _ -> {:error, "Player offline"}
    end
  end
end

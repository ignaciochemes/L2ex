defmodule L2E.Admin.Commands.Give do
  @moduledoc """
  Give item(s) to a player.

  Usage: admin_give <item_id> <count>

  Example: admin_give 1234 10 — grants 10 of item 1234
  """

  alias L2E.Item.TemplateTable

  @doc """
  Execute the give command.
  Args: [item_id_str, count_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [item_id_str, count_str] <- args,
         {item_id, ""} <- Integer.parse(item_id_str),
         {count, ""} <- Integer.parse(count_str),
         true <- item_id > 0,
         true <- count > 0,
         :ok <- validate_item_exists(item_id),
         :ok <- add_to_player_inventory(player_pid, item_id, count) do
      {:ok, "Added #{count}x item #{item_id} to player"}
    else
      _ -> {:error, "admin_give <item_id> <count>"}
    end
  end

  defp validate_item_exists(item_id) do
    case TemplateTable.get(item_id) do
      nil -> {:error, "Item not found"}
      _ -> :ok
    end
  end

  defp add_to_player_inventory(player_pid, item_id, count) do
    # Call the GenServer to add the item
    try do
      GenServer.call(player_pid, {:admin_give_item, item_id, count})
    catch
      :exit, _ -> {:error, "Player offline"}
    end
  end
end

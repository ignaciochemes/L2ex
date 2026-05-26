defmodule L2E.Admin.Commands.GiveItem do
  @moduledoc """
  Give an item directly to the GM's inventory.

  Usage: admin_give_item <item_id> <count>

  Example: admin_give_item 57 1000000 — grants 1 000 000 Adena to the GM
  """

  @doc """
  Execute the give_item command.
  Args: [item_id_str, count_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [item_id_str, count_str] <- args,
         {item_id, ""} <- Integer.parse(item_id_str),
         {count, ""} <- Integer.parse(count_str),
         true <- item_id > 0,
         true <- count > 0 do
      try do
        case GenServer.call(player_pid, {:admin_give_item, item_id, count}) do
          :ok -> {:ok, "Gave #{count}x item #{item_id}"}
          {:error, reason} -> {:error, "Failed to give item: #{inspect(reason)}"}
        end
      catch
        :exit, _ -> {:error, "Player offline"}
      end
    else
      _ -> {:error, "admin_give_item <item_id> <count>"}
    end
  end
end

defmodule L2E.Admin.Commands.SpawnNpc do
  @moduledoc """
  Spawn an NPC at the GM's current position.

  Usage: admin_spawn <npc_id>

  Example: admin_spawn 1001 — spawns NPC 1001 at GM's position
  """

  require Logger

  alias L2E.NPC.SpawnTable

  @doc """
  Execute the spawn_npc command.
  Args: [npc_id_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [npc_id_str] <- args,
         {npc_id, ""} <- Integer.parse(npc_id_str),
         true <- npc_id > 0 do
      spawn_at_gm_position(player_pid, npc_id)
    else
      _ -> {:error, "admin_spawn <npc_id>"}
    end
  end

  defp spawn_at_gm_position(player_pid, npc_id) do
    try do
      # Get GM's position
      {:ok, {x, y, z}} = GenServer.call(player_pid, :get_position)

      # Spawn the NPC
      SpawnTable.admin_spawn(npc_id, x, y, z)

      {:ok, "NPC #{npc_id} spawned at #{x}, #{y}, #{z}"}
    catch
      :exit, _ -> {:error, "Player offline"}
    end
  end
end

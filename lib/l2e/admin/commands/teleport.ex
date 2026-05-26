defmodule L2E.Admin.Commands.Teleport do
  @moduledoc """
  Teleport the GM to world coordinates.

  Usage: admin_teleport <x> <y> <z>

  Example: admin_teleport 83400 148200 -3400
  """

  require Logger

  @doc """
  Execute the teleport command.
  Args: [x_str, y_str, z_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [x_str, y_str, z_str] <- args,
         {x, ""} <- Integer.parse(x_str),
         {y, ""} <- Integer.parse(y_str),
         {z, ""} <- Integer.parse(z_str) do
      teleport_player(player_pid, {x, y, z})
    else
      _ -> {:error, "admin_teleport <x> <y> <z>"}
    end
  end

  defp teleport_player(player_pid, {x, y, z}) do
    try do
      GenServer.call(player_pid, {:admin_teleport, x, y, z})
      {:ok, "Teleported to #{x}, #{y}, #{z}"}
    catch
      :exit, _ -> {:error, "Player offline"}
    end
  end
end

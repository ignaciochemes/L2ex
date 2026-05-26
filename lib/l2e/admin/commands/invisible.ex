defmodule L2E.Admin.Commands.Invisible do
  @moduledoc """
  Toggle the GM's invisibility flag.

  Usage: admin_invisible

  Toggles the invisible flag on/off for the GM.
  Invisible GMs are not visible to other players.
  """

  require Logger

  @doc """
  Execute the invisible toggle command.
  No args required.
  """
  @spec execute(pid()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid) do
    try do
      {:ok, status} = GenServer.call(player_pid, :toggle_invisible)
      {:ok, "Invisibility toggled: #{status}"}
    catch
      :exit, _ -> {:error, "Player offline"}
    end
  end
end

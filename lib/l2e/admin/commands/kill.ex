defmodule L2E.Admin.Commands.Kill do
  @moduledoc """
  Instantly kill a player (set HP to 0).

  Usage: admin_kill <player_name>

  Example: admin_kill Someuser — kills the player named "Someuser"
  Trigger death event, corpse drop, etc. normally.
  """

  require Logger
  import Ecto.Query, only: [from: 2]

  alias L2E.Repo
  alias L2E.DB.Character

  @doc """
  Execute the kill command.
  Args: [player_name_str]
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [player_name] <- args,
         true <- String.length(player_name) > 0 do
      kill_player_by_name(player_pid, player_name)
    else
      _ -> {:error, "admin_kill <player_name>"}
    end
  end

  defp kill_player_by_name(_gm_pid, player_name) do
    # Look up the player by name
    case Repo.get_by(Character, name: player_name) do
      %Character{id: char_id} ->
        # Look up their session in Registry
        case Registry.lookup(L2E.Session.Registry, char_id) do
          [{session_pid, _}] ->
            # Call the session to kill the player
            try do
              GenServer.call(session_pid, :admin_kill)
              {:ok, "Player #{player_name} has been killed"}
            catch
              :exit, _ -> {:error, "Failed to kill player"}
            end

          _ ->
            {:error, "Player #{player_name} is not online"}
        end

      nil ->
        {:error, "Player #{player_name} not found"}
    end
  end
end

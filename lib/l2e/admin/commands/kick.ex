defmodule L2E.Admin.Commands.Kick do
  @moduledoc """
  Disconnect a player from the server.

  Usage: admin_kick <player_name>

  Example: admin_kick BadPlayer — forces disconnection of the player
  """

  alias L2E.Repo
  alias L2E.DB.Character

  @doc """
  Execute the kick command.
  Args: [player_name_str]
  """
  @spec execute(list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(args) do
    with [player_name] <- args,
         true <- String.length(player_name) > 0 do
      kick_player_by_name(player_name)
    else
      _ -> {:error, "admin_kick <player_name>"}
    end
  end

  defp kick_player_by_name(player_name) do
    case Repo.get_by(Character, name: player_name) do
      %Character{id: char_id} ->
        # Look up their session in Registry
        case Registry.lookup(L2E.Session.Registry, char_id) do
          [{session_pid, _}] ->
            # Send the disconnect message
            GenServer.cast(session_pid, :connection_closed)
            {:ok, "Player #{player_name} has been kicked"}

          _ ->
            {:error, "Player #{player_name} is not online"}
        end

      nil ->
        {:error, "Player #{player_name} not found"}
    end
  end
end

defmodule L2E.Admin.Commands.ListPlayers do
  @moduledoc """
  List all currently connected players.

  Usage: admin_list_players

  Returns a paginated list of player names with basic stats.
  """

  require Logger

  @doc """
  Execute the list_players command.
  Returns a formatted string with connected players.
  """
  @spec execute :: {:ok, String.t()}
  def execute do
    players =
      Registry.select(L2E.Session.Registry, [
        {
          {:_, :"$1", :_},
          [],
          [:"$1"]
        }
      ])

    if Enum.empty?(players) do
      {:ok, "No players online"}
    else
      player_count = Enum.count(players)
      player_list = Enum.map_join(players, ", ", &fetch_player_name/1)

      {:ok, "Connected players (#{player_count}): #{player_list}"}
    end
  end

  defp fetch_player_name(char_id) do
    case GenServer.call(
           Registry.lookup(L2E.Session.Registry, char_id) |> List.first() |> elem(0),
           :get_char_name
         ) do
      name when is_binary(name) -> name
      _ -> "Unknown(#{char_id})"
    end
  catch
    :exit, _ -> "Unknown(#{char_id})"
  end
end

defmodule L2E.Admin.Commands.Heal do
  @moduledoc """
  Fully heal a player (set HP to max).

  Usage: admin_heal [<player_name>]

  Example: admin_heal         — heals the GM themselves
  Example: admin_heal Someuser — heals the player named "Someuser"

  The heal is applied by sending {:admin_heal} to the target session,
  which sets HP to max_hp and sends a StatusUpdate packet to the client.
  """

  alias L2E.Repo
  alias L2E.DB.Character

  @doc """
  Execute the heal command.
  Args: [] to heal GM, or [player_name] to heal a named player.
  """
  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, []) do
    send(player_pid, {:admin_heal})
    {:ok, "You have been healed"}
  end

  def execute(_player_pid, [player_name]) when player_name != "" do
    heal_player_by_name(player_name)
  end

  def execute(_player_pid, _args) do
    {:error, "admin_heal [player_name]"}
  end

  defp heal_player_by_name(player_name) do
    case Repo.get_by(Character, name: player_name) do
      %Character{id: char_id} ->
        case Registry.lookup(L2E.Session.Registry, char_id) do
          [{session_pid, _}] ->
            send(session_pid, {:admin_heal})
            {:ok, "#{player_name} has been healed"}

          _ ->
            {:error, "Player #{player_name} is not online"}
        end

      nil ->
        {:error, "Player #{player_name} not found"}
    end
  end
end

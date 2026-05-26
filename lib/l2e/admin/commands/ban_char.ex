defmodule L2E.Admin.Commands.BanChar do
  @moduledoc """
  Ban a character by setting their account access_level to -100.

  Usage: admin_ban_char <player_name>

  Example: admin_ban_char BadPlayer

  Sets the owning account's access_level to -100 (banned). If the player
  is currently online, they are immediately disconnected.
  """

  alias L2E.Repo
  alias L2E.DB.{Account, Character}

  import Ecto.Changeset, only: [change: 2]

  @doc """
  Execute the ban_char command.
  Args: [player_name]
  """
  @spec execute(list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute([player_name]) when player_name != "" do
    ban_character(player_name)
  end

  def execute(_args) do
    {:error, "admin_ban_char <player_name>"}
  end

  defp ban_character(player_name) do
    case Repo.get_by(Character, name: player_name) do
      %Character{id: char_id, account_name: account_name} ->
        with %Account{} = account <- Repo.get_by(Account, username: account_name),
             {:ok, _} <- Repo.update(change(account, %{access_level: -100})) do
          # Kick if online
          case Registry.lookup(L2E.Session.Registry, char_id) do
            [{session_pid, _}] -> GenServer.cast(session_pid, :connection_closed)
            _ -> :ok
          end

          {:ok, "#{player_name} has been banned"}
        else
          nil -> {:error, "Account '#{account_name}' not found"}
          {:error, reason} -> {:error, "Failed to ban: #{inspect(reason)}"}
        end

      nil ->
        {:error, "Character #{player_name} not found"}
    end
  end
end

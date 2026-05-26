defmodule L2E.Admin.Commands.SetClanLevel do
  @moduledoc """
  Set the GM's clan to a specific level by setting reputation to that level's threshold.

  Usage: admin_set_clan_level <level>

  Level must be an integer between 1 and 8.

  Example: admin_set_clan_level 5 — sets the clan reputation to the level 5 threshold (1000)
  """

  @level_thresholds %{
    1 => 0,
    2 => 20,
    3 => 100,
    4 => 350,
    5 => 1_000,
    6 => 2_500,
    7 => 5_000,
    8 => 10_000
  }

  @spec execute(pid(), list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute(player_pid, args) do
    with [level_str] <- args,
         {level, ""} <- Integer.parse(level_str),
         true <- level in 1..8 do
      try do
        case GenServer.call(player_pid, :get_clan_pid) do
          nil ->
            {:error, "You are not in a clan"}

          clan_pid ->
            rep = Map.fetch!(@level_thresholds, level)
            L2E.Clan.set_reputation(clan_pid, rep)
            {:ok, "Clan reputation set to #{rep} (level #{level} threshold)"}
        end
      catch
        :exit, _ -> {:error, "Player offline"}
      end
    else
      _ -> {:error, "admin_set_clan_level <level 1-8>"}
    end
  end
end

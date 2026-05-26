defmodule L2E.Admin.Dispatcher do
  @moduledoc """
  Executes admin commands with access control and audit logging.

  This module receives parsed admin actions from CommandHandler and routes them
  to specific handler modules. Each command is guarded by access_level >= 100 for
  most commands, or > 0 for basic player control commands.

  All command attempts are logged to an audit trail (ETS + optional file).

  Handlers:
  - L2E.Admin.Commands.Give — grant items
  - L2E.Admin.Commands.Delete — remove items
  - L2E.Admin.Commands.Kick — disconnect player
  - L2E.Admin.Commands.Kill — zero out player HP
  - L2E.Admin.Commands.ListPlayers — list connected players
  - L2E.Admin.Commands.SpawnNpc — spawn NPC at position
  """

  require Logger

  @audit_table :admin_audit_log

  @doc """
  Initialize audit logging ETS table (call once at app startup).
  """
  def init_audit_table do
    :ets.new(@audit_table, [:bag, :named_table, {:read_concurrency, true}])
  end

  @doc """
  Dispatch an admin command from a player session.

  Returns `{:ok, message}` on success or `{:error, reason}` on failure.
  All attempts are logged to the audit trail.
  """
  @spec dispatch(pid(), String.t(), list(String.t()), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def dispatch(player_pid, command_name, args, access_level) do
    result = do_dispatch(command_name, args, player_pid, access_level)
    log_audit(command_name, args, access_level, result)
    result
  end

  # -----------------------------------------------------------------------
  # Private dispatch logic
  # -----------------------------------------------------------------------

  defp do_dispatch("give", args, player_pid, access_level) when access_level >= 100 do
    L2E.Admin.Commands.Give.execute(player_pid, args)
  end

  defp do_dispatch("delete", args, player_pid, access_level) when access_level >= 100 do
    L2E.Admin.Commands.Delete.execute(player_pid, args)
  end

  defp do_dispatch("kill", args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Kill.execute(player_pid, args)
  end

  defp do_dispatch("kick", args, _player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Kick.execute(args)
  end

  defp do_dispatch("list_players", _args, _player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.ListPlayers.execute()
  end

  defp do_dispatch("spawn", args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.SpawnNpc.execute(player_pid, args)
  end

  defp do_dispatch("teleport", args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Teleport.execute(player_pid, args)
  end

  defp do_dispatch("invisible", _args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Invisible.execute(player_pid)
  end

  defp do_dispatch("give_item", args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.GiveItem.execute(player_pid, args)
  end

  defp do_dispatch("announce", args, _player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Announce.execute(args)
  end

  defp do_dispatch("heal", args, player_pid, access_level) when access_level > 0 do
    L2E.Admin.Commands.Heal.execute(player_pid, args)
  end

  defp do_dispatch("ban_char", args, _player_pid, access_level) when access_level >= 100 do
    L2E.Admin.Commands.BanChar.execute(args)
  end

  defp do_dispatch("reload", args, _player_pid, access_level) when access_level >= 100 do
    L2E.Admin.Commands.Reload.execute(args)
  end

  # Unknown command or insufficient access
  defp do_dispatch(cmd, _args, _player_pid, access_level) do
    {:error, "Unknown command '#{cmd}' or insufficient access (level: #{access_level})"}
  end

  # -----------------------------------------------------------------------
  # Audit logging
  # -----------------------------------------------------------------------

  defp log_audit(command_name, args, access_level, result) do
    timestamp = System.os_time(:second)
    status = if elem(result, 0) == :ok, do: :success, else: :failure

    log_entry = {
      timestamp,
      command_name,
      args,
      access_level,
      status,
      result
    }

    :ets.insert(@audit_table, log_entry)

    # Also log to application logger
    case result do
      {:ok, msg} ->
        Logger.info("Admin: #{command_name} #{inspect(args)} → #{msg} (level: #{access_level})")

      {:error, reason} ->
        Logger.warning("Admin denied: #{command_name} → #{reason} (level: #{access_level})")
    end
  end

  @doc """
  Retrieve recent audit log entries (last N records).
  """
  @spec audit_log(pos_integer()) :: [tuple()]
  def audit_log(limit \\ 100) do
    :ets.tab2list(@audit_table)
    |> Enum.sort(fn {ts1, _, _, _, _, _}, {ts2, _, _, _, _, _} -> ts1 >= ts2 end)
    |> Enum.take(limit)
  end

  @doc """
  Clear audit log.
  """
  @spec clear_audit_log :: true
  def clear_audit_log do
    :ets.delete_all_objects(@audit_table)
  end
end

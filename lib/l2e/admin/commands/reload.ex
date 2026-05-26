defmodule L2E.Admin.Commands.Reload do
  @moduledoc """
  Trigger a best-effort reload of a data table.

  Usage: admin_reload <target>

  Supported targets:
  - spawns — reload NPC spawn definitions via SpawnTable
  - skills  — (reserved; best-effort confirmation)
  - npcs    — (reserved; best-effort confirmation)
  - items   — (reserved; best-effort confirmation)

  Actual ETS/GenServer data reloads are best-effort. Only SpawnTable
  supports a live reload in the current implementation.
  """

  require Logger

  @valid_targets ~w[skills npcs items spawns]

  @doc """
  Execute the reload command.
  Args: [target]
  """
  @spec execute(list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute([target]) when target in @valid_targets do
    do_reload(target)
  end

  def execute([target]) do
    {:error, "Unknown reload target '#{target}'. Valid: #{Enum.join(@valid_targets, ", ")}"}
  end

  def execute(_args) do
    {:error, "admin_reload <target> — valid targets: #{Enum.join(@valid_targets, ", ")}"}
  end

  defp do_reload("spawns") do
    case L2E.NPC.SpawnTable.reload() do
      :ok -> {:ok, "Spawns reloaded"}
      _ -> {:ok, "Spawns reload requested"}
    end
  end

  defp do_reload(target) do
    Logger.info("[Admin.Reload] Reload requested for '#{target}' — best-effort (no live reloader)")
    {:ok, "#{String.capitalize(target)} reload acknowledged (best-effort)"}
  end
end

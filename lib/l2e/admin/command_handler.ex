defmodule L2E.Admin.CommandHandler do
  @moduledoc """
  Parses GM admin bypass commands into structured action tuples.

  Commands are sent by the client as BypassToServer strings with the
  `admin_` prefix. Execution happens inside PlayerSession so that private
  game functions (teleport, region handoff, etc.) remain encapsulated.

  Required: caller's `access_level` must be > 0 before invoking this module.

  Supported commands
  ------------------
  - `admin_spawn <npc_id>`          — spawn NPC at GM's current position
  - `admin_teleport <x> <y> <z>`   — teleport GM to world coordinates
  - `admin_kick <char_name>`        — force-disconnect a named character
  - `admin_invisible`               — toggle GM invisibility flag
  """

  @type action ::
          {:spawn_npc, npc_id :: pos_integer()}
          | {:teleport, x :: integer(), y :: integer(), z :: integer()}
          | {:kick, char_name :: String.t()}
          | :toggle_invisible

  @doc """
  Parse an `admin_*` bypass string into a structured action.
  Returns `{:ok, action()}` on success or `:ignored` when the command
  is unknown or malformed.
  """
  @spec parse(String.t()) :: {:ok, action()} | :ignored
  def parse(<<"admin_", rest::binary>>) do
    case String.split(rest, " ", trim: true) do
      ["spawn", npc_id_str] ->
        case Integer.parse(npc_id_str) do
          {npc_id, ""} when npc_id > 0 -> {:ok, {:spawn_npc, npc_id}}
          _ -> :ignored
        end

      ["teleport", x_str, y_str, z_str] ->
        with {x, ""} <- Integer.parse(x_str),
             {y, ""} <- Integer.parse(y_str),
             {z, ""} <- Integer.parse(z_str) do
          {:ok, {:teleport, x, y, z}}
        else
          _ -> :ignored
        end

      ["kick", char_name] when char_name != "" ->
        {:ok, {:kick, char_name}}

      ["invisible"] ->
        {:ok, :toggle_invisible}

      _ ->
        :ignored
    end
  end

  def parse(_), do: :ignored
end

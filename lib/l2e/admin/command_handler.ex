defmodule L2E.Admin.CommandHandler do
  @moduledoc """
  Parses GM admin bypass commands into structured action tuples.

  Commands are sent by the client as BypassToServer strings with the
  `admin_` prefix. Execution happens inside PlayerSession so that private
  game functions (teleport, region handoff, etc.) remain encapsulated.

  Required: caller's `access_level` must be > 0 before invoking this module.

  Supported commands
  ------------------
  - `admin_spawn <npc_id>`                    — spawn NPC at GM's current position
  - `admin_teleport <x> <y> <z>`             — teleport GM to world coordinates
  - `admin_kick <char_name>`                  — force-disconnect a named character
  - `admin_invisible`                         — toggle GM invisibility flag
  - `admin_give_item <item_id> <count>`       — give item to GM inventory
  - `admin_announce <message>`                — broadcast server-wide announcement
  - `admin_heal [player_name]`                — fully heal GM or named player
  - `admin_kill <player_name>`                — instantly kill named player
  - `admin_ban_char <player_name>`            — ban character's account (access_level -100)
  - `admin_reload <skills|npcs|items|spawns>` — trigger best-effort data reload
  """

  @type action ::
          {:spawn_npc, npc_id :: pos_integer()}
          | {:teleport, x :: integer(), y :: integer(), z :: integer()}
          | {:kick, char_name :: String.t()}
          | :toggle_invisible
          | {:give_item, item_id :: pos_integer(), count :: pos_integer()}
          | {:announce, message :: String.t()}
          | :admin_heal
          | {:heal, player_name :: String.t()}
          | {:kill, player_name :: String.t()}
          | {:ban_char, char_name :: String.t()}
          | {:reload, target :: String.t()}

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

      ["give_item", item_id_str, count_str] ->
        with {item_id, ""} <- Integer.parse(item_id_str),
             {count, ""} <- Integer.parse(count_str),
             true <- item_id > 0,
             true <- count > 0 do
          {:ok, {:give_item, item_id, count}}
        else
          _ -> :ignored
        end

      ["announce" | words] when words != [] ->
        message = Enum.join(words, " ")
        {:ok, {:announce, message}}

      ["heal"] ->
        {:ok, :admin_heal}

      ["heal", player_name] when player_name != "" ->
        {:ok, {:heal, player_name}}

      ["kill", player_name] when player_name != "" ->
        {:ok, {:kill, player_name}}

      ["ban_char", char_name] when char_name != "" ->
        {:ok, {:ban_char, char_name}}

      ["reload", target] when target in ["skills", "npcs", "items", "spawns"] ->
        {:ok, {:reload, target}}

      _ ->
        :ignored
    end
  end

  def parse(_), do: :ignored
end

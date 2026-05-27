defmodule L2E.Quest.Scripts.DarkElf1stClass do
  @moduledoc """
  1st class transfer for Dark Elf characters.

  Dark Fighter (class 30) → Palus Knight (31) or Assassin (32) at level 20.
  Dark Mage    (class 38) → Shillien Oracle (39) at level 20.

  Talk-based quest: talk to the Dark Elf Class Master, meet level + class requirements,
  and receive a Class Transfer Certificate (1st).
  """
  use L2E.Quest.Engine

  def quest_id, do: 405
  def quest_name, do: "Proof of Dark Elf Heritage"
  def min_level, do: 20

  # NPC 30040 = Dark Elf Class Master (Dark Elven Village)
  def npc_ids, do: [30040]
  def npc_kill_ids, do: []

  # Dark Elf base classes eligible for 1st transfer
  @dark_elf_base_classes [30, 38]

  def on_first_talk(30040, player) do
    cond do
      player.class_id not in @dark_elf_base_classes ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         This trial is reserved for Dark Elves who have not yet chosen a vocational path.
         Your lineage does not qualify.
         </body></html>
         """}

      player.level < min_level() ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         You are not yet ready for advancement. Return when you have reached level #{min_level()}.
         </body></html>
         """}

      true ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         I sense the darkness within you, adventurer. You have trained to level #{min_level()} and
         are ready to choose your vocational path as a #{base_class_name(player.class_id)}.<br>
         <br>
         Available paths: #{available_paths(player.class_id)}<br>
         <br>
         <a action="bypass Quest 30040 advance">I am ready to advance.</a><br>
         <a action="bypass -h npc_30040_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30040, 0, player) do
    if player.level >= min_level() and player.class_id in @dark_elf_base_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Class Master:<br>
      Your dedication is acknowledged. You are now recognized as a #{target_class_name(target)}.
      Embrace the shadow on your new path.
      </body></html>
      """

      new_state = %{
        state: 2,
        cond: 1,
        count: 0,
        reward_taken: false,
        target_class_id: target
      }

      {:ok, html, new_state}
    else
      :skip
    end
  end

  def on_complete(_player, _quest_state) do
    # Dark Elf 1st Class Transfer Certificate — item_id 1852
    {:ok, [{1852, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Dark Fighter → Palus Knight (primary path)
  defp primary_target_class(30), do: 31
  # Dark Mage → Shillien Oracle
  defp primary_target_class(38), do: 39
  defp primary_target_class(_), do: 31

  defp base_class_name(30), do: "Dark Fighter"
  defp base_class_name(38), do: "Dark Mage"
  defp base_class_name(_), do: "Dark Elf"

  defp available_paths(30), do: "Palus Knight, Assassin"
  defp available_paths(38), do: "Shillien Oracle"
  defp available_paths(_), do: "unknown"

  defp target_class_name(31), do: "Palus Knight"
  defp target_class_name(32), do: "Assassin"
  defp target_class_name(39), do: "Shillien Oracle"
  defp target_class_name(_), do: "advanced class"
end

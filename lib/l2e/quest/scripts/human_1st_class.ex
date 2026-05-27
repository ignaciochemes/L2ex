defmodule L2E.Quest.Scripts.Human1stClass do
  @moduledoc """
  1st class transfer for Human characters.

  Human Fighter (class 0) → Warrior (1), Rogue (2), or Knight (4) at level 20.
  Human Mage    (class 10) → Sorcerer (20) or Necromancer (21) at level 20.

  Talk-based quest: talk to the Class Master, meet level + class requirements,
  and receive a Class Transfer Certificate (1st).
  """
  use L2E.Quest.Engine

  def quest_id, do: 401
  def quest_name, do: "Proof of Human Heritage"
  def min_level, do: 20

  # NPC 30037 = Human Class Master (Gludin Village)
  def npc_ids, do: [30037]
  def npc_kill_ids, do: []

  # Human base classes eligible for 1st transfer
  @human_base_classes [0, 10]

  def on_first_talk(30037, player) do
    cond do
      player.class_id not in @human_base_classes ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         This trial is reserved for Humans who have not yet chosen a vocational path.
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
         I see the potential in you, adventurer. You have trained to level #{min_level()} and
         are ready to choose your vocational path as a #{base_class_name(player.class_id)}.<br>
         <br>
         Available paths: #{available_paths(player.class_id)}<br>
         <br>
         <a action="bypass Quest 30037 advance">I am ready to advance.</a><br>
         <a action="bypass -h npc_30037_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30037, 0, player) do
    if player.level >= min_level() and player.class_id in @human_base_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Class Master:<br>
      Your dedication is acknowledged. You are now recognized as a #{target_class_name(target)}.
      May your new path bring you glory.
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
    # Human 1st Class Transfer Certificate — item_id 1850
    {:ok, [{1850, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns the primary 1st-class target for each Human base class.
  # Secondary options (Rogue, Knight, Necromancer) use dedicated path quests.
  # Human Fighter → Warrior
  defp primary_target_class(0), do: 1
  # Human Mage → Sorcerer
  defp primary_target_class(10), do: 20
  defp primary_target_class(_), do: 1

  defp base_class_name(0), do: "Human Fighter"
  defp base_class_name(10), do: "Human Mage"
  defp base_class_name(_), do: "Human"

  defp available_paths(0), do: "Warrior, Rogue, Knight"
  defp available_paths(10), do: "Sorcerer, Necromancer"
  defp available_paths(_), do: "unknown"

  defp target_class_name(1), do: "Warrior"
  defp target_class_name(2), do: "Rogue"
  defp target_class_name(4), do: "Knight"
  defp target_class_name(20), do: "Sorcerer"
  defp target_class_name(21), do: "Necromancer"
  defp target_class_name(_), do: "advanced class"
end

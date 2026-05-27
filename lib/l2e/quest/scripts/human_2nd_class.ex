defmodule L2E.Quest.Scripts.Human2ndClass do
  @moduledoc """
  2nd class transfer for Human characters.

  Eligible 1st-class Humans (level >= 40):
    Warrior (1)     → Gladiator (29) or Warlord (28)   — advances to Gladiator
    Rogue   (2)     → Treasure Hunter (38)
    Knight  (4)     → Paladin (12) or Dark Avenger (13) — advances to Paladin
    Sorcerer  (20)  → Archmage (87)
    Necromancer (21) → Warlock (88)

  Talk-based quest: talk to the Grand Master, meet level + class requirements,
  and receive a Class Transfer Certificate (2nd).
  """
  use L2E.Quest.Engine

  def quest_id, do: 402
  def quest_name, do: "Trial of the Grand Path"
  def min_level, do: 40

  # NPC 30038 = Human Grand Master (Town of Oren)
  def npc_ids, do: [30038]
  def npc_kill_ids, do: []

  # Human 1st-class IDs eligible for 2nd transfer
  @human_first_classes [1, 2, 4, 20, 21]

  def on_first_talk(30038, player) do
    cond do
      player.class_id not in @human_first_classes ->
        {:ok,
         """
         <html><body>
         Grand Master:<br>
         Only those who have completed their first vocational path may seek the grand trial.
         Your current class does not qualify.
         </body></html>
         """}

      player.level < min_level() ->
        {:ok,
         """
         <html><body>
         Grand Master:<br>
         The grand trial demands a seasoned warrior. Return when you have reached level #{min_level()}.
         </body></html>
         """}

      true ->
        target = primary_target_class(player.class_id)

        {:ok,
         """
         <html><body>
         Grand Master:<br>
         #{first_class_name(player.class_id)} — you have proven your dedication through years of
         battle. The path of the #{target_class_name(target)} awaits you.<br>
         <br>
         <a action="bypass Quest 30038 advance">I am ready to receive the title.</a><br>
         <a action="bypass -h npc_30038_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30038, 0, player) do
    if player.level >= min_level() and player.class_id in @human_first_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Grand Master:<br>
      Your mastery is undeniable. The title of #{target_class_name(target)} is now yours.
      Carry it with honor.
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
    # Human 2nd Class Transfer Certificate — item_id 1851
    {:ok, [{1851, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Primary 2nd-class target for each Human 1st class (from ClassAdvancementTable)
  # Warrior → Gladiator
  defp primary_target_class(1), do: 29
  # Rogue → Treasure Hunter
  defp primary_target_class(2), do: 38
  # Knight → Paladin
  defp primary_target_class(4), do: 12
  # Sorcerer → Archmage
  defp primary_target_class(20), do: 87
  # Necromancer → Warlock (placeholder)
  defp primary_target_class(21), do: 88
  defp primary_target_class(_), do: 29

  defp first_class_name(1), do: "Warrior"
  defp first_class_name(2), do: "Rogue"
  defp first_class_name(4), do: "Knight"
  defp first_class_name(20), do: "Sorcerer"
  defp first_class_name(21), do: "Necromancer"
  defp first_class_name(_), do: "Adventurer"

  defp target_class_name(12), do: "Paladin"
  defp target_class_name(13), do: "Dark Avenger"
  defp target_class_name(28), do: "Warlord"
  defp target_class_name(29), do: "Gladiator"
  defp target_class_name(38), do: "Treasure Hunter"
  defp target_class_name(87), do: "Archmage"
  defp target_class_name(88), do: "Warlock"
  defp target_class_name(_), do: "advanced class"
end

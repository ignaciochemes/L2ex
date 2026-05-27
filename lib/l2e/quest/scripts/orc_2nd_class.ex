defmodule L2E.Quest.Scripts.Orc2ndClass do
  @moduledoc """
  2nd class transfer for Orc characters.

  Eligible 1st-class Orcs (level >= 40):
    Monk   (45) → Destroyer (48)
    Raider (47) → Overlord (51) — via clan path; advances to Overlord
    Shaman (50) → Warcryer (52)

  Talk-based quest: talk to the Orc Grand Master, meet level + class requirements,
  and receive a Class Transfer Certificate (2nd).
  """
  use L2E.Quest.Engine

  def quest_id, do: 408
  def quest_name, do: "Trial of Ancestral Might"
  def min_level, do: 40

  # NPC 30101 = Orc Grand Master (Orc Village)
  def npc_ids, do: [30101]
  def npc_kill_ids, do: []

  # Orc 1st-class IDs eligible for 2nd transfer
  @orc_first_classes [45, 47, 50]

  def on_first_talk(30101, player) do
    cond do
      player.class_id not in @orc_first_classes ->
        {:ok,
         """
         <html><body>
         Grand Master:<br>
         Only those who have completed their first vocational path may seek the ancestral trial.
         Your current class does not qualify.
         </body></html>
         """}

      player.level < min_level() ->
        {:ok,
         """
         <html><body>
         Grand Master:<br>
         The ancestral trial demands a proven warrior. Return when you have reached level #{min_level()}.
         </body></html>
         """}

      true ->
        target = primary_target_class(player.class_id)

        {:ok,
         """
         <html><body>
         Grand Master:<br>
         #{first_class_name(player.class_id)} — the ancestors have watched your battles.
         The path of the #{target_class_name(target)} awaits you.<br>
         <br>
         <a action="bypass Quest 30101 advance">I am ready to receive the title.</a><br>
         <a action="bypass -h npc_30101_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30101, 0, player) do
    if player.level >= min_level() and player.class_id in @orc_first_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Grand Master:<br>
      The ancestors name you #{target_class_name(target)}. Walk this path with fury and pride.
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
    # Orc 2nd Class Transfer Certificate — item_id 1855
    {:ok, [{1855, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Monk → Destroyer
  defp primary_target_class(45), do: 48
  # Raider → Overlord
  defp primary_target_class(47), do: 51
  # Shaman → Warcryer
  defp primary_target_class(50), do: 52
  defp primary_target_class(_), do: 48

  defp first_class_name(45), do: "Monk"
  defp first_class_name(47), do: "Raider"
  defp first_class_name(50), do: "Shaman"
  defp first_class_name(_), do: "Orc Adventurer"

  defp target_class_name(48), do: "Destroyer"
  defp target_class_name(51), do: "Overlord"
  defp target_class_name(52), do: "Warcryer"
  defp target_class_name(_), do: "advanced class"
end

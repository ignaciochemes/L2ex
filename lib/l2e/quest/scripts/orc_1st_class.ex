defmodule L2E.Quest.Scripts.Orc1stClass do
  @moduledoc """
  1st class transfer for Orc characters.

  Orc Fighter (class 44) → Monk (45) or Raider (47) at level 20.
  Orc Mage    (class 49) → Shaman (50) at level 20.

  Talk-based quest: talk to the Orc Class Master, meet level + class requirements,
  and receive a Class Transfer Certificate (1st).
  """
  use L2E.Quest.Engine

  def quest_id, do: 407
  def quest_name, do: "Proof of Orcish Blood"
  def min_level, do: 20

  # NPC 30100 = Orc Class Master (Orc Village)
  def npc_ids, do: [30100]
  def npc_kill_ids, do: []

  # Orc base classes eligible for 1st transfer
  @orc_base_classes [44, 49]

  def on_first_talk(30100, player) do
    cond do
      player.class_id not in @orc_base_classes ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         This trial is reserved for Orcs who have not yet chosen a vocational path.
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
         The spirits acknowledge your strength, #{base_class_name(player.class_id)}. You have trained
         to level #{min_level()} and are ready to choose your vocational path.<br>
         <br>
         Available paths: #{available_paths(player.class_id)}<br>
         <br>
         <a action="bypass Quest 30100 advance">I am ready to advance.</a><br>
         <a action="bypass -h npc_30100_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30100, 0, player) do
    if player.level >= min_level() and player.class_id in @orc_base_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Class Master:<br>
      Your dedication is acknowledged. You are now recognized as a #{target_class_name(target)}.
      Carry the honor of your clan.
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
    # Orc 1st Class Transfer Certificate — item_id 1854
    {:ok, [{1854, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Orc Fighter → Monk (primary path)
  defp primary_target_class(44), do: 45
  # Orc Mage → Shaman
  defp primary_target_class(49), do: 50
  defp primary_target_class(_), do: 45

  defp base_class_name(44), do: "Orc Fighter"
  defp base_class_name(49), do: "Orc Mage"
  defp base_class_name(_), do: "Orc"

  defp available_paths(44), do: "Monk, Raider"
  defp available_paths(49), do: "Shaman"
  defp available_paths(_), do: "unknown"

  defp target_class_name(45), do: "Monk"
  defp target_class_name(47), do: "Raider"
  defp target_class_name(50), do: "Shaman"
  defp target_class_name(_), do: "advanced class"
end

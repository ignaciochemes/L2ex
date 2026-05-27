defmodule L2E.Quest.Scripts.Dwarf1stClass do
  @moduledoc """
  1st class transfer for Dwarf characters.

  Dwarf Fighter (class 53) → Scavenger (54) or Artisan (55) at level 20.
  Dwarves have no mage path; Dwarf Fighter is the only base class.

  Talk-based quest: talk to the Dwarf Class Master, meet level + class requirements,
  and receive a Class Transfer Certificate (1st).
  """
  use L2E.Quest.Engine

  def quest_id, do: 409
  def quest_name, do: "Proof of Dwarven Craft"
  def min_level, do: 20

  # NPC 30108 = Dwarf Class Master (Dwarven Village)
  def npc_ids, do: [30108]
  def npc_kill_ids, do: []

  # Dwarf base class eligible for 1st transfer
  @dwarf_base_classes [53]

  def on_first_talk(30108, player) do
    cond do
      player.class_id not in @dwarf_base_classes ->
        {:ok,
         """
         <html><body>
         Class Master:<br>
         This trial is reserved for Dwarven Fighters who have not yet chosen a vocational path.
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
         Fine craftsmanship demands dedication, Dwarf Fighter. You have trained to level #{min_level()}
         and are ready to choose your vocational path.<br>
         <br>
         Available paths: Scavenger, Artisan<br>
         <br>
         <a action="bypass Quest 30108 advance">I am ready to advance.</a><br>
         <a action="bypass -h npc_30108_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30108, 0, player) do
    if player.level >= min_level() and player.class_id in @dwarf_base_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Class Master:<br>
      Your dedication is acknowledged. You are now recognized as a #{target_class_name(target)}.
      May your hands never tire and your craft never fail.
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
    # Dwarf 1st Class Transfer Certificate — item_id 1856
    {:ok, [{1856, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Dwarf Fighter → Scavenger (primary path)
  defp primary_target_class(53), do: 54
  defp primary_target_class(_), do: 54

  defp target_class_name(54), do: "Scavenger"
  defp target_class_name(55), do: "Artisan"
  defp target_class_name(_), do: "advanced class"
end

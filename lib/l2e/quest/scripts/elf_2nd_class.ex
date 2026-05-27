defmodule L2E.Quest.Scripts.Elf2ndClass do
  @moduledoc """
  2nd class transfer for Elf characters.

  Eligible 1st-class Elves (level >= 40):
    Elven Knight (22) → Temple Knight (30) or Swordsinger (31) — advances to Temple Knight
    Elven Scout  (23) → Plains Walker (32)
    Elven Wizard (24) → Spellsinger (33)
    Oracle       (25) → Elder (34)

  Talk-based quest: speak to the Elven High Elder, meet level + class requirements,
  and receive a Class Transfer Certificate (Elf 2nd).
  """
  use L2E.Quest.Engine

  def quest_id, do: 404
  def quest_name, do: "Blessing of the Ancient Forest"
  def min_level, do: 40

  # NPC 30101 = Elven High Elder (Elven Village)
  def npc_ids, do: [30101]
  def npc_kill_ids, do: []

  # Elf 1st-class IDs eligible for 2nd transfer (standard L2J Interlude IDs)
  @elf_first_classes [22, 23, 24, 25]

  def on_first_talk(30101, player) do
    cond do
      player.class_id not in @elf_first_classes ->
        {:ok,
         """
         <html><body>
         High Elder:<br>
         The blessing of the ancient forest is reserved for Elves who have already
         taken their first vocational path. Your class does not qualify.
         </body></html>
         """}

      player.level < min_level() ->
        {:ok,
         """
         <html><body>
         High Elder:<br>
         Patience, young one. The ancient spirits require you to reach level #{min_level()}
         before the blessing may be conferred.
         </body></html>
         """}

      true ->
        target = primary_target_class(player.class_id)

        {:ok,
         """
         <html><body>
         High Elder:<br>
         #{first_class_name(player.class_id)}, the ancient spirits have watched your journey.
         You are worthy to ascend as a #{target_class_name(target)}.<br>
         <br>
         <a action="bypass Quest 30101 advance">I am ready to receive the blessing.</a><br>
         <a action="bypass -h npc_30101_return">I need more preparation.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30101, 0, player) do
    if player.level >= min_level() and player.class_id in @elf_first_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      High Elder:<br>
      The blessing is yours. The ancient forest recognizes you as #{target_class_name(target)}.
      Walk under the protection of the eternal spirits.
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
    # Elf 2nd Class Transfer Certificate — item_id 1853
    {:ok, [{1853, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Primary 2nd-class target for each Elf 1st class (standard L2J Interlude IDs)
  # Elven Knight → Temple Knight
  defp primary_target_class(22), do: 30
  # Elven Scout → Plains Walker
  defp primary_target_class(23), do: 32
  # Elven Wizard → Spellsinger
  defp primary_target_class(24), do: 33
  # Oracle → Elder
  defp primary_target_class(25), do: 34
  defp primary_target_class(_), do: 30

  defp first_class_name(22), do: "Elven Knight"
  defp first_class_name(23), do: "Elven Scout"
  defp first_class_name(24), do: "Elven Wizard"
  defp first_class_name(25), do: "Oracle"
  defp first_class_name(_), do: "Elf"

  defp target_class_name(30), do: "Temple Knight"
  defp target_class_name(31), do: "Swordsinger"
  defp target_class_name(32), do: "Plains Walker"
  defp target_class_name(33), do: "Spellsinger"
  defp target_class_name(34), do: "Elder"
  defp target_class_name(_), do: "advanced class"
end

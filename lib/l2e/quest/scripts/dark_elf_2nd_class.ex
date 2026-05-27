defmodule L2E.Quest.Scripts.DarkElf2ndClass do
  @moduledoc """
  2nd class transfer for Dark Elf characters.

  Eligible 1st-class Dark Elves (level >= 40):
    Palus Knight (31) → Shillien Knight (60)
    Assassin     (32) → Bladedancer (33) or Abyss Walker (34) — advances to Abyss Walker
    Shillien Oracle (39) → Shillien Elder (68)

  Talk-based quest: talk to the Dark Elf Grand Master, meet level + class requirements,
  and receive a Class Transfer Certificate (2nd).
  """
  use L2E.Quest.Engine

  def quest_id, do: 406
  def quest_name, do: "Trial of the Dark Path"
  def min_level, do: 40

  # NPC 30041 = Dark Elf Grand Master (Dark Elven Village)
  def npc_ids, do: [30041]
  def npc_kill_ids, do: []

  # Dark Elf 1st-class IDs eligible for 2nd transfer
  @dark_elf_first_classes [31, 32, 39]

  def on_first_talk(30041, player) do
    cond do
      player.class_id not in @dark_elf_first_classes ->
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
         The grand trial demands a seasoned warrior of the shadows. Return when you have reached level #{min_level()}.
         </body></html>
         """}

      true ->
        target = primary_target_class(player.class_id)

        {:ok,
         """
         <html><body>
         Grand Master:<br>
         #{first_class_name(player.class_id)} — you have proven your worth through darkness and blood.
         The path of the #{target_class_name(target)} awaits you.<br>
         <br>
         <a action="bypass Quest 30041 advance">I am ready to receive the title.</a><br>
         <a action="bypass -h npc_30041_return">Not yet.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30041, 0, player) do
    if player.level >= min_level() and player.class_id in @dark_elf_first_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Grand Master:<br>
      Your mastery of the shadows is undeniable. The title of #{target_class_name(target)} is now yours.
      Walk your path without hesitation.
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
    # Dark Elf 2nd Class Transfer Certificate — item_id 1853
    {:ok, [{1853, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Palus Knight → Shillien Knight
  defp primary_target_class(31), do: 60
  # Assassin → Abyss Walker (primary path)
  defp primary_target_class(32), do: 34
  # Shillien Oracle → Shillien Elder
  defp primary_target_class(39), do: 68
  defp primary_target_class(_), do: 60

  defp first_class_name(31), do: "Palus Knight"
  defp first_class_name(32), do: "Assassin"
  defp first_class_name(39), do: "Shillien Oracle"
  defp first_class_name(_), do: "Dark Elf Adventurer"

  defp target_class_name(34), do: "Abyss Walker"
  defp target_class_name(60), do: "Shillien Knight"
  defp target_class_name(68), do: "Shillien Elder"
  defp target_class_name(_), do: "advanced class"
end

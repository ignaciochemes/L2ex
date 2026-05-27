defmodule L2E.Quest.Scripts.Elf1stClass do
  @moduledoc """
  1st class transfer for Elf characters.

  Elf Fighter (class 18) → Elven Knight (22) or Elven Scout (23) at level 20.
  Elf Mystic  (class 19) → Elven Wizard (24) or Oracle (25) at level 20.

  Talk-based quest: speak to the Elven Elder, meet level + class requirements,
  and receive a Class Transfer Certificate (Elf 1st).
  """
  use L2E.Quest.Engine

  def quest_id, do: 403
  def quest_name, do: "The Elven Path Chosen"
  def min_level, do: 20

  # NPC 30100 = Elven Elder (Elven Village)
  def npc_ids, do: [30100]
  def npc_kill_ids, do: []

  # Elf base classes eligible for 1st transfer
  @elf_base_classes [18, 19]

  def on_first_talk(30100, player) do
    cond do
      player.class_id not in @elf_base_classes ->
        {:ok,
         """
         <html><body>
         Elven Elder:<br>
         The light of the forest does not guide you here. This trial is only for
         Elves who have not yet chosen their vocational path.
         </body></html>
         """}

      player.level < min_level() ->
        {:ok,
         """
         <html><body>
         Elven Elder:<br>
         You have not yet matured enough to walk the chosen path.
         Return when you have reached level #{min_level()}.
         </body></html>
         """}

      true ->
        {:ok,
         """
         <html><body>
         Elven Elder:<br>
         The forest has watched you grow, #{base_class_name(player.class_id)}.
         You have reached level #{min_level()} and the time has come to choose your path.<br>
         <br>
         Available paths: #{available_paths(player.class_id)}<br>
         <br>
         <a action="bypass Quest 30100 advance">I choose my path.</a><br>
         <a action="bypass -h npc_30100_return">I need more time.</a>
         </body></html>
         """}
    end
  end

  def on_talk(30100, 0, player) do
    if player.level >= min_level() and player.class_id in @elf_base_classes do
      target = primary_target_class(player.class_id)

      html = """
      <html><body>
      Elven Elder:<br>
      The ancient spirits acknowledge your choice. You are now a #{target_class_name(target)}.
      Walk your path with grace and purpose.
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
    # Elf 1st Class Transfer Certificate — item_id 1852
    {:ok, [{1852, 1}]}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Primary 1st-class target for each Elf base class (standard L2J Interlude IDs)
  # Elf Fighter → Elven Knight
  defp primary_target_class(18), do: 22
  # Elf Mystic → Elven Wizard
  defp primary_target_class(19), do: 24
  defp primary_target_class(_), do: 22

  defp base_class_name(18), do: "Elf Fighter"
  defp base_class_name(19), do: "Elf Mystic"
  defp base_class_name(_), do: "Elf"

  defp available_paths(18), do: "Elven Knight, Elven Scout"
  defp available_paths(19), do: "Elven Wizard, Oracle"
  defp available_paths(_), do: "unknown"

  defp target_class_name(22), do: "Elven Knight"
  defp target_class_name(23), do: "Elven Scout"
  defp target_class_name(24), do: "Elven Wizard"
  defp target_class_name(25), do: "Oracle"
  defp target_class_name(_), do: "advanced class"
end

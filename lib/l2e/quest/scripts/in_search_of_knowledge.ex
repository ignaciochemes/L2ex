defmodule L2E.Quest.Scripts.InSearchOfKnowledge do
  use L2E.Quest.Engine

  def quest_id, do: 255
  def quest_name, do: "In Search of Knowledge"
  def min_level, do: 1

  # NPC 31646 = Newbie Guide (starting village)
  def npc_ids, do: [31646]
  def npc_kill_ids, do: []

  def on_first_talk(31646, player) do
    if Map.get(player, :level, 1) >= min_level() do
      html = """
      <html><body>
      Newbie Guide:<br>
      Welcome to the world of Lineage II, #{player_name(player)}!<br>
      I have some supplies to help you on your journey.<br>
      <a action="bypass Quest 31646 start">Please, give them to me.</a><br>
      <a action="bypass -h npc_#{31646}_return">No, thank you.</a>
      </body></html>
      """

      {:ok, html}
    else
      :skip
    end
  end

  def on_talk(31646, 0, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Here are some Scrolls of Escape to help you travel safely.
    Good luck on your adventure!
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(31646, _cond, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    You have already received your starter supplies. Safe travels!
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 1, count: 0, reward_taken: true}}
  end

  def on_complete(_player, _quest_state) do
    # 5x Scroll of Escape (novice) item_id 10650
    {:ok, [{10650, 5}]}
  end

  defp player_name(%{name: name}), do: name
  defp player_name(_), do: "adventurer"
end

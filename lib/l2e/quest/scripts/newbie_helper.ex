defmodule L2E.Quest.Scripts.NewbieHelper do
  use L2E.Quest.Engine

  def quest_id, do: 259
  def quest_name, do: "Newbie Helper"
  def min_level, do: 1

  # NPC 30602 = Newbie Helper (second race helper)
  def npc_ids, do: [30602]
  def npc_kill_ids, do: []

  def on_first_talk(30602, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Welcome, adventurer! I have some starter supplies for you.<br>
    Take them — they will help you on your journey.<br>
    <a action="bypass Quest 30602 start">Thank you!</a><br>
    <a action="bypass -h npc_#{30602}_return">No, thank you.</a>
    </body></html>
    """

    {:ok, html}
  end

  def on_talk(30602, 0, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Here are your starter supplies. Use them wisely, adventurer!
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(30602, _cond, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    You have already received your starter supplies. Good luck out there!
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 1, count: 0, reward_taken: true}}
  end

  def on_complete(_player, _quest_state) do
    # 50x Spiritshot (novice) item_id 5790
    {:ok, [{5790, 50}]}
  end
end

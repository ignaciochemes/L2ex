defmodule L2E.Quest.Scripts.LeafOnTheWater do
  use L2E.Quest.Engine

  def quest_id, do: 257
  def quest_name, do: "Leaf on the Water"
  def min_level, do: 1

  # NPC 31646 = Newbie Guide
  def npc_ids, do: [31646]
  def npc_kill_ids, do: []

  def on_first_talk(31646, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Adventurer, I need you to carry a special herb to test your reliability.
    Take it and bring it back to me to prove you are trustworthy.<br>
    <a action="bypass Quest 31646 start">I'll do it.</a><br>
    <a action="bypass -h npc_#{31646}_return">Not now.</a>
    </body></html>
    """

    {:ok, html}
  end

  def on_talk(31646, 0, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Take this herb and carry it carefully.
    Return to me once you have it in hand.
    </body></html>
    """

    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(31646, 1, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Excellent! You returned the herb safely. You are trustworthy indeed.
    Here is your reward.<br>
    <a action="bypass Quest 31646 reward">Claim reward</a>
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 2, count: 0, reward_taken: false}}
  end

  def on_complete(_player, _quest_state) do
    # Ring of Knowledge — item_id 49
    {:ok, [{49, 1}]}
  end
end

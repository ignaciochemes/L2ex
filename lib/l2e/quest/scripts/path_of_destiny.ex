defmodule L2E.Quest.Scripts.PathOfDestiny do
  use L2E.Quest.Engine

  def quest_id, do: 256
  def quest_name, do: "Path of Destiny"
  def min_level, do: 1

  # NPC 30601 = Newbie Helper
  def npc_ids, do: [30601]

  # Common low-level starting-area monsters (approximate level 1-10)
  def npc_kill_ids, do: [20001, 20002, 20003, 20004, 20005, 20006, 20007, 20008, 20009, 20010]

  @required_kills 10

  def on_first_talk(30601, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Adventurer, to prove your worth you must defeat some of the young monsters
    lurking nearby. Hunt #{@required_kills} of them and return to me.<br>
    <a action="bypass Quest 30601 start">I accept the challenge.</a><br>
    <a action="bypass -h npc_#{30601}_return">Not now.</a>
    </body></html>
    """

    {:ok, html}
  end

  def on_talk(30601, 0, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Your challenge has begun! Hunt #{@required_kills} young monsters
    and return to me when you are done.
    </body></html>
    """

    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(30601, 1, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Keep going! You have not yet defeated #{@required_kills} monsters. Come back when done.
    </body></html>
    """

    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(30601, 2, _player) do
    html = """
    <html><body>
    Newbie Helper:<br>
    Well done! You have proven your strength, adventurer. Accept this reward.<br>
    <a action="bypass Quest 30601 reward">Claim reward</a>
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 2, count: 0, reward_taken: false}}
  end

  def on_kill(_npc_id, _player, quest_state) do
    if quest_state.state == 1 and quest_state.cond == 1 do
      new_count = quest_state.count + 1

      if new_count >= @required_kills do
        {:ok, %{quest_state | count: new_count, cond: 2}}
      else
        {:ok, %{quest_state | count: new_count}}
      end
    else
      :skip
    end
  end

  def on_complete(_player, _quest_state) do
    # Dye of STR +1 item_id 4537
    {:ok, [{4537, 1}]}
  end
end

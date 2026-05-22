defmodule L2E.Quest.Scripts.ExplorationOfGiantsCave do
  use L2E.Quest.Engine

  def quest_id, do: 213
  def quest_name, do: "Exploration of Giants Cave"
  def min_level, do: 36

  # NPC 30516 = Researcher Lorain at Giants Cave entrance
  def npc_ids, do: [30516]
  def npc_kill_ids, do: [20678]

  @required_kills 10

  def on_first_talk(30516, player) do
    if player.level >= min_level() do
      html = """
      <html><body>
      Researcher Lorain:<br>
      The Giants Cave holds many secrets — and dangers. I need someone to survey
      the area and defeat the Cave Servants that guard the entrance.<br>
      Will you help me?<br>
      <a action="bypass Quest 30516 start">I'll do it.</a><br>
      <a action="bypass -h npc_#{30516}_return">Not now.</a>
      </body></html>
      """
      {:ok, html}
    else
      html = """
      <html><body>
      Researcher Lorain:<br>
      You need to be at least level #{min_level()} to help me. Come back when you're stronger.
      </body></html>
      """
      {:ok, html}
    end
  end

  def on_talk(30516, 0, _player) do
    html = """
    <html><body>
    Researcher Lorain:<br>
    Please defeat #{@required_kills} Cave Servants (NPC #20678) near the cave entrance
    and return to me. You've defeated: 0 / #{@required_kills}.<br>
    <a action="bypass -h npc_#{30516}_return">Understood.</a>
    </body></html>
    """
    new_state = %{state: 1, cond: 1, count: 0, reward_taken: false}
    {:ok, html, new_state}
  end

  def on_talk(30516, 1, _player) do
    html = """
    <html><body>
    Researcher Lorain:<br>
    Keep going! Defeat #{@required_kills} Cave Servants to complete the survey.<br>
    <a action="bypass -h npc_#{30516}_return">I'll continue.</a>
    </body></html>
    """
    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(30516, 2, _player) do
    html = """
    <html><body>
    Researcher Lorain:<br>
    Excellent work! You've completed the survey. Here is your reward.<br>
    <a action="bypass Quest 30516 reward">Claim reward</a>
    </body></html>
    """
    {:ok, html, %{state: 2, cond: 2, count: 0, reward_taken: false}}
  end

  def on_kill(20678, _player, quest_state) do
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
    # 50000 adena + 1 Scroll: Enchant Weapon Grade D (item_id 735)
    {:ok, [{57, 50_000}, {735, 1}]}
  end
end

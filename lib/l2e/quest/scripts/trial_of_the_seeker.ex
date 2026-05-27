defmodule L2E.Quest.Scripts.TrialOfTheSeeker do
  use L2E.Quest.Engine

  def quest_id, do: 258
  def quest_name, do: "Trial of the Seeker"
  def min_level, do: 5

  # NPC 31646 = Newbie Guide
  def npc_ids, do: [31646]
  # NPC 20001 = Imp (common low-level mob)
  def npc_kill_ids, do: [20001]

  @required_kills 5

  def on_first_talk(31646, player) do
    if Map.get(player, :level, 1) >= min_level() do
      html = """
      <html><body>
      Newbie Guide:<br>
      You have grown in strength, #{player_name(player)}. Now it is time for a true trial.<br>
      Defeat #{@required_kills} Imps lurking nearby and prove your courage.<br>
      <a action="bypass Quest 31646 start">I am ready.</a><br>
      <a action="bypass -h npc_#{31646}_return">Not yet.</a>
      </body></html>
      """

      {:ok, html}
    else
      html = """
      <html><body>
      Newbie Guide:<br>
      You are not yet ready for this trial.
      Return when you have reached level #{min_level()}.
      </body></html>
      """

      {:ok, html}
    end
  end

  def on_talk(31646, 0, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Your trial has begun! Defeat #{@required_kills} Imps (NPC #20001) and return to me.
    </body></html>
    """

    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(31646, 1, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    Keep fighting! Defeat #{@required_kills} Imps to complete your trial.
    </body></html>
    """

    {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
  end

  def on_talk(31646, 2, _player) do
    html = """
    <html><body>
    Newbie Guide:<br>
    You have completed your trial! You are a true seeker. Here is your reward.<br>
    <a action="bypass Quest 31646 reward">Claim reward</a>
    </body></html>
    """

    {:ok, html, %{state: 2, cond: 2, count: 0, reward_taken: false}}
  end

  def on_kill(20001, _player, quest_state) do
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
    # 5000 Adena (item_id 57) as reward proxy for EXP/SP
    {:ok, [{57, 5000}]}
  end

  defp player_name(%{name: name}), do: name
  defp player_name(_), do: "adventurer"
end

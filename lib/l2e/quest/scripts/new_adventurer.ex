defmodule L2E.Quest.Scripts.NewAdventurer do
  use L2E.Quest.Engine

  # Quest ID 255 = "Path of the New Adventurer" (L2 Interlude)
  def quest_id, do: 255
  def quest_name, do: "Path of the New Adventurer"
  def min_level, do: 1

  # NPC 30008 = Newbie Guide (Human Town of Gludin Harbour / Talking Island)
  def npc_ids, do: [30008]
  def npc_kill_ids, do: []

  def on_first_talk(30008, player) do
    if player.level >= min_level() do
      html = """
      <html><body>
      Newbie Guide:<br>
      Welcome, #{player_name(player)}! I can help you on your path.<br>
      Are you ready to begin your adventure?<br>
      <a action="bypass Quest 30008 start">Yes, I am ready!</a><br>
      <a action="bypass -h npc_#{30008}_return">No, not yet.</a>
      </body></html>
      """

      {:ok, html}
    else
      :skip
    end
  end

  def on_talk(30008, 0, _player) do
    # cond 0: quest just accepted, tell player to come back at level 5
    html = """
    <html><body>
    Newbie Guide:<br>
    You've started on your path! Come back when you reach level 5
    and I will reward your efforts.<br>
    <a action="bypass -h npc_#{30008}_return">Understood.</a>
    </body></html>
    """

    new_state = %{state: 1, cond: 1, count: 0, reward_taken: false}
    {:ok, html, new_state}
  end

  def on_talk(30008, 1, player) do
    if player.level >= 5 do
      html = """
      <html><body>
      Newbie Guide:<br>
      You have reached level 5 — congratulations, adventurer!<br>
      Here is your reward: a basic weapon and supplies.<br>
      <a action="bypass Quest 30008 reward">Claim reward</a>
      </body></html>
      """

      new_state = %{state: 2, cond: 2, count: 0, reward_taken: false}
      {:ok, html, new_state}
    else
      html = """
      <html><body>
      Newbie Guide:<br>
      You are not yet level 5. Keep fighting and come back when you're stronger!<br>
      <a action="bypass -h npc_#{30008}_return">I'll be back.</a>
      </body></html>
      """

      {:ok, html, %{state: 1, cond: 1, count: 0, reward_taken: false}}
    end
  end

  def on_complete(_player, _quest_state) do
    # Rewards: 3000 adena (item_id 57) + Scroll of Escape x5 (item_id 1061)
    {:ok, [{57, 3000}, {1061, 5}]}
  end

  defp player_name(%{char_id: _}), do: "adventurer"
end

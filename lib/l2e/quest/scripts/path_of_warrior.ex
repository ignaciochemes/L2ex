defmodule L2E.Quest.Scripts.PathOfWarrior do
  use L2E.Quest.Engine

  def quest_id, do: 211
  def quest_name, do: "Path of the Warrior"
  def min_level, do: 19

  # NPC 30017 = Master Auron (Warrior guild)
  def npc_ids, do: [30017]
  def npc_kill_ids, do: []

  @required_class_id 0

  def on_first_talk(30017, player) do
    cond do
      player.level < min_level() ->
        html = """
        <html><body>
        Master Auron:<br>
        You are not yet ready to walk the path of a Warrior.
        Return when you have reached level #{min_level()}.
        </body></html>
        """
        {:ok, html}

      player.class_id != @required_class_id ->
        html = """
        <html><body>
        Master Auron:<br>
        The path of the Warrior is not for you. Only Human Fighters may seek this advancement.
        </body></html>
        """
        {:ok, html}

      true ->
        html = """
        <html><body>
        Master Auron:<br>
        So you seek the path of the Warrior? A worthy goal for a Human Fighter of level #{min_level()} or above.<br>
        Prove your dedication and I will advance your class.<br>
        <a action="bypass Quest 30017 advance">I am ready to advance.</a><br>
        <a action="bypass -h npc_#{30017}_return">Not yet.</a>
        </body></html>
        """
        {:ok, html}
    end
  end

  def on_talk(30017, 0, player) do
    if player.level >= min_level() and player.class_id == @required_class_id do
      html = """
      <html><body>
      Master Auron:<br>
      You have proven yourself worthy. The title of Warrior is yours.<br>
      Speak to me again to receive your advancement.
      </body></html>
      """
      new_state = %{state: 2, cond: 1, count: 0, reward_taken: false}
      {:ok, html, new_state}
    else
      :skip
    end
  end

  def on_complete(_player, _quest_state) do
    # Mark of Warrior (class change proof) — item_id 1665
    {:ok, [{1665, 1}]}
  end
end

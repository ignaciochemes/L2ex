defmodule L2E.Quest.Handler do
  @moduledoc """
  Routes game events to active quest scripts.

  Called from PlayerSession on:
    - NPC kill → dispatch_kill/3
    - NPC bypass (talk) → dispatch_talk/4
  """
  alias L2E.Quest.Registry, as: QReg

  @doc "Called when a player kills an NPC. Returns updated quests map."
  def dispatch_kill(npc_template_id, player_info, quests) do
    QReg.modules_for_kill(npc_template_id)
    |> Enum.reduce(quests, fn {quest_id, mod}, acc_quests ->
      quest_state =
        Map.get(acc_quests, quest_id, %{state: 0, cond: 0, count: 0, reward_taken: false})

      case mod.on_kill(npc_template_id, player_info, quest_state) do
        {:ok, new_state} -> Map.put(acc_quests, quest_id, new_state)
        :skip -> acc_quests
      end
    end)
  end

  @doc "Called when a player talks to an NPC. Returns {html | nil, updated_quests}."
  def dispatch_talk(npc_id, npc_template_id, player_info, quests) do
    case QReg.modules_for_npc(npc_template_id) do
      [] ->
        {nil, quests}

      [{quest_id, mod} | _] ->
        quest_state =
          Map.get(quests, quest_id, %{state: 0, cond: 0, count: 0, reward_taken: false})

        cond_val = Map.get(quest_state, :cond, 0)
        is_new = Map.get(quest_state, :state, 0) == 0

        if is_new do
          case mod.on_first_talk(npc_id, player_info) do
            {:ok, html} -> {html, quests}
            :skip -> {nil, quests}
          end
        else
          case mod.on_talk(npc_id, cond_val, player_info) do
            {:ok, html, new_state} -> {html, Map.put(quests, quest_id, new_state)}
            :skip -> {nil, quests}
          end
        end
    end
  end
end

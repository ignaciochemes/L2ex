defmodule L2E.Clan do
  @moduledoc """
  M22: Clan (Pledge) GenServer.

  Owns clan state: id, name, leader, members, pending invitations.

  ## Design

  - Clans are started by the ClanTable when a player creates one
  - Invitations time out after 30 s
  - Member list broadcast to joining member on join
  - Leave / oust remove the member and notify others

  ## Message API (cast)

    {:invite, target_id, target_pid}
      — leader invites target; target gets AskJoinPledge packet

    {:answer_invite, answerer_id, answerer_pid, accept :: boolean()}
      — target answers the pending invite

    {:leave, char_id}
      — member leaves voluntarily or is kicked

    {:kick, target_name}
      — leader kicks a named member
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.Packet.Server

  @invite_timeout_ms 30_000

  @type member :: %{
          char_id: pos_integer(),
          char_name: String.t(),
          pid: pid() | nil,
          level: non_neg_integer(),
          class_id: non_neg_integer()
        }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns the clan pid for a given char_id (clan member), or nil."
  @spec find_by_member(pos_integer()) :: pid() | nil
  def find_by_member(char_id) do
    case Registry.lookup(L2E.Session.Registry, {:clan_member, char_id}) do
      [{clan_pid, _}] -> clan_pid
      [] -> nil
    end
  end

  @doc "Returns the clan pid by clan_id, or nil."
  @spec find_by_id(pos_integer()) :: pid() | nil
  def find_by_id(clan_id) do
    case Registry.lookup(L2E.Session.Registry, {:clan, clan_id}) do
      [{clan_pid, _}] -> clan_pid
      [] -> nil
    end
  end

  def invite(clan_pid, target_id, target_pid) do
    GenServer.cast(clan_pid, {:invite, target_id, target_pid})
  end

  def answer_invite(clan_pid, answerer_id, answerer_pid, accept) do
    GenServer.cast(clan_pid, {:answer_invite, answerer_id, answerer_pid, accept})
  end

  def leave(clan_pid, char_id) do
    GenServer.cast(clan_pid, {:leave, char_id})
  end

  def kick(clan_pid, target_name) do
    GenServer.cast(clan_pid, {:kick, target_name})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(opts) do
    clan_id = Keyword.fetch!(opts, :clan_id)
    clan_name = Keyword.fetch!(opts, :clan_name)
    leader_id = Keyword.fetch!(opts, :leader_id)
    leader_pid = Keyword.fetch!(opts, :leader_pid)

    Registry.register(L2E.Session.Registry, {:clan, clan_id}, self())

    state = %{
      clan_id: clan_id,
      clan_name: clan_name,
      leader_id: leader_id,
      # %{char_id => member()}
      members: %{},
      # %{char_id => {pid, timer_ref}}
      pending_invites: %{}
    }

    state = add_member(state, leader_id, leader_pid)

    Logger.info("[Clan] '#{clan_name}' (id=#{clan_id}) created by leader=#{leader_id}")
    {:ok, state}
  end

  # ── Invite ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_cast({:invite, target_id, target_pid}, state) do
    cond do
      Map.has_key?(state.members, target_id) ->
        {:noreply, state}

      Map.has_key?(state.pending_invites, target_id) ->
        {:noreply, state}

      true ->
        pkt = %Server.AskJoinPledge{
          requestor_id: state.leader_id,
          clan_name: state.clan_name
        }

        send(target_pid, {:send_packet, pkt})

        timer = Process.send_after(self(), {:invite_timeout, target_id}, @invite_timeout_ms)
        new_state = put_in(state.pending_invites[target_id], {target_pid, timer})
        {:noreply, new_state}
    end
  end

  # ── Answer invite ─────────────────────────────────────────────────────────────

  def handle_cast({:answer_invite, answerer_id, answerer_pid, accept}, state) do
    case Map.pop(state.pending_invites, answerer_id) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, timer}, new_invites} ->
        Process.cancel_timer(timer)
        state = %{state | pending_invites: new_invites}

        if accept do
          new_state = add_member(state, answerer_id, answerer_pid)
          broadcast_member_joined(new_state, answerer_id)
          {:noreply, new_state}
        else
          leader_pid = get_pid(state, state.leader_id)
          if leader_pid, do: send(leader_pid, {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_rejected()}})
          {:noreply, state}
        end
    end
  end

  # ── Leave / kick ──────────────────────────────────────────────────────────────

  def handle_cast({:leave, char_id}, state) do
    case do_remove_member(state, char_id) do
      {:disband, new_state} -> {:stop, :normal, new_state}
      {:ok, new_state} -> {:noreply, new_state}
    end
  end

  def handle_cast({:kick, target_name}, state) do
    case Enum.find(state.members, fn {_, m} -> m.char_name == target_name end) do
      nil ->
        {:noreply, state}

      {char_id, _} ->
        case do_remove_member(state, char_id) do
          {:disband, new_state} -> {:stop, :normal, new_state}
          {:ok, new_state} -> {:noreply, new_state}
        end
    end
  end

  # ── Clan chat broadcast ──────────────────────────────────────────────────────

  def handle_cast({:clan_chat, sender_id, packet}, state) do
    broadcast_to_others(state, sender_id, {:send_packet, packet})
    {:noreply, state}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # ── Invite timeout ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:invite_timeout, target_id}, state) do
    new_state = %{state | pending_invites: Map.delete(state.pending_invites, target_id)}
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Enum.find(state.members, fn {_, m} -> m.pid == pid end) do
      nil ->
        {:noreply, state}

      {char_id, _} ->
        case do_remove_member(state, char_id) do
          {:disband, new_state} -> {:stop, :normal, new_state}
          {:ok, new_state} -> {:noreply, new_state}
        end
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp add_member(state, char_id, pid) do
    if pid, do: Process.monitor(pid)
    register_member(char_id, self())

    member = %{char_id: char_id, char_name: char_name_for(pid), pid: pid, level: 1, class_id: 0}
    new_members = Map.put(state.members, char_id, member)
    new_state = %{state | members: new_members}

    # Send member list to joining member
    if pid do
      members_list = Enum.map(new_members, fn {id, m} -> %{char_name: m.char_name, level: m.level, class_id: m.class_id, object_id: id} end)
      send(pid, {:send_packet, %Server.PledgeShowMemberListAll{clan_id: state.clan_id, members: members_list}})
      send(pid, {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_joined_clan()}})
    end

    new_state
  end

  defp do_remove_member(state, char_id) do
    case Map.pop(state.members, char_id) do
      {nil, _} ->
        {:ok, state}

      {member, remaining} ->
        unregister_member(char_id)

        if member.pid do
          send(member.pid, :party_disbanded)
          send(member.pid, {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_left_clan()}})
        end

        delete_pkt = %Server.PledgeShowMemberListDelete{char_name: member.char_name}
        new_state = %{state | members: remaining}
        broadcast_to_all(new_state, {:send_packet, delete_pkt})

        # Disband if empty
        if map_size(remaining) == 0 do
          Logger.info("[Clan] '#{state.clan_name}' disbanded")
          Registry.unregister(L2E.Session.Registry, {:clan, state.clan_id})
          {:disband, new_state}
        else
          # New leader if old one left
          final_state =
            if char_id == state.leader_id do
              {new_leader_id, _} = Enum.at(remaining, 0)
              %{new_state | leader_id: new_leader_id}
            else
              new_state
            end

          {:ok, final_state}
        end
    end
  end

  defp broadcast_member_joined(state, new_char_id) do
    case Map.get(state.members, new_char_id) do
      nil -> :ok
      member ->
        pkt = %Server.PledgeShowMemberListAdd{
          char_name: member.char_name,
          level: member.level,
          class_id: member.class_id,
          object_id: new_char_id
        }

        broadcast_to_others(state, new_char_id, {:send_packet, pkt})
    end
  end

  defp broadcast_to_all(state, msg) do
    Enum.each(state.members, fn {_, m} -> if m.pid, do: send(m.pid, msg) end)
  end

  defp broadcast_to_others(state, exclude_id, msg) do
    Enum.each(state.members, fn {id, m} ->
      if id != exclude_id and m.pid, do: send(m.pid, msg)
    end)
  end

  defp get_pid(state, char_id) do
    case Map.get(state.members, char_id) do
      nil -> nil
      m -> m.pid
    end
  end

  defp char_name_for(nil), do: ""

  defp char_name_for(pid) do
    case GenServer.call(pid, :get_party_info, 1000) do
      {:ok, %{char_name: name}} -> name
      _ -> ""
    end
  rescue
    _ -> ""
  end

  defp register_member(char_id, clan_pid) do
    try do
      Registry.register(L2E.Session.Registry, {:clan_member, char_id}, clan_pid)
    catch
      :error, _ -> :ok
    end
  end

  defp unregister_member(char_id) do
    Registry.unregister(L2E.Session.Registry, {:clan_member, char_id})
  end
end

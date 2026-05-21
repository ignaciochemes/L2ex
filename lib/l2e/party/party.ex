defmodule L2E.Party do
  @moduledoc """
  M21: Party GenServer.

  Owns party state: leader, members, distribution type, pending invitations.

  ## Design

  - Max 9 members (Interlude rule)
  - Leader leaves → next member becomes leader; party disbands when 1 member remains
  - Invitations time out after 30 s if not answered
  - Member vitals broadcast to party window via PartySmallWindowUpdate
  - EXP/SP sharing: when a member kills something, all party members near the kill
    receive a share. (Simplified: equal share for now; distance-based share in future.)

  ## Message API (cast)

    {:invite, target_char_id, target_pid, invitor_name}
      — invitor sends invite to target; target gets AskJoinParty packet

    {:answer_invite, answerer_char_id, answerer_pid, accept :: boolean()}
      — target's answer to the pending invite

    {:leave, char_id}
      — member leaves voluntarily or is kicked

    {:kick, target_name}
      — leader kicks a named member

    {:vital_update, char_id, hp, mp}
      — member session reports vitals change; broadcast to party window
  """

  use GenServer, restart: :temporary
  require Logger

  alias L2E.Packet.Server

  @max_members 9
  @invite_timeout_ms 30_000

  @type member :: %{
          char_id: pos_integer(),
          char_name: String.t(),
          pid: pid(),
          hp: float(),
          max_hp: float(),
          mp: float(),
          max_mp: float(),
          level: non_neg_integer(),
          class_id: non_neg_integer()
        }

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns the party pid for a given char_id, or nil."
  @spec find(pos_integer()) :: pid() | nil
  def find(char_id) do
    case Registry.lookup(L2E.Session.Registry, {:party_member, char_id}) do
      [{party_pid, _}] -> party_pid
      [] -> nil
    end
  end

  @doc "Invite char to a party (creates party if leader has none)."
  def invite(party_pid, target_char_id, target_pid, invitor_name) do
    GenServer.cast(party_pid, {:invite, target_char_id, target_pid, invitor_name})
  end

  @doc "Target answers the invite."
  def answer_invite(party_pid, answerer_char_id, answerer_pid, accept) do
    GenServer.cast(party_pid, {:answer_invite, answerer_char_id, answerer_pid, accept})
  end

  @doc "Member leaves or is kicked."
  def leave(party_pid, char_id) do
    GenServer.cast(party_pid, {:leave, char_id})
  end

  @doc "Leader kicks a member by name."
  def kick(party_pid, target_name) do
    GenServer.cast(party_pid, {:kick, target_name})
  end

  @doc "Member reports vitals update to party window."
  def vital_update(party_pid, char_id, hp, mp) do
    GenServer.cast(party_pid, {:vital_update, char_id, hp, mp})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(opts) do
    leader_id = Keyword.fetch!(opts, :leader_id)
    leader_pid = Keyword.fetch!(opts, :leader_pid)
    dist = Keyword.get(opts, :distribution_type, 1)

    # Register the party by leader's char_id so it can be found
    Registry.register(L2E.Session.Registry, {:party, leader_id}, self())

    # Register leader as member
    register_member(leader_id)

    state = %{
      leader_id: leader_id,
      distribution_type: dist,
      # %{char_id => member()}
      members: %{},
      # %{char_id => {pid, timer_ref}}
      pending_invites: %{}
    }

    state = add_member(state, leader_id, leader_pid)

    Logger.info("[Party] Created by leader=#{leader_id}")
    {:ok, state}
  end

  # ── Invite ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_cast({:invite, target_id, target_pid, invitor_name}, state) do
    cond do
      map_size(state.members) >= @max_members ->
        {:noreply, state}

      Map.has_key?(state.members, target_id) ->
        {:noreply, state}

      Map.has_key?(state.pending_invites, target_id) ->
        {:noreply, state}

      true ->
        pkt = %Server.AskJoinParty{
          requestor_name: invitor_name,
          distribution_type: state.distribution_type
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
          # Send rejection system message to leader
          leader_pid = get_pid(state, state.leader_id)

          if leader_pid do
            send(
              leader_pid,
              {:send_packet,
               %Server.SystemMessage{message_id: Server.SystemMessage.msg_rejected()}}
            )
          end

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

  # ── Vitals update ────────────────────────────────────────────────────────────

  def handle_cast({:vital_update, char_id, hp, mp}, state) do
    case Map.get(state.members, char_id) do
      nil ->
        {:noreply, state}

      member ->
        updated = %{member | hp: hp, mp: mp}
        new_state = put_in(state.members[char_id], updated)

        update_pkt = %Server.PartySmallWindowUpdate{
          object_id: char_id,
          hp: hp,
          max_hp: member.max_hp,
          mp: mp,
          max_mp: member.max_mp
        }

        broadcast_to_others(new_state, char_id, {:send_packet, update_pkt})
        {:noreply, new_state}
    end
  end

  # ── Party chat broadcast ──────────────────────────────────────────────────────

  def handle_cast({:party_chat, sender_id, packet}, state) do
    broadcast_to_others(state, sender_id, {:send_packet, packet})
    {:noreply, state}
  end

  # Catch-all for unrecognized casts
  def handle_cast(_msg, state), do: {:noreply, state}

  # ── Invite timeout ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:invite_timeout, target_id}, state) do
    new_state = %{state | pending_invites: Map.delete(state.pending_invites, target_id)}
    {:noreply, new_state}
  end

  # Member process died
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
    Process.monitor(pid)
    register_member(char_id)

    # Attempt to get session stats
    member_info = fetch_member_info(char_id, pid)

    new_members = Map.put(state.members, char_id, member_info)
    new_state = %{state | members: new_members}

    # Send party window to new member
    members_list = build_member_list(new_state)

    send(
      pid,
      {:send_packet,
       %Server.PartySmallWindowAll{
         distribution_type: state.distribution_type,
         members: members_list
       }}
    )

    # Ack join
    send(
      pid,
      {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_joined_party()}}
    )

    new_state
  end

  defp do_remove_member(state, char_id) do
    case Map.pop(state.members, char_id) do
      {nil, _} ->
        {:ok, state}

      {member, remaining} ->
        unregister_member(char_id)

        # Notify removed member
        send(member.pid, :party_disbanded)

        send(
          member.pid,
          {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_left_party()}}
        )

        # Notify others
        delete_pkt = %Server.PartySmallWindowDelete{
          object_id: char_id,
          char_name: member.char_name
        }

        new_state = %{state | members: remaining}
        broadcast_to_all(new_state, {:send_packet, delete_pkt})

        # Disband if only 1 member left
        if map_size(remaining) <= 1 do
          Enum.each(remaining, fn {id, m} ->
            unregister_member(id)
            send(m.pid, :party_disbanded)

            send(
              m.pid,
              {:send_packet,
               %Server.SystemMessage{message_id: Server.SystemMessage.msg_left_party()}}
            )
          end)

          Logger.info("[Party] Disbanded (too few members)")
          {:disband, %{state | members: %{}}}
        else
          # Elect new leader if old leader left
          final_state =
            if char_id == state.leader_id do
              {new_leader_id, _} = Enum.at(remaining, 0)
              Logger.info("[Party] New leader: #{new_leader_id}")
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
      nil ->
        :ok

      member ->
        pkt = %Server.PartySmallWindowAdd{
          distribution_type: state.distribution_type,
          member: member_to_map(new_char_id, member, state.leader_id)
        }

        broadcast_to_others(state, new_char_id, {:send_packet, pkt})
    end
  end

  defp broadcast_to_all(state, msg) do
    Enum.each(state.members, fn {_, m} -> send(m.pid, msg) end)
  end

  defp broadcast_to_others(state, exclude_id, msg) do
    Enum.each(state.members, fn {id, m} ->
      if id != exclude_id, do: send(m.pid, msg)
    end)
  end

  defp build_member_list(state) do
    Enum.map(state.members, fn {id, m} -> member_to_map(id, m, state.leader_id) end)
  end

  defp member_to_map(char_id, member, leader_id) do
    %{
      char_name: member.char_name,
      object_id: char_id,
      hp: member.hp,
      max_hp: member.max_hp,
      mp: member.mp,
      max_mp: member.max_mp,
      level: member.level,
      class_id: member.class_id,
      is_leader: char_id == leader_id
    }
  end

  defp get_pid(state, char_id) do
    case Map.get(state.members, char_id) do
      nil -> nil
      m -> m.pid
    end
  end

  defp register_member(char_id) do
    try do
      Registry.register(L2E.Session.Registry, {:party_member, char_id}, self())
    catch
      :error, _ -> :ok
    end
  end

  defp unregister_member(char_id) do
    Registry.unregister(L2E.Session.Registry, {:party_member, char_id})
  end

  defp fetch_member_info(char_id, pid) do
    base = %{
      char_id: char_id,
      char_name: "",
      pid: pid,
      hp: 0.0,
      max_hp: 0.0,
      mp: 0.0,
      max_mp: 0.0,
      level: 1,
      class_id: 0
    }

    case GenServer.call(pid, :get_party_info, 1000) do
      {:ok, info} -> Map.merge(base, info)
      _ -> base
    end
  rescue
    _ ->
      %{
        char_id: char_id,
        char_name: "",
        pid: pid,
        hp: 0.0,
        max_hp: 0.0,
        mp: 0.0,
        max_mp: 0.0,
        level: 1,
        class_id: 0
      }
  end
end

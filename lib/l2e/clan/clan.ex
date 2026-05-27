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

  import Ecto.Query, only: [from: 2]

  alias L2E.Packet.Server
  alias L2E.Repo

  @invite_timeout_ms 30_000

  @level_thresholds %{
    1 => 0,
    2 => 20,
    3 => 100,
    4 => 350,
    5 => 1_000,
    6 => 2_500,
    7 => 5_000,
    8 => 10_000
  }

  @max_members_by_level %{
    1 => 10,
    2 => 20,
    3 => 30,
    4 => 40,
    5 => 50,
    6 => 60,
    7 => 80,
    8 => 90
  }

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

  def add_reputation(clan_pid, amount), do: GenServer.cast(clan_pid, {:add_reputation, amount})
  def set_reputation(clan_pid, amount), do: GenServer.cast(clan_pid, {:set_reputation, amount})
  def get_info(clan_pid), do: GenServer.call(clan_pid, :get_info)
  def max_members(clan_pid), do: GenServer.call(clan_pid, :max_members)

  def add_clan_skill(clan_pid, skill_id, skill_level),
    do: GenServer.cast(clan_pid, {:add_clan_skill, skill_id, skill_level})

  def get_skills(clan_pid), do: GenServer.call(clan_pid, :get_skills)

  # ── Clan war public API ───────────────────────────────────────────────────────

  @doc "Declare war on a target clan. Returns :ok | {:error, :already_at_war} | {:error, :clan_level_too_low}"
  def declare_war(clan_pid, target_clan_id),
    do: GenServer.call(clan_pid, {:declare_war, target_clan_id})

  @doc "Defender accepts a war declaration made by attacker_clan_id."
  def accept_war(clan_pid, attacker_clan_id),
    do: GenServer.call(clan_pid, {:accept_war, attacker_clan_id})

  @doc "Surrender to the given clan, ending the war."
  def surrender(clan_pid, to_clan_id),
    do: GenServer.call(clan_pid, {:surrender, to_clan_id})

  @doc "Record a war kill. killer_is_us=true means this clan's member killed an enemy."
  def add_war_kill(clan_pid, enemy_clan_id, killer_is_us),
    do: GenServer.cast(clan_pid, {:add_war_kill, enemy_clan_id, killer_is_us})

  @doc "Returns the wars map for this clan."
  def get_wars(clan_pid), do: GenServer.call(clan_pid, :get_wars)

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

    {db_level, db_reputation, db_castle_id, db_clan_hall_id} =
      try do
        case Repo.get(L2E.DB.Clan, clan_id) do
          %L2E.DB.Clan{} = record ->
            {record.level || 1, record.reputation_points || 0, record.castle_id || 0,
             record.clan_hall_id || 0}

          nil ->
            {1, 0, 0, 0}
        end
      rescue
        _ -> {1, 0, 0, 0}
      end

    db_skills =
      try do
        Repo.all(from(cs in L2E.DB.ClanSkill, where: cs.clan_id == ^clan_id))
        |> Enum.reduce(%{}, fn cs, acc -> Map.put(acc, cs.skill_id, cs.skill_level) end)
      rescue
        _ -> %{}
      end

    db_wars =
      try do
        attacker_wars =
          Repo.all(
            from(w in L2E.DB.ClanWar,
              where: w.attacker_clan_id == ^clan_id and w.state != "ended"
            )
          )

        defender_wars =
          Repo.all(
            from(w in L2E.DB.ClanWar,
              where: w.defender_clan_id == ^clan_id and w.state != "ended"
            )
          )

        wars_as_attacker =
          Enum.reduce(attacker_wars, %{}, fn w, acc ->
            Map.put(acc, w.defender_clan_id, %{
              state: String.to_atom(w.state),
              attacker_kills: w.attacker_kills,
              defender_kills: w.defender_kills
            })
          end)

        Enum.reduce(defender_wars, wars_as_attacker, fn w, acc ->
          Map.put_new(acc, w.attacker_clan_id, %{
            state: String.to_atom(w.state),
            attacker_kills: w.defender_kills,
            defender_kills: w.attacker_kills
          })
        end)
      rescue
        _ -> %{}
      end

    db_enemies =
      db_wars
      |> Enum.filter(fn {_, w} -> w.state == :mutual end)
      |> Enum.map(fn {id, _} -> id end)

    state = %{
      clan_id: clan_id,
      clan_name: clan_name,
      leader_id: leader_id,
      level: db_level,
      reputation_points: db_reputation,
      castle_id: db_castle_id,
      clan_hall_id: db_clan_hall_id,
      skills: db_skills,
      # %{other_clan_id => %{state: :declared|:mutual, attacker_kills: int, defender_kills: int}}
      wars: db_wars,
      # list of clan_ids in :mutual war with us
      enemies: db_enemies,
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

          if leader_pid,
            do:
              send(
                leader_pid,
                {:send_packet,
                 %Server.SystemMessage{message_id: Server.SystemMessage.msg_rejected()}}
              )

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

  def handle_cast({:add_reputation, amount}, state) when is_integer(amount) do
    new_rep = max(0, state.reputation_points + amount)
    new_state = %{state | reputation_points: new_rep}
    new_state = check_level_up(new_state)

    Task.start(fn ->
      case Repo.get(L2E.DB.Clan, state.clan_id) do
        nil ->
          :ok

        record ->
          record
          |> Ecto.Changeset.change(%{
            reputation_points: new_state.reputation_points,
            level: new_state.level
          })
          |> Repo.update()
      end
    end)

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "clan:#{state.clan_id}",
      {:clan_updated, new_state.level, new_state.reputation_points}
    )

    {:noreply, new_state}
  end

  def handle_cast({:set_reputation, amount}, state) when is_integer(amount) and amount >= 0 do
    new_state = %{state | reputation_points: amount}
    new_state = check_level_up(new_state)

    Task.start(fn ->
      case Repo.get(L2E.DB.Clan, state.clan_id) do
        nil ->
          :ok

        record ->
          record
          |> Ecto.Changeset.change(%{
            reputation_points: new_state.reputation_points,
            level: new_state.level
          })
          |> Repo.update()
      end
    end)

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "clan:#{state.clan_id}",
      {:clan_updated, new_state.level, new_state.reputation_points}
    )

    {:noreply, new_state}
  end

  def handle_cast({:add_clan_skill, skill_id, skill_level}, state) do
    new_skills = Map.put(state.skills, skill_id, skill_level)

    Task.start(fn ->
      %L2E.DB.ClanSkill{}
      |> L2E.DB.ClanSkill.changeset(%{
        clan_id: state.clan_id,
        skill_id: skill_id,
        skill_level: skill_level
      })
      |> Repo.insert(
        on_conflict: {:replace, [:skill_level, :updated_at]},
        conflict_target: [:clan_id, :skill_id]
      )
    end)

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "clan:#{state.clan_id}",
      {:clan_skill_added, skill_id, skill_level}
    )

    {:noreply, %{state | skills: new_skills}}
  end

  @impl GenServer
  def handle_cast({:set_clan_hall, hall_id}, state) do
    new_state = %{state | clan_hall_id: hall_id}

    Task.start(fn ->
      case Repo.get(L2E.DB.Clan, state.clan_id) do
        nil ->
          :ok

        record ->
          record
          |> Ecto.Changeset.change(%{clan_hall_id: hall_id})
          |> Repo.update()
      end
    end)

    Phoenix.PubSub.broadcast(L2E.PubSub, "clan:#{state.clan_id}", {:clan_hall_acquired, hall_id})
    {:noreply, new_state}
  end

  # ── Clan war — notification casts ─────────────────────────────────────────────

  # Notification from attacker's clan: they declared war against us
  def handle_cast({:war_declared_against_us, attacker_clan_id}, state) do
    if Map.has_key?(state.wars, attacker_clan_id) do
      {:noreply, state}
    else
      war_entry = %{state: :declared, attacker_kills: 0, defender_kills: 0}
      new_wars = Map.put(state.wars, attacker_clan_id, war_entry)

      Phoenix.PubSub.broadcast(
        L2E.PubSub,
        "clan:#{state.clan_id}",
        {:war_declared_against_us, attacker_clan_id, state.clan_id}
      )

      {:noreply, %{state | wars: new_wars}}
    end
  end

  # Notification: defender accepted war → attacker promotes to :mutual
  def handle_cast({:war_accepted, defender_clan_id}, state) do
    case Map.get(state.wars, defender_clan_id) do
      nil ->
        {:noreply, state}

      war ->
        updated_war = %{war | state: :mutual}
        new_wars = Map.put(state.wars, defender_clan_id, updated_war)
        new_enemies = [defender_clan_id | state.enemies] |> Enum.uniq()

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:war_mutual, state.clan_id, defender_clan_id}
        )

        {:noreply, %{state | wars: new_wars, enemies: new_enemies}}
    end
  end

  # Other clan surrendered to us
  def handle_cast({:war_surrendered, other_clan_id}, state) do
    new_wars = Map.delete(state.wars, other_clan_id)
    new_enemies = Enum.reject(state.enemies, &(&1 == other_clan_id))

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "clan:#{state.clan_id}",
      {:war_surrender, other_clan_id, state.clan_id}
    )

    {:noreply, %{state | wars: new_wars, enemies: new_enemies}}
  end

  # Record a war kill: killer_is_us=true → we killed them, false → they killed us
  def handle_cast({:add_war_kill, enemy_clan_id, killer_is_us}, state) do
    case Map.get(state.wars, enemy_clan_id) do
      nil ->
        {:noreply, state}

      war ->
        updated_war =
          if killer_is_us,
            do: %{war | attacker_kills: war.attacker_kills + 1},
            else: %{war | defender_kills: war.defender_kills + 1}

        new_wars = Map.put(state.wars, enemy_clan_id, updated_war)
        new_state = %{state | wars: new_wars}

        Task.start(fn ->
          Repo.update_all(
            from(w in L2E.DB.ClanWar,
              where:
                w.attacker_clan_id == ^state.clan_id and
                  w.defender_clan_id == ^enemy_clan_id
            ),
            set: [
              attacker_kills: updated_war.attacker_kills,
              defender_kills: updated_war.defender_kills
            ]
          )
        end)

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:war_kill_update, enemy_clan_id, updated_war}
        )

        {:noreply, new_state}
    end
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  # ── Clan war — call handlers ───────────────────────────────────────────────────

  @impl true
  def handle_call({:declare_war, target_clan_id}, _from, state) do
    cond do
      state.level < 3 ->
        {:reply, {:error, :clan_level_too_low}, state}

      Map.has_key?(state.wars, target_clan_id) ->
        {:reply, {:error, :already_at_war}, state}

      true ->
        war_entry = %{state: :declared, attacker_kills: 0, defender_kills: 0}
        new_wars = Map.put(state.wars, target_clan_id, war_entry)
        new_state = %{state | wars: new_wars}

        Task.start(fn ->
          %L2E.DB.ClanWar{}
          |> L2E.DB.ClanWar.changeset(%{
            attacker_clan_id: state.clan_id,
            defender_clan_id: target_clan_id,
            state: "declared"
          })
          |> Repo.insert(on_conflict: :nothing)
        end)

        case find_by_id(target_clan_id) do
          nil -> :ok
          target_pid -> GenServer.cast(target_pid, {:war_declared_against_us, state.clan_id})
        end

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:war_declared, state.clan_id, target_clan_id}
        )

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:accept_war, attacker_clan_id}, _from, state) do
    case Map.get(state.wars, attacker_clan_id) do
      %{state: :declared} = war ->
        updated_war = %{war | state: :mutual}
        new_wars = Map.put(state.wars, attacker_clan_id, updated_war)
        new_enemies = [attacker_clan_id | state.enemies] |> Enum.uniq()
        new_state = %{state | wars: new_wars, enemies: new_enemies}

        Task.start(fn ->
          Repo.update_all(
            from(w in L2E.DB.ClanWar,
              where:
                w.attacker_clan_id == ^attacker_clan_id and
                  w.defender_clan_id == ^state.clan_id
            ),
            set: [state: "mutual"]
          )
        end)

        case find_by_id(attacker_clan_id) do
          nil -> :ok
          attacker_pid -> GenServer.cast(attacker_pid, {:war_accepted, state.clan_id})
        end

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:war_mutual, state.clan_id, attacker_clan_id}
        )

        {:reply, :ok, new_state}

      _ ->
        {:reply, {:error, :no_pending_war}, state}
    end
  end

  def handle_call({:surrender, to_clan_id}, _from, state) do
    case Map.get(state.wars, to_clan_id) do
      nil ->
        {:reply, {:error, :not_at_war}, state}

      _ ->
        new_wars = Map.delete(state.wars, to_clan_id)
        new_enemies = Enum.reject(state.enemies, &(&1 == to_clan_id))
        new_state = %{state | wars: new_wars, enemies: new_enemies}

        Task.start(fn ->
          Repo.update_all(
            from(w in L2E.DB.ClanWar,
              where:
                (w.attacker_clan_id == ^state.clan_id and w.defender_clan_id == ^to_clan_id) or
                  (w.attacker_clan_id == ^to_clan_id and w.defender_clan_id == ^state.clan_id)
            ),
            set: [state: "ended"]
          )
        end)

        case find_by_id(to_clan_id) do
          nil -> :ok
          other_pid -> GenServer.cast(other_pid, {:war_surrendered, state.clan_id})
        end

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:war_surrender, state.clan_id, to_clan_id}
        )

        {:reply, :ok, new_state}
    end
  end

  def handle_call(:get_wars, _from, state) do
    {:reply, state.wars, state}
  end

  # ── Clan info / skills queries ─────────────────────────────────────────────────

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply,
     %{
       clan_id: state.clan_id,
       clan_name: state.clan_name,
       level: state.level,
       reputation_points: state.reputation_points,
       leader_id: state.leader_id,
       castle_id: state.castle_id,
       clan_hall_id: state.clan_hall_id,
       members: state.members
     }, state}
  end

  def handle_call(:max_members, _from, state) do
    {:reply, Map.get(@max_members_by_level, state.level, 10), state}
  end

  def handle_call(:get_skills, _from, state) do
    {:reply, state.skills, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, {:error, :unknown_call}, state}
  end

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
      members_list =
        Enum.map(new_members, fn {id, m} ->
          %{char_name: m.char_name, level: m.level, class_id: m.class_id, object_id: id}
        end)

      send(
        pid,
        {:send_packet,
         %Server.PledgeShowMemberListAll{clan_id: state.clan_id, members: members_list}}
      )

      send(
        pid,
        {:send_packet, %Server.SystemMessage{message_id: Server.SystemMessage.msg_joined_clan()}}
      )
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

          send(
            member.pid,
            {:send_packet,
             %Server.SystemMessage{message_id: Server.SystemMessage.msg_left_clan()}}
          )
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
      nil ->
        :ok

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

  defp check_level_up(state) when state.level >= 8, do: state

  defp check_level_up(state) do
    next_level = state.level + 1

    case Map.get(@level_thresholds, next_level) do
      nil ->
        state

      threshold when state.reputation_points >= threshold ->
        new_state = %{state | level: next_level}

        Phoenix.PubSub.broadcast(
          L2E.PubSub,
          "clan:#{state.clan_id}",
          {:clan_level_up, next_level}
        )

        check_level_up(new_state)

      _ ->
        state
    end
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

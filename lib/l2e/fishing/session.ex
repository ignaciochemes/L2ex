defmodule L2E.Fishing.Session do
  @moduledoc """
  Per-player fishing state machine.
  States: :idle → :waiting_bite → :hooked → stop

  Spawned on demand by PlayerSession when the player starts fishing.
  Sends messages back to the owner PlayerSession pid.

  OTP design: unsupervised (started directly via start_link from PlayerSession),
  restart: :temporary — do not restart on crash.
  """

  use GenServer, restart: :temporary
  require Logger

  # 10 seconds minimum before a bite
  @bite_delay_min_ms 10_000
  # 30 seconds maximum before a bite
  @bite_delay_max_ms 30_000
  # 20 seconds to reel before fish escapes
  @reel_timeout_ms 20_000

  defstruct [
    :owner_pid,
    :char_id,
    :x,
    :y,
    :z,
    :fish_id,
    fish_state: :idle,
    reel_hp: 100,
    bite_timer: nil,
    reel_timer: nil
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## Public API

  def start_fishing(pid, x, y, z), do: GenServer.cast(pid, {:cast_line, x, y, z})
  def stop_fishing(pid), do: GenServer.cast(pid, :stop)
  def pump_reel(pid), do: GenServer.cast(pid, :pump_reel)

  ## Callbacks

  @impl true
  def init(opts) do
    owner_pid = Keyword.fetch!(opts, :owner_pid)
    char_id = Keyword.fetch!(opts, :char_id)
    {:ok, %__MODULE__{owner_pid: owner_pid, char_id: char_id}}
  end

  @impl true
  def handle_cast({:cast_line, x, y, z}, state) do
    delay =
      @bite_delay_min_ms + :rand.uniform(@bite_delay_max_ms - @bite_delay_min_ms)

    timer = Process.send_after(self(), :fish_bite, delay)
    send(state.owner_pid, {:fishing_started, x, y, z})
    {:noreply, %{state | fish_state: :waiting_bite, x: x, y: y, z: z, bite_timer: timer}}
  end

  @impl true
  def handle_cast(:stop, state) do
    cancel_timer(state.bite_timer)
    cancel_timer(state.reel_timer)
    send(state.owner_pid, {:fishing_stopped, :cancelled})
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast(:pump_reel, %{fish_state: :hooked} = state) do
    new_reel_hp = state.reel_hp - 20

    if new_reel_hp <= 0 do
      cancel_timer(state.reel_timer)
      fish_id = state.fish_id || pick_random_fish()
      send(state.owner_pid, {:fishing_stopped, {:caught, fish_id}})
      {:stop, :normal, state}
    else
      send(state.owner_pid, {:fishing_reel_hp, new_reel_hp})
      {:noreply, %{state | reel_hp: new_reel_hp}}
    end
  end

  # Not hooked — ignore reel input
  def handle_cast(:pump_reel, state), do: {:noreply, state}

  @impl true
  def handle_info(:fish_bite, state) do
    reel_timer = Process.send_after(self(), :reel_timeout, @reel_timeout_ms)
    fish_id = pick_random_fish()
    send(state.owner_pid, {:fish_bit, fish_id})

    {:noreply,
     %{state | fish_state: :hooked, fish_id: fish_id, reel_timer: reel_timer, reel_hp: 100}}
  end

  @impl true
  def handle_info(:reel_timeout, state) do
    send(state.owner_pid, {:fishing_stopped, :escaped})
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ## Private helpers

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  # L2 Interlude fish item IDs: 6497–6518
  defp pick_random_fish do
    6497 + :rand.uniform(22) - 1
  end
end

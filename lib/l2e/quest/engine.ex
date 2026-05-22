defmodule L2E.Quest.Engine do
  @moduledoc """
  Quest DSL for L2E.

  Quest scripts `use L2E.Quest.Engine` and implement callbacks:
    - on_first_talk(npc_id, player_state) :: {:ok, html} | :skip
    - on_talk(npc_id, cond, player_state) :: {:ok, html, new_quest_state} | :skip
    - on_kill(npc_id, player_state, quest_state) :: {:ok, new_quest_state} | :skip
    - on_complete(player_state, quest_state) :: {:ok, rewards} | :skip

  Quest state per character: %{state: 0|1|2, cond: integer, count: integer, reward_taken: boolean}
    state 0 = not started, 1 = in progress, 2 = completed

  Quest script modules register themselves in ETS :quest_registry on load.
  """

  @callback quest_id() :: pos_integer()
  @callback quest_name() :: String.t()
  @callback min_level() :: pos_integer()
  @callback on_first_talk(npc_id :: pos_integer(), player :: map()) ::
              {:ok, html :: String.t()} | :skip
  @callback on_talk(npc_id :: pos_integer(), cond :: integer(), player :: map()) ::
              {:ok, html :: String.t(), new_quest_state :: map()} | :skip
  @callback on_kill(npc_id :: pos_integer(), player :: map(), quest_state :: map()) ::
              {:ok, new_quest_state :: map()} | :skip
  @callback on_complete(player :: map(), quest_state :: map()) ::
              {:ok, rewards :: list()} | :skip

  defmacro __using__(_opts) do
    quote do
      @behaviour L2E.Quest.Engine
      require Logger

      # Register this quest module in ETS when the module is loaded
      def child_spec(_opts),
        do: %{id: __MODULE__, start: {__MODULE__, :register, []}, type: :worker, restart: :transient}

      def register do
        L2E.Quest.Registry.register(__MODULE__)
        :ignore
      end

      # Default implementations — override as needed
      def on_first_talk(_npc_id, _player), do: :skip
      def on_talk(_npc_id, _cond, _player), do: :skip
      def on_kill(_npc_id, _player, _quest_state), do: :skip
      def on_complete(_player, _quest_state), do: {:ok, []}

      defoverridable on_first_talk: 2, on_talk: 3, on_kill: 3, on_complete: 2
    end
  end
end

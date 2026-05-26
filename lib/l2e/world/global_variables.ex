defmodule L2E.World.GlobalVariables do
  @moduledoc "Server-wide persistent key-value store."
  use GenServer
  require Logger

  @table :global_variables

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get(key, default \\ nil) do
    case :ets.lookup(@table, key) do
      [{_, value}] -> value
      [] -> default
    end
  end

  def get_integer(key, default \\ 0) do
    case get(key, nil) do
      nil -> default
      v -> String.to_integer(to_string(v))
    end
  end

  def set(key, value) do
    GenServer.cast(__MODULE__, {:set, key, value})
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    load_from_db()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:set, key, value}, state) do
    :ets.insert(@table, {key, value})
    persist(key, value)
    {:noreply, state}
  end

  defp load_from_db do
    try do
      rows = L2E.Repo.all(L2E.DB.GlobalVariable)

      Enum.each(rows, fn row ->
        :ets.insert(@table, {row.name, row.value})
      end)

      Logger.info("[GlobalVariables] loaded #{length(rows)} variables from DB")
    rescue
      e ->
        Logger.warning("[GlobalVariables] Could not load from DB: #{inspect(e)}")
    end
  end

  defp persist(key, value) do
    try do
      L2E.Repo.insert!(
        %L2E.DB.GlobalVariable{name: key, value: to_string(value)},
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: :name
      )
    rescue
      e -> Logger.warning("[GlobalVariables] persist failed: #{inspect(e)}")
    end
  end
end

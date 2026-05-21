defmodule L2E.Data.Loader do
  @moduledoc """
  Generic XML file loader for game data.

  Wraps SweetXml with helpers for the patterns used in L2J Mobius XML files:
  - `<set name="key" val="value"/>` attribute maps
  - `<stats>` subtrees with typed sub-elements
  - Globbing a directory for all .xml files (excluding custom/ subdirs)

  All paths are relative to the data root at:
    L2J_Mobius_CT_0_Interlude/dist/game/data/
  """

  import SweetXml

  @data_root Path.join([
               :code.priv_dir(:l2e) |> List.to_string() |> Path.dirname() |> Path.dirname(),
               "L2J_Mobius_CT_0_Interlude",
               "dist",
               "game",
               "data"
             ])

  @doc "Absolute path to the L2J gamedata root."
  def data_root, do: @data_root

  @doc """
  Returns all .xml files under `rel_path` (relative to data_root),
  excluding anything inside a `custom/` subdirectory.
  """
  @spec xml_files(String.t()) :: [String.t()]
  def xml_files(rel_path) do
    base = Path.join(@data_root, rel_path)

    Path.wildcard(Path.join(base, "**/*.xml"))
    |> Enum.reject(&String.contains?(&1, "/custom/"))
    |> Enum.reject(&String.contains?(&1, "\\custom\\"))
  end

  @doc """
  Parses a single XML file and passes its document to `fun`.
  Returns whatever `fun` returns, or `[]` on parse error.
  """
  @spec parse_file(String.t(), (any() -> any())) :: any()
  def parse_file(path, fun) do
    case File.read(path) do
      {:ok, content} ->
        try do
          doc = parse(content)
          fun.(doc)
        rescue
          e ->
            require Logger
            Logger.warning("[Data.Loader] Failed to parse #{path}: #{inspect(e)}")
            []
        end

      {:error, reason} ->
        require Logger
        Logger.warning("[Data.Loader] Cannot read #{path}: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Parses all .xml files in `rel_path` and flat-maps results through `fun`.
  """
  @spec parse_dir(String.t(), (any() -> [any()])) :: [any()]
  def parse_dir(rel_path, fun) do
    xml_files(rel_path)
    |> Enum.flat_map(fn path -> parse_file(path, fun) end)
  end

  # -----------------------------------------------------------------------
  # Helpers for common L2J XML patterns
  # -----------------------------------------------------------------------

  @doc """
  Extracts a `<set name="key" val="value"/>` map from a node's children.
  Returns `%{"key" => "value_string"}`.
  """
  @spec set_map(any()) :: %{String.t() => String.t()}
  def set_map(node) do
    node
    |> xpath(~x"./set"l,
      name: ~x"./@name"s,
      val: ~x"./@val"s
    )
    |> Map.new(fn %{name: k, val: v} -> {k, v} end)
  end

  @doc "Parses a string to integer, returning `default` on failure."
  @spec to_int(String.t() | nil, integer()) :: integer()
  def to_int(nil, default), do: default
  def to_int("", default), do: default

  def to_int(s, default) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  @doc "Parses a string to float, returning `default` on failure."
  @spec to_float(String.t() | nil, float()) :: float()
  def to_float(nil, default), do: default
  def to_float("", default), do: default

  def to_float(s, default) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> default
    end
  end

  @doc "Parses a boolean string (`true`/`false`/`1`/`0`), defaulting to `false`."
  @spec to_bool(String.t() | nil) :: boolean()
  def to_bool("true"), do: true
  def to_bool("1"), do: true
  def to_bool(_), do: false
end

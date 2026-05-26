defmodule L2E.Geodata do
  @moduledoc """
  M55: Geodata — ETS-backed binary geodata parser and LOS/movement checks.

  Loads L2 Interlude `.l2j` region files from `priv/game/data/geodata/` on
  startup. Falls back to stub mode (fully passable) when no files are present,
  preserving compatibility with all existing callers.

  ## Binary file format (`{rx}_{ry}.l2j`, little-endian)
  Each file holds 256×256 blocks stored in blockX-major, blockY-minor order.
  Each block starts with a 1-byte type tag:
  - `0` (flat):       2-byte signed-short height (all cells share it, all NSWE open)
  - `1` (complex):    64 × 2-byte cells, each encodes height+nswe
  - `2` (multilayer): 64 cells, each prefixed by 1-byte layer count, then that
                      many 2-byte layer records (height+nswe per layer)

  Cell 16-bit encoding (from L2J ComplexBlock / MultilayerBlock):
  - bits 0-3  = NSWE flags (E=1, W=2, S=4, N=8)
  - bits 4-15 = encoded height — decode as: `(raw & 0xFFF0) >> 1` (arithmetic)

  ## ETS table `:geodata_blocks`
  Key: `{region_x, region_y, block_x, block_y}`
  Value: `{:flat, height}` | `{:complex, cells_tuple}` | `{:multilayer, cells_tuple}`

  `cells_tuple` is a 64-element tuple indexed by `cell_x * 8 + cell_y`.
  - Complex cell element: `{height, nswe}`
  - Multilayer cell element: `[{height, nswe}, ...]` (list of layers)
  """

  use GenServer
  import Bitwise
  require Logger

  # NSWE bitmask constants (L2J Cell.java)
  @nswe_east  0x1
  @nswe_west  0x2
  @nswe_south 0x4
  @nswe_north 0x8

  # World coordinate origin and geo-coordinate scale (L2J GeoEngine.java)
  @world_min_x -655_360
  @world_min_y -589_824
  @coord_scale 16

  # Region = 256 blocks × 8 cells per axis
  @region_cells_x 2048
  @region_cells_y 2048

  # Block = 8×8 cells
  @block_cells_x 8
  @block_cells_y 8

  @type pos :: {integer(), integer(), integer()}

  # ── Public API ────────────────────────────────────────────────────────────────

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns true if there is line-of-sight between two positions."
  @spec can_see?(pos(), pos()) :: boolean()
  def can_see?(from, to), do: do_can_see(from, to)

  @doc "Returns true if movement from `from` to `to` is unobstructed."
  @spec can_move?(pos(), pos(), non_neg_integer()) :: boolean()
  def can_move?(from, to, heading), do: do_can_move(from, to, heading)

  @doc "Returns the ground Z coordinate at (x, y) nearest to z."
  @spec get_height(integer(), integer(), integer()) :: integer()
  def get_height(x, y, z), do: do_get_height(x, y, z)

  @doc "Returns the list of loaded region {rx, ry} pairs."
  @spec loaded_regions() :: [{integer(), integer()}]
  def loaded_regions(), do: GenServer.call(__MODULE__, :loaded_regions)

  # ── GenServer ─────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Create or reuse the ETS table (handles GenServer restarts gracefully)
    case :ets.whereis(:geodata_blocks) do
      :undefined ->
        :ets.new(:geodata_blocks, [:named_table, :public, :set, read_concurrency: true])

      _tid ->
        :ets.delete_all_objects(:geodata_blocks)
    end

    loaded = scan_and_load_geodata()
    {:ok, %{loaded: loaded}}
  end

  @impl true
  def handle_call(:loaded_regions, _from, %{loaded: loaded} = state) do
    {:reply, MapSet.to_list(loaded), state}
  end

  # ── Core logic (direct ETS reads — no GenServer serialisation) ────────────────

  defp do_can_see({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dist = :math.sqrt(dx * dx + dy * dy)
    steps = min(64, max(1, trunc(dist / @coord_scale)))

    Enum.all?(0..(steps - 1), fn i ->
      t0 = i / steps
      t1 = (i + 1) / steps
      px = trunc(x1 + dx * t0)
      py = trunc(y1 + dy * t0)
      pz = trunc(z1 + (z2 - z1) * t0)
      cx = trunc(x1 + dx * t1)
      cy = trunc(y1 + dy * t1)
      cz = trunc(z1 + (z2 - z1) * t1)
      do_can_move({px, py, pz}, {cx, cy, cz}, 0)
    end)
  end

  defp do_can_move({x1, y1, z1}, {x2, y2, _z2}, _heading) do
    case get_geo_data(x1, y1) do
      nil ->
        true

      {:flat, _h} ->
        true

      {:complex, cells} ->
        needed = direction_to_nswe(x1, y1, x2, y2)
        if needed == 0 do
          true
        else
          {cx, cy} = world_to_cell(x1, y1)
          {_h, nswe} = elem(cells, cx * @block_cells_y + cy)
          (nswe &&& needed) == needed
        end

      {:multilayer, cells} ->
        needed = direction_to_nswe(x1, y1, x2, y2)
        if needed == 0 do
          true
        else
          {cx, cy} = world_to_cell(x1, y1)
          layers = elem(cells, cx * @block_cells_y + cy)
          {_h, nswe} = find_nearest_layer(layers, z1)
          (nswe &&& needed) == needed
        end
    end
  end

  defp do_get_height(x, y, z) do
    case get_geo_data(x, y) do
      nil ->
        z

      {:flat, h} ->
        h

      {:complex, cells} ->
        {cx, cy} = world_to_cell(x, y)
        {h, _nswe} = elem(cells, cx * @block_cells_y + cy)
        h

      {:multilayer, cells} ->
        {cx, cy} = world_to_cell(x, y)
        layers = elem(cells, cx * @block_cells_y + cy)
        {h, _nswe} = find_nearest_layer(layers, z)
        h
    end
  end

  # ── Coordinate helpers ────────────────────────────────────────────────────────

  defp world_to_geo(x, y) do
    {div(x - @world_min_x, @coord_scale), div(y - @world_min_y, @coord_scale)}
  end

  defp world_to_region(x, y) do
    {gx, gy} = world_to_geo(x, y)
    {div(gx, @region_cells_x), div(gy, @region_cells_y)}
  end

  defp world_to_block(x, y) do
    {gx, gy} = world_to_geo(x, y)
    {rem(div(gx, @block_cells_x), 256), rem(div(gy, @block_cells_y), 256)}
  end

  defp world_to_cell(x, y) do
    {gx, gy} = world_to_geo(x, y)
    {rem(gx, @block_cells_x), rem(gy, @block_cells_y)}
  end

  defp get_geo_data(x, y) do
    {rx, ry} = world_to_region(x, y)
    {bx, by} = world_to_block(x, y)

    case :ets.lookup(:geodata_blocks, {rx, ry, bx, by}) do
      [{_key, block}] -> block
      [] -> nil
    end
  end

  # ── NSWE helpers ─────────────────────────────────────────────────────────────

  defp direction_to_nswe(x1, y1, x2, y2) do
    dx = x2 - x1
    dy = y2 - y1
    nswe = 0
    nswe = if dx > 0, do: nswe ||| @nswe_east, else: nswe
    nswe = if dx < 0, do: nswe ||| @nswe_west, else: nswe
    nswe = if dy > 0, do: nswe ||| @nswe_south, else: nswe
    nswe = if dy < 0, do: nswe ||| @nswe_north, else: nswe
    nswe
  end

  defp find_nearest_layer([single], _z), do: single

  defp find_nearest_layer(layers, z) do
    Enum.min_by(layers, fn {h, _nswe} -> abs(h - z) end)
  end

  # ── Height decoding ───────────────────────────────────────────────────────────

  # L2J formula: (short)(raw & 0xFFF0) >> 1  (arithmetic right-shift)
  # `masked` is unsigned 16-bit (result of raw &&& 0xFFF0, always 0..65535).
  # If bit 15 is set the value is negative in signed-16 representation.
  defp decode_height(masked) when masked >= 0x8000, do: div(masked - 0x10000, 2)
  defp decode_height(masked), do: div(masked, 2)

  # ── File loading ──────────────────────────────────────────────────────────────

  defp scan_and_load_geodata do
    geodata_dir = Application.app_dir(:l2e, "priv/game/data/geodata")

    if File.dir?(geodata_dir) do
      geodata_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".l2j"))
      |> Enum.reduce(MapSet.new(), fn filename, acc ->
        case parse_region_filename(filename) do
          {:ok, rx, ry} ->
            path = Path.join(geodata_dir, filename)

            if load_region(path, rx, ry) do
              MapSet.put(acc, {rx, ry})
            else
              acc
            end

          :error ->
            Logger.warning("[Geodata] Ignoring malformed filename: #{filename}")
            acc
        end
      end)
    else
      Logger.info("[Geodata] priv/game/data/geodata not found — stub mode active")
      MapSet.new()
    end
  end

  defp parse_region_filename(name) do
    base = String.replace_suffix(name, ".l2j", "")

    case String.split(base, "_") do
      [rx_str, ry_str] ->
        with {rx, ""} <- Integer.parse(rx_str),
             {ry, ""} <- Integer.parse(ry_str) do
          {:ok, rx, ry}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp load_region(path, rx, ry) do
    case File.read(path) do
      {:ok, data} ->
        try do
          parse_and_store_region(data, rx, ry)
          Logger.info("[Geodata] Loaded region #{rx}_#{ry} (#{byte_size(data)} bytes)")
          true
        rescue
          e ->
            Logger.warning("[Geodata] Failed to parse #{rx}_#{ry}: #{Exception.message(e)}")
            false
        end

      {:error, reason} ->
        Logger.warning("[Geodata] Region #{rx}_#{ry} not loaded — stub mode (#{reason})")
        false
    end
  end

  # ── Binary parsing ────────────────────────────────────────────────────────────

  defp parse_and_store_region(data, rx, ry) do
    # 256×256 = 65536 blocks, blockX-major blockY-minor order
    parse_blocks(data, rx, ry, 0, 0)
  end

  # All 256 block columns processed — done
  defp parse_blocks(_data, _rx, _ry, 256, _by), do: :ok

  # Flat block (type 0): single signed-short height, all NSWE open
  defp parse_blocks(<<0, h::little-signed-16, rest::binary>>, rx, ry, bx, by) do
    :ets.insert(:geodata_blocks, {{rx, ry, bx, by}, {:flat, h}})
    {nbx, nby} = next_block(bx, by)
    parse_blocks(rest, rx, ry, nbx, nby)
  end

  # Complex block (type 1): 64 cells × 2 bytes each
  defp parse_blocks(<<1, rest::binary>>, rx, ry, bx, by) do
    {cells, rest2} = parse_complex_cells(rest, 0, [])
    :ets.insert(:geodata_blocks, {{rx, ry, bx, by}, {:complex, List.to_tuple(cells)}})
    {nbx, nby} = next_block(bx, by)
    parse_blocks(rest2, rx, ry, nbx, nby)
  end

  # Multilayer block (type 2): 64 cells, each with variable layers
  defp parse_blocks(<<2, rest::binary>>, rx, ry, bx, by) do
    {cells, rest2} = parse_ml_cells(rest, 0, [])
    :ets.insert(:geodata_blocks, {{rx, ry, bx, by}, {:multilayer, List.to_tuple(cells)}})
    {nbx, nby} = next_block(bx, by)
    parse_blocks(rest2, rx, ry, nbx, nby)
  end

  defp next_block(bx, 255), do: {bx + 1, 0}
  defp next_block(bx, by), do: {bx, by + 1}

  # Parse 64 complex cells (each 2 bytes: height+nswe)
  defp parse_complex_cells(data, 64, acc), do: {Enum.reverse(acc), data}

  defp parse_complex_cells(<<raw::little-16, rest::binary>>, i, acc) do
    nswe = raw &&& 0xF
    height = decode_height(raw &&& 0xFFF0)
    parse_complex_cells(rest, i + 1, [{height, nswe} | acc])
  end

  # Parse 64 multilayer cells; each cell: 1-byte layer count + N×2-byte layers
  defp parse_ml_cells(data, 64, acc), do: {Enum.reverse(acc), data}

  defp parse_ml_cells(<<n_layers::8, rest::binary>>, i, acc) do
    {layers, rest2} = parse_ml_layers(rest, n_layers, [])
    parse_ml_cells(rest2, i + 1, [layers | acc])
  end

  defp parse_ml_layers(data, 0, acc), do: {Enum.reverse(acc), data}

  defp parse_ml_layers(<<raw::little-16, rest::binary>>, n, acc) do
    nswe = raw &&& 0xF
    height = decode_height(raw &&& 0xFFF0)
    parse_ml_layers(rest, n - 1, [{height, nswe} | acc])
  end
end
